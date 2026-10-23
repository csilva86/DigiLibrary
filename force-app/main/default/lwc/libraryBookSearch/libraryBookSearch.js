import { LightningElement, wire } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    publish,
    subscribe,
    unsubscribe,
    APPLICATION_SCOPE,
    MessageContext
} from 'lightning/messageService';
import LIBRARY_REFRESH_CHANNEL from '@salesforce/messageChannel/LibraryRefresh__c';
import searchBooks from '@salesforce/apex/LibraryService.searchBooks';
import importBook from '@salesforce/apex/LibraryService.importBook';

const MIN_CHARS = 2;

/**
 * Unified book search + loan interface.
 *
 * The search runs only when the user asks for it: pressing the "Search" button
 * (enabled once the term has at least two characters) or Enter in the field.
 * searchBooks is imperative because it makes a callout (Open Library) and can
 * therefore not be cacheable; running it per keystroke would spam that API.
 *
 * Each result row is either:
 *   - local  -> copy badge + <c-library-loan-button>, or
 *   - external -> "Register / Import" button that creates the Library_Book__c
 *     and re-runs the last search so it becomes loanable.
 *
 * After a loan is created / a book is imported the component re-runs the last
 * submitted search and publishes on LibraryRefresh so the sibling list
 * components reload. It also subscribes to the channel so a loan deleted
 * elsewhere refreshes the visible rows.
 */
export default class LibraryBookSearch extends LightningElement {
    term = ''; // live value of the input
    submittedTerm = ''; // term the visible results belong to
    borrowerId;
    isLoading = false;
    error;
    rows = [];

    _channelSubscription;

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        this._channelSubscription = subscribe(
            this.messageContext,
            LIBRARY_REFRESH_CHANNEL,
            () => this.runSearch(),
            { scope: APPLICATION_SCOPE }
        );
    }

    disconnectedCallback() {
        unsubscribe(this._channelSubscription);
        this._channelSubscription = null;
    }

    handleTermChange(event) {
        this.term = event.detail.value ?? '';
    }

    handleTermKeyUp(event) {
        if (event.key === 'Enter' && this.canSearch) {
            this.handleSearch();
        }
    }

    handleBorrowerChange(event) {
        this.borrowerId = event.detail.recordId;
    }

    handleSearch() {
        this.submittedTerm = this.term.trim();
        this.runSearch();
    }

    async runSearch() {
        if (this.submittedTerm.length < MIN_CHARS) {
            this.rows = [];
            this.error = undefined;
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        try {
            const results = await searchBooks({ searchTerm: this.submittedTerm });
            this.rows = results.map((r) => this.mapRow(r));
            this.error = undefined;
        } catch (err) {
            this.rows = [];
            this.error = this.reduceError(err);
        } finally {
            this.isLoading = false;
        }
    }

    mapRow(result) {
        const available = result.availableCopies ?? 0;
        const total = result.totalCopies ?? 0;
        return {
            key: result.bookId || `ext:${result.title}`,
            bookId: result.bookId,
            title: result.title,
            author: result.author,
            existsLocally: result.existsLocally,
            importing: false,
            copiesLabel: result.existsLocally
                ? `${available} of ${total} available`
                : 'Not in the library yet',
            badgeClass: !result.existsLocally
                ? 'slds-badge'
                : available <= 0
                  ? 'slds-badge slds-theme_error'
                  : 'slds-badge slds-theme_success'
        };
    }

    async handleImport(event) {
        const { title, author } = event.currentTarget.dataset;
        this.setImporting(title, true);
        try {
            const bookId = await importBook({ title, author: author || null });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Book imported',
                    message: `"${title}" was added to the library.`,
                    variant: 'success'
                })
            );
            // Flip the row to "local" right away; runSearch() then reconciles
            // (the Apex SOQL backfill keeps it local despite SOSL index lag).
            this.markImported(title, bookId);
            this.publishRefresh(bookId);
            await this.runSearch();
        } catch (err) {
            this.setImporting(title, false);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not import the book',
                    message: this.reduceError(err),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        }
    }

    setImporting(title, value) {
        this.rows = this.rows.map((row) =>
            row.title === title && !row.existsLocally
                ? { ...row, importing: value }
                : row
        );
    }

    markImported(title, bookId) {
        this.rows = this.rows.map((row) =>
            row.title === title && !row.existsLocally
                ? {
                      ...row,
                      bookId,
                      existsLocally: true,
                      importing: false,
                      copiesLabel: '1 of 1 available',
                      badgeClass: 'slds-badge slds-theme_success'
                  }
                : row
        );
    }

    handleLoanCreated(event) {
        this.publishRefresh(event?.detail?.bookId);
        this.dispatchEvent(new RefreshEvent());
        this.runSearch();
    }

    publishRefresh(bookId) {
        publish(this.messageContext, LIBRARY_REFRESH_CHANNEL, {
            source: 'libraryBookSearch',
            bookId: bookId
        });
    }

    get canSearch() {
        return !this.isLoading && this.term.trim().length >= MIN_CHARS;
    }

    get searchDisabled() {
        return !this.canSearch;
    }

    get hasSubmittedSearch() {
        return this.submittedTerm.length >= MIN_CHARS;
    }

    get hasResults() {
        return this.rows.length > 0;
    }

    get showEmptyState() {
        return (
            this.hasSubmittedSearch &&
            !this.isLoading &&
            !this.error &&
            !this.hasResults
        );
    }

    get showPrompt() {
        return !this.hasSubmittedSearch && !this.isLoading;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (typeof error?.body?.message === 'string') {
            return error.body.message;
        }
        if (typeof error?.message === 'string') {
            return error.message;
        }
        return 'Could not search for books. Please try again.';
    }
}
