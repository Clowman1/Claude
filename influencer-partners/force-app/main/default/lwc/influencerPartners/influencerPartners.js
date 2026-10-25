import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHome from '@salesforce/apex/InfluencerPartnersController.getHome';
import getLeads from '@salesforce/apex/InfluencerPartnersController.getLeads';
import getLoans from '@salesforce/apex/InfluencerPartnersController.getLoans';
import getResults from '@salesforce/apex/InfluencerPartnersController.getResults';
import setStage from '@salesforce/apex/InfluencerPartnersController.setStage';
import findDuplicates from '@salesforce/apex/InfluencerPartnersController.findDuplicates';
import createPartner from '@salesforce/apex/InfluencerPartnersController.createPartner';
import addExisting from '@salesforce/apex/InfluencerPartnersController.addExisting';
import { errorMessage } from 'c/bdUtils';
import { money, num, pct, shortDate, recordUrl, stageClass } from './format';

const VIEWS = [
    { value: 'pipeline', label: 'Pipeline' },
    { value: 'leads', label: 'Leads' },
    { value: 'loans', label: 'Loans' },
    { value: 'results', label: 'Results' }
];
const RANGES = [
    { value: 'MONTH', label: 'This month' },
    { value: 'QUARTER', label: 'This quarter' },
    { value: 'YTD', label: 'YTD' },
    { value: 'ALL', label: 'All time' }
];

// Influencer Partners pipeline. Its own tab, and embedded (embedded=true) in Ernesto's Marketing Command Center.
export default class InfluencerPartners extends LightningElement {
    @api embedded = false;
    home;
    loading = true;
    error;
    view = 'pipeline';
    selectedId;
    showLost = false;
    dragId;
    overStage;

    leads;
    loans;
    results;
    range = 'YTD';
    leadPartner = '';
    leadStatus = '';
    loanPartner = '';
    loanStatus = '';

    lostFor;
    lostReason = '';
    adding = false;
    add = {};
    dupes = [];
    busy = false;
    modalError;

    connectedCallback() { this.load(); }

