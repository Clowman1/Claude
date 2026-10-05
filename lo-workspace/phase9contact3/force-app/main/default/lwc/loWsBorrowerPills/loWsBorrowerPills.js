import { LightningElement, api } from 'lwc';
import getLeadBorrowers from '@salesforce/apex/ExternalLoPortalController.getLeadBorrowers';
import addLeadBorrower from '@salesforce/apex/ExternalLoPortalController.addLeadBorrower';
import { reduceApexError } from 'c/portalUtils';

const EMPTY = { firstName: '', lastName: '', phone: '', email: '', relationship: '' };
const NO_EMAIL = 'No email — document requests and condition lists can’t be sent to this borrower. Add an email to include them.';

/**
 * LO Workspace lead Overview: "<Primary> (Primary)" + one pill per co-borrower + "+ Add borrower".
 * Fires `select` (detail.recordId = the Lead or a Borrower__c). The parent points the Contact card at it.
 */
export default class LoWsBorrowerPills extends LightningElement {
    @api selectedId;
    pills = [];
    relationships = [];
    canEdit = false;
    adding = false;
    saving = false;
    error;
    form = { ...EMPTY };
    _leadId;

    @api
    get leadId() {
        return this._leadId;
    }
    set leadId(value) {
        if (value === this._leadId) return;
        this._leadId = value;
        this.adding = false;
        this.refresh();
    }

    @api
    async refresh() {
        if (!this._leadId) return;
        try {
            const result = await getLeadBorrowers({ leadId: this._leadId });
            this.pills = result.pills || [];
            this.canEdit = result.canEdit;
            this.relationships = result.relationships || [];
            this.error = undefined;
        } catch (e) {
            this.error = reduceApexError(e);
        }
    }

    get decoratedPills() {
        const selected = this.selectedId || this._leadId;
        return this.pills.map((p) => ({
            ...p,
            pressed: String(p.id === selected),
            title: p.noEmail ? NO_EMAIL : null,
            pillClass: p.id === selected ? 'bp-pill bp-pill-active' : 'bp-pill'
        }));
    }

    get relationshipOptions() {
        return this.relationships.map((v) => ({ value: v, selected: v === this.form.relationship }));
    }

    handleSelect(event) {
        this.dispatchEvent(new CustomEvent('select', { detail: { recordId: event.currentTarget.dataset.id } }));
    }

    handleAddOpen() {
        this.form = { ...EMPTY };
        this.error = undefined;
        this.adding = true;
    }

    handleAddCancel() {
        this.adding = false;
    }

    handleInput(event) {
        this.form = { ...this.form, [event.target.dataset.field]: event.target.value };
    }

    async handleAddSave(event) {
        event.preventDefault();
        this.saving = true;
        this.error = undefined;
        try {
            const id = await addLeadBorrower({ leadId: this._leadId, ...this.form });
            this.adding = false;
            await this.refresh();
            this.dispatchEvent(new CustomEvent('select', { detail: { recordId: id } }));
        } catch (e) {
            this.error = reduceApexError(e);
        } finally {
            this.saving = false;
        }
    }
}