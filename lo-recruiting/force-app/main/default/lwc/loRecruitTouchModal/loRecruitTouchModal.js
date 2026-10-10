import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import logTouch from '@salesforce/apex/LoRecruitingController.logTouch';
import suggestNextTouch from '@salesforce/apex/LoRecruitingController.suggestNextTouch';
import { errorMessage } from 'c/bdUtils';

const KINDS = ['Call', 'Text', 'Email', 'In person', 'Note'];

// Log touch for a recruit: moves New -> Contacted (or -> Conversation when ticked) and sets the next touch date.
export default class LoRecruitTouchModal extends LightningElement {
    @api recruitId;
    @api recruitName;
    kind = 'Call';
    notes = '';
    conversation = false;
    nextTouch;
    busy = false;
    error;

    connectedCallback() { this.suggest(); }

    async suggest() {
        try {
            this.nextTouch = await suggestNextTouch({ leadId: this.recruitId, conversation: this.conversation });
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    get kindButtons() { return KINDS.map((k) => ({ value: k, cls: 'pill' + (k === this.kind ? ' pill-on' : '') })); }
    get isNote() { return this.kind === 'Note'; }
    get title() { return 'Log touch' + (this.recruitName ? ' · ' + this.recruitName : ''); }

    pickKind(event) { this.kind = event.currentTarget.dataset.value; }
    handleNotes(event) { this.notes = event.target.value; }
    handleConversation(event) {
        this.conversation = event.target.checked;
        this.suggest();
    }
    handleNext(event) { this.nextTouch = event.target.value || null; }

    async save() {
        this.busy = true;
        this.error = null;
        try {
            await logTouch({ leadId: this.recruitId, kind: this.kind, notes: this.notes, conversation: this.conversation, nextTouch: this.nextTouch });
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
