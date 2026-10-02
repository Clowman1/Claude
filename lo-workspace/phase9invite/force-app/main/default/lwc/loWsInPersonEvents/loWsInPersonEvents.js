import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLoInviteHome from '@salesforce/apex/BdCommandCenterController.getLoInviteHome';
import { errorMessage, eventRow } from 'c/bdUtils';
import { isExperienceCloudContext } from 'c/portalUtils';

/**
 * LO Workspace: Fred's BD "Schedule invite" + "Upcoming" card, relabelled for outside LOs.
 * Reuses bdInviteModal / bdUpcomingCard / bdEventTracker; the server limits the partners to the
 * LO's own tags and owned partners and the events to ones they host. Never runs in the portal.
 * Parents call openInvite() from their own header button.
 */
export default class LoWsInPersonEvents extends NavigationMixin(LightningElement) {
    @api hideCard = false;
    data;
    error;
    inviteFor;   // array of partner ids while the modal is open
    trackerId;
    inPortal = isExperienceCloudContext();

    connectedCallback() {
        if (!this.inPortal) this.load();
    }

    async load() {
        try {
            this.data = await getLoInviteHome();
            this.error = null;
        } catch (e) {
            this.data = null;
            this.error = errorMessage(e);
        }
    }

    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message }));
    }

    get showCard() { return !this.hideCard && !!this.data; }
    get upcoming() { return this.data ? this.data.upcoming.map((e) => eventRow(e)) : []; }
    get partners() { return this.data ? this.data.partners.map((p) => ({ id: p.id, name: p.name, company: p.company })) : []; }
    get showInvite() { return Array.isArray(this.inviteFor); }

    @api
    openInvite() {
        if (this.inPortal) return;
        if (!this.data) {
            this.toast('In Person Invite is not available', 'error', this.error || 'Still loading. Try again in a moment.');
            return;
        }
        this.inviteFor = [];
    }

    closeInvite() { this.inviteFor = null; }
    async inviteSent(event) {
        this.inviteFor = null;
        this.toast('Invites queued', 'success', 'Emails go out first, then the texts. RSVPs update here automatically.');
        await this.load();
        this.trackerId = event.detail.campaignId;
    }

    openTracker(event) { this.trackerId = event.detail.campaignId; }
    closeTracker() {
        this.trackerId = null;
        this.load();
    }

    openCalendar() {
        this[NavigationMixin.Navigate]({ type: 'standard__objectPage', attributes: { objectApiName: 'Event', actionName: 'home' } });
    }
}
