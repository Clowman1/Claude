import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getHome from '@salesforce/apex/LoRecruitingController.getHome';
import getWeekStats from '@salesforce/apex/LoRecruitingController.getWeekStats';
import setStage from '@salesforce/apex/LoRecruitingController.setStage';
import markHired from '@salesforce/apex/LoRecruitingController.markHired';
import { errorMessage, whenLabel, localDate } from 'c/bdUtils';

const CLOSED = ['Hired', 'Not Interested'];
const ENGAGED = ['Conversation', 'Meeting Set', 'Met', 'Offer Out'];
const QUEUE_PAGE = 25;
const BOARD_CAP = 60;
const FILTERS = [
    { value: 'all', label: 'All' },
    { value: 'due', label: 'Due' },
    { value: 'bm', label: 'Branch Mgr' },
    { value: 'inhouse', label: 'Possible In House' },
    { value: 'switch', label: 'Company switch' }
];

function volumeLabel(volume, period) {
    if (volume == null) return '';
    const m = volume / 1000000;
    return '$' + (m >= 10 ? m.toFixed(0) : m.toFixed(1)) + 'M' + (period ? ' · ' + period : '');
}

function todayYmd() {
    const d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}

export default class LoRecruiting extends LightningElement {
    home;
    week;
    loading = true;
    error;
    view = 'today';
    layout = 'list';
    recruiter = 'mine';
    filter = 'all';
    search = '';
    queueShown = QUEUE_PAGE;
    selectedId;
    touchFor;

    connectedCallback() { this.load(); }

