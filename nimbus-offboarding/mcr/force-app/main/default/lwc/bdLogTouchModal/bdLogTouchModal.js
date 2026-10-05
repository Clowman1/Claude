import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import logTouch from '@salesforce/apex/BdCommandCenterController.logTouch';
import { errorMessage } from 'c/bdUtils';

const KINDS = ['In person', 'Call', 'Text', 'Email', 'Note'];

// One Log touch dialog for the home rows, the partner workspace and the account page.
export default class BdLogTouchModal extends LightningElement {
    @api partnerId;
    @api partnerName;
    kind = 'In person';
    notes = '';
    busy = false;
    error;

    get kindButtons() {
        return KINDS.map((k) => ({ value: k, cls: 'pill' + (k === this.kind ? ' pill-on' : '') }));
    }
    get isNote() { return this.kind === 'Note'; }
    get title() { return 'Log touch' + (this.partnerName ? ' · ' + this.partnerName : ''); }

    pickKind(event) { this.kind = event.currentTarget.dataset.value; }
    handleNotes(event) { this.notes = event.target.value; }

    async save() {
        this.busy = true;
        this.error = null;
        try {
            await logTouch({ accountId: this.partnerId, kind: this.kind, notes: this.notes });
            this.dispatchEvent(new ShowToastEvent({ title: this.isNote ? 'Note saved' : 'Touch logged', variant: 'success' }));
            this.dispatchEvent(new CustomEvent('logged'));
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }

    close() {
        if (!this.busy) this.dispatchEvent(new CustomEvent('close'));
    }
}