import { LightningElement, api } from 'lwc';

export default class LeadPortalDocRequestManualEntry extends LightningElement {
    @api category;
    @api description;
    errorMessage = '';

    get incomeClass() {
        return this.cardClass('Income');
    }

    get assetClass() {
        return this.cardClass('Asset');
    }

    get creditClass() {
        return this.cardClass('Credit');
    }

    get otherClass() {
        return this.cardClass('Other');
    }

    cardClass(value) {
        return this.category === value ? 'option-card option-card-selected' : 'option-card';
    }

    handleTypeSelect(event) {
        this.category = event.currentTarget.dataset.value;
        this.errorMessage = '';
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
        this.errorMessage = '';
    }

    @api
    validate() {
        if (!this.category) {
            this.errorMessage = 'Choose a condition type.';
        } else if (!this.description || !this.description.trim()) {
            this.errorMessage = 'Describe what the borrower needs to send.';
        } else {
            return { isValid: true };
        }
        return { isValid: false, errorMessage: this.errorMessage };
    }
}