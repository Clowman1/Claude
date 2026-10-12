import { LightningElement, api } from 'lwc';
import getConversionPreview from '@salesforce/apex/ExternalLoPortalConversionFacade.getConversionPreview';
import confirmLeadConversion from '@salesforce/apex/ExternalLoPortalConversionFacade.confirmConversionWithReceived';
import { reduceApexError, showPortalToast } from 'c/portalUtils';

// The phrase LeadConversionGuardService.BLOCK_MESSAGE opens with; ConvertLead wraps it in its own text.
const isDocumentsBlock = (message) => String(message || '').includes('Finish the document review first');

export default class ExternalLoLeadConversionModal extends LightningElement {
    @api contextRecordKey;

    loading = true;
    saving = false;
    acknowledged = false;
    preview;
    /** Missing items the LO marked Info received (labels as in preview.missingFields). */
    received = [];
    /** LeadConversionGuardService refused: open document requests or undecisioned documents. */
    blockedByDocuments = false;

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

    // Data from ARIVE wins (green check). Empty fields can be marked Info received. SSN is assumed on file.
    get checklistRows() {
        if (!this.preview) {
            return [];
        }
        const missing = this.preview.missingFields || [];
        const rows = [
            { key: 'name', label: 'Borrower name', value: this.preview.borrowerName, missingLabel: 'Borrower name' },
            { key: 'income', label: 'Borrower income', value: this.preview.borrowerIncome, missingLabel: 'Borrower income' },
            { key: 'ssn', label: 'Borrower SSN', value: this.preview.ssnPresent ? this.preview.ssnMasked : 'On file with LO', missingLabel: null },
            { key: 'address', label: 'Subject property', value: this.preview.propertyAddress, missingLabel: 'Subject property' },
            { key: 'value', label: 'Estimated property value', value: this.preview.estimatedPropertyValue, missingLabel: 'Estimated property value' },
            { key: 'amount', label: 'Loan amount', value: this.preview.loanAmount, missingLabel: 'Loan amount' }
        ];
        return rows.map((row) => {
            const isMissing = !!row.missingLabel && missing.includes(row.missingLabel);
            const isReceived = isMissing && this.received.includes(row.missingLabel);
            return {
                ...row,
                value: row.value || (isReceived ? 'Info received' : '—'),
                isMissing,
                isReceived,
                checked: !isMissing || isReceived,
                buttonLabel: isReceived ? 'Undo' : 'Info received'
            };
        });
    }

    get dialogLabel() {
        return this.blockedByDocuments ? 'Finish the document review first' : 'Confirm TRID application pieces';
    }

    get outstanding() {
        return (this.preview?.missingFields || []).filter((label) => !this.received.includes(label));
    }

    get missingMessage() {
        const outstanding = this.outstanding;
        return outstanding.length ? 'Fill in on the lead or mark Info received: ' + outstanding.join(', ') : null;
    }

    get disableConfirm() {
        return this.saving || !this.preview || this.preview.alreadyConverted || this.outstanding.length > 0 || !this.acknowledged;
    }

    handleReceived(event) {
        const label = event.currentTarget.dataset.label;
        this.received = this.received.includes(label)
            ? this.received.filter((item) => item !== label)
            : [...this.received, label];
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
                acknowledged: this.acknowledged,
                infoReceived: this.received
            });
            if (result.success) {
                showPortalToast(this, 'Lead converted', result.userMessage, 'success');
                this.dispatchEvent(new CustomEvent('converted', {
                    detail: { transactionKey: result.transactionKey }
                }));
                return;
            }
            if (isDocumentsBlock(result.userMessage)) {
                this.blockedByDocuments = true;
                return;
            }
            showPortalToast(this, 'Conversion blocked', result.userMessage, 'warning');
        } catch (error) {
            const message = reduceApexError(error);
            if (isDocumentsBlock(message)) {
                this.blockedByDocuments = true;
                return;
            }
            showPortalToast(this, 'Conversion failed', message, 'error');
        } finally {
            this.saving = false;
        }
    }
}