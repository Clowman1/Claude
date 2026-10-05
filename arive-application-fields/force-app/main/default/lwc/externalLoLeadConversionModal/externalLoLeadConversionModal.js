import { LightningElement, api } from 'lwc';
import getConversionPreview from '@salesforce/apex/ExternalLoPortalConversionFacade.getConversionPreview';
import confirmLeadConversion from '@salesforce/apex/ExternalLoPortalConversionFacade.confirmConversion';
import { reduceApexError, showPortalToast } from 'c/portalUtils';

export default class ExternalLoLeadConversionModal extends LightningElement {
    @api contextRecordKey;

    loading = true;
    saving = false;
    acknowledged = false;
    preview;

    connectedCallback() {
        this.loadPreview();
    }

    async loadPreview() {
        if (!this.contextRecordKey) {
            this.loading = false;
            return;
        }
        this.loading = true;
        try {
            this.preview = await getConversionPreview({ contextRecordKey: this.contextRecordKey });
        } catch (error) {
            showPortalToast(this, 'Unable to load conversion checklist', reduceApexError(error), 'error');
            this.dispatchEvent(new CustomEvent('close'));
        } finally {
            this.loading = false;
        }
    }

    get checklistRows() {
        if (!this.preview) {
            return [];
        }
        return [
            { key: 'name', label: 'Borrower name', value: this.preview.borrowerName || '—' },
            { key: 'income', label: 'Borrower income', value: this.preview.borrowerIncome || '—' },
            { key: 'ssn', label: 'Borrower SSN', value: this.preview.ssnMasked || '—' },
            { key: 'address', label: 'Subject property', value: this.preview.propertyAddress || '—' },
            { key: 'value', label: 'Estimated property value', value: this.preview.estimatedPropertyValue || '—' },
            { key: 'amount', label: 'Loan amount', value: this.preview.loanAmount || '—' }
        ];
    }

    get missingMessage() {
        const missing = this.preview?.missingFields || [];
        if (!missing.length) {
            return null;
        }
        return `Complete on the lead before converting: ${missing.join(', ')}`;
    }

    get disableConfirm() {
        return this.saving || !this.preview?.readyToConvert || !this.acknowledged;
    }

    handleAckChange(event) {
        this.acknowledged = event.target.checked;
    }

    handleDecline() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleConfirm() {
        this.saving = true;
        try {
            const result = await confirmLeadConversion({
                contextRecordKey: this.contextRecordKey,
                acknowledged: this.acknowledged
            });
            if (result.success) {
                showPortalToast(this, 'Lead converted', result.userMessage, 'success');
                this.dispatchEvent(new CustomEvent('converted', {
                    detail: { transactionKey: result.transactionKey }
                }));
                return;
            }
            showPortalToast(this, 'Conversion blocked', result.userMessage, 'warning');
        } catch (error) {
            showPortalToast(this, 'Conversion failed', reduceApexError(error), 'error');
        } finally {
            this.saving = false;
        }
    }
}