import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEvent from '@salesforce/apex/BdCommandCenterController.getEvent';
import resendInvite from '@salesforce/apex/BdCommandCenterController.resendInvite';
import { industryClass, errorMessage, dayParts } from 'c/bdUtils';

const STATUS_CLASS = { 'Yes - Attending': 'chip yes', 'No - Unable to Attend': 'chip no' };

export default class BdEventTracker extends NavigationMixin(LightningElement) {
    @api campaignId;
    @api canEdit = false;
    // LO Workspace: the Campaign record page needs the BD-only RealtorEventWorkspaceController.
    @api hideOpen = false;
    data;
    error;
    busyId;

    connectedCallback() { this.load(); }

    async load() {
        try {
            this.data = await getEvent({ campaignId: this.campaignId });
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    get showOpen() { return !this.hideOpen; }
    get ev() { return this.data && this.data.event; }
    get header() {
        const e = this.ev;
        if (!e) return '';
        return e.kind + ' · ' + dayParts(e.startDate).label + (e.timeLabel ? ' · ' + e.timeLabel : '');
    }
    get sub() {
        const e = this.ev;
        return [e && e.location, this.data && 'Hosts: ' + this.data.hosts.join(', ')].filter(Boolean).join(' · ');
    }
    get invitees() {
        return ((this.data && this.data.invitees) || []).map((r) => ({
            ...r,
            statusCls: STATUS_CLASS[r.status] || 'chip wait',
            indCls: industryClass(r.industry),
            canResend: this.canEdit && !STATUS_CLASS[r.status] && r.status !== 'Invite List' && r.status !== 'Invitation Queued',
            resending: this.busyId === r.memberId
        }));
    }

    async resend(event) {
        const id = event.currentTarget.dataset.id;
        this.busyId = id;
        try {
            const message = await resendInvite({ campaignMemberId: id });
            this.dispatchEvent(new ShowToastEvent({ title: 'Invite resent', message, variant: 'success' }));
            await this.load();
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not resend', message: errorMessage(e), variant: 'error' }));
        } finally {
            this.busyId = null;
        }
    }

    openCampaign() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.campaignId, actionName: 'view' } });
    }

    close() { this.dispatchEvent(new CustomEvent('close')); }
}