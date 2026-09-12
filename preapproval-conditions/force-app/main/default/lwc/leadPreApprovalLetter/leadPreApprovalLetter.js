import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getContext from '@salesforce/apex/LeadPreApprovalLetterController.getContext';
import saveDetailsAndBuildLetter from '@salesforce/apex/LeadPreApprovalLetterController.saveDetailsAndBuildLetter';
import finalizeLetter from '@salesforce/apex/LeadPreApprovalLetterController.finalizeLetter';

const STEP_DETAILS = 'details';
const STEP_PREVIEW = 'preview';

/**
 * Pre-Approval Letter quick action. Two steps: capture the terms, then edit the rendered letter
 * before downloading it. The terms save onto the Lead as part of generating, so the record and the
 * letter cannot disagree, and finalizing moves the Lead to Pre-Approval.
 */
export default class LeadPreApprovalLetter extends NavigationMixin(LightningElement) {
    @api recordId;

    @track step = STEP_DETAILS;
    @track financingOptions = [];
    @track propertyOptions = [];
    @track nonQmOptions = [];
    @track signerOptions = [];

    borrowerName = '';
    purchasePrice;
    loanAmount;
    financingType = '';
    propertyType = '';
    nonQmType = '';
    nonQmTriggerValue = 'NON-QM';
    docsReviewed = '';
    signerId;
    letterHtml = '';

    isLoading = false;
    errorMessage = '';

    connectedCallback() {
        this.loadContext();
    }

    // ---------- state ----------

    get isDetailsStep() {
        return this.step === STEP_DETAILS;
    }

