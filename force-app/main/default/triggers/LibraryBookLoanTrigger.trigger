/**
 * Trigger on Library_Book_Loan__c.
 *
 * Delegates all logic to LibraryBookLoanTriggerHandler:
 *   - after insert  -> validates availability (Available_Copies__c > 0) and
 *                      decreases Available_Copies__c by one per loan.
 *   - after delete  -> increases Available_Copies__c by one per removed loan.
 *
 * "after" contexts are used so the loan records already have Ids and the
 * inventory update runs against committed child rows.
 */
trigger LibraryBookLoanTrigger on Library_Book_Loan__c(after insert, after delete) {
    Boolean afterInsert = Trigger.isAfter && Trigger.isInsert;
    Boolean afterDelete = Trigger.isAfter && Trigger.isDelete;
    
    if (afterInsert) {
        LibraryBookLoanTriggerHandler.handleAfterInsert(Trigger.new);
    } else if (afterDelete) {
        LibraryBookLoanTriggerHandler.handleAfterDelete(Trigger.old);
    }
}
