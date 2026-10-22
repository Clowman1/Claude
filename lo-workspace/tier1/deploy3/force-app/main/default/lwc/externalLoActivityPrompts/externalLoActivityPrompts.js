import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { registerTourHooks } from 'c/loWsTourHooks';
import getAllUpNext from '@salesforce/apex/PerfectDayHomeController.getAllUpNext';
import completeUpNextItem from '@salesforce/apex/PerfectDayHomeController.completeUpNextItem';
import deferUpNextItem from '@salesforce/apex/PerfectDayHomeController.deferUpNextItem';
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
const KIND_ICON = { touch: 'T', task: '✓', appt: '◷', review: '!', reply: '↩', other: '•' };
const GROUP_PILL = {
    overdue: { label: 'Overdue', className: 'pill pill-overdue' },
    today: { label: 'Today', className: 'pill pill-today' },
    upcoming: { label: 'Upcoming', className: 'pill pill-upcoming' }
};

// Follow-up rows carry taskId; upcoming-task rows only carry it in their 'task:<id>' key.
function taskIdOf(row) {
    if (row.taskId) {
        return row.taskId;
    }
    const key = row.promptKey || '';
    return key.startsWith('task:') ? key.slice(5) : undefined;
}

export default class ExternalLoActivityPrompts extends LightningElement {
    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
    }

    @api prompts = [];

    // ---------- Open all modal (2026-10-08) ----------
    allOpen = false;
    allLoading = false;
    allError;
    allRows = [];
    kindFilter = 'all';
    busyKey;

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
                    canOpen: !!r.recordId,
                    taskId: taskIdOf(r),
                    canTomorrow: !!taskIdOf(r) && g.id !== 'upcoming',
                    busy: this.busyKey === r.promptKey
                }));
            return { ...g, items, count: items.length };
        }).filter((g) => g.count > 0);
    }

    get allEmpty() {
        return !this.allLoading && !this.allError && this.allGroups.length === 0;
    }

    // Mark complete / Tomorrow on any follow-up Task in the list, without leaving it.
    async handleRowTask(event) {
        const { key, action } = event.currentTarget.dataset;
        const row = this.allRows.find((r) => r.promptKey === key);
        const taskId = row && taskIdOf(row);
        if (!taskId || this.busyKey) {
            return;
        }
        this.busyKey = key;
        try {
            if (action === 'complete') {
                await completeUpNextItem({ recordId: taskId, objectApiName: 'Task' });
            } else {
                await deferUpNextItem({ recordId: taskId, objectApiName: 'Task', deferOption: 'tomorrow' });
            }
            this.allRows = this.allRows.filter((r) => r.promptKey !== key);
            this.dispatchEvent(new CustomEvent('taskschanged'));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Unable to update the task', message: reduceApexError(error), variant: 'error' }));
        } finally {
            this.busyKey = undefined;
        }
    }

    handleOpenRow(event) {
        const { id, object, key } = event.currentTarget.dataset;
        if (!id) {
            return;
        }
        this.allOpen = false;
        const reply = this.allRows.find((r) => r.promptKey === key && r.isTextReply);
        if (reply) {
            this.dispatchEvent(new CustomEvent('openreply', { detail: { prompt: reply } }));
            return;
        }
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
            // O4b/O4h: reply cards get their own hook so up-next-alert / up-next-actions land on document alerts and normal cards.
            tourHook: item.isTextReply ? 'up-next-reply' : item.isHighAlert ? 'up-next-alert' : null,
            actionsHook: item.isTextReply ? null : 'up-next-actions',
            showSnooze: item.canSnooze !== false
        }));
    }

    handleReview(event) {
        const promptKey = event.currentTarget.dataset.key;
        const prompt = this.items.find((item) => item.promptKey === promptKey);
        this.dispatchEvent(new CustomEvent('reviewprompt', { detail: { prompt } }));
    }

    // comms-settings: a reply to an automated text.
    handleOpenReply(event) {
        const prompt = this.items.find((item) => item.promptKey === event.currentTarget.dataset.key);
        this.dispatchEvent(new CustomEvent('openreply', { detail: { prompt } }));
    }

    handleReplyHandled(event) {
        const prompt = this.items.find((item) => item.promptKey === event.currentTarget.dataset.key);
        this.dispatchEvent(new CustomEvent('replyhandled', { detail: { prompt } }));
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