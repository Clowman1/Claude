import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHome from '@salesforce/apex/BdCommandCenterController.getHome';
import confirmMeeting from '@salesforce/apex/BdCommandCenterController.confirmMeeting';
import linkCall from '@salesforce/apex/BdCommandCenterController.linkCall';
import { industryClass, errorMessage, duration, formatPhone, whenLabel, dayParts } from 'c/bdUtils';

const BAR_COLOR = { Realtor: '#244d8f', CPA: '#0f766e', 'Title Agent': '#6d28d9', 'Insurance Agent': '#c2690f' };

export default class BdCommandCenter extends NavigationMixin(LightningElement) {
    @api mode = 'home';

    home;
    loading = true;
    error;
    repId;
    view = 'today';
    layout = 'board';
    industryFilter = 'All';
    needsOnly = false;
    search = '';
    selectedPartnerId;
    showAdd = false;
    addPhone;
    inviteFor;           // array of partner ids, or null when closed
    trackerId;
    linkingTaskId;
    linkPartnerId;

    connectedCallback() { this.load(); }

    async load() {
        this.loading = !this.home;
        try {
            this.home = await getHome({ repId: this.repId });
            this.repId = this.home.repId;
            this.error = null;
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    reload() { return this.load(); }

    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message }));
    }

    // ------------------------------------------------ header

    get isOverview() { return this.mode === 'overview'; }
    get canEdit() { return this.home && this.home.canEdit; }
    get hasRep() { return this.home && this.home.repId; }
    get greeting() {
        const h = new Date().getHours();
        const part = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
        return this.isOverview ? 'BD Overview · ' + (this.home ? this.home.repName : '') : part + ', ' + (this.home ? this.home.repFirstName : '');
    }
    get todayLabel() {
        return new Date().toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
    }
    rcOpened = false;
    get showRcPrompt() { return this.canEdit && this.home.rcConnected === false && !!this.home.rcAuthUrl; }
    connectRc() {
        window.open(this.home.rcAuthUrl, '_blank');
        this.rcOpened = true;
    }

    get repOptions() { return ((this.home && this.home.reps) || []).map((r) => ({ label: r.name, value: r.id })); }
    get showRepPicker() { return this.home && this.home.isManager && this.repOptions.length > 0; }
    changeRep(event) {
        this.repId = event.detail.value;
        this.selectedPartnerId = null;
        this.home = null;
        this.load();
    }

    get navItems() {
        return [
            { value: 'today', label: 'Today' },
            { value: 'partners', label: 'Partners' },
            { value: 'events', label: 'Events' }
        ].map((n) => ({ ...n, cls: 'nav' + (n.value === this.view ? ' nav-on' : '') }));
    }
    pickView(event) {
        this.view = event.currentTarget.dataset.value;
        // Partners opens on the board unless a partner is being viewed.
        if (this.view === 'partners' && !this.selectedPartnerId) this.layout = 'board';
    }
    get isToday() { return this.view === 'today'; }
    get isPartners() { return this.view === 'partners'; }
    get isEvents() { return this.view === 'events'; }

    get s() { return this.home.stats; }
    get meetingsSub() {
        const kinds = {};
        (this.home.upcoming || []).concat(this.home.toConfirm || []).forEach((e) => { kinds[e.kind] = (kinds[e.kind] || 0) + 1; });
        return Object.keys(kinds).map((k) => kinds[k] + ' ' + k.toLowerCase()).join(' · ') || 'none scheduled';
    }

    // ------------------------------------------------ partners

    decorate(p) {
        return {
            ...p,
            chipCls: industryClass(p.industry),
            quietLabel: p.lastTouch ? (p.daysQuiet === 0 ? 'Touched today' : p.daysQuiet + ' days quiet') : 'No touch yet',
            quietCls: p.needsTouch ? 'warn qd' : 'muted qd',
            sub: [p.company, p.stage].filter(Boolean).join(' · '),
            rowCls: 'row clickable' + (p.id === this.selectedPartnerId ? ' sel' : '')
        };
    }

    get allPartners() { return ((this.home && this.home.partners) || []).map((p) => this.decorate(p)); }

    get needsTouch() {
        return this.allPartners
            .filter((p) => p.needsTouch && (this.industryFilter === 'All' || p.industry === this.industryFilter))
            .slice(0, 10);
    }
    get needsTouchCount() { return this.home ? this.home.stats.needsTouch : 0; }
    get hasNeedsTouch() { return this.needsTouch.length > 0; }

    get industryPills() {
        const by = (this.home && this.home.stats.byIndustry) || {};
        const pills = [{ value: 'All', label: 'All ' + ((this.home && this.home.stats.partners) || 0) }];
        ((this.home && this.home.industries) || []).forEach((i) => { if (by[i]) pills.push({ value: i, label: i + ' ' + by[i] }); });
        return pills.map((p) => ({ ...p, cls: 'pill' + (p.value === this.industryFilter ? ' pill-on' : '') }));
    }
    pickIndustry(event) { this.industryFilter = event.currentTarget.dataset.value; }
    get needsCls() { return 'pill' + (this.needsOnly ? ' pill-on' : ''); }
    toggleNeeds() { this.needsOnly = !this.needsOnly; }
    handleSearch(event) { this.search = event.target.value; }

    get filteredPartners() {
        const t = (this.search || '').trim().toLowerCase();
        return this.allPartners.filter((p) =>
            (this.industryFilter === 'All' || p.industry === this.industryFilter)
            && (!this.needsOnly || p.needsTouch)
            && (!t || [p.name, p.company, p.phone, p.email].some((v) => v && v.toLowerCase().includes(t))));
    }
    get hasPartners() { return this.filteredPartners.length > 0; }

    get isBoard() { return this.layout === 'board'; }
    get listBtnCls() { return 'sg' + (this.isBoard ? '' : ' sg-on'); }
    get boardBtnCls() { return 'sg' + (this.isBoard ? ' sg-on' : ''); }
    showList() { this.layout = 'list'; }
    showBoard() {
        this.selectedPartnerId = null;
        this.layout = 'board';
    }

    get columns() {
        const partners = this.filteredPartners;
        return ((this.home && this.home.stages) || []).map((stage) => {
            const cards = partners.filter((p) => p.stage === stage);
            return { stage, cards, count: cards.length, colCls: 'col' + (stage === 'Dormant' ? ' col-dim' : '') };
        });
    }

    openPartner(event) {
        this.selectedPartnerId = event.currentTarget.dataset.id;
        this.view = 'partners';
        this.layout = 'list';
    }
    closePartner() {
        this.selectedPartnerId = null;
        this.layout = 'board';
    }
    get hasSelection() { return !!this.selectedPartnerId; }

    // ------------------------------------------------ calls

    callRow(c) {
        const dir = c.kind === 'Text' ? (c.direction === 'Inbound' ? 'Text in' : 'Text out')
            : (c.direction || 'Call') + (c.seconds ? ' · ' + duration(c.seconds) : c.direction === 'Inbound' ? '' : ' · no answer');
        return {
            ...c,
            dirLabel: dir,
            dirCls: 'chip ' + (c.kind === 'Text' ? 'oth' : c.direction === 'Inbound' ? 're' : c.seconds ? 'yes' : 'oth'),
            when: whenLabel(c.whenAt),
            numberLabel: formatPhone(c.phoneNumber)
        };
    }
    get calls() { return ((this.home && this.home.calls) || []).slice(0, 8).map((c) => this.callRow(c)); }
    get hasCalls() { return this.calls.length > 0; }
    get unmatched() {
        return ((this.home && this.home.unmatchedCalls) || []).map((c) => ({ ...this.callRow(c), linking: c.taskId === this.linkingTaskId }));
    }
    get hasUnmatched() { return this.canEdit && this.unmatched.length > 0; }
    get partnerOptions() { return this.allPartners.map((p) => ({ label: p.name + (p.company ? ' · ' + p.company : ''), value: p.id })); }

    startLink(event) { this.linkingTaskId = event.currentTarget.dataset.id; this.linkPartnerId = null; }
    cancelLink() { this.linkingTaskId = null; }
    get linkDisabled() { return !this.linkPartnerId; }
    pickLinkPartner(event) { this.linkPartnerId = event.detail.value; }
    async saveLink() {
        try {
            await linkCall({ taskId: this.linkingTaskId, accountId: this.linkPartnerId });
            this.linkingTaskId = null;
            this.toast('Call linked', 'success');
            await this.reload();
        } catch (e) {
            this.toast('Could not link the call', 'error', errorMessage(e));
        }
    }
    addFromCall(event) {
        this.addPhone = formatPhone(event.currentTarget.dataset.number);
        this.showAdd = true;
    }

    // ------------------------------------------------ events

    eventRow(e) {
        const d = dayParts(e.startDate);
        return {
            ...e, dow: d.dow, day: d.day,
            when: (e.timeLabel || '') + (e.location ? ' · ' + e.location : ''),
            who: e.partnerNames.join(', ') + (e.invited > e.partnerNames.length ? ' +' + (e.invited - e.partnerNames.length) : ''),
            rsvp: e.attending + ' attending · ' + e.awaiting + ' awaiting' + (e.declined ? ' · ' + e.declined + ' declined' : ''),
            boxCls: 'ev ' + (e.awaiting === 0 && e.attending > 0 ? 'ev-ok' : 'ev-wait')
        };
    }
    get upcoming() { return ((this.home && this.home.upcoming) || []).map((e) => this.eventRow(e)); }
    get hasUpcoming() { return this.upcoming.length > 0; }
    get toConfirm() { return ((this.home && this.home.toConfirm) || []).map((e) => this.eventRow(e)); }
    get hasToConfirm() { return this.canEdit && this.toConfirm.length > 0; }

    async answerMeeting(event) {
        const { id, held } = event.currentTarget.dataset;
        try {
            await confirmMeeting({ campaignId: id, held: held === 'yes' });
            this.toast(held === 'yes' ? 'Marked as held. Attendees moved to Met.' : 'Marked as did not happen', 'success');
            await this.reload();
        } catch (e) {
            this.toast('Could not save', 'error', errorMessage(e));
        }
    }

    logTouchFor;
    openLogTouch(event) {
        this.logTouchFor = { id: event.currentTarget.dataset.id, name: event.currentTarget.dataset.name };
    }
    closeLogTouch() { this.logTouchFor = null; }
    touchLogged() {
        this.logTouchFor = null;
        this.reload();
    }

    openTracker(event) { this.trackerId = event.currentTarget.dataset.id || event.detail.campaignId; }
    closeTracker() { this.trackerId = null; this.reload(); }

    get industryBars() {
        const by = (this.home && this.home.stats.byIndustry) || {};
        const max = Math.max(1, ...Object.values(by));
        return Object.keys(by).sort((a, b) => by[b] - by[a]).map((k) => ({
            name: k, count: by[k],
            style: `width:${Math.round((by[k] / max) * 100)}%;background:${BAR_COLOR[k] || '#5f6f86'}`
        }));
    }

    // ------------------------------------------------ modals

    openCalendar() {
        this[NavigationMixin.Navigate]({ type: 'standard__objectPage', attributes: { objectApiName: 'Event', actionName: 'home' } });
    }

    openAdd() { this.addPhone = null; this.showAdd = true; }
    closeAdd() { this.showAdd = false; }
    async partnerSaved(event) {
        this.showAdd = false;
        this.toast('Partner added to your book', 'success');
        await this.reload();
        this.selectedPartnerId = event.detail.accountId;
        this.view = 'partners';
        this.layout = 'list';
    }
    imported() { this.reload(); }

    get pickerPartners() { return this.allPartners.map((p) => ({ id: p.id, name: p.name, company: p.company })); }
    openInvite() { this.inviteFor = []; }
    inviteOne(event) {
        this.inviteFor = [event.detail && event.detail.partnerId ? event.detail.partnerId : event.currentTarget.dataset.id];
    }
    get showInvite() { return Array.isArray(this.inviteFor); }
    closeInvite() { this.inviteFor = null; }
    async inviteSent(event) {
        this.inviteFor = null;
        this.toast('Invites queued', 'success', 'Emails go out first, then the texts. RSVPs update here automatically.');
        await this.reload();
        this.trackerId = event.detail.campaignId;
    }
}
