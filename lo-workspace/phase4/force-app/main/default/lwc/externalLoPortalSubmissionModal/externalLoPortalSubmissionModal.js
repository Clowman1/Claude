import { LightningElement, api } from 'lwc';

export default class ExternalLoPortalSubmissionModal extends LightningElement {
    @api contextLoanKey;
    flowStarted = false;

    get inputVariables() {
        return [
            {
                name: 'recordId',
                type: 'String',
                value: this.contextLoanKey
            }
        ];
    }

    renderedCallback() {
        if (!this.contextLoanKey || this.flowStarted) {
            return;
        }
        const flow = this.template.querySelector('lightning-flow');
        if (!flow) {
            return;
        }
        this.flowStarted = true;
        flow.startFlow('Loan_Origination_Submission_Form', this.inputVariables);
    }

    handleStatusChange(event) {
        const status = event.detail.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.dispatchEvent(new CustomEvent('submitted'));
            this.dispatchEvent(new CustomEvent('close'));
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}