    async load() {
        this.loading = !this.home;
        try {
            this.home = await getHome();
            if (this.recruiter === 'mine' && !this.home.recruits.some((r) => r.ownerId === this.home.userId)) this.recruiter = 'all';
            this.error = null;
            this.loadWeek();
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }
    reload() { return this.load(); }

    async loadWeek() {
        try {
            this.week = await getWeekStats({ ownerId: this.ownerFilterId });
        } catch (e) {
            this.week = null;
        }
    }

    toast(title, variant, message) { this.dispatchEvent(new ShowToastEvent({ title, variant, message })); }

    // ------------------------------------------------ header + filters

    get greeting() {
        const h = new Date().getHours();
        return (h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening') + ', ' + (this.home ? this.home.firstName : '');
    }
    get todayLabel() { return new Date().toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' }); }

    get recruiterOptions() {
        const others = ((this.home && this.home.recruiters) || [])
            .filter((r) => r.value !== this.home.userId)
            .map((r) => ({ label: r.label, value: r.value }));
        return [{ label: 'My recruits', value: 'mine' }, { label: 'All recruiters', value: 'all' }, ...others];
    }
    get ownerFilterId() {
        if (this.recruiter === 'all') return null;
        return this.recruiter === 'mine' ? this.home.userId : this.recruiter;
    }
    changeRecruiter(event) {
        this.recruiter = event.detail.value;
        this.queueShown = QUEUE_PAGE;
        this.loadWeek();
    }

    get navItems() {
        return [{ value: 'today', label: 'Today' }, { value: 'recruits', label: 'Recruits' }]
            .map((n) => ({ ...n, cls: 'nav' + (n.value === this.view ? ' nav-on' : '') }));
    }
    pickView(event) { this.view = event.currentTarget.dataset.value; }
    get isToday() { return this.view === 'today'; }
    get isRecruits() { return this.view === 'recruits'; }

    get filterPills() { return FILTERS.map((f) => ({ ...f, cls: 'pill' + (f.value === this.filter ? ' pill-on' : '') })); }
    pickFilter(event) { this.filter = event.currentTarget.dataset.value; }
    handleSearch(event) { this.search = event.target.value; }

    // ------------------------------------------------ recruits

    decorate(r) {
        const due = r.nextTouch && r.nextTouch <= todayYmd() && !CLOSED.includes(r.stage);
        const next = localDate(r.nextTouch);
        return {
            ...r,
            due,
            volumeLabel: volumeLabel(r.volume, r.volumePeriod),
            sub: [r.company, r.city].filter(Boolean).join(' · '),
            dialPhone: r.mobile || r.phone,
            nextLabel: next ? (due ? 'Due ' : 'Next ') + next.toLocaleDateString([], { month: 'short', day: 'numeric' }) : '',
            nextCls: due ? 'warn qd' : 'muted qd',
            rowCls: 'row clickable' + (r.id === this.selectedId ? ' sel' : '')
        };
    }

    get mine() {
        const owner = this.home && this.ownerFilterId;
        return ((this.home && this.home.recruits) || []).filter((r) => !owner || r.ownerId === owner).map((r) => this.decorate(r));
    }

    get dueList() {
        return this.mine.filter((r) => r.due).sort((a, b) => (a.nextTouch < b.nextTouch ? -1 : a.nextTouch > b.nextTouch ? 1 : (b.volume || 0) - (a.volume || 0)));
    }
    get hasDue() { return this.dueList.length > 0; }
    get dueCount() { return this.dueList.length; }

    get queueAll() { return this.mine.filter((r) => r.stage === 'New' && !r.due); }   // already volume-sorted by Apex
    get queue() { return this.queueAll.slice(0, this.queueShown); }
    get queueCount() { return this.queueAll.length; }
    get hasQueue() { return this.queue.length > 0; }
    get moreQueue() { return this.queueAll.length > this.queueShown; }
    showMoreQueue() { this.queueShown += QUEUE_PAGE; }

    get filtered() {
        const t = (this.search || '').trim().toLowerCase();
        return this.mine.filter((r) =>
            (this.filter === 'all'
                || (this.filter === 'due' && r.due)
                || (this.filter === 'bm' && r.branchManager)
                || (this.filter === 'inhouse' && r.inHouse)
                || (this.filter === 'switch' && r.companySwitch))
            && (!t || [r.name, r.company, r.nmls, r.city, r.county, r.phone, r.mobile, r.email].some((v) => v && v.toLowerCase().includes(t))));
    }
    get hasFiltered() { return this.filtered.length > 0; }
    get filteredCount() { return this.filtered.length; }

    // ------------------------------------------------ stats

    get stageCounts() {
        const by = {};
        this.mine.forEach((r) => { by[r.stage] = (by[r.stage] || 0) + 1; });
        return by;
    }
    get statRecruits() { return this.mine.length; }
    get statEngaged() { const by = this.stageCounts; return ENGAGED.reduce((n, s) => n + (by[s] || 0), 0); }
    get statHired() { return this.stageCounts.Hired || 0; }
    get statTouched() { return this.week ? this.week.touchedThisWeek : '–'; }
    get statCalls() { return this.week ? this.week.callsThisWeek : '–'; }

    get funnel() {
        const by = this.stageCounts;
        const max = Math.max(1, ...Object.values(by));
        return ((this.home && this.home.stages) || []).map((s) => ({
            name: s, count: by[s] || 0,
            style: `width:${Math.round(((by[s] || 0) / max) * 100)}%;background:${CLOSED.includes(s) || s === 'Not Now' ? '#9aa6b8' : '#244d8f'}`
        }));
    }

    get meetings() {
        const owner = this.ownerFilterId;
        const ids = new Set(this.mine.map((r) => r.id));
        return ((this.home && this.home.meetings) || []).filter((m) => !owner || ids.has(m.leadId))
            .map((m) => ({ ...m, when: whenLabel(m.startAt) }));
    }
    get hasMeetings() { return this.meetings.length > 0; }

    // ------------------------------------------------ list / board

    get isBoard() { return this.layout === 'board'; }
    get listBtnCls() { return 'sg' + (this.isBoard ? '' : ' sg-on'); }
    get boardBtnCls() { return 'sg' + (this.isBoard ? ' sg-on' : ''); }
    showList() { this.layout = 'list'; }
    showBoard() { this.selectedId = null; this.layout = 'board'; }

    get columns() {
        const rows = this.filtered;
        return ((this.home && this.home.stages) || []).map((stage) => {
            const all = rows.filter((r) => r.stage === stage);
            return {
                stage, cards: all.slice(0, BOARD_CAP), count: all.length,
                more: all.length > BOARD_CAP ? '+' + (all.length - BOARD_CAP) + ' more: use the list or search' : null,
                colCls: 'col' + (CLOSED.includes(stage) || stage === 'Not Now' ? ' col-dim' : '')
            };
        });
    }

    dragStart(event) {
        event.dataTransfer.setData('text/plain', event.currentTarget.dataset.id);
        event.dataTransfer.effectAllowed = 'move';
    }
    allowDrop(event) {
        event.preventDefault();
        event.currentTarget.classList.add('col-over');
    }
    leaveDrop(event) { event.currentTarget.classList.remove('col-over'); }
    async dropOnStage(event) {
        event.preventDefault();
        event.currentTarget.classList.remove('col-over');
        const stage = event.currentTarget.dataset.stage;
        const id = event.dataTransfer.getData('text/plain');
        const r = this.home.recruits.find((x) => x.id === id);
        if (!r || r.stage === stage) return;
        await this.changeStage(r, stage);
    }

    async changeStage(r, stage) {
        try {
            if (stage === 'Hired') {
                const ok = await LightningConfirm.open({
                    message: 'Mark ' + r.name + ' as Hired? This creates their Candidate account and starts the onboarding checklist.',
                    label: 'Mark Hired', theme: 'success'
                });
                if (!ok) return;
                await markHired({ leadId: r.id });
            } else {
                await setStage({ leadId: r.id, stage });
            }
            this.toast(r.name + ' moved to ' + stage, 'success');
            await this.reload();
        } catch (e) {
            this.toast('Could not change the stage', 'error', errorMessage(e));
        }
    }

    // ------------------------------------------------ open / touch

    openRecruit(event) {
        this.selectedId = event.currentTarget.dataset.id;
        this.view = 'recruits';
        this.layout = 'list';
    }
    closeRecruit() { this.selectedId = null; }
    get hasSelection() { return !!this.selectedId; }

    openTouch(event) {
        event.stopPropagation();
        this.touchFor = { id: event.currentTarget.dataset.id, name: event.currentTarget.dataset.name };
    }
    closeTouch() { this.touchFor = null; }
    touchLogged() {
        this.touchFor = null;
        this.reload();
    }
    stop(event) { event.stopPropagation(); }

    // ------------------------------------------------ in person meeting (the BD Coffee / Lunch / Happy Hour scheduler)

    inviteFor;
    openInvite(event) {
        const r = this.home.recruits.find((x) => x.id === event.currentTarget.dataset.id);
        if (r) this.inviteFor = { partners: [{ id: r.id, name: r.name, company: r.company }], ids: [r.id] };
    }
    closeInvite() { this.inviteFor = null; }
    inviteSent() {
        this.inviteFor = null;
        this.toast('Invite sent', 'success', 'Email first, then a text. They move to Meeting Set; RSVPs show on their timeline.');
        this.reload();
    }
}
