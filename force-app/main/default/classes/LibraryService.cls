/**
 * Service layer for the DigiLibrary book management feature.
 *
 * searchBooks - unified search: local Library_Book__c (SOSL) merged with the
 *               Open Library API, so the UI can offer "Request Loan" for books
 *               already in the catalogue and "Import" for the rest. Not
 *               cacheable because it performs a callout.
 * importBook  - persists an external book as a new Library_Book__c so it can
 *               then be loaned.
 * loanBook    - pure Apex entry point; throws NoAvailableCopiesException when
 *               the book has no copies left (as required by the challenge).
 * requestLoan - @AuraEnabled wrapper for the LWC. It converts any failure into
 *               an AuraHandledException, because only AuraHandledException
 *               messages are forwarded to the client (a raw custom exception
 *               would reach the LWC as a generic "internal server error").
 */
public with sharing class LibraryService {
    /** SOSL needs at least 2 non-wildcard characters to run. */
    @TestVisible
    private static final Integer MIN_SEARCH_LENGTH = 2;

    /** Cap the result set so a broad term stays cheap on the client and server. */
    @TestVisible
    private static final Integer MAX_RESULTS = 50;

    /** One row of the unified search: either a catalogued book or an import candidate. */
    public class BookSearchResult {
        @AuraEnabled
        public Id bookId; // null until imported
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String author;
        @AuraEnabled
        public Decimal availableCopies; // null for external-only rows
        @AuraEnabled
        public Decimal totalCopies; // null for external-only rows
        @AuraEnabled
        public Boolean existsLocally;
        @AuraEnabled
        public String source; // 'LOCAL' | 'EXTERNAL'

        /** Row for a book already in the catalogue. */
        public BookSearchResult(Library_Book__c book) {
            this.bookId = book.Id;
            this.title = book.Title__c;
            this.author = book.Author__c;
            this.availableCopies = book.Available_Copies__c;
            this.totalCopies = book.Total_Copies__c;
            this.existsLocally = true;
            this.source = 'LOCAL';
        }

        /** Row for an Open Library match not yet imported. */
        public BookSearchResult(String title, String author) {
            this.title = title;
            this.author = author;
            this.existsLocally = false;
            this.source = 'EXTERNAL';
        }
    }

    /**
     * Searches books by title or author, merging the local catalogue (SOSL)
     * with the Open Library API. Local matches come first (they carry copy
     * counts and can be loaned right away); external-only matches follow as
     * import candidates. Titles present in both are shown once, as the local
     * (actionable) row. If the external call fails, local results are still
     * returned.
     *
     * @param searchTerm free text typed by the user
     * @return unified rows; an empty list when the term is too short
     */
    @AuraEnabled
    public static List<BookSearchResult> searchBooks(String searchTerm) {
        List<BookSearchResult> rows = new List<BookSearchResult>();
        if (
            String.isBlank(searchTerm) ||
            searchTerm.trim().length() < MIN_SEARCH_LENGTH
        ) {
            return rows;
        }

        // 1. Local catalogue via SOSL.
        Set<String> localTitleKeys = new Set<String>();
        for (Library_Book__c book : findLocalBooks(searchTerm)) {
            rows.add(new BookSearchResult(book));
            localTitleKeys.add(normalizeTitle(book.Title__c));
        }

        // 2. Open Library candidates.
        List<OpenLibraryService.ExternalBook> externalBooks = OpenLibraryService.search(searchTerm);

        // 3. Exact-title SOQL backfill. The SOSL index lags a few seconds behind
        //    inserts, so a book just imported can be missing from step 1; SOQL
        //    is transactionally consistent and catches it, keeping the row
        //    actionable instead of offering "Import" for a catalogued book.
        Map<String, Library_Book__c> backfillByTitleKey = booksByExactTitle(
            externalBooks,
            localTitleKeys
        );

        for (OpenLibraryService.ExternalBook external : externalBooks) {
            String key = normalizeTitle(external.title);
            if (localTitleKeys.contains(key)) {
                continue; // already an actionable local row from SOSL
            }
            if (backfillByTitleKey.containsKey(key)) {
                rows.add(new BookSearchResult(backfillByTitleKey.get(key)));
                localTitleKeys.add(key);
                continue;
            }
            rows.add(new BookSearchResult(external.title, external.author));
        }

        return rows;
    }

    /**
     * SOQL lookup of Library_Book__c by exact Name for the external titles not
     * already matched by SOSL - bridges the SOSL indexing delay after an import.
     */
    private static Map<String, Library_Book__c> booksByExactTitle(
        List<OpenLibraryService.ExternalBook> externalBooks,
        Set<String> alreadyMatchedKeys
    ) {
        Map<String, Library_Book__c> byKey = new Map<String, Library_Book__c>();

        Set<String> titles = new Set<String>();
        for (OpenLibraryService.ExternalBook external : externalBooks) {
            if (
                String.isNotBlank(external.title) &&
                !alreadyMatchedKeys.contains(normalizeTitle(external.title))
            ) {
                titles.add(external.title.trim());
            }
        }
        if (titles.isEmpty()) {
            return byKey;
        }

        for (Library_Book__c book : [
            SELECT Id, Name, Title__c, Author__c, Available_Copies__c, Total_Copies__c
            FROM Library_Book__c
            WHERE Name IN :titles
            LIMIT :MAX_RESULTS
        ]) {
            byKey.put(normalizeTitle(book.Title__c), book);
        }
        return byKey;
    }

    /**
     * Persists an external book as a new Library_Book__c (1 copy, available)
     * so it can be loaned. If a book with the same title already exists its Id
     * is returned instead of creating a duplicate.
     *
     * @param title  book title from the external metadata (required)
     * @param author book author from the external metadata (optional)
     * @return the Id of the existing or newly created Library_Book__c
     */
    @AuraEnabled
    public static Id importBook(String title, String author) {
        try {
            if (String.isBlank(title)) {
                throw new IllegalArgumentException('A title is required to import a book.');
            }

            String cleanTitle = title.trim();
            List<Library_Book__c> existing = [
                SELECT Id
                FROM Library_Book__c
                WHERE Name = :cleanTitle
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }

            Library_Book__c book = new Library_Book__c(
                Name = cleanTitle,
                Author__c = String.isBlank(author) ? null : author.trim(),
                Total_Copies__c = 1,
                Available_Copies__c = 1
            );
            insert book;
            return book.Id;
        } catch (DmlException e) {
            throw toAuraException(
                e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage()
            );
        } catch (Exception e) {
            throw toAuraException(e.getMessage());
        }
    }

    private static List<Library_Book__c> findLocalBooks(String searchTerm) {
        String searchKey = sanitizeSoslTerm(searchTerm) + '*';

        List<List<SObject>> results = [
            FIND :searchKey
            IN ALL FIELDS
            RETURNING
                Library_Book__c(
                    Id,
                    Name,
                    Title__c,
                    Author__c,
                    Available_Copies__c,
                    Total_Copies__c
                    ORDER BY Title__c
                    LIMIT :MAX_RESULTS
                )
        ];

        return (List<Library_Book__c>) results[0];
    }

    private static String normalizeTitle(String title) {
        return title == null ? '' : title.trim().toLowerCase();
    }

    /**
     * Escapes the characters SOSL treats as operators so a stray symbol in the
     * user's input raises no SearchException. Backslash is escaped first to
     * avoid double-escaping the ones added afterwards.
     */
    private static String sanitizeSoslTerm(String term) {
        String cleaned = term.trim();
        for (
            String ch : new List<String>{
                '\\', '?', '&', '|', '!', '{', '}', '[', ']',
                '(', ')', '^', '~', '*', ':', '"', '\'', '+', '-'
            }
        ) {
            cleaned = cleaned.replace(ch, '\\' + ch);
        }
        return cleaned;
    }

    /**
     * Registers a loan for the given book / borrower.
     *
     * @param bookId      Library_Book__c to borrow
     * @param borrowerId  Contact borrowing the book
     * @return the Id of the created Library_Book_Loan__c
     * @throws NoAvailableCopiesException when Available_Copies__c <= 0
     */
    public static Id loanBook(Id bookId, Id borrowerId) {
        if (bookId == null || borrowerId == null) {
            throw new IllegalArgumentException(
                'Select a book and a borrower to register the loan.'
            );
        }

        List<Library_Book__c> books = [
            SELECT Id, Name, Available_Copies__c
            FROM Library_Book__c
            WHERE Id = :bookId
            FOR UPDATE
        ];

        if (books.isEmpty()) {
            throw new NoAvailableCopiesException('Book not found.');
        }

        Library_Book__c book = books[0];
        Decimal available = (book.Available_Copies__c != null)
            ? book.Available_Copies__c
            : 0;

        if (available <= 0) {
            throw new NoAvailableCopiesException(
                'The book "' +
                book.Name +
                '" has no available copies right now. ' +
                'Try again once a copy is returned.'
            );
        }

        Library_Book_Loan__c loan = new Library_Book_Loan__c(
            Book__c = bookId,
            Borrower__c = borrowerId,
            Loan_Start_Date__c = Date.today(),
            Loan_End_Date__c = Date.today().addDays(30)
        );
        // The trigger decrements Available_Copies__c on this insert.
        insert loan;
        return loan.Id;
    }

    /**
     * LWC-facing entry point. Returns the new loan Id on success and raises an
     * AuraHandledException carrying a user-friendly message on failure so the
     * component can render it in a toast.
     */
    @AuraEnabled
    public static Id requestLoan(Id bookId, Id borrowerId) {
        try {
            return loanBook(bookId, borrowerId);
        } catch (NoAvailableCopiesException e) {
            throw toAuraException(e.getMessage());
        } catch (DmlException e) {
            // e.g. the trigger's addError firing under a concurrent request
            String msg = (e.getNumDml() > 0) ? e.getDmlMessage(0) : e.getMessage();
            throw toAuraException(msg);
        } catch (Exception e) {
            throw toAuraException(e.getMessage());
        }
    }

    private static AuraHandledException toAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
