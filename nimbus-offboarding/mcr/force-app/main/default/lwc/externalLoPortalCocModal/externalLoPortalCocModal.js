import { LightningElement, api, wire } from 'lwc';
import getCocReasonOptions from '@salesforce/apex/ExternalLoPortalCocFacade.getReasonOptions';
import submitPortalCocRequest from '@salesforce/apex/ExternalLoPortalCocFacade.submitCocRequest';
import { reduceApexError, showPortalToast } from 'c/portalUtils';

export default class ExternalLoPortalCocModal extends LightningElement {
    @api contextLoanKey;

    reason;
    notes = '';
    newBaseLoanAmount;
    newAppraisedValue;
    newRate;
    newProgram = '';
    saving = false;
    reasonOptions = [];

    @wire(getCocReasonOptions)
    wiredReasons({ data }) {
        if (data) {
            this.reasonOptions = data.map((entry) => ({ label: entry.label, value: entry.value }));
        }
    }

    get showLoanAmountField() {
        return this.reason === 'Loan Amount';
    }

    get showAppraisalField() {
        return this.reason === 'Appraisal/LTV';
    }

    get showRateField() {
        return this.reason === 'Rate Change';
    }

    get showProgramField() {
        return this.reason === 'Program Change';
    }

    get disableSubmit() {
        return this.saving || !this.reason;
    }

    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    handleAmountChange(event) {
        this.newBaseLoanAmount = event.target.value ? Number(event.target.value) : null;
    }

    handleAppraisalChange(event) {
        this.newAppraisedValue = event.target.value ? Number(event.target.value) : null;
    }

    handleRateChange(event) {
        this.newRate = event.target.value ? Number(event.target.value) : null;
    }

    handleProgramChange(event) {
        this.newProgram = event.target.value;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSubmit() {
        this.saving = true;
        try {
            const result = await submitPortalCocRequest({
                contextLoanKey: this.contextLoanKey,
                request: {
                    reason: this.reason,
                    notes: this.notes,
                    newBaseLoanAmount: this.newBaseLoanAmount,
                    newAppraisedValue: this.newAppraisedValue,
                    newRate: this.newRate,
                    newProgram: this.newProgram
                }
            });
            if (result.success) {
                showPortalToast(this, 'COC submitted', result.userMessage, 'success');
                this.dispatchEvent(new CustomEvent('submitted'));
                return;
            }
            showPortalToast(this, 'COC not submitted', result.userMessage, 'warning');
        } catch (error) {
            showPortalToast(this, 'COC failed', reduceApexError(error), 'error');
        } finally {
            this.saving = false;
        }
    }
}