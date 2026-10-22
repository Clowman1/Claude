import { LightningElement, api, wire } from 'lwc';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import LEAD_SOURCE from '@salesforce/schema/Lead.LeadSource';
import getAddLeadOptions from '@salesforce/apex/ExternalLoPortalController.getAddLeadOptions';
import createLoWorkspaceLead from '@salesforce/apex/ExternalLoPortalController.createLoWorkspaceLead';
import tagPartner from '@salesforce/apex/ExternalLoPortalController.tagPartner';

const NEW_REALTOR = '__new';
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
    /** Optional starting values { firstName, lastName, phone, email } (e.g. New lead for a past client). */
    @api prefill;

    connectedCallback() {
        const p = this.prefill || {};
        this.form = {
            ...this.form,
            firstName: p.firstName || '',
            lastName: p.lastName || '',
            phone: p.phone || '',
            email: p.email || ''
        };
    }

    form = {
        firstName: '', lastName: '', phone: '', email: '', purpose: '', realtorId: '', leadSource: '',
        rName: '', rPhone: '', rEmail: '', rCompany: '', rMarket: ''
    };
    matches = [];
    consumerRecordTypeId;
    leadSources = [];

    // Lead Source values of the Consumer lead record type, in org order (Realtor Referral comes from a realtor).
    @wire(getPicklistValues, { recordTypeId: '$consumerRecordTypeId', fieldApiName: LEAD_SOURCE })
    wiredSources({ data }) {
        if (data) {
            this.leadSources = data.values.map((v) => v.value).filter((v) => v !== 'Realtor Referral');
        }
    }
    purposes = [];
    realtors = [];
    saving = false;
    error;

    @wire(getAddLeadOptions)
    wiredOptions({ data, error }) {
        if (data) {
            this.purposes = data.purposes || [];
            this.realtors = data.realtors || [];
            this.consumerRecordTypeId = data.consumerRecordTypeId;
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
        return [{ id: '', label: 'None' }, ...this.realtors, { id: NEW_REALTOR, label: '+ New realtor' }].map((r) => ({
            value: r.id,
            label: r.label,
            selected: r.id === this.form.realtorId
        }));
    }

    // Shown only when no realtor is picked: with one the source is Realtor Referral.
    get showLeadSource() {
        return !this.locked && !this.form.realtorId;
    }

    get leadSourceOptions() {
        return this.leadSources.map((v) => ({ value: v, label: v, selected: v === this.form.leadSource }));
    }

    get isNewRealtor() {
        return !this.locked && this.form.realtorId === NEW_REALTOR;
    }

    get hasMatches() {
        return this.matches.length > 0;
    }

    handleInput(event) {
        this.form = { ...this.form, [event.target.dataset.field]: event.target.value };
        this.error = undefined;
        this.matches = [];
    }

    // Duplicate hit on "+ New realtor": tag the existing realtor, then create the lead with them.
    async handleTagMatch(event) {
        const { id, name } = event.currentTarget.dataset;
        this.saving = true;
        try {
            await tagPartner({ accountId: id, email: this.form.rEmail, phone: this.form.rPhone });
            if (!this.realtors.some((r) => r.id === id)) this.realtors = [...this.realtors, { id, label: name }];
            this.form = { ...this.form, realtorId: id };
            this.matches = [];
        } catch (error) {
            this.error = reduceApexError(error);
            this.saving = false;
            return;
        }
        this.saving = false;
        await this.submit();
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
        if (this.isNewRealtor) {
            if (!f.rName.trim() || !f.rCompany.trim()) return 'Enter the new realtor’s name and brokerage.';
            if (!f.rPhone.trim() && !f.rEmail.trim()) return 'Enter the new realtor’s phone or email.';
        }
        return null;
    }

    async handleSubmit(event) {
        event.preventDefault();
        if (this.saving) return;
        this.error = this.validate();
        if (this.error) return;
        await this.submit();
    }

    async submit() {
        const f = this.form;
        const isNew = this.isNewRealtor;
        this.saving = true;
        try {
            const result = await createLoWorkspaceLead({
                firstName: f.firstName,
                lastName: f.lastName,
                phone: f.phone,
                email: f.email,
                purpose: f.purpose,
                realtorId: this.realtorId || (isNew ? null : f.realtorId) || null,
                newRealtorName: isNew ? f.rName : null,
                newRealtorPhone: isNew ? f.rPhone : null,
                newRealtorEmail: isNew ? f.rEmail : null,
                newRealtorCompany: isNew ? f.rCompany : null,
                newRealtorMarket: isNew ? f.rMarket : null,
                leadSource: this.showLeadSource ? f.leadSource || null : null
            });
            if (result.realtorMatches && result.realtorMatches.length) {
                this.matches = result.realtorMatches;
                return;
            }
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