    async load() {
        this.error = null;
        try {
            this.home = await getHome();
            if (this.view !== 'pipeline') await this.loadView();
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    async loadView() {
        try {
            if (this.view === 'leads') this.leads = await getLeads();
            if (this.view === 'loans') this.loans = await getLoans();
            if (this.view === 'results') this.results = await getResults({ range: this.range });
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    // ------------------------------------------------------------ header + nav
    get shellClass() { return this.embedded ? 'shell embedded' : 'shell'; }
    get navItems() { return VIEWS.map((v) => ({ ...v, cls: 'nav' + (v.value === this.view ? ' nav-on' : '') })); }
    get isPipeline() { return this.view === 'pipeline'; }
    get isLeads() { return this.view === 'leads'; }
    get isLoans() { return this.view === 'loans'; }
    get isResults() { return this.view === 'results'; }
    pickView(event) {
        this.view = event.currentTarget.dataset.value;
        this.loadView();
    }

    get partners() { return this.home ? this.home.partners : []; }
    get stats() {
        const p = this.partners;
        const leads = p.reduce((s, x) => s + x.leads, 0);
        const closed = p.reduce((s, x) => s + x.closed, 0);
        const volume = p.reduce((s, x) => s + (x.volume || 0), 0);
        return {
            partners: p.filter((x) => x.stage !== 'Lost').length,
            active: this.home ? this.home.active : 0,
            needsTouch: this.home ? this.home.needsTouch : 0,
            leads, closed, volume: money(volume)
        };
    }

    // ------------------------------------------------------------ pipeline board
    get columns() {
        if (!this.home) return [];
        return this.home.stages
            .filter((s) => s !== 'Lost' || this.showLost)
            .map((stage) => {
                const cards = this.partners.filter((p) => p.stage === stage).map((p) => ({
                    ...p,
                    cls: 'kcard' + (p.id === this.selectedId ? ' kcard-sel' : ''),
                    audienceLabel: p.audience ? num(p.audience) + ' followers' : null,
                    quiet: p.needsTouch ? p.daysQuiet + 'd quiet' : null,
                    production: p.leads ? p.leads + ' leads · ' + p.closed + ' closed' : null
                }));
                return {
                    stage, cards, count: cards.length,
                    cls: 'col' + (stage === 'Lost' ? ' col-dim' : '') + (stage === this.overStage ? ' col-over' : ''),
                    chip: stageClass(stage)
                };
            });
    }
    get lostCount() { return this.partners.filter((p) => p.stage === 'Lost').length; }
    get lostToggleLabel() { return (this.showLost ? 'Hide' : 'Show') + ' Lost (' + this.lostCount + ')'; }
    toggleLost() { this.showLost = !this.showLost; }

    openPartner(event) { this.selectedId = event.currentTarget.dataset.id; }
    closePartner() { this.selectedId = null; }
    get hasSelection() { return !!this.selectedId; }

    dragStart(event) {
        this.dragId = event.currentTarget.dataset.id;
        event.dataTransfer.setData('text/plain', this.dragId);
    }
    dragOver(event) {
        event.preventDefault();
        this.overStage = event.currentTarget.dataset.stage;
    }
    dragLeave() { this.overStage = null; }
    async drop(event) {
        event.preventDefault();
        const stage = event.currentTarget.dataset.stage;
        const id = this.dragId;
        this.overStage = null;
        this.dragId = null;
        const p = this.partners.find((x) => x.id === id);
        if (!p || p.stage === stage) return;
        if (stage === 'Lost') {
            this.askLost(id);
            return;
        }
        await this.moveStage(id, stage, null);
    }

    async moveStage(id, stage, reason) {
        try {
            await setStage({ accountId: id, stage, lostReason: reason });
            await this.load();
            this.refreshPanel();
        } catch (e) {
            this.toast('Could not move partner', errorMessage(e), 'error');
        }
    }

    refreshPanel() {
        const panel = this.template.querySelector('c-influencer-partner-panel');
        if (panel) panel.refresh();
    }

    // Panel events
    handleChanged() { this.load(); }
    handleLost(event) { this.askLost(event.detail.id); }

    // ------------------------------------------------------------ Lost dialog
    askLost(id) {
        this.lostFor = this.partners.find((p) => p.id === id);
        this.lostReason = '';
        this.modalError = null;
    }
    get lostOptions() { return (this.home ? this.home.lostReasons : []).map((v) => ({ label: v, value: v })); }
    pickLostReason(event) { this.lostReason = event.detail.value; }
    cancelLost() { this.lostFor = null; }
    async confirmLost() {
        if (!this.lostReason) {
            this.modalError = 'Pick a reason.';
            return;
        }
        const id = this.lostFor.id;
        this.lostFor = null;
        await this.moveStage(id, 'Lost', this.lostReason);
    }

    // ------------------------------------------------------------ Add partner
    get channelOptions() { return (this.home ? this.home.channels : []).map((v) => ({ label: v, value: v })); }
    get loOptions() { return [{ label: '— None —', value: '' }].concat((this.home ? this.home.loanOfficers : []).map((o) => ({ label: o.label, value: o.value }))); }
    get hasDupes() { return this.dupes.length > 0; }
    openAdd() {
        this.adding = true;
        this.add = {};
        this.dupes = [];
        this.modalError = null;
    }
    closeAdd() { if (!this.busy) this.adding = false; }
    handleAdd(event) {
        const field = event.target.dataset.field;
        let value = event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (field === 'audience') value = value === '' || value == null ? null : Number(value);
        this.add = { ...this.add, [field]: value };
    }
    async checkDupes() {
        if (!this.add.email && !this.add.phone) return;
        try {
            this.dupes = (await findDuplicates({ email: this.add.email || null, phone: this.add.phone || null }))
                .map((d) => ({ ...d, label: d.alreadyPartner ? 'Already a partner' : 'Select' }));
        } catch (e) {
            this.dupes = [];
        }
    }
    input() {
        const a = this.add;
        return {
            firstName: a.firstName, lastName: a.lastName, email: a.email, phone: a.phone,
            channel: a.channel, channelUrl: a.channelUrl, audience: a.audience, offerWebsite: a.offerWebsite,
            loId: a.loId || null
        };
    }
    async useExisting(event) {
        const id = event.currentTarget.dataset.id;
        const d = this.dupes.find((x) => x.id === id);
        this.busy = true;
        try {
            if (!d.alreadyPartner) await addExisting({ accountId: id, input: this.input() });
            this.adding = false;
            await this.load();
            this.view = 'pipeline';
            this.selectedId = id;
        } catch (e) {
            this.modalError = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }
    async saveAdd() {
        this.busy = true;
        this.modalError = null;
        try {
            const id = await createPartner({ input: this.input() });
            this.adding = false;
            await this.load();
            this.view = 'pipeline';
            this.selectedId = id;
            this.toast('Partner added', 'Added at Target.', 'success');
        } catch (e) {
            this.modalError = errorMessage(e);
            await this.checkDupes();
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------------------ Leads / Loans tables
    get partnerFilterOptions() {
        return [{ label: 'All partners', value: '' }]
            .concat(this.partners.map((p) => ({ label: p.name, value: p.id })))
            .concat([{ label: 'No partner', value: 'none' }]);
    }
    statusOptions(rows) {
        const set = [...new Set((rows || []).map((r) => r.status).filter(Boolean))].sort();
        return [{ label: 'All statuses', value: '' }].concat(set.map((s) => ({ label: s, value: s })));
    }
    matches(row, partner, status) {
        if (partner === 'none' && row.partnerId) return false;
        if (partner && partner !== 'none' && row.partnerId !== partner) return false;
        return !status || row.status === status;
    }
    get leadStatusOptions() { return this.statusOptions(this.leads); }
    get leadRows() {
        return (this.leads || []).filter((r) => this.matches(r, this.leadPartner, this.leadStatus)).map((r) => ({
            ...r, url: recordUrl('Lead', r.id), createdLabel: shortDate(r.created),
            preLabel: shortDate(r.preApprovalDate), convertedLabel: r.converted ? 'Yes' : ''
        }));
    }
    get leadCount() { return this.leadRows.length; }
    get noLeads() { return !!this.leads && this.leadRows.length === 0; }
    get loanStatusOptions() { return this.statusOptions(this.loans); }
    get loanRows() {
        return (this.loans || []).filter((r) => this.matches(r, this.loanPartner, this.loanStatus)).map((r) => ({
            ...r, url: recordUrl('Transaction__c', r.id), amountLabel: money(r.amount),
            closedLabel: shortDate(r.closedDate), createdLabel: shortDate(r.created)
        }));
    }
    get loanCount() { return this.loanRows.length; }
    get noLoans() { return !!this.loans && this.loanRows.length === 0; }
    get loanVolume() {
        return money(this.loanRows.filter((r) => r.status === 'Post-Closed').reduce((s, r) => s + (r.amount || 0), 0));
    }
    filter(event) {
        this[event.target.dataset.field] = event.detail.value;
    }

    // ------------------------------------------------------------ Results
    get rangeButtons() { return RANGES.map((r) => ({ ...r, cls: 'sg' + (r.value === this.range ? ' sg-on' : '') })); }
    async pickRange(event) {
        this.range = event.currentTarget.dataset.value;
        this.results = await getResults({ range: this.range });
    }
    row(r) {
        return {
            ...r, volumeLabel: money(r.volume), costLabel: r.cost ? money(r.cost) : '—',
            cplLabel: r.costPerClosed != null ? money(r.costPerClosed) : '—', convLabel: pct(r.conversion),
            chip: stageClass(r.stage)
        };
    }
    get total() { return this.results ? this.row(this.results.total) : null; }
    get leaderboard() {
        if (!this.results) return [];
        const max = Math.max(1, ...this.results.partners.map((p) => p.volume || 0));
        return this.results.partners
            .map((p) => this.row(p))
            .sort((a, b) => (b.volume - a.volume) || (b.closed - a.closed) || (b.leads - a.leads) || a.partnerName.localeCompare(b.partnerName))
            .map((p, i) => ({ ...p, rank: i + 1, barStyle: 'width:' + Math.round(((p.volume || 0) / max) * 100) + '%' }));
    }
    get noLeaderboard() { return !!this.results && this.leaderboard.length === 0; }
    openFromResults(event) {
        this.selectedId = event.currentTarget.dataset.id;
        this.view = 'pipeline';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
