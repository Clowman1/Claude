import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLeadContext from '@salesforce/apex/ZoomMeetingController.getLeadContext';
import scheduleMeeting from '@salesforce/apex/ZoomMeetingController.scheduleMeeting';
import getFreshStartUrl from '@salesforce/apex/ZoomMeetingController.getFreshStartUrl';
import refreshRecordings from '@salesforce/apex/ZoomMeetingController.refreshRecordings';
import { errorMessage } from 'c/bdUtils';

// The BD version of zoomMeetingAssistant: same ZoomMeetingController calls, partner wording,
// dashboard styling, and no "Schedule For" - a BD rep only books under their own Zoom account
// (enforced server-side in ZoomMeetingController too).
export default class BdZoomPanel extends LightningElement {
    _recordId;
    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        if (value !== this._recordId) {
            this._recordId = value;
            this.topic = '';
            this.loadContext();
        }
    }

    context;
    loading = true;
    unavailable = false;
    busy = false;
    topic = '';
    startDate = '';
    startTime = '';
    duration = '30';
    agenda = '';
    showInvite = false;
    partnerEmail = '';
    additionalEmails = '';
    invitationSubject = '';
    invitationBody = '';
    template = 'intro';

    async loadContext() {
        if (!this._recordId) return;
        this.loading = true;
        try {
            this.context = await getLeadContext({ leadId: this._recordId });
            this.unavailable = false;
            if (!this.topic) this.topic = this.context && this.context.leadName ? `Zoom · ${this.context.leadName}` : 'Zoom meeting';
        } catch (e) {
            this.unavailable = true;
        } finally {
            this.loading = false;
        }
    }

    get durationOptions() {
        return [15, 30, 45, 60, 90, 120].map((m) => ({ label: `${m} minutes`, value: String(m) }));
    }

    get startTimeOptions() {
        const options = [];
        for (let hour = 7; hour <= 21; hour += 1) {
            for (const minute of [0, 15, 30, 45]) {
                if (hour === 21 && minute > 0) continue;
                const value = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00.000`;
                options.push({ label: `${hour % 12 || 12}:${String(minute).padStart(2, '0')} ${hour < 12 ? 'AM' : 'PM'}`, value });
            }
        }
        return options;
    }

    get templateButtons() {
        return [{ value: 'intro', label: 'Partner intro' }, { value: 'checkin', label: 'Partner check-in' }]
            .map((t) => ({ ...t, cls: 'sg' + (t.value === this.template ? ' sg-on' : '') }));
    }

    get meetings() {
        const fmt = new Intl.DateTimeFormat('en-US', { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
        const now = Date.now();
        return ((this.context && this.context.meetings) || []).map((m) => {
            const start = m.scheduledStart ? new Date(m.scheduledStart) : null;
            const upcoming = start && start.getTime() + (m.durationMinutes || 30) * 60000 > now;
            return {
                ...m,
                startLabel: start ? fmt.format(start) : '',
                upcoming,
                statusCls: 'chip ' + (upcoming ? 'yes' : 'oth'),
                statusLabel: upcoming ? 'Upcoming' : (m.status || 'Past'),
                hasRecordings: (m.recordings || []).length > 0
            };
        });
    }
    get hasMeetings() { return this.meetings.length > 0; }
    get senderLine() {
        return this.context ? `${this.context.senderName} (${this.context.senderEmail})` : '';
    }
    get scheduleDisabled() { return this.busy || !this.topic.trim() || !this.startDate || !this.startTime; }

    handleInput(event) {
        this[event.target.dataset.field] = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
    }

    openInvite() {
        this.partnerEmail = (this.context && this.context.leadEmail) || '';
        this.additionalEmails = '';
        this.applyTemplate();
        this.showInvite = true;
    }
    closeInvite() { if (!this.busy) this.showInvite = false; }

    pickTemplate(event) {
        this.template = event.currentTarget.dataset.value;
        this.applyTemplate();
    }

    // Switching template rewrites the subject and body, discarding edits (same as the LO tool).
    applyTemplate() {
        const name = ((this.context && this.context.leadName) || '').trim();
        const first = name.split(/\s+/)[0] || 'there';
        const sender = (this.context && this.context.senderName) || '';
        const when = this.meetingWhen();
        if (this.template === 'checkin') {
            this.invitationSubject = `Quick Zoom check-in with ${sender}`;
            this.invitationBody = `Hi ${first},\n\nLooking forward to catching up! I'd love to hear how business is going and share what's new at Reach Home Loans.\n\nWhen: ${when}\nLength: ${this.duration} minutes\nJoin Zoom: {ZoomLink}\n\nIf the time no longer works, just reply and we'll find another.\n\nTalk soon!`;
        } else {
            this.invitationSubject = `Let's connect on Zoom${name ? ` - ${name}` : ''}`;
            this.invitationBody = `Hi ${first},\n\nThanks for making time to connect! I'm looking forward to learning more about your business and sharing how Reach Home Loans takes care of the clients you refer.\n\nWhen: ${when}\nLength: ${this.duration} minutes\nJoin Zoom: {ZoomLink}\n\nFeel free to reply if you need to reschedule or want to bring anyone else from your team.\n\nLooking forward to it!`;
        }
    }

    meetingWhen() {
        if (!this.startDate || !this.startTime) return '';
        return new Intl.DateTimeFormat('en-US', {
            weekday: 'long', month: 'long', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit'
        }).format(new Date(`${this.startDate}T${this.startTime}`));
    }

    async confirmSchedule() {
        if (!this.partnerEmail.trim() && !this.additionalEmails.trim()) {
            this.toast('Recipient required', 'Enter the partner email or at least one other recipient.', 'error');
            return;
        }
        this.busy = true;
        try {
            const result = await scheduleMeeting({
                leadId: this._recordId,
                topic: this.topic,
                startDateTime: new Date(`${this.startDate}T${this.startTime}`).toISOString(),
                durationMinutes: Number(this.duration),
                agenda: this.agenda,
                borrowerEmail: this.partnerEmail,
                additionalEmails: this.additionalEmails,
                invitationSubject: this.invitationSubject,
                invitationBody: this.invitationBody,
                hostUserId: null
            });
            this.toast(
                result.invitationSent ? 'Zoom scheduled and invite sent' : 'Zoom scheduled',
                result.invitationSent ? 'The partner invitation email was sent.' : `Saved, but the email could not be sent: ${result.invitationError}`,
                result.invitationSent ? 'success' : 'warning'
            );
            this.showInvite = false;
            this.startDate = '';
            this.startTime = '';
            this.agenda = '';
            await this.loadContext();
            this.dispatchEvent(new CustomEvent('scheduled'));
        } catch (e) {
            this.toast('Zoom meeting was not scheduled', errorMessage(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    async start(event) {
        try {
            window.open(await getFreshStartUrl({ zoomMeetingRecordId: event.currentTarget.dataset.id }), '_blank');
        } catch (e) {
            this.toast('Unable to launch Zoom', errorMessage(e), 'error');
        }
    }

    join(event) {
        window.open(event.currentTarget.dataset.url, '_blank');
    }

    async importRecording(event) {
        this.busy = true;
        try {
            const count = await refreshRecordings({ zoomMeetingRecordId: event.currentTarget.dataset.id });
            this.toast('Zoom recordings refreshed',
                count ? `${count} recording file${count === 1 ? '' : 's'} imported.` : 'No completed recording is available from Zoom yet.',
                count ? 'success' : 'info');
            await this.loadContext();
        } catch (e) {
            this.toast('Unable to refresh Zoom recordings', errorMessage(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}