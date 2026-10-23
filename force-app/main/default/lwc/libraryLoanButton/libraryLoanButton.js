import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import requestLoan from '@salesforce/apex/LibraryService.requestLoan';

/**
 * Request-a-loan button.
 *
 * Two ways to provide the book:
 *   - dropped on a Library_Book__c record page  -> uses `recordId`;
 *   - embedded by a list/search component        -> pass `bookId` / `bookTitle`.
 *
 * The borrower can be supplied by the parent through `borrowerId`; when it is
 * not, the component renders its own Contact picker (standalone use).
 *
 * On success or failure it shows a toast; on success it also emits a
 * `loancreated` event so a parent list can refresh available copies.
 */
export default class LibraryLoanButton extends LightningElement {
    /** Set automatically when placed on a Library_Book__c record page. */
    @api recordId;
    /** Explicit book id when embedded outside a record page. */
    @api bookId;
    /** Book title, used only to make the toast message friendlier. */
    @api bookTitle;
    /** Borrower provided by a parent component; hides the internal picker. */
    @api borrowerId;

    selectedBorrowerId;
    loading = false;

    get effectiveBookId() {
        return this.bookId || this.recordId;
    }

    get effectiveBorrowerId() {
        return this.borrowerId || this.selectedBorrowerId;
    }

    get showBorrowerPicker() {
        // Standalone use (record page): no borrower supplied and no explicit
        // bookId, so the component owns the Contact selection. When embedded in
        // a list the parent passes bookId and feeds borrowerId, so the internal
        // picker stays hidden and the button just disables until it arrives.
        return !this.borrowerId && !this.bookId;
    }

    get buttonDisabled() {
        return (
            this.loading || !this.effectiveBookId || !this.effectiveBorrowerId
        );
    }

    handleBorrowerChange(event) {
        this.selectedBorrowerId = event.detail.recordId;
    }

    async handleRequestLoan() {
        this.loading = true;
        try {
            const loanId = await requestLoan({
                bookId: this.effectiveBookId,
                borrowerId: this.effectiveBorrowerId
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Loan registered',
                    message: this.bookTitle
                        ? `"${this.bookTitle}" was loaned successfully.`
                        : 'Loan registered successfully.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('loancreated', {
                    detail: { bookId: this.effectiveBookId, loanId }
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not register the loan',
                    message: this.getErrorMessage(error),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.loading = false;
        }
    }

    /** Normalizes the many shapes an Apex/LWC error can take into one string. */
    getErrorMessage(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (typeof error?.body?.message === 'string') {
            return error.body.message;
        }
        if (typeof error?.message === 'string') {
            return error.message;
        }
        return 'Unexpected error while registering the loan. Please try again.';
    }
}
