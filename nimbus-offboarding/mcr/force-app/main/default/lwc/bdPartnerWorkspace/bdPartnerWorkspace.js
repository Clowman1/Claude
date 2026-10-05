import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPartner from '@salesforce/apex/BdCommandCenterController.getPartner';
import setStage from '@salesforce/apex/BdCommandCenterController.setStage';
import setIndustry from '@salesforce/apex/BdCommandCenterController.setIndustry';
import createReferralLead from '@salesforce/apex/BdCommandCenterController.createReferralLead';
import { industryClass, errorMessage, whenLabel, dayParts, copyText } from 'c/bdUtils';

const KIND_ICON = {
    call: 'utility:call', text: 'utility:sms', email: 'utility:email', meeting: 'utility:event',
    event: 'utility:event', touch: 'utility:touch_action', note: 'utility:note'
};
const KIND_CLASS = { call: 'dot g', text: 'dot b', email: 'dot b', meeting: 'dot o', event: 'dot o', touch: 'dot g', note: 'dot n' };

export default class BdPartnerWorkspace extends NavigationMixin(LightningElement) {
    @api repId;
    @api canEdit = false;
    @api stages = [];
    @api industries = [];

    _partnerId;
    @api
    get partnerId() { return this._partnerId; }
    set partnerId(value) {
        if (value !== this._partnerId) {
            this._partnerId = value;
            this.tab = 'timeline';
            this.load();
        }
    }

    detail;
    loading = false;
    error;
    tab = 'timeline';
    showTouch = false;
    showLead = false;
    lead = {};
    busy = false;

    async load() {
        if (!this._partnerId) return;
        this.loading = true;
        this.error = null;
        try {
            this.detail = await getPartner({ accountId: this._partnerId, repId: this.repId });
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    get p() { return this.detail ? this.detail.partner : null; }
    get industryCls() { return industryClass(this.p && this.p.industry); }
    get subLine() {
        const p = this.p;
        return p ? [p.company, p.phone, p.email].filter(Boolean).join(' · ') : '';
    }
    get lastTouchLabel() {
        const p = this.p;
        if (!p) return '';
        if (!p.lastTouch) return 'Never';
        return p.daysQuiet === 0 ? 'Today' : p.daysQuiet + (p.daysQuiet === 1 ? ' day ago' : ' days ago');
    }
    get quietCls() { return this.p && this.p.needsTouch ? 'warn' : ''; }

    get stageSteps() {
        const p = this.p;
        if (!p) return [];
        const shown = (this.stages || []).filter((s) => s !== 'Dormant');
        const at = shown.indexOf(p.stage);
        return shown.map((s, i) => ({
            value: s,
            barCls: 'step' + (at >= 0 && i <= at ? ' on' : ''),
            labelCls: 'steplbl' + (s === p.stage ? ' cur' : '')
        }));
    }
    get isDormant() { return this.p && this.p.stage === 'Dormant'; }
    get stageOptions() { return (this.stages || []).map((s) => ({ label: s, value: s })); }
    get industryOptions() { return (this.industries || []).map((s) => ({ label: s, value: s })); }

    get timeline() {
        return ((this.detail && this.detail.timeline) || []).map((t) => ({
            ...t, icon: KIND_ICON[t.kind] || 'utility:record', dotCls: KIND_CLASS[t.kind] || 'dot n', when: whenLabel(t.whenAt)
        }));
    }
    get hasTimeline() { return this.timeline.length > 0; }
    get leads() { return (this.detail && this.detail.referredLeads) || []; }
    get hasLeads() { return this.leads.length > 0; }
    get leadCount() { return this.leads.length; }
    get nextEvent() {
        const e = this.detail && this.detail.nextEvent;
        if (!e) return null;
        const d = dayParts(e.startDate);
        return { ...e, when: d.label + (e.timeLabel ? ' · ' + e.timeLabel : '') };
    }

    get isTimeline() { return this.tab === 'timeline'; }
    get isRingSense() { return this.tab === 'ringsense'; }
    get isActivity() { return this.tab === 'activity'; }
    get activityTabCls() { return 'tab' + (this.isActivity ? ' tab-on' : ''); }
    showActivity() { this.tab = 'activity'; }
    get isLeads() { return this.tab === 'leads'; }
    get timelineTabCls() { return 'tab' + (this.isTimeline ? ' tab-on' : ''); }
    get ringSenseTabCls() { return 'tab' + (this.isRingSense ? ' tab-on' : ''); }
    get leadsTabCls() { return 'tab' + (this.isLeads ? ' tab-on' : ''); }
    showTimeline() {
        if (this.tab === 'activity') this.load();
        this.tab = 'timeline';
    }
    showRingSense() { this.tab = 'ringsense'; }
    showLeads() { this.tab = 'leads'; }

    // ------------------------------------------------ edits

    async changeStage(event) {
        await this.save(() => setStage({ accountId: this._partnerId, stage: event.detail.value }), 'Stage updated');
    }

    async changeIndustry(event) {
        await this.save(() => setIndustry({ accountId: this._partnerId, industry: event.detail.value }), 'Industry updated');
    }

    openTouch() { this.showTouch = true; }
    closeTouch() { this.showTouch = false; }
    async touchLogged() {
        this.showTouch = false;
        await this.load();
        this.dispatchEvent(new CustomEvent('changed'));
    }

    openLead() { this.showLead = true; this.lead = {}; }
    closeLead() { this.showLead = false; }
    handleLead(event) { this.lead = { ...this.lead, [event.target.dataset.field]: event.target.value }; }
    get leadDisabled() {
        return this.busy || !this.lead.firstName || !this.lead.lastName || (!this.lead.phone && !this.lead.email);
    }
    async saveLead() {
        const ok = await this.save(() => createReferralLead({
            accountId: this._partnerId, firstName: this.lead.firstName, lastName: this.lead.lastName,
            phone: this.lead.phone, email: this.lead.email, notes: this.lead.notes
        }), 'Lead created and routed');
        if (ok) { this.showLead = false; this.tab = 'leads'; }
    }

    async save(action, message) {
        this.busy = true;
        try {
            await action();
            this.dispatchEvent(new ShowToastEvent({ title: message, variant: 'success' }));
            await this.load();
            this.dispatchEvent(new CustomEvent('changed'));
            return true;
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not save', message: errorMessage(e), variant: 'error' }));
            return false;
        } finally {
            this.busy = false;
        }
    }

    selectAll(event) { event.target.select(); }
    async copyIntake() {
        const ok = await copyText(this.p.intakeUrl);
        this.dispatchEvent(new ShowToastEvent({
            title: ok ? 'Intake link copied' : 'Copy failed: select the link and copy it',
            variant: ok ? 'success' : 'warning'
        }));
    }

    invite() {
        this.dispatchEvent(new CustomEvent('invite', { detail: { partnerId: this._partnerId } }));
    }

    openEvent() {
        this.dispatchEvent(new CustomEvent('openevent', { detail: { campaignId: this.detail.nextEvent.campaignId } }));
    }

    openRecord(event) {
        const id = event.currentTarget.dataset.id || this._partnerId;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }

    back() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}