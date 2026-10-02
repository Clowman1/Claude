import { LightningElement, api, track } from 'lwc';
import { FlowNavigationNextEvent, FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class PulseFlowButtonBar extends LightningElement {
    @api buttons; // JSON string that will be parsed into an array
    @api mode = 'Navigation'; // Default mode is "Navigation", can be "Selection"
    @api barLabel; // Label for the button bar
    @api barLabelStyle; // CSS styling for the bar label
    @api buttonLabelStyle; // CSS styling for the button label

    @track buttonArray = []; // Array of button objects with additional display properties
    @api selectedValue = null; // Track selected value for Selection mode; accessible directly by the flow
    @api selectedValues = ''; // Comma-separated string for multi-selection mode

    connectedCallback() {
        try {
            // Parse JSON string to array of button objects
            const buttonsParsed = JSON.parse(this.buttons);
            
            // Initialize each button's variant and icon details
            this.buttonArray = buttonsParsed.map(button => ({
                ...button,
                variant: 'neutral', // Set all buttons to neutral initially
                icon: button.icon || null, // Optional icon
                iconPosition: button.iconPosition === 'right' ? 'right' : 'left' // Default to left if not specified
            }));
        } catch (error) {
            console.error("Error parsing buttons JSON:", error);
        }
    }

    handleButtonClick(event) {
        const buttonValue = event.target.dataset.value;
        this.selectedValue = buttonValue; // Update selected value

        // Dispatch the attribute change event to make the selected value available in the flow
        const attributeChangeEvent = new FlowAttributeChangeEvent('selectedValue', this.selectedValue);
        this.dispatchEvent(attributeChangeEvent);

        if (this.mode === 'Navigation') {
            // Dispatch the Next event to simulate the Next button behavior in flows
            const navigateNextEvent = new FlowNavigationNextEvent();
            this.dispatchEvent(navigateNextEvent);
        } else if (this.mode === 'Selection') {
            // Update only the selected button to 'brand' and others to 'neutral'
            this.buttonArray = this.buttonArray.map(button => ({
                ...button,
                variant: button.value === buttonValue ? 'brand' : 'neutral'
            }));
        }
    }
}