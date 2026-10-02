import { LightningElement, api } from 'lwc';
import getContactInfo from '@salesforce/apex/ExternalLoPortalController.getContactInfo';
import updateContactInfo from '@salesforce/apex/ExternalLoPortalController.updateContactInfo';
import { reduceApexError } from 'c/portalUtils';

const FIELDS = ['phone', 'mobile', 'email', 'street', 'city', 'state', 'postalCode'];

/**
 * LO Workspace contact card (Overview of a lead, partner or past client). Reads and saves through
 * non-cacheable Apex, so the card always shows what was saved. LO Workspace only: parents do not
 * render it in the Partner Workspace portal. Fires `saved` with the fresh ContactInfo.
 */
export default class LoWsContactCard extends LightningElement {
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

    /** The parent calls this after Pre-Approval Details saved (City / State are shared). */
    @api
    refresh() {
        if (!this.editing) this.load();
    }

    async load() {
        if (!this._recordId) return;
        this.loading = true;
        this.loadError = undefined;
        try {
            this.info = (await getContactInfo({ recordId: this._recordId })) || {};
        } catch (error) {
            this.loadError = reduceApexError(error);
        } finally {
            this.loading = false;
        }
    }

    get rows() {
        const c = this.info;
        const digits = (v) => (v || '').replace(/[^0-9+]/g, '');
        const cityLine = [c.city, [c.state, c.postalCode].filter(Boolean).join(' ')].filter(Boolean).join(', ');
        const address = [c.street, cityLine].filter(Boolean).join('\n');
        return [
            { label: 'Company', value: c.company },
            { label: 'Phone', value: c.phone, href: c.phone && `tel:${digits(c.phone)}` },
            { label: 'Mobile', value: c.mobile, href: c.mobile && `tel:${digits(c.mobile)}` },
            { label: 'Email', value: c.email, href: c.email && `mailto:${c.email}` },
            { label: 'Mailing address', value: address }
        ].filter((row) => row.value);
    }

    get isEmpty() {
        return this.rows.length === 0;
    }

    handleEdit() {
        this.draft = Object.fromEntries(FIELDS.map((f) => [f, this.info[f] || '']));
        this.saveError = undefined;
        this.editing = true;
    }

    handleCancel() {
        this.editing = false;
    }

    handleInput(event) {
        this.draft = { ...this.draft, [event.target.dataset.field]: event.target.value };
    }

    async handleSave(event) {
        event.preventDefault();
        this.saving = true;
        this.saveError = undefined;
        try {
            this.info = await updateContactInfo({ recordId: this._recordId, ...this.draft });
            this.editing = false;
            this.dispatchEvent(new CustomEvent('saved', { detail: { ...this.info } }));
        } catch (error) {
            this.saveError = reduceApexError(error);
        } finally {
            this.saving = false;
        }
    }
}
