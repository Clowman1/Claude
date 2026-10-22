import { LightningElement, api } from 'lwc';
import { createRecord } from 'lightning/uiRecordApi';
import { reduceApexError, showPortalToast } from 'c/portalUtils';

// Slim New Note modal (mockup B, 2026-10-08). Replaces the /apex/AddNewNote pop-up window.
// The chip becomes the note's Subject; Type__c stays 'Note' so it shows on the Notes tab,
// in Last_Note__c and in the Lead Team notification.
const LOOKUP_BY_OBJECT = { Lead: 'Lead__c', Transaction__c: 'Transaction__c', Account: 'Account__c' };
const TYPES = ['General', 'Borrower call', 'Realtor', 'Docs'];

export default class LoWsNoteModal extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api recordName;

    noteType = 'General';
    body = '';
    pinned = false;
    saving = false;
    error;

    connectedCallback() {
        this._onKeydown = (event) => {
            if (event.key === 'Escape') this.close();
        };
        window.addEventListener('keydown', this._onKeydown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._onKeydown);
    }

    renderedCallback() {
        if (!this._focused) {
            this._focused = true;
            this.template.querySelector('textarea')?.focus();
        }
    }

    get isLeadNote() {
        return this.objectApiName === 'Lead';
    }

    get typeChips() {
        return TYPES.map((t) => ({
            label: t,
            pressed: String(t === this.noteType),
            className: t === this.noteType ? 'chip chip-on' : 'chip'
        }));
    }

    get saveDisabled() {
        return this.saving || !this.body.trim();
    }

    get saveLabel() {
        return this.saving ? 'Saving…' : 'Save note';
    }

    handleType(event) {
        this.noteType = event.currentTarget.dataset.type;
    }

    handleBody(event) {
        this.body = event.target.value;
    }

    handlePin(event) {
        this.pinned = event.target.checked;
    }

    handleBackdrop(event) {
        if (event.target === event.currentTarget) this.close();
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        const lookup = LOOKUP_BY_OBJECT[this.objectApiName];
        if (!lookup || this.saveDisabled) {
            return;
        }
        this.saving = true;
        this.error = undefined;
        // Keep the subject the Lead Team email has always used for a plain lead note.
        const subject = this.noteType === 'General' && this.isLeadNote ? 'Lead Update' : this.noteType;
        try {
            await createRecord({
                apiName: 'Enhanced_Note__c',
                fields: {
                    [lookup]: this.recordId,
                    Type__c: 'Note',
                    Subject__c: subject,
                    Body__c: this.body.trim(),
                    Is_Pinned__c: this.pinned
                }
            });
            showPortalToast(this, 'Note saved', '', 'success');
            this.dispatchEvent(new CustomEvent('saved'));
        } catch (error) {
            this.error = reduceApexError(error);
        } finally {
            this.saving = false;
        }
    }
}