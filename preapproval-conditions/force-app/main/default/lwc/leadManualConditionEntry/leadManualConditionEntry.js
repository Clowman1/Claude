import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class LeadManualConditionEntry extends LightningElement {
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
        this.dispatchEvent(new FlowAttributeChangeEvent('category', this.category));
        this.errorMessage = '';
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('description', this.description));
        this.errorMessage = '';
    }

    // Unlike the chooser, this screen keeps its Next button: the description is free text, so
    // there is no click that means "done".
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