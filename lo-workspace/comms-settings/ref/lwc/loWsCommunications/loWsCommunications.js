import { LightningElement, api, wire } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';
import getCommunications from '@salesforce/apex/LoWsCommunicationsService.getCommunications';
import getPartnerTexts from '@salesforce/apex/LoWsCommunicationsService.getPartnerTexts';

// Read-only Communications tab (2026-10-08): Calls / SMS / Emails for one borrower, every Reach user.
// O3: + Texts (Twilio texts from this loan/lead to the borrower and agents, and replies). texts-only = realtor page.
const DIRECTION = {
    in: { icon: '↙', className: 'dir dir-in', label: 'Incoming' },
    out: { icon: '↗', className: 'dir dir-out', label: 'Outgoing' },
    missed: { icon: '✕', className: 'dir dir-miss', label: 'Missed' }
};
const DAY = { month: 'short', day: 'numeric', year: 'numeric' };
const TIME = { hour: 'numeric', minute: '2-digit' };

export default class LoWsCommunications extends LightningElement {
    @api recordId;
    @api textsOnly = false;

    tab = 'calls';
    data;
    error;
    loading = true;
    openSummaries = new Set();
    openThreads;

    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
        if (this.textsOnly) {
            this.tab = 'texts';
        }
    }

    // Only one of the two wires runs: an undefined parameter keeps a wire idle.
    get commsRecordId() {
        return this.textsOnly ? undefined : this.recordId;
    }
    get partnerTextsId() {
        return this.textsOnly ? this.recordId : undefined;
    }

    @wire(getPartnerTexts, { accountId: '$partnerTextsId' })
    wiredTexts({ data, error }) {
        if (data) {
            this.data = { texts: data };
            this.error = undefined;
            this.loading = false;
        } else if (error) {
            this.error = error?.body?.message || 'Texts could not be loaded.';
            this.loading = false;
        }
    }

    @wire(getCommunications, { recordId: '$commsRecordId' })
    wired({ data, error }) {
        if (data) {
            this.data = data;
            this.error = undefined;
            this.loading = false;
            // The newest email conversation starts open.
            this.openThreads = new Set(data.emails?.length ? [data.emails[0].key] : []);
        } else if (error) {
            this.error = error?.body?.message || 'Communications could not be loaded.';
            this.loading = false;
        }
    }

    // ---------- Tabs ----------

    get tabs() {
        const counts = {
            calls: this.data?.calls?.length ?? 0,
            sms: this.data?.sms?.length ?? 0,
            emails: this.data?.emails?.length ?? 0,
            texts: this.data?.texts?.length ?? 0
        };
        return [
            { id: 'calls', label: 'Calls' },
            { id: 'sms', label: 'SMS' },
            { id: 'emails', label: 'Emails' },
            { id: 'texts', label: 'Texts' }
        ].map((t) => ({
            ...t,
            tourHook: 'comms-' + t.id, // O4b: comms-texts
            count: counts[t.id],
            selected: String(t.id === this.tab),
            className: t.id === this.tab ? 'tab tab-on' : 'tab'
        }));
    }

    handleTab(event) {
        this.tab = event.currentTarget.dataset.tab;
    }

    get showCalls() {
        return this.tab === 'calls';
    }
    get showSms() {
        return this.tab === 'sms';
    }
    get showEmails() {
        return this.tab === 'emails';
    }
    get showTexts() {
        return this.tab === 'texts';
    }
    get showTabs() {
        return !this.textsOnly;
    }

    // ---------- Calls ----------

    get calls() {
        return (this.data?.calls || []).map((c) => {
            const dir = DIRECTION[c.direction] || DIRECTION.out;
            const when = c.at ? new Date(c.at) : null;
            const open = this.openSummaries.has(c.id);
            return {
                ...c,
                dirIcon: dir.icon,
                dirClass: dir.className,
                dirLabel: dir.label,
                title: `${c.fromLabel || 'Unknown'} → ${c.toLabel || 'Unknown'}`,
                meta: [
                    when ? `${when.toLocaleDateString(undefined, DAY)}, ${when.toLocaleTimeString(undefined, TIME)}` : null,
                    c.direction === 'missed' ? 'Missed' : c.durationLabel
                ]
                    .filter(Boolean)
                    .join(' · '),
                hasSummary: !!c.summary,
                summaryOpen: open,
                summaryLabel: open ? 'Hide summary' : 'Summary',
                summaryExpanded: String(open)
            };
        });
    }

    get callsEmpty() {
        return !this.calls.length;
    }

    handleSummary(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.openSummaries);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        this.openSummaries = next;
    }

    // ---------- SMS (oldest first, grouped by day) ----------

    get smsDays() {
        const days = [];
        let current;
        for (const m of this.data?.sms || []) {
            const when = m.at ? new Date(m.at) : null;
            const dayLabel = when ? when.toLocaleDateString(undefined, DAY) : 'Undated';
            if (!current || current.label !== dayLabel) {
                current = { label: dayLabel, messages: [] };
                days.push(current);
            }
            current.messages.push({
                ...m,
                bubbleClass: m.fromBorrower ? 'bubble bubble-them' : 'bubble bubble-us',
                stamp: [m.fromLabel, when ? when.toLocaleTimeString(undefined, TIME) : null].filter(Boolean).join(' · ')
            });
        }
        return days;
    }

    get smsEmpty() {
        return !(this.data?.sms || []).length;
    }

    // ---------- Texts (Twilio, oldest first, grouped by day; read-only) ----------

    get textDays() {
        const days = [];
        let current;
        for (const m of this.data?.texts || []) {
            const when = m.at ? new Date(m.at) : null;
            const dayLabel = when ? when.toLocaleDateString(undefined, DAY) : 'Undated';
            if (!current || current.label !== dayLabel) {
                current = { label: dayLabel, messages: [] };
                days.push(current);
            }
            const time = when ? when.toLocaleTimeString(undefined, TIME) : null;
            current.messages.push({
                ...m,
                bubbleClass: m.fromBorrower ? 'bubble bubble-them' : 'bubble bubble-us',
                hintKey: m.id + '-hint',
                stamp: [m.fromBorrower ? m.fromLabel : `To ${m.toLabel || 'Unknown'}`, time].filter(Boolean).join(' · ')
            });
        }
        return days;
    }

    get textsEmpty() {
        return !(this.data?.texts || []).length;
    }

    // ---------- Emails ----------

    get threads() {
        return (this.data?.emails || []).map((t) => {
            const open = this.openThreads?.has(t.key);
            const last = t.lastAt ? new Date(t.lastAt).toLocaleDateString(undefined, DAY) : '';
            const preview = t.messages?.length ? (t.messages[t.messages.length - 1].body || '').slice(0, 140) : '';
            return {
                ...t,
                open,
                expanded: String(!!open),
                last,
                summaryLine: `${t.participants || ''} · ${t.count} message${t.count === 1 ? '' : 's'}${open ? '' : ' · ' + preview}`,
                messages: (t.messages || []).map((m) => ({
                    ...m,
                    when: m.at ? `${new Date(m.at).toLocaleDateString(undefined, DAY)}, ${new Date(m.at).toLocaleTimeString(undefined, TIME)}` : ''
                }))
            };
        });
    }

    get emailsEmpty() {
        return !this.threads.length;
    }

    handleThread(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.openThreads);
        if (next.has(key)) next.delete(key);
        else next.add(key);
        this.openThreads = next;
    }
}