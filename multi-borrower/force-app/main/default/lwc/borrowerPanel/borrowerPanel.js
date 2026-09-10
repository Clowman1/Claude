import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, createRecord, updateRecord, deleteRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getBorrowers from '@salesforce/apex/BorrowerPersonAccountService.getBorrowers';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';

const MAX_BORROWERS = 4;
const LEAD = 'Lead';
const EDITABLE_FIELDS = ['First_Name__c', 'Last_Name__c', 'Email__c', 'Phone__c'];

const LEAD_OPTIONAL = ['Lead.FirstName', 'Lead.LastName', 'Lead.Name', 'Lead.Email', 'Lead.Phone'];

// Borrower_Name__c is the primary borrower's Person Account. The *_Co_Borrower__pc fields are the
// frozen legacy model, read only as a fallback for files that predate Borrower__c.
const TRANSACTION_OPTIONAL = [
    'Transaction__c.Borrower_Name__c',
    'Transaction__c.Borrower_Name__r.Name',
    'Transaction__c.Borrower_Name__r.PersonEmail',
    'Transaction__c.Borrower_Name__r.PersonMobilePhone',
    'Transaction__c.Borrower_Name__r.First_Name_Co_Borrower__pc',
    'Transaction__c.Borrower_Name__r.Last_Name_Co_Borrower__pc',
    'Transaction__c.Borrower_Name__r.Email_Co_Borrower__pc',
    'Transaction__c.Borrower_Name__r.Mobile_Co_Borrower__pc'
];

const PROPERTY_BY_FIELD = {
    First_Name__c: 'firstName',
    Last_Name__c: 'lastName',
    Email__c: 'email',
    Phone__c: 'phone'
};

export default class BorrowerPanel extends LightningElement {
    @api recordId;
    @api objectApiName;

    // These must be real fields, not getters: a @wire reactive reference ('$name') resolves a
    // component property, and pointing it at a getter breaks the component at construction.
    parentFields;
    parentOptionalFields;
    isLead = false;

    expanded = {};
    draft = null;
    saving = false;

    parentRecord;
    borrowerResult;

    connectedCallback() {
        this.isLead = this.objectApiName === LEAD;
        this.parentFields = this.isLead ? ['Lead.Id'] : ['Transaction__c.Id'];
        this.parentOptionalFields = this.isLead ? LEAD_OPTIONAL : TRANSACTION_OPTIONAL;
    }

    // Phones get the list and the contact details, not the editing controls.
    get isReadOnly() {
        return FORM_FACTOR === 'Small';
    }

    get isEditable() {
        return !this.isReadOnly;
    }

    @wire(getRecord, {
        recordId: '$recordId',
        fields: '$parentFields',
        optionalFields: '$parentOptionalFields'
    })
    wiredParent({ data }) {
        if (data) {
            this.parentRecord = data;
        }
    }

    @wire(getBorrowers, { recordId: '$recordId' })
    wiredBorrowers(result) {
        this.borrowerResult = result;
    }

    get primary() {
        if (!this.parentRecord) {
            return null;
        }
        const name = this.isLead
            ? getFieldValue(this.parentRecord, 'Lead.Name')
            : getFieldValue(this.parentRecord, 'Transaction__c.Borrower_Name__r.Name');
        if (!name) {
            return null;
        }
        return {
            key: 'primary',
            name,
            email: this.isLead
                ? getFieldValue(this.parentRecord, 'Lead.Email')
                : getFieldValue(this.parentRecord, 'Transaction__c.Borrower_Name__r.PersonEmail'),
            phone: this.isLead
                ? getFieldValue(this.parentRecord, 'Lead.Phone')
                : getFieldValue(this.parentRecord, 'Transaction__c.Borrower_Name__r.PersonMobilePhone'),
            role: 'Primary Borrower',
            editable: false,
            removable: false,
            isOpen: !!this.expanded.primary
        };
    }

    get coBorrowers() {
        const records = (this.borrowerResult && this.borrowerResult.data) || [];
        return records.map((record) => ({
            key: record.Id,
            id: record.Id,
            name: record.Name,
            firstName: record.First_Name__c,
            lastName: record.Last_Name__c,
            email: record.Email__c,
            phone: record.Phone__c,
            role: 'Co-Borrower',
            editable: this.isEditable,
            removable: this.isEditable,
            // Once a Person Account exists the row is soft-flagged rather than deleted.
            hasAccount: !!record.Account__c,
            isOpen: !!this.expanded[record.Id]
        }));
    }

