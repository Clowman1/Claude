import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPartner from '@salesforce/apex/InfluencerPartnersController.getPartner';
import setStage from '@salesforce/apex/InfluencerPartnersController.setStage';
import reopen from '@salesforce/apex/InfluencerPartnersController.reopen';
import savePartner from '@salesforce/apex/InfluencerPartnersController.savePartner';
import logTouch from '@salesforce/apex/InfluencerPartnersController.logTouch';
import createLead from '@salesforce/apex/InfluencerPartnersController.createLead';
import { errorMessage, copyText, whenLabel } from 'c/bdUtils';

const KINDS = ['Call', 'Text', 'Email', 'Meeting', 'Note'];
const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const money = (v) => (v == null ? '—' : USD.format(v));

// Side workspace for one influencer partner: stage, details, intake link, touches, leads and loans.
export default class InfluencerPartnerPanel extends LightningElement {
    @api stages = [];
    @api channels = [];
    @api loanOfficers = [];
    _partnerId;
    detail;
    error;
    editing = false;
    form = {};
    busy = false;
    touching = false;
    kind = 'Call';
    touchNotes = '';
    leading = false;
    lead = {};
    modalError;

    @api
    get partnerId() { return this._partnerId; }
    set partnerId(value) {
        this._partnerId = value;
        this.editing = false;
        this.refresh();
    }

