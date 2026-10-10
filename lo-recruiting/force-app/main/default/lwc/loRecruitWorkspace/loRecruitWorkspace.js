import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getRecruit from '@salesforce/apex/LoRecruitingController.getRecruit';
import setStage from '@salesforce/apex/LoRecruitingController.setStage';
import setNextTouch from '@salesforce/apex/LoRecruitingController.setNextTouch';
import setRecruiter from '@salesforce/apex/LoRecruitingController.setRecruiter';
import markHired from '@salesforce/apex/LoRecruitingController.markHired';
import addNote from '@salesforce/apex/LoRecruitingController.addNote';
import { errorMessage, whenLabel, localDate } from 'c/bdUtils';

const KIND_ICON = {
    call: 'utility:call', text: 'utility:sms', email: 'utility:email', meeting: 'utility:event', touch: 'utility:touch_action', note: 'utility:note'
};
const KIND_CLASS = { call: 'dot g', text: 'dot b', email: 'dot b', meeting: 'dot o', touch: 'dot g', note: 'dot n' };
function volumeLabel(volume, period) {
    if (volume == null) return '';
    const m = volume / 1000000;
    return '$' + (m >= 10 ? m.toFixed(0) : m.toFixed(1)) + 'M' + (period ? ' · ' + period : '');
}
const PATH = ['New', 'Contacted', 'Conversation', 'Meeting Set', 'Met', 'Offer Out', 'Hired'];

export default class LoRecruitWorkspace extends NavigationMixin(LightningElement) {
    @api stages = [];
    @api recruiters = [];
    @api repFirstName;

    _recruitId;
    @api
    get recruitId() { return this._recruitId; }
    set recruitId(value) {
        if (value !== this._recruitId) {
            this._recruitId = value;
            this.tab = 'timeline';
            this.load();
        }
    }

    detail;
    loading = false;
    error;
    tab = 'timeline';
    showTouch = false;
    busy = false;

