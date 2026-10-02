import { LightningElement, api } from 'lwc';
import getPreApprovalDetails from '@salesforce/apex/ExternalLoPortalController.getPreApprovalDetails';
import savePreApprovalDetails from '@salesforce/apex/ExternalLoPortalController.savePreApprovalDetails';
import { reduceApexError } from 'c/portalUtils';

const MONEY = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const NUMBER_FIELDS = ['loanAmount', 'downPaymentAmount', 'downPaymentPercent', 'estimatedPayment', 'purchasePrice'];
const DASH = '—';

/**
 * LO Workspace lead Overview: Pre-Approval Details. Every field always shows ("—" when empty).
 * The owner edits them all in one inline form, saved in one call. Non-cacheable Apex, so it always
 * shows what was saved. Fires `saved` (detail = fresh values) and `openrealtor` (detail.recordId).
 */
export default class LoWsLeadDetails extends LightningElement {
    info = {};
    loading = true;
    loadError;
    editing = false;
    saving = false;
    saveError;
    draft = {};
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) return;
        this._recordId = value;
        this.editing = false;
        this.load();
    }

    /** The parent calls this after the Contact card saved (City / State are shared). */
    @api
    refresh() {
        if (!this.editing) this.load();
    }

    async load() {
        if (!this._recordId) return;
        this.loading = true;
        this.loadError = undefined;
        try {
            this.info = (await getPreApprovalDetails({ leadId: this._recordId })) || {};
        } catch (error) {
            this.loadError = reduceApexError(error);
        } finally {
            this.loading = false;
        }
    }

    get rows() {
        const d = this.info;
        const money = (v) => (v === null || v === undefined ? null : MONEY.format(v));
        const down = [money(d.downPaymentAmount), d.downPaymentPercent == null ? null : `${d.downPaymentPercent}%`]
            .filter(Boolean)
            .join(' · ');
        return [
            { label: 'Loan purpose', value: d.purpose && d.purpose.split(';').join(', ') },
            { label: 'Loan program', value: d.program },
            { label: 'Loan Amount', value: money(d.loanAmount) },
            { label: 'Down payment', value: down },
            { label: 'Estimated payment', value: money(d.estimatedPayment) },
            { label: 'Property type', value: d.propertyType },
            { label: 'Buying timeline', value: d.buyingTimeline },
            { label: 'Location', value: [d.city, d.state].filter(Boolean).join(', ') },
            { label: 'Purchase price', value: money(d.purchasePrice) }
        ].map((row) => ({ ...row, value: row.value || DASH }));
    }

    get showEdit() {
        return this.info.canEdit && !this.editing && !this.loading;
    }

    get realtorLabel() {
        return this.info.realtorName || DASH;
    }

    get realtorIsLink() {
        return !!(this.info.realtorId && this.info.realtorLinkable);
    }

    // Selects keep a current value that is no longer active (or a multi-value purpose) selectable.
    options(values, current) {
        const list = [...(values || [])];
        if (current && !list.includes(current)) list.push(current);
        return [{ value: '', label: DASH }, ...list.map((v) => ({ value: v, label: v.split(';').join(', ') }))].map(
            (o) => ({ ...o, selected: o.value === (current || '') })
        );
    }

    get purposeOptions() {
        return this.options(this.info.purposes, this.draft.purpose);
    }

    get propertyTypeOptions() {
        return this.options(this.info.propertyTypes, this.draft.propertyType);
    }

    get timelineOptions() {
        return this.options(this.info.timelines, this.draft.buyingTimeline);
    }

    get realtorOptions() {
        const list = [...(this.info.realtors || [])];
        if (this.info.realtorId && !list.some((r) => r.id === this.info.realtorId)) {
            list.push({ id: this.info.realtorId, label: `${this.info.realtorName || 'Current realtor'} (current)` });
        }
        return [{ id: '', label: 'None' }, ...list].map((r) => ({
            value: r.id,
            label: r.label,
            selected: r.id === (this.draft.realtorId || '')
        }));
    }

    handleEdit() {
        const d = this.info;
        this.draft = {
            purpose: d.purpose || '',
            program: d.program || '',
            propertyType: d.propertyType || '',
            buyingTimeline: d.buyingTimeline || '',
            city: d.city || '',
            state: d.state || '',
            realtorId: d.realtorId || '',
            ...Object.fromEntries(NUMBER_FIELDS.map((f) => [f, d[f] ?? '']))
        };
        this.saveError = undefined;
        this.editing = true;
    }

    handleCancel() {
        this.editing = false;
    }

    handleInput(event) {
        this.draft = { ...this.draft, [event.target.dataset.field]: event.target.value };
    }

    handleRealtorClick(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('openrealtor', { detail: { recordId: this.info.realtorId } }));
    }

    async handleSave(event) {
        event.preventDefault();
        const payload = { ...this.draft, realtorId: this.draft.realtorId || null };
        NUMBER_FIELDS.forEach((f) => {
            const raw = String(payload[f] ?? '').replace(/[^0-9.-]/g, '');
            payload[f] = raw === '' ? null : Number(raw);
        });
        if (NUMBER_FIELDS.some((f) => Number.isNaN(payload[f]))) {
            this.saveError = 'Enter numbers only in the amount fields.';
            return;
        }
        this.saving = true;
        this.saveError = undefined;
        try {
            this.info = await savePreApprovalDetails({ leadId: this._recordId, detailsJson: JSON.stringify(payload) });
            this.editing = false;
            this.dispatchEvent(new CustomEvent('saved', { detail: { ...this.info } }));
        } catch (error) {
            this.saveError = reduceApexError(error);
        } finally {
            this.saving = false;
        }
    }
}
