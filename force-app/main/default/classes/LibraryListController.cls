/**
 * Read-only controller for the custom library list components
 * (libraryBookList / libraryLoanList).
 *
 * Both methods are cacheable so the components can @wire them and call
 * refreshApex on demand (driven by the LibraryRefresh message channel) after
 * a loan is created or removed.
 */
public with sharing class LibraryListController {
    /** Upper bound so a large library still returns one cheap query. */
    @TestVisible
    private static final Integer MAX_ROWS = 200;

    /**
     * All books, ordered by title, with the inventory counters.
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Book__c> getBooks() {
        return [
            SELECT
                Id,
                Name,
                Title__c,
                Author__c,
                Available_Copies__c,
                Total_Copies__c
            FROM Library_Book__c
            ORDER BY Title__c
            LIMIT :MAX_ROWS
        ];
    }

    /**
     * Most recent loans first, with borrower name and book title resolved.
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Book_Loan__c> getRecentLoans() {
        return [
            SELECT
                Id,
                Name,
                Borrower__c,
                Borrower__r.Name,
                Book__c,
                Book__r.Title__c,
                Loan_Start_Date__c,
                Loan_End_Date__c,
                CreatedDate
            FROM Library_Book_Loan__c
            ORDER BY CreatedDate DESC
            LIMIT :MAX_ROWS
        ];
    }
}
