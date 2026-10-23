/**
 * Unit tests for LibraryBookLoanTrigger + LibraryBookLoanTriggerHandler:
 * inventory decrement on insert, increment on delete, availability guard
 * (addError), bulk aggregation, partial success and null-copy handling.
 */
@IsTest
private class LibraryBookLoanTriggerTest {
    @IsTest
    static void insert_decrementsAvailableCopies() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(5, 5);

        Test.startTest();
        insert LibraryTestDataFactory.newLoan(b.Id, c.Id);
        Test.stopTest();

        Assert.areEqual(
            4,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :b.Id]
            .Available_Copies__c
        );
    }

    @IsTest
    static void delete_incrementsAvailableCopies() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(5, 5);
        Library_Book_Loan__c loan = LibraryTestDataFactory.newLoan(b.Id, c.Id);
        insert loan; // -> 4

        Test.startTest();
        delete loan; // -> 5
        Test.stopTest();

        Assert.areEqual(
            5,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :b.Id]
            .Available_Copies__c
        );
    }

    @IsTest
    static void insert_bulk_decrementsByLoanCount() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(10, 10);

        List<Library_Book_Loan__c> loans = new List<Library_Book_Loan__c>();
        for (Integer i = 0; i < 5; i++) {
            loans.add(LibraryTestDataFactory.newLoan(b.Id, c.Id));
        }

        Test.startTest();
        insert loans;
        Test.stopTest();

        Assert.areEqual(
            5,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :b.Id]
            .Available_Copies__c
        );
    }

    @IsTest
    static void insert_noCopies_blocksLoanWithFriendlyError() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(2, 0);

        Test.startTest();
        try {
            insert LibraryTestDataFactory.newLoan(b.Id, c.Id);
            Assert.fail('Expected DmlException raised by addError');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('no available copies'));
        }
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Library_Book_Loan__c WHERE Book__c = :b.Id]
        );
        Assert.areEqual(
            0,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :b.Id]
            .Available_Copies__c
        );
    }

    @IsTest
    static void insert_partialBulk_commitsFulfillableOnly() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c okBook = LibraryTestDataFactory.createBook(1, 1);
        Library_Book__c depletedBook = LibraryTestDataFactory.createBook(1, 0);

        List<Library_Book_Loan__c> loans = new List<Library_Book_Loan__c>{
            LibraryTestDataFactory.newLoan(okBook.Id, c.Id),
            LibraryTestDataFactory.newLoan(depletedBook.Id, c.Id)
        };

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(loans, false);
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess(), 'loan for the available book should commit');
        Assert.isFalse(results[1].isSuccess(), 'loan for the depleted book should fail');
        Assert.areEqual(
            0,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :okBook.Id]
            .Available_Copies__c
        );
        Assert.areEqual(
            0,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :depletedBook.Id]
            .Available_Copies__c
        );
    }

    @IsTest
    static void insert_nullAvailableCopies_treatedAsZero() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(3, null);

        Test.startTest();
        try {
            insert LibraryTestDataFactory.newLoan(b.Id, c.Id);
            Assert.fail('Expected DmlException - null available treated as 0');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('no available copies'));
        }
        Test.stopTest();
    }

    @IsTest
    static void delete_nullAvailableCopies_treatedAsZero() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book__c b = LibraryTestDataFactory.createBook(2, 2);
        Library_Book_Loan__c loan = LibraryTestDataFactory.newLoan(b.Id, c.Id);
        insert loan; // -> 1
        b.Available_Copies__c = null;
        update b;

        Test.startTest();
        delete loan; // handleAfterDelete: null -> 0, then + 1
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT Available_Copies__c FROM Library_Book__c WHERE Id = :b.Id]
            .Available_Copies__c
        );
    }

    @IsTest
    static void loanWithoutBook_isIgnoredByTrigger() {
        Contact c = LibraryTestDataFactory.createContact();
        Library_Book_Loan__c loan = new Library_Book_Loan__c(
            Borrower__c = c.Id,
            Loan_Start_Date__c = Date.today()
        );

        Test.startTest();
        insert loan; // handleAfterInsert early-returns (no book in the batch)
        delete loan; // handleAfterDelete early-returns
        Test.stopTest();

        Assert.isNotNull(loan.Id);
    }
}
