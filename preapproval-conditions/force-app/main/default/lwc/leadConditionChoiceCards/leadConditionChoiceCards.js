import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent, FlowNavigationNextEvent } from 'lightning/flowSupport';

export default class LeadConditionChoiceCards extends LightningElement {
    @api selectedChoice;

    get initialClass() {
        return this.cardClass('Create Initial Bundle');
    }

    get additionalClass() {
        return this.cardClass('Additional Conditions');
    }

    cardClass(value) {
        return this.selectedChoice === value ? 'choice-card choice-card-selected' : 'choice-card';
    }

    // Picking a card IS the decision, so it advances the flow itself and the screen hides its
    // footer. A Next button on a two-option chooser is a second click that adds nothing.
    handleSelect(event) {
        this.selectedChoice = event.currentTarget.dataset.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedChoice', this.selectedChoice));
        this.dispatchEvent(new FlowNavigationNextEvent());
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleSelect(event);
        }
    }

    // The flow still calls validate() when the footer is hidden and navigation is programmatic;
    // selectedChoice is always set by the time this runs because the click sets it first.
    @api
    validate() {
        return this.selectedChoice
            ? { isValid: true }
            : { isValid: false, errorMessage: 'Please choose a condition workflow.' };
    }
}
