import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import {
    publish,
    subscribe,
    unsubscribe,
    APPLICATION_SCOPE,
    MessageContext
} from 'lightning/messageService';
import LIBRARY_REFRESH_CHANNEL from '@salesforce/messageChannel/LibraryRefresh__c';
import getRecentLoans from '@salesforce/apex/LibraryListController.getRecentLoans';

const ROW_ACTIONS = [
    { label: 'Delete', name: 'delete', iconName: 'utility:delete' }
];

const COLUMNS = [
    { label: 'Loan', fieldName: 'name', type: 'text', initialWidth: 140 },
    { label: 'Borrower', fieldName: 'borrowerName', type: 'text' },
    { label: 'Book', fieldName: 'bookTitle', type: 'text' },
    { label: 'Start date', fieldName: 'startDate', type: 'date-local', initialWidth: 130 },
    { label: 'Due date', fieldName: 'endDate', type: 'date-local', initialWidth: 130 },
    { type: 'action', typeAttributes: { rowActions: ROW_ACTIONS } }
];

/**
 * Custom replacement for the standard Library_Book_Loan__c list view.
 *
 * - Reloads in place when a loan is created/removed (LibraryRefresh channel).
 * - Each row has a "Delete" action that deletes the loan. The
 *   LibraryBookLoanTrigger increments Available_Copies__c on delete; this
 *   component then refreshes itself and publishes on the channel so the book
 *   list / search cards pick up the restored copy.
 */
export default class LibraryLoanList extends LightningElement {
    columns = COLUMNS;
    loans = [];
    error;

    wiredLoansResult;
    _subscription;

    @wire(MessageContext)
    messageContext;

    @wire(getRecentLoans)
    wiredLoans(result) {
        this.wiredLoansResult = result;
        const { data, error } = result;
        if (data) {
            this.loans = data.map((row) => ({
                Id: row.Id,
                name: row.Name,
                bookId: row.Book__c,
                borrowerName: row.Borrower__r ? row.Borrower__r.Name : '',
                bookTitle: row.Book__r ? row.Book__r.Title__c : '',
                startDate: row.Loan_Start_Date__c,
                endDate: row.Loan_End_Date__c
            }));
            this.error = undefined;
        } else if (error) {
            this.loans = [];
            this.error = this.getErrorMessage(error);
        }
    }

    connectedCallback() {
        this._subscription = subscribe(
            this.messageContext,
            LIBRARY_REFRESH_CHANNEL,
            () => refreshApex(this.wiredLoansResult),
            { scope: APPLICATION_SCOPE }
        );
    }

    disconnectedCallback() {
        unsubscribe(this._subscription);
        this._subscription = null;
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'delete') {
            this.confirmAndDelete(event.detail.row);
        }
    }

    async confirmAndDelete(row) {
        const confirmed = await LightningConfirm.open({
            message: `Delete loan ${row.name}? The copy of "${row.bookTitle}" returns to the collection.`,
            variant: 'header',
            label: 'Confirm deletion'
        });
        if (!confirmed) {
            return;
        }

        try {
            await deleteRecord(row.Id);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Loan deleted',
                    message: `${row.name} removed. Copy returned to the collection.`,
                    variant: 'success'
                })
            );

            await refreshApex(this.wiredLoansResult);
            publish(this.messageContext, LIBRARY_REFRESH_CHANNEL, {
                source: 'libraryLoanList',
                bookId: row.bookId
            });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not delete the loan',
                    message: this.getErrorMessage(error),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        }
    }

    get hasLoans() {
        return this.loans.length > 0;
    }

    get showEmpty() {
        return !this.error && this.loans.length === 0;
    }

    getErrorMessage(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (typeof error?.body?.message === 'string') {
            return error.body.message;
        }
        return 'Could not load the loans.';
    }
}