    async load() {
        if (!this._recruitId) return;
        this.loading = true;
        this.error = null;
        try {
            this.detail = await getRecruit({ leadId: this._recruitId });
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    get r() { return this.detail ? this.detail.recruit : null; }
    get subLine() {
        const r = this.r;
        return r ? [r.company, r.nmls ? 'NMLS ' + r.nmls : null, volumeLabel(r.volume, r.volumePeriod)].filter(Boolean).join(' · ') : '';
    }
    get dialPhone() { return this.r && (this.r.mobile || this.r.phone); }
    get smsHref() { return this.dialPhone ? 'sms:' + this.dialPhone.replace(/\D/g, '') : null; }
    get mailHref() { return this.r && this.r.email ? 'mailto:' + this.r.email : null; }
    get stageChipCls() {
        const s = this.r && this.r.stage;
        return 'chip ' + (s === 'Hired' ? 'yes' : s === 'Not Interested' ? 'no' : s === 'Not Now' ? 'oth' : 're');
    }
    get isHired() { return this.r && this.r.stage === 'Hired'; }
    get isOpen() { return !this.isHired; }

    get pathSteps() {
        const at = PATH.indexOf(this.r ? this.r.stage : '');
        return PATH.map((s, i) => ({ value: s, barCls: 'step' + (at >= 0 && i <= at ? ' on' : ''), labelCls: 'steplbl' + (i === at ? ' cur' : '') }));
    }
    get offPath() { return this.r && PATH.indexOf(this.r.stage) < 0; }
    get offPathNote() {
        return this.r && this.r.stage === 'Not Now'
            ? 'Not Now: back in the Due list on the next touch date.'
            : 'Not Interested: marked Do Not Call and email opt-out.';
    }

    get links() {
        const d = this.detail;
        if (!d) return [];
        return [['LinkedIn', d.linkedIn], ['Instagram', d.instagram], ['Website', d.website], ['RETR profile', d.retr]]
            .filter((pair) => pair[1]).map((pair) => ({ label: pair[0], url: pair[1] }));
    }
    get hasLinks() { return this.links.length > 0; }
    get office() {
        const d = this.detail;
        if (!d) return '';
        return [d.street, [this.r.city, d.state].filter(Boolean).join(', '), d.zip].filter(Boolean).join(' · ');
    }
    get agentLine() {
        const d = this.detail;
        return d && d.agentPartner ? d.agentPartner + (d.agentCompany ? ' · ' + d.agentCompany : '') : '';
    }
    get lastActivityLabel() {
        const d = localDate(this.r && this.r.lastActivity);
        return d ? d.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' }) : 'None';
    }

    get stageOptions() { return (this.stages || []).filter((s) => s !== 'Hired').map((s) => ({ label: s, value: s })); }
    get recruiterOptions() { return (this.recruiters || []).map((o) => ({ label: o.label, value: o.value })); }

    get timeline() {
        return ((this.detail && this.detail.timeline) || []).map((t) => ({
            ...t, icon: KIND_ICON[t.kind] || 'utility:record', dotCls: KIND_CLASS[t.kind] || 'dot n', when: whenLabel(t.whenAt)
        }));
    }
    get hasTimeline() { return this.timeline.length > 0; }

    get isTimeline() { return this.tab === 'timeline'; }
    get isZoom() { return this.tab === 'zoom'; }
    get isRingSense() { return this.tab === 'ringsense'; }
    get isDetails() { return this.tab === 'details'; }
    get isNotes() { return this.tab === 'notes'; }
    get notesTabCls() { return this.tabCls('notes'); }

    // ------------------------------------------------ recruiting notes

    noteDraft = '';
    get notes() { return ((this.detail && this.detail.notes) || []).map((n) => ({ ...n, when: whenLabel(n.whenAt) })); }
    get hasNotes() { return this.notes.length > 0; }
    get noteCount() { return this.notes.length; }
    get noteDisabled() { return this.busy || !(this.noteDraft || '').trim(); }
    handleNoteDraft(event) { this.noteDraft = event.target.value; }
    async saveNote() {
        if (await this.save(() => addNote({ leadId: this._recruitId, body: this.noteDraft }), 'Note saved')) this.noteDraft = '';
    }
    tabCls(name) { return 'tab' + (this.tab === name ? ' tab-on' : ''); }
    get timelineTabCls() { return this.tabCls('timeline'); }
    get zoomTabCls() { return this.tabCls('zoom'); }
    get ringSenseTabCls() { return this.tabCls('ringsense'); }
    get detailsTabCls() { return this.tabCls('details'); }
    showTab(event) {
        const next = event.currentTarget.dataset.tab;
        if (this.tab === 'zoom' && next === 'timeline') this.load();
        this.tab = next;
    }

    // ------------------------------------------------ edits

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

    changeStage(event) { return this.save(() => setStage({ leadId: this._recruitId, stage: event.detail.value }), 'Stage updated'); }
    changeNext(event) { return this.save(() => setNextTouch({ leadId: this._recruitId, nextTouch: event.target.value || null }), 'Next touch updated'); }
    changeRecruiter(event) { return this.save(() => setRecruiter({ leadId: this._recruitId, userId: event.detail.value }), 'Recruiter changed'); }

    async notInterested() {
        const ok = await LightningConfirm.open({
            message: 'Mark ' + this.r.name + ' Not Interested? This also sets Do Not Call and email opt-out on the lead.',
            label: 'Not Interested', theme: 'warning'
        });
        if (ok) await this.save(() => setStage({ leadId: this._recruitId, stage: 'Not Interested' }), 'Marked Not Interested');
    }

    async hired() {
        const ok = await LightningConfirm.open({
            message: 'Mark ' + this.r.name + ' as Hired? This creates their Candidate account and starts the onboarding checklist.',
            label: 'Mark Hired', theme: 'success'
        });
        if (ok) await this.save(() => markHired({ leadId: this._recruitId }), 'Hired: Candidate account created');
    }

    meetingScheduled() {
        this.load();
        this.dispatchEvent(new CustomEvent('changed'));   // the home reload auto-moves them to Meeting Set
    }

    // In person meeting: the BD Coffee / Lunch / Happy Hour scheduler, inviting this recruit (scope "recruit").
    showInvite = false;
    get invitePartners() { return this.r ? [{ id: this.r.id, name: this.r.name, company: this.r.company }] : []; }
    get inviteIds() { return this.r ? [this.r.id] : []; }
    openInvite() { this.showInvite = true; }
    closeInvite() { this.showInvite = false; }
    async inviteSent() {
        this.showInvite = false;
        this.dispatchEvent(new ShowToastEvent({ title: 'Invite sent', message: 'Email first, then a text. RSVPs show on the timeline.', variant: 'success' }));
        this.dispatchEvent(new CustomEvent('changed'));   // the home reload moves them to Meeting Set
        await this.load();
    }

    openTouch() { this.showTouch = true; }
    closeTouch() { this.showTouch = false; }
    async touchLogged() {
        this.showTouch = false;
        await this.load();
        this.dispatchEvent(new CustomEvent('changed'));
    }

    openRecord(event) {
        const id = event.currentTarget.dataset.id || this._recruitId;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }
}