    get isPreviewStep() {
        return this.step === STEP_PREVIEW;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get signerRadioOptions() {
        return this.signerOptions.map(option => ({ label: option.label, value: option.userId }));
    }

    // Loan amount above purchase price is almost always a typo, and it produces an LTV over 100%
    // on a document that goes to a realtor.
    get validationMessage() {
        if (!this.purchasePrice) {
            return 'Enter a purchase price.';
        }
        if (!this.loanAmount) {
            return 'Enter a loan amount.';
        }
        if (Number(this.loanAmount) > Number(this.purchasePrice)) {
            return 'The loan amount is higher than the purchase price. Check both figures before generating.';
        }
        if (!this.financingType) {
            return 'Choose a financing type.';
        }
        if (!this.propertyType) {
            return 'Choose a property type.';
        }
        if (this.isNonQm && !this.nonQmType) {
            return 'Choose which Non-QM programme this is.';
        }
        return '';
    }

    // The Non-QM programme is asked for only when it applies, and required once it does.
    get isNonQm() {
        return String(this.financingType || '').toUpperCase()
            === String(this.nonQmTriggerValue || '').toUpperCase();
    }

    get generateDisabled() {
        return this.isLoading || Boolean(this.validationMessage);
    }

    get ltvLabel() {
        if (!this.purchasePrice || !this.loanAmount) {
            return '';
        }
        const ltv = (Number(this.loanAmount) / Number(this.purchasePrice)) * 100;
        return Number.isFinite(ltv) ? `${ltv.toFixed(2)}% LTV` : '';
    }

    get hasLtvLabel() {
        return Boolean(this.ltvLabel);
    }

    // ---------- load ----------

    async loadContext() {
        this.isLoading = true;
        try {
            const context = await getContext({ leadId: this.recordId });
            this.borrowerName = context.borrowerName;
            this.purchasePrice = context.purchasePrice;
            this.loanAmount = context.loanAmount;
            this.financingType = context.financingType || '';
            this.propertyType = context.propertyType || '';
            this.docsReviewed = context.docsReviewed || '';
            this.financingOptions = context.financingOptions || [];
            this.propertyOptions = context.propertyOptions || [];
            this.nonQmOptions = context.nonQmOptions || [];
            this.nonQmTriggerValue = context.nonQmTriggerValue || this.nonQmTriggerValue;
            this.nonQmType = context.nonQmType || '';
            this.signerOptions = context.signerOptions || [];
            this.signerId = context.defaultSignerId;
        } catch (error) {
            this.errorMessage = this.readableError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ---------- details ----------

    handlePurchasePriceChange(event) {
        this.purchasePrice = event.target.value;
    }

    handleLoanAmountChange(event) {
        this.loanAmount = event.target.value;
    }

    handleFinancingChange(event) {
        this.financingType = event.detail.value;
        // Dropping the sub-type on the way out stops a stale programme riding along if the Loan
        // Officer picks Non-QM, chooses DSCR, then switches the financing to Conventional.
        if (!this.isNonQm) {
            this.nonQmType = '';
        }
    }

    handleNonQmChange(event) {
        this.nonQmType = event.detail.value;
    }

    handlePropertyChange(event) {
        this.propertyType = event.detail.value;
    }

    handleDocsReviewedChange(event) {
        this.docsReviewed = event.target.value;
    }

    handleSignerChange(event) {
        this.signerId = event.detail.value;
    }

    async handleGenerate() {
        const validation = this.validationMessage;
        if (validation) {
            this.errorMessage = validation;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        try {
            this.letterHtml = await saveDetailsAndBuildLetter({
                leadId: this.recordId,
                purchasePrice: this.purchasePrice,
                loanAmount: this.loanAmount,
                financingType: this.financingType,
                propertyType: this.propertyType,
                nonQmType: this.nonQmType,
                docsReviewed: this.docsReviewed,
                signerId: this.signerId
            });
            this.step = STEP_PREVIEW;
            // The preview is a contenteditable region, so the HTML is injected after render rather
            // than bound: LWC templates escape markup, and this letter is markup by definition.
            Promise.resolve().then(() => this.paintPreview());
        } catch (error) {
            this.errorMessage = this.readableError(error);
        } finally {
            this.isLoading = false;
        }
    }

    paintPreview() {
        const host = this.template.querySelector('.letter-canvas');
        if (host) {
            host.innerHTML = this.letterHtml;
        }
    }

    // ---------- preview ----------

    handleBackToDetails() {
        this.captureEdits();
        this.step = STEP_DETAILS;
    }

    captureEdits() {
        const host = this.template.querySelector('.letter-canvas');
        if (host) {
            this.letterHtml = host.innerHTML;
        }
    }

    async handleFinalize() {
        this.captureEdits();
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const result = await finalizeLetter({
                leadId: this.recordId,
                letterHtml: this.letterHtml
            });

            const downloaded = this.deliverPdf(result);

            this.dispatchEvent(new ShowToastEvent({
                title: 'Pre-approval letter finalized',
                message: downloaded
                    ? 'The PDF has been downloaded.'
                    : 'The letter is opening in a new tab.',
                variant: 'success'
            }));
            this.close();
        } catch (error) {
            this.errorMessage = this.readableError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Saves the PDF straight to the browser downloads.
     *
     * The bytes come back with the finalize call, so there is no second trip and no tab to
     * close. If rendering them failed the page link is still there, and opening it is better
     * than leaving the Loan Officer with a letter they cannot get hold of.
     */
    deliverPdf(result) {
        if (!result?.pdfBase64) {
            if (result?.pdfPath) {
                window.open(result.pdfPath, '_blank');
            }
            return false;
        }

        try {
            const binary = atob(result.pdfBase64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) {
                bytes[i] = binary.charCodeAt(i);
            }
            const blobUrl = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
            const link = document.createElement('a');
            link.href = blobUrl;
            link.download = result.fileName || 'Pre-Approval Letter.pdf';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            // Given back on the next tick so the click has taken the data.
            window.setTimeout(() => URL.revokeObjectURL(blobUrl), 1000);
            return true;
        } catch (downloadError) {
            if (result.pdfPath) {
                window.open(result.pdfPath, '_blank');
            }
            return false;
        }
    }

    handleCancel() {
        this.close();
    }

    // The same component is reachable as a quick action and as a flow screen, and each host closes
    // a different way. Firing both is harmless: whichever host is listening acts, the other ignores.
    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
        this.dispatchEvent(new FlowNavigationFinishEvent());
    }

    readableError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Something went wrong. Please try again.'
        );
    }
}