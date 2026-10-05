import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getStatus from '@salesforce/apex/RingSenseSubscriptionController.getStatus';
import reregister from '@salesforce/apex/RingSenseSubscriptionController.reregister';

export default class RingSenseSubscriptionAdmin extends LightningElement {
    loading = false;
    success = true;
    message = '';
    lastCallInsightCreatedDate;
    hoursSinceLastInsight;
    subscriptions = [];

    columns = [
        { label: 'Status', fieldName: 'status' },
        { label: 'Expiration', fieldName: 'expirationTime' },
        { label: 'Subscription Id', fieldName: 'id' },
        { label: 'Webhook address', fieldName: 'address', wrapText: true },
        { label: 'Event filters', fieldName: 'eventFilters', wrapText: true }
    ];

    connectedCallback() {
        this.loadStatus();
    }

    get healthSummary() {
        if (!this.lastCallInsightCreatedDate) {
            return 'No Call Insight records in this org.';
        }
        const hours = this.hoursSinceLastInsight == null ? '?' : this.hoursSinceLastInsight;
        return `Last Call Insight: ${this.lastCallInsightCreatedDate} (${hours} hours ago)`;
    }

    get hasSubscriptions() {
        return this.subscriptions && this.subscriptions.length > 0;
    }

    get showEmpty() {
        return !this.loading && !this.hasSubscriptions;
    }

    async loadStatus() {
        this.loading = true;
        try {
            const result = await getStatus();
            this.applyResult(result);
        } catch (e) {
            this.success = false;
            this.message = this.errorMessage(e);
            this.toast('Error', this.message, 'error');
        } finally {
            this.loading = false;
        }
    }

    async handleRefresh() {
        await this.loadStatus();
    }

    async handleReregister() {
        const confirmed = await LightningConfirm.open({
            message:
                'Re-register the RingSense webhook subscription? An Active matching subscription will be renewed; otherwise a new one is created.',
            label: 'Re-register webhook',
            theme: 'warning'
        });
        if (!confirmed) {
            return;
        }
        this.loading = true;
        try {
            const result = await reregister();
            this.applyResult(result);
            this.toast(result.success ? 'Success' : 'Error', result.message, result.success ? 'success' : 'error');
        } catch (e) {
            this.success = false;
            this.message = this.errorMessage(e);
            this.toast('Error', this.message, 'error');
        } finally {
            this.loading = false;
        }
    }

    applyResult(result) {
        this.success = result && result.success;
        this.message = result && result.message ? result.message : '';
        this.lastCallInsightCreatedDate = result && result.lastCallInsightCreatedDate;
        this.hoursSinceLastInsight = result && result.hoursSinceLastInsight;
        this.subscriptions = result && result.subscriptions ? result.subscriptions : [];
    }

    errorMessage(e) {
        if (e && e.body && e.body.message) {
            return e.body.message;
        }
        return e && e.message ? e.message : 'Unknown error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}