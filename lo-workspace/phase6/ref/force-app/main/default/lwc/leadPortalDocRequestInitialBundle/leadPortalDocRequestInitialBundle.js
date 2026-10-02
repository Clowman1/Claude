import { LightningElement, api } from 'lwc';

export default class LeadPortalDocRequestInitialBundle extends LightningElement {
    @api loanPurpose;
    @api employmentType;
    @api selfEmploymentType;
    errorMessage = '';

    get purchaseClass() {
        return this.cardClass(this.loanPurpose, 'Purchase');
    }

    get refinanceClass() {
        return this.cardClass(this.loanPurpose, 'Refinance');
    }

    cardClass(currentValue, value) {
        return currentValue === value ? 'option-card option-card-selected' : 'option-card';
    }

    handleSelect(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.currentTarget.dataset.value;
        this[field] = value;
        this.employmentType = null;
        this.selfEmploymentType = null;
        this.errorMessage = '';
        this.dispatchEvent(
            new CustomEvent('portaladvance', {
                detail: {
                    loanPurpose: this.loanPurpose,
                    employmentType: this.employmentType,
                    selfEmploymentType: this.selfEmploymentType
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleSelect(event);
        }
    }
}