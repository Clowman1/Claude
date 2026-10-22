import { LightningElement, api } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';
import logCommunication from '@salesforce/apex/ExternalLoPortalController.logCommunication';
import { reduceApexError } from 'c/portalUtils';

const CHANNELS = [
    { id: 'call', label: 'Call' },
    { id: 'text', label: 'Text' },
    { id: 'email', label: 'Email' },
    { id: 'in-person', label: 'In person' },
    { id: 'video', label: 'Video' }
];

const OUTCOMES = {
    call: [
        { id: 'connected', label: 'Connected — spoke with them' },
        { id: 'left-voicemail', label: 'Left a voicemail' },
        { id: 'no-answer', label: 'No answer — no voicemail left' },
        { id: 'meeting-set', label: 'Connected — meeting scheduled' },
        { id: 'application-started', label: 'Connected — application started' },
        { id: 'not-interested', label: 'Connected — not interested right now' }
    ],
    text: [
        { id: 'replied', label: 'They replied' },
        { id: 'sent-no-reply', label: 'Sent — no reply yet' },
        { id: 'meeting-set', label: 'Replied — meeting scheduled' },
        { id: 'not-interested', label: 'Replied — not interested right now' }
    ],
    email: [
        { id: 'replied', label: 'They replied' },
        { id: 'sent-no-reply', label: 'Sent — no reply yet' },
        { id: 'meeting-set', label: 'Replied — meeting scheduled' },
        { id: 'application-started', label: 'Replied — application started' },
        { id: 'bounced', label: 'Bounced / undeliverable' },
        { id: 'not-interested', label: 'Replied — not interested right now' }
    ],
    'in-person': [
        { id: 'met', label: 'Met in person' },
        { id: 'meeting-set', label: 'Met — next meeting scheduled' },
        { id: 'application-started', label: 'Met — application started' },
        { id: 'no-show', label: 'They did not show' },
        { id: 'not-interested', label: 'Met — not interested right now' }
    ],
    video: [
        { id: 'connected', label: 'Attended — spoke with them' },
        { id: 'meeting-set', label: 'Attended — follow-up scheduled' },
        { id: 'application-started', label: 'Attended — application started' },
        { id: 'no-show', label: 'They did not join' },
        { id: 'not-interested', label: 'Attended — not interested right now' }
    ]
};

export default class PortalCommunicationModal extends LightningElement {
    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
    }

    @api targetRecordId;
    @api objectApiName;
    @api subjectName;
    @api subjectContext;
    @api goalCredit;
    @api phone;
    @api email;

    channel = 'call';
    outcome = OUTCOMES.call[0].id;
    notes = '';
    followUp = 'tomorrow';
    followUpError;
    saving = false;
    errorMessage;

    _open = false;

    @api
    get open() {
        return this._open;
    }

    set open(value) {
        this._open = value;
        if (value) {
            this.resetForm();
        }
    }

    get channels() {
        return CHANNELS.map((item) => ({
            ...item,
            className: item.id === this.channel ? 'channel-btn channel-btn-active' : 'channel-btn'
        }));
    }

    get outcomeOptions() {
        return OUTCOMES[this.channel] || OUTCOMES.call;
    }

    get saveButtonLabel() {
        return this.saving ? 'Saving…' : 'Save activity';
    }

    get modalTitle() {
        return this.subjectName ? `Log communication — ${this.subjectName}` : 'Log communication';
    }

    handleChannelClick(event) {
        this.channel = event.currentTarget.dataset.channel;
        this.outcome = this.outcomeOptions[0].id;
    }

    handleOutcomeChange(event) {
        this.outcome = event.target.value;
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    // c-lo-ws-follow-up-picker: general = Task with an 8 AM reminder, exact = calendar Event.
    handleFollowUpChange(event) {
        this.followUp = event.detail.value;
        this.followUpError = event.detail.error;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    get resolvedObjectApiName() {
        return this.objectApiName || 'Lead';
    }

    async handleSave() {
        if (!this.targetRecordId) {
            this.errorMessage = 'A record is required to log communication.';
            return;
        }
        if (!this.notes || this.notes.trim().length < 3) {
            this.errorMessage = 'Add a short note so the activity history stays useful.';
            return;
        }
        if (this.followUpError) {
            this.errorMessage = this.followUpError;
            return;
        }
        this.errorMessage = undefined;
        this.saving = true;
        try {
            const result = await logCommunication({
                recordId: this.targetRecordId,
                objectApiName: this.resolvedObjectApiName,
                channel: this.channel,
                outcome: this.outcome,
                notes: this.notes,
                followUpOption: this.followUp
            });
            this.dispatchEvent(
                new CustomEvent('logged', {
                    detail: { message: result.userMessage }
                })
            );
            this.handleClose();
        } catch (error) {
            this.errorMessage = reduceApexError(error);
        } finally {
            this.saving = false;
        }
    }

    resetForm() {
        this.channel = 'call';
        this.outcome = OUTCOMES.call[0].id;
        this.notes = '';
        this.followUp = 'tomorrow';
        this.followUpError = undefined;
        this.errorMessage = undefined;
        this.saving = false;
    }
}