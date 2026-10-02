import { LightningElement, api, wire } from 'lwc';
import getAddLeadOptions from '@salesforce/apex/ExternalLoPortalController.getAddLeadOptions';
import createLoWorkspaceLead from '@salesforce/apex/ExternalLoPortalController.createLoWorkspaceLead';
import { reduceApexError } from 'c/portalUtils';

/**
 * LO Workspace Add lead (My Leads, a My Realtors row, a realtor page). Required: first + last name,
 * phone, email, loan purpose. Referring realtor is optional; with realtor-id set it is pre-filled
 * and locked. The server re-checks everything and applies the Phase 6 duplicate rules.
 * Fires `created` (detail.leadId, detail.message) and `close`.
 */
export default class LoWsAddLeadForm extends LightningElement {
    @api realtorId;
    @api realtorName;

    form = { firstName: '', lastName: '', phone: '', email: '', purpose: '', realtorId: '' };
    purposes = [];
    realtors = [];
    saving = false;
    error;

    @wire(getAddLeadOptions)
    wiredOptions({ data, error }) {
        if (data) {
            this.purposes = data.purposes || [];
            this.realtors = data.realtors || [];
        } else if (error) {
            this.error = reduceApexError(error);
        }
    }

    get locked() {
        return !!this.realtorId;
    }

    get purposeOptions() {
        return this.purposes.map((p) => ({ value: p, label: p, selected: p === this.form.purpose }));
    }

    get realtorOptions() {
        return [{ id: '', label: 'None' }, ...this.realtors].map((r) => ({
            value: r.id,
            label: r.label,
            selected: r.id === this.form.realtorId
        }));
    }

    handleInput(event) {
        this.form = { ...this.form, [event.target.dataset.field]: event.target.value };
        this.error = undefined;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    validate() {
        const f = this.form;
        if (!f.firstName.trim() || !f.lastName.trim()) return 'Enter the borrower’s first and last name.';
        const digits = f.phone.replace(/[^0-9]/g, '').replace(/^1(?=\d{10}$)/, '');
        if (digits.length !== 10) return 'Enter a 10-digit phone number.';
        const email = f.email.trim();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.toLowerCase() === 'na@na.com') {
            return 'Enter the borrower’s real email address.';
        }
        if (!f.purpose) return 'Pick a loan purpose.';
        return null;
    }

    async handleSubmit(event) {
        event.preventDefault();
        if (this.saving) return;
        this.error = this.validate();
        if (this.error) return;
        this.saving = true;
        try {
            const result = await createLoWorkspaceLead({
                firstName: this.form.firstName,
                lastName: this.form.lastName,
                phone: this.form.phone,
                email: this.form.email,
                purpose: this.form.purpose,
                realtorId: this.realtorId || this.form.realtorId || null
            });
            this.dispatchEvent(
                new CustomEvent('created', { detail: { leadId: result.leadId, message: result.userMessage } })
            );
        } catch (error) {
            this.error = reduceApexError(error);
        } finally {
            this.saving = false;
        }
    }
}
