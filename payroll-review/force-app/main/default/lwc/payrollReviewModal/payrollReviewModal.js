import { api } from 'lwc';
import LightningModal from 'lightning/modal';

// Command Center wrapper for c-payroll-review. Closes with 'Reviewed' after Looks good.
export default class PayrollReviewModal extends LightningModal {
    @api review;

    handleDone(event) {
        this.close(event.detail);
    }
}
