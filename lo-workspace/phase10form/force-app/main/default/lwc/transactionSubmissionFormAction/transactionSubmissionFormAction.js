import { api, LightningElement } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

// Quick action Transaction__c.Submission_Form_Modern. Hosts the guided wizard; the legacy flow
// Loan_Origination_Submission_Form stays deployed (unused) as the fallback.
export default class TransactionSubmissionFormAction extends LightningElement {
    @api recordId;

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
