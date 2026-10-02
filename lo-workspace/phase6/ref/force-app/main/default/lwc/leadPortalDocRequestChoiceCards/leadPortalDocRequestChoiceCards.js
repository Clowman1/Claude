import { LightningElement } from 'lwc';

export default class LeadPortalDocRequestChoiceCards extends LightningElement {
    selectedChoice = '';

    get initialClass() {
        return this.cardClass('Create Initial Bundle');
    }

    get additionalClass() {
        return this.cardClass('Additional Conditions');
    }

    cardClass(value) {
        return this.selectedChoice === value ? 'choice-card choice-card-selected' : 'choice-card';
    }

    handleSelect(event) {
        this.selectedChoice = event.currentTarget.dataset.value;
        this.dispatchEvent(
            new CustomEvent('portaladvance', {
                detail: { selectedChoice: this.selectedChoice },
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