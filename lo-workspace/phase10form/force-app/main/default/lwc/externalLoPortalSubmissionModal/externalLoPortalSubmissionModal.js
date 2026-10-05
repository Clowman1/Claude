import { LightningElement, api } from 'lwc';

// Used by externalLoLoans (Partner Workspace + LO Workspace). Same contract as before
// (contextLoanKey in; submitted + close out), now hosting the guided wizard instead of the flow.
export default class ExternalLoPortalSubmissionModal extends LightningElement {
    @api contextLoanKey;
    submitted = false;

    handleSubmitted() {
        this.submitted = true;
    }

    handleClose() {
        // Parent reloads the loan on "submitted"; it also closes the modal.
        this.dispatchEvent(new CustomEvent(this.submitted ? 'submitted' : 'close'));
    }
}
