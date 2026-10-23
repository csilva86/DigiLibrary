/**
 * Custom exception thrown when a loan is requested for a book
 * that has no available copies (Available_Copies__c <= 0).
 */
public class NoAvailableCopiesException extends Exception {}