    @api
    async refresh() {
        if (!this._partnerId) return;
        this.error = null;
        try {
            this.detail = await getPartner({ accountId: this._partnerId });
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    get p() { return this.detail ? this.detail.partner : null; }
    get initials() {
        return this.p ? ((this.p.firstName || '').charAt(0) + (this.p.lastName || '').charAt(0)).toUpperCase() : '';
    }
    get isLost() { return this.p && this.p.stage === 'Lost'; }
    get stageOptions() { return this.stages.map((s) => ({ label: s, value: s })); }
    get channelOptions() { return this.channels.map((s) => ({ label: s, value: s })); }
    get loOptions() { return [{ label: '— None —', value: '' }].concat(this.loanOfficers.map((o) => ({ label: o.label, value: o.value }))); }
    get audienceLabel() { return this.p && this.p.audience ? Number(this.p.audience).toLocaleString('en-US') : '—'; }
    get feeLabel() { return this.p && this.p.monthlyFee != null ? money(this.p.monthlyFee) + ' / month' : '—'; }
    get lostLine() { return this.isLost ? 'Lost from ' + (this.p.lostFrom || '?') + ' · ' + (this.p.lostReason || '') : null; }
    get touchLine() {
        if (!this.p) return '';
        return this.p.lastTouch ? 'Last touch ' + whenLabel(this.p.lastTouch) + ' · ' + this.p.daysQuiet + 'd ago' : 'No touches yet';
    }
    get touchCls() { return 'sm ' + (this.p && this.p.needsTouch ? 'warn' : 'muted'); }
    get r() {
        const r = this.detail ? this.detail.results : null;
        if (!r) return null;
        return {
            ...r, volumeLabel: money(r.volume), costLabel: r.cost ? money(r.cost) : '—',
            cplLabel: r.costPerClosed != null ? money(r.costPerClosed) : '—', convLabel: r.conversion == null ? '—' : r.conversion + '%'
        };
    }
    get timeline() {
        return (this.detail ? this.detail.timeline : []).slice(0, 40).map((t) => ({
            ...t, when: whenLabel(t.whenAt), dotCls: 'dot dot-' + (t.kind || '').toLowerCase()
        }));
    }
    get hasTimeline() { return this.timeline.length > 0; }
    get leads() {
        return (this.detail ? this.detail.leads : []).slice(0, 25).map((l) => ({ ...l, url: '/lightning/r/Lead/' + l.id + '/view' }));
    }
    get hasLeads() { return this.leads.length > 0; }
    get loans() {
        return (this.detail ? this.detail.loans : []).slice(0, 25).map((l) => ({ ...l, url: '/lightning/r/Transaction__c/' + l.id + '/view', amountLabel: money(l.amount) }));
    }
    get hasLoans() { return this.loans.length > 0; }

    close() { this.dispatchEvent(new CustomEvent('close')); }
    changed() { this.dispatchEvent(new CustomEvent('changed')); }

    async pickStage(event) {
        const stage = event.detail.value;
        if (stage === this.p.stage) return;
        if (stage === 'Lost') {
            // Parent owns the reason dialog; re-render resets this combobox to the real stage.
            this.dispatchEvent(new CustomEvent('lost', { detail: { id: this.p.id } }));
            this.detail = { ...this.detail };
            return;
        }
        await this.run(() => setStage({ accountId: this.p.id, stage, lostReason: null }), 'Moved to ' + stage);
    }
    async doReopen() { await this.run(() => reopen({ accountId: this.p.id }), 'Reopened'); }

    async copyCode() {
        const ok = await copyText(this.p.code);
        this.toast(ok ? 'Partner code copied' : 'Copy failed', ok ? this.p.code : 'Select and copy the code instead.', ok ? 'success' : 'error');
    }

    // -------------------------------------------------- edit details
    startEdit() {
        const p = this.p;
        this.form = {
            firstName: p.firstName, lastName: p.lastName, email: p.email, phone: p.phone, channel: p.channel,
            channelUrl: p.channelUrl, audience: p.audience, offerWebsite: p.offerWebsite, loId: p.loId || '',
            code: p.code, agreementDate: p.agreementDate, monthlyFee: p.monthlyFee, notes: p.notes
        };
        this.modalError = null;
        this.editing = true;
    }
    cancelEdit() { this.editing = false; }
    handleForm(event) {
        const field = event.target.dataset.field;
        let value = event.detail.value !== undefined ? event.detail.value : event.target.value;
        if ((field === 'audience' || field === 'monthlyFee') && (value === '' || value == null)) value = null;
        this.form = { ...this.form, [field]: value };
    }
    get codeHelp() {
        return this.p && this.p.codeLocked ? 'Locked: leads have already come in with this code.' : 'Editable until the first lead arrives.';
    }
    async saveEdit() {
        const f = this.form;
        const input = {
            ...f, id: this.p.id, loId: f.loId || null,
            audience: f.audience == null ? null : Number(f.audience),
            monthlyFee: f.monthlyFee == null ? null : Number(f.monthlyFee),
            agreementDate: f.agreementDate || null
        };
        this.modalError = null;
        this.busy = true;
        try {
            await savePartner({ input });
            this.editing = false;
            await this.refresh();
            this.changed();
            this.toast('Saved', null, 'success');
        } catch (e) {
            this.modalError = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }

    // -------------------------------------------------- log touch
    get kindButtons() { return KINDS.map((k) => ({ value: k, cls: 'pill' + (k === this.kind ? ' pill-on' : '') })); }
    get isNote() { return this.kind === 'Note'; }
    openTouch() { this.touching = true; this.kind = 'Call'; this.touchNotes = ''; this.modalError = null; }
    closeTouch() { if (!this.busy) this.touching = false; }
    pickKind(event) { this.kind = event.currentTarget.dataset.value; }
    handleTouchNotes(event) { this.touchNotes = event.target.value; }
    async saveTouch() {
        const ok = await this.run(() => logTouch({ accountId: this.p.id, kind: this.kind, notes: this.touchNotes }), this.isNote ? 'Note saved' : 'Touch logged');
        if (ok) this.touching = false;
    }

    // -------------------------------------------------- new lead
    openLead() { this.leading = true; this.lead = {}; this.modalError = null; }
    closeLead() { if (!this.busy) this.leading = false; }
    handleLead(event) { this.lead = { ...this.lead, [event.target.dataset.field]: event.target.value }; }
    async saveLead() {
        const l = this.lead;
        const ok = await this.run(() => createLead({
            accountId: this.p.id, firstName: l.firstName, lastName: l.lastName, phone: l.phone || null, email: l.email || null, notes: l.notes || null
        }), 'Lead created');
        if (ok) this.leading = false;
    }

    async run(fn, success) {
        this.busy = true;
        this.modalError = null;
        try {
            await fn();
            await this.refresh();
            this.changed();
            this.toast(success, null, 'success');
            return true;
        } catch (e) {
            this.modalError = errorMessage(e);
            if (!this.touching && !this.leading) this.toast('Something went wrong', this.modalError, 'error');
            return false;
        } finally {
            this.busy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
