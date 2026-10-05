import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import convertLead from '@salesforce/apex/RealtorLeadConvertController.convertLead';

export default class RealtorLeadConvertAction extends LightningElement {
    @api recordId;
    isRunning = false;

    @api
    async invoke() {
        if (this.isRunning) {
            return;
        }
        this.isRunning = true;

        try {
            const result = await convertLead({ recordId: this.recordId });
            if (result?.success) {
                this.showSuccessToast(result);
            } else {
                this.showErrorToast(result?.userMessage || 'Unable to convert this Realtor Lead.');
            }
        } catch (error) {
            this.showErrorToast(this.getErrorMessage(error));
        } finally {
            this.isRunning = false;
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }

    showSuccessToast(result) {
        const accountId = result.accountId;
        const accountName = result.accountName || 'Account';
        const accountUrl = `/${accountId}`;
        const fallbackText = result.usedFollowUpFallback ? ' Lead link stored in Follow Up Account.' : '';

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Convert Complete',
                message: `${result.userMessage || 'Person Account linked.'} {0}.${fallbackText}`,
                messageData: [{ url: accountUrl, label: accountName }],
                variant: 'success'
            })
        );
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Convert Failed',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    getErrorMessage(error) {
        if (!error) {
            return 'An unexpected error occurred.';
        }
        if (error.body?.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'An unexpected error occurred.';
    }
}