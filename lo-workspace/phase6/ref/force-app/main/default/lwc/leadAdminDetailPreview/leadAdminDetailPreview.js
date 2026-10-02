import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeadAdminDetailPreview extends LightningElement {
    @api recordId;

    handleReset() {
        this.template.querySelectorAll('lightning-input-field').forEach((field) => field.reset());
    }

    handleSuccess() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Lead updated',
                message: 'Your changes were saved.',
                variant: 'success'
            })
        );
    }
}