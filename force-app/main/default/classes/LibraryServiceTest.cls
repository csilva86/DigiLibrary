/**
 * Unit tests for LibraryService: unified searchBooks (local SOSL + Open Library
 * merge), importBook, loanBook / requestLoan and the private sanitizeSoslTerm /
 * toAuraException helpers.
 */
@IsTest
private class LibraryServiceTest {
    private static void mockEmptyExternal() {
        Test.setMock(
            HttpCalloutMock.class,
            OpenLibraryCalloutMock.ok(new List<Map<String, Object>>())
        );
    }

    @IsTest
    static void searchBooks_blankOrShortTerm_returnsEmpty() {
        Test.startTest();
        Assert.areEqual(0, LibraryService.searchBooks(null).size());
        Assert.areEqual(0, LibraryService.searchBooks('   ').size());
        Assert.areEqual(0, LibraryService.searchBooks('a').size());
        Test.stopTest();
    }

    @IsTest
    static void searchBooks_returnsLocalRows() {
        List<Library_Book__c> books = LibraryTestDataFactory.createBooks(3);
        Test.setFixedSearchResults(new List<Id>{ books[0].Id, books[1].Id });
        mockEmptyExternal();

        Test.startTest();
        List<LibraryService.BookSearchResult> found = LibraryService.searchBooks('Book');
        Test.stopTest();

        Assert.areEqual(2, found.size(), 'two local records');
        Assert.isTrue(found[0].existsLocally);
        Assert.areEqual('LOCAL', found[0].source);
        Assert.isNotNull(found[0].bookId);
    }

    @IsTest
    static void searchBooks_escapesReservedCharacters() {
        List<Library_Book__c> books = LibraryTestDataFactory.createBooks(1);
        Test.setFixedSearchResults(new List<Id>{ books[0].Id });
        mockEmptyExternal();

        Test.startTest();
        List<LibraryService.BookSearchResult> found = LibraryService.searchBooks('Tom? & (Sawyer)* -x');
        Test.stopTest();

        Assert.areEqual(1, found.size(), 'reserved characters must be escaped, not raise SearchException');
    }

