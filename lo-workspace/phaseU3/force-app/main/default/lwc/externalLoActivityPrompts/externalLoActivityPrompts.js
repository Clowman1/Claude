import { LightningElement, api } from 'lwc';
import getAllUpNext from '@salesforce/apex/PerfectDayHomeController.getAllUpNext';
import { reduceApexError } from 'c/portalUtils';
import EXTLO_PROMPT_LOG from '@salesforce/label/c.ExtLO_Prompt_Log';
import EXTLO_PROMPT_TOMORROW from '@salesforce/label/c.ExtLO_Prompt_Tomorrow';

const GROUPS = [
    { id: 'overdue', label: 'Overdue', className: 'group-head group-overdue' },
    { id: 'today', label: 'Today', className: 'group-head group-today' },
    { id: 'upcoming', label: 'Coming up', className: 'group-head group-upcoming' }
];
const KIND_FILTERS = [
    { id: 'all', label: 'All' },
    { id: 'touch', label: 'Weekly touches' },
    { id: 'task', label: 'Tasks' },
    { id: 'appt', label: 'Appointments' }
];
const KIND_ICON = { touch: 'T', task: '✓', appt: '◷', review: '!', other: '•' };
const GROUP_PILL = {
    overdue: { label: 'Overdue', className: 'pill pill-overdue' },
    today: { label: 'Today', className: 'pill pill-today' },
    upcoming: { label: 'Upcoming', className: 'pill pill-upcoming' }
};

export default class ExternalLoActivityPrompts extends LightningElement {
    @api prompts = [];

    // ---------- Open all modal (2026-10-08) ----------
    allOpen = false;
    allLoading = false;
    allError;
    allRows = [];
    kindFilter = 'all';

    async handleOpenAll() {
        this.allOpen = true;
        this.kindFilter = 'all';
        this.allLoading = true;
        this.allError = undefined;
        try {
            this.allRows = (await getAllUpNext()) || [];
        } catch (error) {
            this.allRows = [];
            this.allError = reduceApexError(error);
        } finally {
            this.allLoading = false;
        }
    }

    handleCloseAll() {
        this.allOpen = false;
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape') {
            this.allOpen = false;
        }
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.allOpen = false;
        }
    }

    handleKindFilter(event) {
        this.kindFilter = event.currentTarget.dataset.kind;
    }

    get allCount() {
        return this.allRows.length;
    }

    get kindChips() {
        return KIND_FILTERS.map((k) => ({
            ...k,
            pressed: String(k.id === this.kindFilter),
            className: k.id === this.kindFilter ? 'chip chip-on' : 'chip'
        }));
    }

    get allGroups() {
        const rows = this.allRows.filter((r) => this.kindFilter === 'all' || r.kind === this.kindFilter);
        return GROUPS.map((g) => {
            const items = rows
                .filter((r) => r.upNextGroup === g.id)
                .map((r, i) => ({
                    ...r,
                    rowKey: `${r.promptKey}-${i}`,
                    icon: KIND_ICON[r.kind] || '•',
                    pill: GROUP_PILL[g.id],
                    canOpen: !!r.recordId
                }));
            return { ...g, items, count: items.length };
        }).filter((g) => g.count > 0);
    }

    get allEmpty() {
        return !this.allLoading && !this.allError && this.allGroups.length === 0;
    }

    handleOpenRow(event) {
        const { id, object } = event.currentTarget.dataset;
        if (!id) {
            return;
        }
        this.allOpen = false;
        this.dispatchEvent(new CustomEvent('openrecord', { detail: { recordId: id, objectApiName: object } }));
    }

    labels = {
        log: EXTLO_PROMPT_LOG,
        tomorrow: EXTLO_PROMPT_TOMORROW
    };

    get items() {
        // Show the next three; the list refills from the server as prompts are logged or snoozed.
        // Follow-up rows (canComplete) lead with Mark complete, so Log drops to secondary.
        return (this.prompts || []).slice(0, 3).map((item) => ({
            ...item,
            logClass: item.canComplete ? 'btn btn-secondary' : 'btn btn-primary',
            cardClass: item.isHighAlert ? 'prompt-card prompt-card-alert' : 'prompt-card',
            showSnooze: item.canSnooze !== false
        }));
    }

    handleReview(event) {
        const promptKey = event.currentTarget.dataset.key;
        const prompt = this.items.find((item) => item.promptKey === promptKey);
        this.dispatchEvent(new CustomEvent('reviewprompt', { detail: { prompt } }));
    }

    handleComplete(event) {
        const promptKey = event.currentTarget.dataset.key;
        const prompt = this.items.find((item) => item.promptKey === promptKey);
        this.dispatchEvent(new CustomEvent('completeprompt', { detail: { prompt } }));
    }

    get isEmpty() {
        return !this.items.length;
    }

    handleLog(event) {
        const promptKey = event.currentTarget.dataset.key;
        const prompt = this.items.find((item) => item.promptKey === promptKey);
        this.dispatchEvent(new CustomEvent('logprompt', { detail: { prompt } }));
    }

    handleSnooze(event) {
        const promptKey = event.currentTarget.dataset.key;
        const prompt = this.items.find((item) => item.promptKey === promptKey);
        this.dispatchEvent(new CustomEvent('snoozeprompt', { detail: { prompt } }));
    }
}