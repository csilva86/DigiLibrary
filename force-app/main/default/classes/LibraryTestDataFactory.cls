/**
 * Test-only data factory for the DigiLibrary suite. Marked @IsTest so it is
 * excluded from org code-coverage and is never callable from production code.
 */
@IsTest
public class LibraryTestDataFactory {
    private static Integer counter = 0;

    private static String suffix() {
        counter++;
        return String.valueOf(counter);
    }

    public static Contact createContact() {
        Contact c = new Contact(LastName = 'Borrower ' + suffix());
        insert c;
        return c;
    }

    // NOTE: Library_Book__c.Title__c is a formula field (mirrors Name), so the
    // title is written through the Name field; Title__c reflects it.
    public static Library_Book__c createBook(Integer total, Integer available) {
        Library_Book__c book = new Library_Book__c(
            Name = 'Test Book ' + suffix(),
            Author__c = 'Author ' + suffix(),
            Total_Copies__c = total,
            Available_Copies__c = available
        );
        insert book;
        return book;
    }

    public static List<Library_Book__c> createBooks(Integer howMany) {
        List<Library_Book__c> books = new List<Library_Book__c>();
        for (Integer i = 0; i < howMany; i++) {
            books.add(
                new Library_Book__c(
                    Name = 'Book ' + i + ' ' + suffix(),
                    Author__c = 'Author ' + i,
                    Total_Copies__c = 5,
                    Available_Copies__c = 5
                )
            );
        }
        insert books;
        return books;
    }

    public static Library_Book_Loan__c newLoan(Id bookId, Id borrowerId) {
        return new Library_Book_Loan__c(
            Book__c = bookId,
            Borrower__c = borrowerId,
            Loan_Start_Date__c = Date.today()
        );
    }
}