    @IsTest
    static void searchBooks_mergesExternalRowsNotInCatalogue() {
        Library_Book__c local = LibraryTestDataFactory.createBook(3, 3);
        String localTitle = [SELECT Title__c FROM Library_Book__c WHERE Id = :local.Id].Title__c;
        Test.setFixedSearchResults(new List<Id>{ local.Id });
        Test.setMock(
            HttpCalloutMock.class,
            OpenLibraryCalloutMock.ok(
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'title' => localTitle, 'author_name' => new List<String>{ 'Someone' } },
                    new Map<String, Object>{ 'title' => 'Remote Only Book', 'author_name' => new List<String>{ 'Remote Author' } }
                }
            )
        );

        Test.startTest();
        List<LibraryService.BookSearchResult> rows = LibraryService.searchBooks('book');
        Test.stopTest();

        Assert.areEqual(2, rows.size(), 'local row + one external-only row (matching title deduped)');
        Assert.isTrue(rows[0].existsLocally, 'local first');
        Assert.isFalse(rows[1].existsLocally, 'external-only second');
        Assert.areEqual('EXTERNAL', rows[1].source);
        Assert.areEqual('Remote Only Book', rows[1].title);
        Assert.areEqual('Remote Author', rows[1].author);
        Assert.isNull(rows[1].bookId);
    }

    @IsTest
    static void searchBooks_externalFailure_stillReturnsLocalRows() {
        List<Library_Book__c> books = LibraryTestDataFactory.createBooks(2);
        Test.setFixedSearchResults(new List<Id>{ books[0].Id });
        Test.setMock(HttpCalloutMock.class, OpenLibraryCalloutMock.failing());

        Test.startTest();
        List<LibraryService.BookSearchResult> rows = LibraryService.searchBooks('Book');
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'a remote outage must not break local search');
        Assert.isTrue(rows[0].existsLocally);
    }

    @IsTest
    static void searchBooks_bookMissedBySosl_isBackfilledFromSoql() {
        // Book exists locally but the SOSL index has not caught up (empty fixed
        // results). The exact-title SOQL backfill must still classify it local.
        Library_Book__c local = LibraryTestDataFactory.createBook(1, 1);
        String title = [SELECT Name FROM Library_Book__c WHERE Id = :local.Id].Name;
        Test.setFixedSearchResults(new List<Id>());
        Test.setMock(
            HttpCalloutMock.class,
            OpenLibraryCalloutMock.ok(
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'title' => title, 'author_name' => new List<String>{ 'X' } }
                }
            )
        );

        Test.startTest();
        List<LibraryService.BookSearchResult> rows = LibraryService.searchBooks('anything');
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.isTrue(rows[0].existsLocally, 'SOQL backfill reclassifies it as local');
        Assert.areEqual(local.Id, rows[0].bookId);
        Assert.areEqual('LOCAL', rows[0].source);
    }

    @IsTest
    static void importBook_createsAvailableBook() {
        Test.startTest();
        Id bookId = LibraryService.importBook('Brave New World', 'Aldous Huxley');
        Test.stopTest();

        Library_Book__c created = [
            SELECT Name, Author__c, Total_Copies__c, Available_Copies__c
            FROM Library_Book__c
            WHERE Id = :bookId
        ];
        Assert.areEqual('Brave New World', created.Name);
        Assert.areEqual('Aldous Huxley', created.Author__c);
        Assert.areEqual(1, created.Total_Copies__c);
        Assert.areEqual(1, created.Available_Copies__c);
    }

    @IsTest
    static void importBook_existingTitle_returnsExistingId() {
        Library_Book__c existing = LibraryTestDataFactory.createBook(4, 4);
        String title = [SELECT Name FROM Library_Book__c WHERE Id = :existing.Id].Name;

        Test.startTest();
        Id bookId = LibraryService.importBook(title, 'Whoever');
        Test.stopTest();

        Assert.areEqual(existing.Id, bookId, 'no duplicate created');
        Assert.areEqual(1, [SELECT COUNT() FROM Library_Book__c WHERE Name = :title]);
    }

    @IsTest
    static void importBook_blankTitle_throwsAuraHandled() {
        Test.startTest();
        try {
            LibraryService.importBook('   ', 'Nobody');
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void importBook_dmlFailure_wrappedAsAuraHandled() {
        // Name maxes out at 80 chars -> STRING_TOO_LONG DmlException on insert.
        String tooLong = 'X'.repeat(200);

        Test.startTest();
        try {
            LibraryService.importBook(tooLong, 'Some Author');
            Assert.fail('Expected AuraHandledException from the DmlException path');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void loanBook_decrementsAvailableCopies() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(5, 5);

        Test.startTest();
        Id loanId = LibraryService.loanBook(b.Id, c.Id);
        Test.stopTest();

        Assert.isNotNull(loanId);
        Assert.areEqual(
            4,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :b.Id]
            .Available_Copies__c
        );
    }

    @IsTest
    static void loanBook_nullArguments_throwsIllegalArgument() {
        Contact c = LibraryTestDataFactory.createContact();

        Test.startTest();
        try {
            LibraryService.loanBook(null, c.Id);
            Assert.fail('Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Select a book'));
        }
        Test.stopTest();
    }

    @IsTest
    static void loanBook_bookNotFound_throwsNoAvailableCopies() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(1, 1);
        Id ghostBookId = b.Id;
        delete b;

        Test.startTest();
        try {
            LibraryService.loanBook(ghostBookId, c.Id);
            Assert.fail('Expected NoAvailableCopiesException');
        } catch (NoAvailableCopiesException e) {
            Assert.isTrue(e.getMessage().contains('not found'));
        }
        Test.stopTest();
    }

    @IsTest
    static void loanBook_noCopies_throwsNoAvailableCopies() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(2, 0);

        Test.startTest();
        try {
            LibraryService.loanBook(b.Id, c.Id);
            Assert.fail('Expected NoAvailableCopiesException');
        } catch (NoAvailableCopiesException e) {
            Assert.isTrue(e.getMessage().contains('no available copies'));
        }
        Test.stopTest();
    }

    @IsTest
    static void requestLoan_success_returnsLoanIdAndDecrements() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(3, 3);

        Test.startTest();
        Id loanId = LibraryService.requestLoan(b.Id, c.Id);
        Test.stopTest();

        Assert.isNotNull(loanId);
        Assert.areEqual(
            2,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :b.Id]
            .Available_Copies__c
        );
    }

    @IsTest
    static void requestLoan_noCopies_throwsAuraHandled() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(1, 0);

        Test.startTest();
        try {
            LibraryService.requestLoan(b.Id, c.Id);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void requestLoan_nullArguments_throwsAuraHandled() {
        Test.startTest();
        try {
            LibraryService.requestLoan(null, null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void requestLoan_dmlFailure_wrappedAsAuraHandled() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(5, 5);
        Id ghostBorrowerId = c.Id;
        // Borrower no longer exists -> inserting the loan raises a DmlException,
        // exercising the catch (DmlException) branch of requestLoan.
        delete c;

        Test.startTest();
        try {
            LibraryService.requestLoan(b.Id, ghostBorrowerId);
            Assert.fail('Expected AuraHandledException from the DmlException path');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }
}
