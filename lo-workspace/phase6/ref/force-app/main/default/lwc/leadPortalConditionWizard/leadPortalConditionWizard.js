import { LightningElement, api, track } from 'lwc';
import savePortalRequests from '@salesforce/apex/LeadPortalDocumentRequestFacade.savePortalRequests';

const WORKFLOW_INITIAL = 'Create Initial Bundle';
const WORKFLOW_ADDITIONAL = 'Additional Conditions';
const ALL = 'ALL';

export default class LeadPortalConditionWizard extends LightningElement {
    @api contextRecordKey;
    @api borrowerOptions = [];

    currentStep = 'choice';
    workflowChoice;
    assignment = ALL;
    loanPurpose;
    employmentType;
    selfEmploymentType;
    manualCategory;
    manualDescription = '';
    borrowerStepSkipped = false;
    isSaving = false;
    errorMessage = '';

    @track borrowerCards = [];
    ineligibleNames = [];

    handleExit() {
        this.dispatchEvent(new CustomEvent('exit'));
    }

    handleBack() {
        this.errorMessage = '';
        if (this.currentStep === 'borrower') {
            this.currentStep = 'choice';
            return;
        }
        if (this.currentStep === 'bundle') {
            this.currentStep = this.borrowerStepSkipped ? 'choice' : 'borrower';
            return;
        }
        if (this.currentStep === 'preset') {
            this.currentStep =
                this.employmentType === 'Self Employed' && this.selfEmploymentType
                    ? 'selfEmployment'
                    : 'employment';
            return;
        }
        if (this.currentStep === 'selfEmployment') {
            this.currentStep = 'employment';
            return;
        }
        if (this.currentStep === 'employment') {
            this.currentStep = 'bundle';
            return;
        }
        if (this.currentStep === 'manual') {
            this.currentStep = this.borrowerStepSkipped ? 'choice' : 'borrower';
        }
    }

    handleChoiceSelect(event) {
        const choice = event.currentTarget.dataset.value;
        this.workflowChoice = choice;
        this.errorMessage = '';
        this.applyBorrowerAssignmentFromOptions();
    }

    handleChoiceKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleChoiceSelect(event);
        }
    }

    applyBorrowerAssignmentFromOptions() {
        if (!this.contextRecordKey) {
            this.errorMessage = 'Lead record could not be determined. Refresh the page and try again.';
            return;
        }
        this.errorMessage = '';
        this.borrowerCards = [];
        this.ineligibleNames = [];

        const options = this.borrowerOptions || [];
        if (options.length === 0) {
            // Partner Workspace cannot call cacheable Lead-id Apex from LWC without triggering Lead LDS.
            // Default to the whole file until initializeData supplies borrowerOptions (no extra call).
            this.assignment = ALL;
            this.borrowerStepSkipped = true;
            this.afterBorrowerStep();
            return;
        }

        const assignable = options.filter((option) => option.assignable);
        this.ineligibleNames = options
            .filter((option) => !option.assignable)
            .map((option) => option.label);

        if (assignable.length <= 2) {
            this.assignment = ALL;
            this.borrowerStepSkipped = true;
            this.afterBorrowerStep();
            return;
        }

        this.borrowerStepSkipped = false;
        this.borrowerCards = assignable.map((option) => this.toBorrowerCard(option));
        this.currentStep = 'borrower';
    }

    toBorrowerCard(option) {
        const isAll = option.value === ALL;
        return {
            value: option.value,
            kicker: isAll ? 'Shared' : option.isPrimary ? 'Primary Borrower' : 'Co-Borrower',
            title: option.label,
            copy: isAll
                ? 'Items the whole file shares, like a purchase contract. Everyone sees them, and the first upload satisfies them for all.'
                : `Only ${option.label} sees these in their portal, and only they are asked for them.`,
            cssClass: 'choice-card'
        };
    }

    handleBorrowerSelect(event) {
        this.assignment = event.currentTarget.dataset.value;
        this.afterBorrowerStep();
    }

    handleBorrowerKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleBorrowerSelect(event);
        }
    }

    afterBorrowerStep() {
        if (this.workflowChoice === WORKFLOW_INITIAL) {
            this.currentStep = 'bundle';
            return;
        }
        this.currentStep = 'manual';
    }

    handleBundleSelect(event) {
        this.loanPurpose = event.currentTarget.dataset.value;
        this.employmentType = null;
        this.selfEmploymentType = null;
        this.errorMessage = '';
        this.currentStep = 'employment';
    }

    handleEmploymentSelect(event) {
        this.employmentType = event.currentTarget.dataset.value;
        this.selfEmploymentType = null;
        this.errorMessage = '';
        if (this.employmentType === 'Self Employed') {
            this.currentStep = 'selfEmployment';
            return;
        }
        this.currentStep = 'preset';
    }

    handleEmploymentKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleEmploymentSelect(event);
        }
    }

    handleSelfEmploymentSelect(event) {
        this.selfEmploymentType = event.currentTarget.dataset.value;
        this.errorMessage = '';
        this.currentStep = 'preset';
    }

    handleSelfEmploymentKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleSelfEmploymentSelect(event);
        }
    }

    handleBundleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleBundleSelect(event);
        }
    }

    handleManualTypeSelect(event) {
        this.manualCategory = event.currentTarget.dataset.value;
        this.errorMessage = '';
    }

    handleManualDescriptionChange(event) {
        this.manualDescription = event.target.value;
        this.errorMessage = '';
    }

    handlePresetComplete() {
        this.dispatchEvent(new CustomEvent('complete'));
    }

    async handleManualSave() {
        const validation = this.validateManualEntry();
        if (!validation.isValid) {
            this.errorMessage = validation.errorMessage;
            return;
        }
        const trimmedDescription = (this.manualDescription || '').trim();
        this.isSaving = true;
        this.errorMessage = '';
        try {
            await savePortalRequests({
                contextRecordId: String(this.contextRecordKey),
                requests: [{
                    name: trimmedDescription,
                    subject: trimmedDescription,
                    description: trimmedDescription,
                    category: this.manualCategory,
                    type: 'Loan Officer',
                    status: 'New',
                    includeInEmail: true,
                    canBorrowerSee: true,
                    assignment: this.assignment
                }]
            });
            this.dispatchEvent(new CustomEvent('complete'));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    validateManualEntry() {
        if (!this.manualCategory) {
            return { isValid: false, errorMessage: 'Choose a condition type.' };
        }
        if (!this.manualDescription || !this.manualDescription.trim()) {
            return { isValid: false, errorMessage: 'Describe what the borrower needs to send.' };
        }
        return { isValid: true };
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unable to continue.';
    }

    get isChoiceStep() {
        return this.currentStep === 'choice';
    }

    get isBorrowerStep() {
        return this.currentStep === 'borrower';
    }

    get isBundleStep() {
        return this.currentStep === 'bundle';
    }

    get isEmploymentStep() {
        return this.currentStep === 'employment';
    }

    get isSelfEmploymentStep() {
        return this.currentStep === 'selfEmployment';
    }

    get isPresetStep() {
        return this.currentStep === 'preset';
    }

    get isManualStep() {
        return this.currentStep === 'manual';
    }

    get showBack() {
        return this.currentStep !== 'choice';
    }

    get initialClass() {
        return this.cardClass(WORKFLOW_INITIAL);
    }

    get additionalClass() {
        return this.cardClass(WORKFLOW_ADDITIONAL);
    }

    cardClass(value) {
        return this.workflowChoice === value ? 'choice-card choice-card-selected' : 'choice-card';
    }

    get purchaseClass() {
        return this.optionClass(this.loanPurpose, 'Purchase');
    }

    get refinanceClass() {
        return this.optionClass(this.loanPurpose, 'Refinance');
    }

    get w2EmploymentClass() {
        return this.optionClass(this.employmentType, 'W2');
    }

    get selfEmployedClass() {
        return this.optionClass(this.employmentType, 'Self Employed');
    }

    get retiredEmploymentClass() {
        return this.optionClass(this.employmentType, 'Retired');
    }

    get vaEmploymentClass() {
        return this.optionClass(this.employmentType, 'VA');
    }

    get llcSelfEmploymentClass() {
        return this.optionClass(this.selfEmploymentType, 'LLC');
    }

    get partnershipSelfEmploymentClass() {
        return this.optionClass(this.selfEmploymentType, 'Partnership');
    }

    get sCorpSelfEmploymentClass() {
        return this.optionClass(this.selfEmploymentType, 'S Corporation');
    }

    optionClass(currentValue, value) {
        return currentValue === value ? 'option-card option-card-selected' : 'option-card';
    }

    get incomeClass() {
        return this.optionClass(this.manualCategory, 'Income');
    }

    get assetClass() {
        return this.optionClass(this.manualCategory, 'Asset');
    }

    get creditClass() {
        return this.optionClass(this.manualCategory, 'Credit');
    }

    get otherClass() {
        return this.optionClass(this.manualCategory, 'Other');
    }

    get hasIneligibleBorrowers() {
        return this.ineligibleNames.length > 0;
    }

    get ineligibleMessage() {
        const names = this.ineligibleNames.join(', ');
        const single = this.ineligibleNames.length === 1;
        return `${names} ${single ? 'has' : 'have'} no email address, so they cannot be assigned conditions yet. Add an email on the Borrowers panel first.`;
    }
}