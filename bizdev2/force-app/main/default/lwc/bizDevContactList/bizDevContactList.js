import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContacts from '@salesforce/apex/BizDevContactController.getContacts';
import createContact from '@salesforce/apex/BizDevContactController.createContact';
import saveNote from '@salesforce/apex/BizDevContactController.saveNote';

const EMPTY_FORM = {
    firstName: '',
    lastName: '',
    phone: '',
    email: '',
    businessType: '',
    notes: ''
};

export default class BizDevContactList extends LightningElement {
    contacts = [];
    error;
    isLoading = true;
    isModalOpen = false;
    isSaving = false;
    expandedContactId;
    noteDraft = '';
    searchTerm = '';
    form = { ...EMPTY_FORM };

    wiredContactsResult;

    @wire(getContacts)
    wiredContacts(result) {
        this.wiredContactsResult = result;
        const { data, error } = result;
        if (data) {
            this.contacts = data.map((contact) => this.decorate(contact));
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.contacts = [];
            this.error = this.extractError(error);
            this.isLoading = false;
        }
    }

    decorate(contact) {
        const isExpanded = contact.id === this.expandedContactId;
        return {
            ...contact,
            lastCallText: this.formatStamp(contact.lastCall),
            lastCallClass: this.stampClass(contact.lastCall),
            lastSmsText: this.formatStamp(contact.lastSms),
            lastSmsClass: this.stampClass(contact.lastSms),
            nextEventText: this.formatEvent(contact),
            hasNextEvent: !!contact.nextEventDate,
            createdOnText: this.formatDate(contact.createdDate),
            phoneHref: contact.phone ? `tel:${contact.phone}` : '',
            emailHref: contact.email ? `mailto:${contact.email}` : '',
            isExpanded,
            notesButtonLabel: contact.noteCount
                ? `Notes (${contact.noteCount})`
                : 'Add note',
            rowClass: isExpanded ? 'bdc-row bdc-row-expanded' : 'bdc-row',
            decoratedNotes: (contact.notes || []).map((note) => ({
                ...note,
                createdText: this.formatStamp(note.createdDate)
            }))
        };
    }

    // Recency is the whole point of these two columns, so the cell leads with how long ago it was
    // and keeps the exact date as a tooltip.
    formatStamp(value) {
        if (!value) {
            return '';
        }
        const when = new Date(value);
        const days = Math.floor((Date.now() - when.getTime()) / 86400000);
        const exact = new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        }).format(when);
        if (days <= 0) {
            return `Today - ${exact}`;
        }
        if (days === 1) {
            return `Yesterday - ${exact}`;
        }
        return `${days}d ago - ${exact}`;
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        }).format(new Date(value));
    }

    stampClass(value) {
        if (!value) {
            return 'bdc-stamp bdc-stamp-never';
        }
        const days = Math.floor((Date.now() - new Date(value).getTime()) / 86400000);
        if (days >= 45) {
            return 'bdc-stamp bdc-stamp-cold';
        }
        if (days >= 14) {
            return 'bdc-stamp bdc-stamp-warm';
        }
        return 'bdc-stamp bdc-stamp-fresh';
    }

    formatEvent(contact) {
        if (!contact.nextEventDate) {
            return '';
        }
        const when = new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(new Date(contact.nextEventDate));
        return `${when} - ${contact.nextEventSubject}`;
    }

    get filteredContacts() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) {
            return this.contacts;
        }
        return this.contacts.filter((contact) =>
            [contact.name, contact.businessType, contact.phone, contact.email]
                .filter(Boolean)
                .some((value) => value.toLowerCase().includes(term))
        );
    }

    get hasContacts() {
        return this.filteredContacts.length > 0;
    }

    get contactCount() {
        return this.contacts.length;
    }

    get countLabel() {
        const total = this.contacts.length;
        return total === 1 ? '1 contact' : `${total} contacts`;
    }

    get isSaveDisabled() {
        return this.isSaving;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleOpenModal() {
        this.form = { ...EMPTY_FORM };
        this.isModalOpen = true;
    }

    handleCloseModal() {
        this.isModalOpen = false;
        this.form = { ...EMPTY_FORM };
    }

    handleFormChange(event) {
        const field = event.target.dataset.field;
        if (field) {
            this.form = { ...this.form, [field]: event.target.value };
        }
    }

    async handleCreate() {
        this.isSaving = true;
        try {
            await createContact({
                firstName: this.form.firstName,
                lastName: this.form.lastName,
                phone: this.form.phone,
                email: this.form.email,
                businessType: this.form.businessType,
                notes: this.form.notes
            });
            this.toast('Contact added', 'success');
            this.isModalOpen = false;
            this.form = { ...EMPTY_FORM };
            await this.reload();
        } catch (error) {
            this.toast(this.extractError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleToggleNotes(event) {
        const contactId = event.currentTarget.dataset.id;
        this.expandedContactId = this.expandedContactId === contactId ? undefined : contactId;
        this.noteDraft = '';
        this.contacts = this.contacts.map((contact) => ({
            ...contact,
            isExpanded: contact.id === this.expandedContactId,
            rowClass: contact.id === this.expandedContactId ? 'bdc-row bdc-row-expanded' : 'bdc-row'
        }));
    }

    handleNoteDraftChange(event) {
        this.noteDraft = event.target.value || '';
    }

    async handleSaveNote(event) {
        const contactId = event.currentTarget.dataset.id;
        if (!this.noteDraft.trim()) {
            this.toast('Enter a note before saving.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            await saveNote({ accountId: contactId, body: this.noteDraft });
            this.noteDraft = '';
            this.toast('Note saved', 'success');
            await this.reload();
        } catch (error) {
            this.toast(this.extractError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async reload() {
        if (this.wiredContactsResult) {
            await refreshApex(this.wiredContactsResult);
            this.contacts = this.contacts.map((contact) => ({
                ...contact,
                isExpanded: contact.id === this.expandedContactId,
                rowClass: contact.id === this.expandedContactId ? 'bdc-row bdc-row-expanded' : 'bdc-row'
            }));
        }
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ message, variant }));
    }

    extractError(error) {
        if (!error) {
            return 'Something went wrong.';
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (Array.isArray(error.body) && error.body.length) {
            return error.body[0].message;
        }
        return error.message || 'Something went wrong.';
    }
}