    // Legacy __pc co-borrower, shown read-only only when this file has no Borrower__c rows at all.
    get legacyCoBorrower() {
        if (this.isLead || !this.parentRecord || this.coBorrowers.length) {
            return null;
        }
        const first = getFieldValue(this.parentRecord, 'Transaction__c.Borrower_Name__r.First_Name_Co_Borrower__pc');
        const last = getFieldValue(this.parentRecord, 'Transaction__c.Borrower_Name__r.Last_Name_Co_Borrower__pc');
        const name = [first, last].filter(Boolean).join(' ');
        if (!name) {
            return null;
        }
        return {
            key: 'legacy',
            name,
            email: getFieldValue(this.parentRecord, 'Transaction__c.Borrower_Name__r.Email_Co_Borrower__pc'),
            phone: getFieldValue(this.parentRecord, 'Transaction__c.Borrower_Name__r.Mobile_Co_Borrower__pc'),
            role: 'Co-Borrower (legacy)',
            editable: false,
            removable: false,
            isOpen: !!this.expanded.legacy
        };
    }

    get rows() {
        const rows = [];
        const primaryRow = this.primary;
        if (primaryRow) {
            rows.push(primaryRow);
        }
        rows.push(...this.coBorrowers);
        const legacy = this.legacyCoBorrower;
        if (legacy) {
            rows.push(legacy);
        }
        // Templates cannot hold expressions, so the derived display bits are added here.
        return rows.map((row) => ({
            ...row,
            chevron: row.isOpen ? 'utility:chevronup' : 'utility:chevrondown',
            mailto: row.email ? 'mailto:' + row.email : null,
            tel: row.phone ? 'tel:' + row.phone : null
        }));
    }

    get canAdd() {
        // ponytail: the 4-borrower cap lives here only, not in a validation rule, so data loads and
        // legacy rows missing an email can still be created. Add a rule if entry moves off this UI.
        return this.isEditable && !this.draft && this.coBorrowers.length + 1 < MAX_BORROWERS;
    }

    get capReached() {
        return this.isEditable && !this.draft && this.coBorrowers.length + 1 >= MAX_BORROWERS;
    }

    get hasNoBorrowers() {
        return !this.rows.length;
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.expanded = { ...this.expanded, [key]: !this.expanded[key] };
    }

    handleAdd() {
        this.draft = { First_Name__c: '', Last_Name__c: '', Email__c: '', Phone__c: '' };
    }

    handleCancel() {
        this.draft = null;
    }

    handleDraftChange(event) {
        this.draft = { ...this.draft, [event.target.dataset.field]: event.target.value };
    }

    async handleSaveNew() {
        const missing = EDITABLE_FIELDS.filter((field) => !(this.draft[field] || '').trim());
        if (missing.length) {
            this.toast('First name, last name, email and phone are all required.', 'error');
            return;
        }

        const first = this.draft.First_Name__c.trim();
        const last = this.draft.Last_Name__c.trim();
        const fields = {
            First_Name__c: first,
            Last_Name__c: last,
            Email__c: this.draft.Email__c.trim(),
            Phone__c: this.draft.Phone__c.trim(),
            Name: (first + ' ' + last).slice(0, 80)
        };
        fields[this.isLead ? 'Lead__c' : 'Transaction__c'] = this.recordId;

        this.saving = true;
        try {
            await createRecord({ apiName: 'Borrower__c', fields });
            this.draft = null;
            await refreshApex(this.borrowerResult);
            this.toast('Borrower added.', 'success');
        } catch (error) {
            this.toast(this.message(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    async handleFieldCommit(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.target.value;
        const row = this.coBorrowers.find((candidate) => candidate.id === id);
        if (!row || row[PROPERTY_BY_FIELD[field]] === value) {
            return;
        }

        const fields = { Id: id };
        fields[field] = value;
        if (field === 'First_Name__c' || field === 'Last_Name__c') {
            const first = field === 'First_Name__c' ? value : row.firstName;
            const last = field === 'Last_Name__c' ? value : row.lastName;
            fields.Name = [first, last].filter(Boolean).join(' ').slice(0, 80);
        }

        try {
            await updateRecord({ fields });
            await refreshApex(this.borrowerResult);
        } catch (error) {
            this.toast(this.message(error), 'error');
        }
    }

    async handleRemove(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.coBorrowers.find((candidate) => candidate.id === id);
        if (!row) {
            return;
        }

        try {
            if (row.hasAccount) {
                // Soft-flag, so emails and conditions already tied to this person are not orphaned.
                await updateRecord({ fields: { Id: id, Removed__c: true } });
            } else {
                await deleteRecord(id);
            }
            await refreshApex(this.borrowerResult);
            this.toast('Borrower removed.', 'success');
        } catch (error) {
            this.toast(this.message(error), 'error');
        }
    }

    message(error) {
        if (error && error.body) {
            if (error.body.message) {
                return error.body.message;
            }
            const outputErrors = error.body.output && error.body.output.errors;
            if (outputErrors && outputErrors.length) {
                return outputErrors[0].message;
            }
        }
        return 'Could not save the borrower.';
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ message, variant }));
    }
}
