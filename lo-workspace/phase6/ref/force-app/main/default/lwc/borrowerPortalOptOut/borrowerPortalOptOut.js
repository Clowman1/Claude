import { LightningElement } from 'lwc';
import handleOptOut from '@salesforce/apex/OptOutController.handleOptOut';

const SUCCESS_THEME = 'slds-theme_info';
const ERROR_THEME = 'slds-theme_error';

export default class BorrowerPortalOptOut extends LightningElement {
    isLoading = true;
    resultMessage = 'Updating your preferences...';
    alertThemeClass = SUCCESS_THEME;

    connectedCallback() {
        this.processOptOut();
    }

    async processOptOut() {
        const email = new URLSearchParams(window.location.search).get('email');
        if (!email) {
            this.resultMessage = 'There was an issue updating your opt out. Please contact the company directly.';
            this.alertThemeClass = ERROR_THEME;
            this.isLoading = false;
            return;
        }

        try {
            await handleOptOut({ email });
            this.resultMessage = 'Thank you for notifying us of your preferences.';
            this.alertThemeClass = SUCCESS_THEME;
        } catch (error) {
            this.resultMessage =
                error?.body?.message ||
                'There was an issue updating your opt out. Please contact the company directly.';
            this.alertThemeClass = ERROR_THEME;
        } finally {
            this.isLoading = false;
        }
    }

    get alertClass() {
        return `portal-alert slds-notify slds-notify_alert slds-theme_alert-texture ${this.alertThemeClass}`;
    }
}