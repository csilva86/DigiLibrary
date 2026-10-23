import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import {
    subscribe,
    unsubscribe,
    APPLICATION_SCOPE,
    MessageContext
} from 'lightning/messageService';
import LIBRARY_REFRESH_CHANNEL from '@salesforce/messageChannel/LibraryRefresh__c';
import getBooks from '@salesforce/apex/LibraryListController.getBooks';

const COLUMNS = [
    { label: 'Title', fieldName: 'Title__c', type: 'text' },
    { label: 'Author', fieldName: 'Author__c', type: 'text' },
    {
        label: 'Available',
        fieldName: 'Available_Copies__c',
        type: 'number',
        cellAttributes: { alignment: 'left' },
        initialWidth: 120
    },
    {
        label: 'Total',
        fieldName: 'Total_Copies__c',
        type: 'number',
        cellAttributes: { alignment: 'left' },
        initialWidth: 100
    }
];

/**
 * Custom replacement for the standard Library_Book__c list view, so it can be
 * reloaded in place when a loan is registered. It subscribes to the
 * LibraryRefresh message channel and calls refreshApex on the wired query.
 */
export default class LibraryBookList extends LightningElement {
    columns = COLUMNS;
    books = [];
    error;

    wiredBooksResult;
    _subscription;

    @wire(MessageContext)
    messageContext;

    @wire(getBooks)
    wiredBooks(result) {
        this.wiredBooksResult = result;
        const { data, error } = result;
        if (data) {
            this.books = data;
            this.error = undefined;
        } else if (error) {
            this.books = [];
            this.error = this.getErrorMessage(error);
        }
    }

    connectedCallback() {
        this._subscription = subscribe(
            this.messageContext,
            LIBRARY_REFRESH_CHANNEL,
            () => refreshApex(this.wiredBooksResult),
            { scope: APPLICATION_SCOPE }
        );
    }

    disconnectedCallback() {
        unsubscribe(this._subscription);
        this._subscription = null;
    }

    get hasBooks() {
        return this.books.length > 0;
    }

    get showEmpty() {
        return !this.error && this.books.length === 0;
    }

    getErrorMessage(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (typeof error?.body?.message === 'string') {
            return error.body.message;
        }
        return 'Could not load the books.';
    }
}
