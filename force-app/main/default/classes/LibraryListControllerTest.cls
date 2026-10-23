/**
 * Unit tests for LibraryListController.getBooks / getRecentLoans.
 */
@IsTest
private class LibraryListControllerTest {
    @TestSetup
    static void makeData() {
        Contact c = LibraryTestDataFactory.createContact();
        List<Library_Book__c> books = LibraryTestDataFactory.createBooks(3);
        insert new List<Library_Book_Loan__c>{
            LibraryTestDataFactory.newLoan(books[0].Id, c.Id),
            LibraryTestDataFactory.newLoan(books[1].Id, c.Id)
        };
    }

    @IsTest
    static void getBooks_returnsAllOrderedByTitle() {
        Test.startTest();
        List<Library_Book__c> books = LibraryListController.getBooks();
        Test.stopTest();

        Assert.areEqual(3, books.size());
        for (Integer i = 1; i < books.size(); i++) {
            Assert.isTrue(
                books[i - 1].Title__c <= books[i].Title__c,
                'results should be ordered by Title__c'
            );
        }
    }

    @IsTest
    static void getRecentLoans_returnsLoansWithRelatedNames() {
        Test.startTest();
        List<Library_Book_Loan__c> loans = LibraryListController.getRecentLoans();
        Test.stopTest();

        Assert.areEqual(2, loans.size());
        Assert.isNotNull(loans[0].Borrower__r.Name);
        Assert.isNotNull(loans[0].Book__r.Title__c);
    }
}
