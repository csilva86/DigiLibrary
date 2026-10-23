/**
 * Handler for LibraryBookLoanTrigger.
 *
 * Keeps the Library_Book__c inventory in sync with loan records:
 *   - On insert: validates there are available copies and decreases
 *     Available_Copies__c by the number of new loans for each book.
 *   - On delete: increases Available_Copies__c by the number of removed
 *     loans for each book.
 *
 * Fully bulkified: one SOQL query and one DML statement per book set,
 * regardless of how many loan records are processed in the transaction.
 *
 * When a book has no available copies the offending loan record is flagged
 * with SObject.addError(NoAvailableCopiesException). Compared to throwing:
 *   - the message shown on the standard UI / Data Loader is clean, with no
 *     "Class.X: line N" stack noise;
 *   - a bulk insert still commits the loans that CAN be fulfilled;
 *   - the custom exception type is still the one surfaced.
 * The LibraryService.loanBook path additionally throws the custom exception
 * up front so callers (and the LWC) get it before any DML.
 */
public with sharing class LibraryBookLoanTriggerHandler {
    @TestVisible
    private static final String NO_COPIES_MESSAGE =
        'The book "{0}" has no available copies right now. ' +
        'Try again once a copy is returned.';

    /**
     * Handles inserted loans: validates availability and decrements inventory.
     * @param newLoans the Trigger.new list of Library_Book_Loan__c records
     */
    public static void handleAfterInsert(List<Library_Book_Loan__c> newLoans) {
        Map<Id, Integer> requestedByBookId = countLoansByBook(newLoans);
        if (requestedByBookId.isEmpty()) {
            return;
        }

        Map<Id, Library_Book__c> booksById = new Map<Id, Library_Book__c>(
            [
                SELECT Id, Name, Available_Copies__c, Total_Copies__c
                FROM Library_Book__c
                WHERE Id IN :requestedByBookId.keySet()
                FOR UPDATE
            ]
        );

        Set<Id> unfulfillableBookIds = new Set<Id>();
        List<Library_Book__c> booksToUpdate = new List<Library_Book__c>();

        for (Id bookId : requestedByBookId.keySet()) {
            Library_Book__c book = booksById.get(bookId);
            Integer requested = requestedByBookId.get(bookId);
            Decimal available = (book != null && book.Available_Copies__c != null)
                ? book.Available_Copies__c
                : 0;

            if (book == null || available < requested) {
                unfulfillableBookIds.add(bookId);
            } else {
                book.Available_Copies__c = available - requested;
                booksToUpdate.add(book);
            }
        }

        if (!unfulfillableBookIds.isEmpty()) {
            for (Library_Book_Loan__c loan : newLoans) {
                if (!unfulfillableBookIds.contains(loan.Book__c)) {
                    continue;
                }
                Library_Book__c book = booksById.get(loan.Book__c);
                String bookName = (book != null) ? book.Name : 'selected';
                loan.addError(
                    new NoAvailableCopiesException(
                        String.format(
                            NO_COPIES_MESSAGE,
                            new List<Object>{ bookName }
                        )
                    )
                );
            }
        }

        if (!booksToUpdate.isEmpty()) {
            update booksToUpdate;
        }
    }

    /**
     * Handles deleted loans: increments inventory back.
     * @param oldLoans the Trigger.old list of Library_Book_Loan__c records
     */
    public static void handleAfterDelete(List<Library_Book_Loan__c> oldLoans) {
        Map<Id, Integer> releasedByBookId = countLoansByBook(oldLoans);
        if (releasedByBookId.isEmpty()) {
            return;
        }

        List<Library_Book__c> booksToUpdate = new List<Library_Book__c>();
        for (Library_Book__c book : [
            SELECT Id, Available_Copies__c, Total_Copies__c
            FROM Library_Book__c
            WHERE Id IN :releasedByBookId.keySet()
            FOR UPDATE
        ]) {
            Decimal available = (book.Available_Copies__c != null)
                ? book.Available_Copies__c
                : 0;
            book.Available_Copies__c = available + releasedByBookId.get(book.Id);
            booksToUpdate.add(book);
        }

        update booksToUpdate;
    }

    /**
     * Groups loan records by their Book__c lookup and counts them.
     * Records with a null Book__c are ignored.
     */
    private static Map<Id, Integer> countLoansByBook(List<Library_Book_Loan__c> loans) {
        Map<Id, Integer> countByBookId = new Map<Id, Integer>();
        for (Library_Book_Loan__c loan : loans) {
            if (loan.Book__c == null) {
                continue;
            }
            Integer current = countByBookId.containsKey(loan.Book__c)
                ? countByBookId.get(loan.Book__c)
                : 0;
            countByBookId.put(loan.Book__c, current + 1);
        }
        return countByBookId;
    }
}
