import { LightningElement, api } from 'lwc';
import createInvite from '@salesforce/apex/BdCommandCenterController.createInvite';
import searchCoHosts from '@salesforce/apex/BdCommandCenterController.searchCoHosts';
import { errorMessage } from 'c/bdUtils';

const KINDS = ['Coffee', 'Lunch', 'Happy Hour'];
const DEFAULT_TIME = { Coffee: '08:30:00.000', Lunch: '12:00:00.000', 'Happy Hour': '17:30:00.000' };

export default class BdInviteModal extends LightningElement {
    @api partners = [];      // [{ id, name, company }]
    @api preselectedIds = [];
    @api repFirstName;

    kind = 'Coffee';
    name = '';
    eventDate;
    eventTime = DEFAULT_TIME.Coffee;
    minutes = '60';
    location = '';
    note = '';
    selectedIds = [];
    partnerTerm = '';
    coHosts = [];
    coHostTerm = '';
    coHostHits = [];
    busy = false;
    error;

    connectedCallback() {
        this.selectedIds = [...(this.preselectedIds || [])];
    }

    get kindButtons() {
        return KINDS.map((k) => ({ value: k, cls: 'sg' + (k === this.kind ? ' sg-on' : '') }));
    }

    pickKind(event) {
        const prev = this.kind;
        this.kind = event.currentTarget.dataset.value;
        if (this.eventTime === DEFAULT_TIME[prev]) this.eventTime = DEFAULT_TIME[this.kind];
    }

    get lengthOptions() {
        return [
            { label: '30 min', value: '30' }, { label: '45 min', value: '45' }, { label: '1 hour', value: '60' },
            { label: '90 min', value: '90' }, { label: '2 hours', value: '120' }
        ];
    }

    get namePlaceholder() {
        const who = this.selectedPartners.length === 1 ? this.selectedPartners[0].name : 'partners';
        return `${this.kind} with ${this.repFirstName || 'me'} · ${who}`;
    }

    handleField(event) {
        this[event.target.dataset.field] = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
    }

    // ------------------------------------------------ partners (from the rep's book)

    get selectedPartners() {
        return this.selectedIds.map((id) => (this.partners || []).find((p) => p.id === id)).filter(Boolean);
    }

    get partnerHits() {
        const t = (this.partnerTerm || '').trim().toLowerCase();
        if (t.length < 2) return [];
        return (this.partners || [])
            .filter((p) => !this.selectedIds.includes(p.id))
            .filter((p) => (p.name || '').toLowerCase().includes(t) || (p.company || '').toLowerCase().includes(t))
            .slice(0, 8);
    }

    handlePartnerTerm(event) { this.partnerTerm = event.target.value; }

    addPartner(event) {
        this.selectedIds = [...this.selectedIds, event.currentTarget.dataset.id];
        this.partnerTerm = '';
    }

    removePartner(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedIds = this.selectedIds.filter((x) => x !== id);
    }

    // ------------------------------------------------ co-hosts

    handleCoHostTerm(event) {
        this.coHostTerm = event.target.value;
        window.clearTimeout(this.coHostTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.coHostTimer = window.setTimeout(() => this.runCoHostSearch(), 300);
    }

    async runCoHostSearch() {
        if (!this.coHostTerm || this.coHostTerm.trim().length < 2) { this.coHostHits = []; return; }
        try {
            const rows = await searchCoHosts({ term: this.coHostTerm });
            const chosen = new Set(this.coHosts.map((c) => c.userId));
            this.coHostHits = rows.filter((r) => !chosen.has(r.userId)).slice(0, 8);
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    addCoHost(event) {
        const hit = this.coHostHits.find((h) => h.userId === event.currentTarget.dataset.id);
        if (hit) this.coHosts = [...this.coHosts, hit];
        this.coHostTerm = '';
        this.coHostHits = [];
    }

    removeCoHost(event) {
        const id = event.currentTarget.dataset.id;
        this.coHosts = this.coHosts.filter((c) => c.userId !== id);
    }

    // ------------------------------------------------ send

    get sendDisabled() {
        return this.busy || !this.eventDate || !this.eventTime || this.selectedIds.length === 0;
    }

    async send() {
        this.busy = true;
        this.error = null;
        try {
            const campaignId = await createInvite({
                req: {
                    kind: this.kind,
                    name: this.name,
                    eventDate: this.eventDate,
                    eventTime: this.eventTime.slice(0, 5),
                    minutes: parseInt(this.minutes, 10),
                    location: this.location,
                    note: this.note,
                    partnerIds: this.selectedIds,
                    coHostIds: this.coHosts.map((c) => c.userId)
                }
            });
            this.dispatchEvent(new CustomEvent('sent', { detail: { campaignId } }));
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}
