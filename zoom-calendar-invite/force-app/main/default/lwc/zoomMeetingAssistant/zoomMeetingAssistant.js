import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import getLeadContext from '@salesforce/apex/ZoomMeetingController.getLeadContext';
import scheduleMeeting from '@salesforce/apex/ZoomMeetingController.scheduleMeeting';
import getFreshStartUrl from '@salesforce/apex/ZoomMeetingController.getFreshStartUrl';
import refreshRecordings from '@salesforce/apex/ZoomMeetingController.refreshRecordings';

export default class ZoomMeetingAssistant extends NavigationMixin(LightningElement) {
    @api recordId;
    context;
    isAvailable = true;
    isLoading = true;
    isSaving = false;
    topic = '';
    startDate = '';
    startTime = '';
    duration = '30';
    agenda = '';
    hostUserId = '';
    showInvitationModal = false;
    borrowerEmail = '';
    additionalEmails = '';
    invitationSubject = '';
    invitationBody = '';
    meetingTemplate = 'preapproval';

    connectedCallback() {
        this.loadContext();
    }

    async loadContext() {
        this.isLoading = true;
        try {
            this.context = await getLeadContext({ leadId: this.recordId });
            this.isAvailable = true;
            this.hostUserId = this.context?.hostOptions?.[0]?.value || '';
            if (!this.topic) this.topic = this.context?.leadName ? `Zoom Meeting - ${this.context.leadName}` : 'Zoom Meeting';
        } catch (error) {
            // The assistant is optional. Users who are not provisioned for Zoom
            // (including users without Apex class access) should not see an
            // initialization error on every Lead page they visit.
            this.isAvailable = false;
        } finally {
            this.isLoading = false;
        }
    }

    // The first option is always the running user, so anything beyond it means this
    // user can schedule on someone else's behalf and the picker is worth showing.
    get hasOtherHosts() {
        return (this.context?.hostOptions || []).length > 1;
    }

    get hostOptions() {
        return (this.context?.hostOptions || []).map(({ label, value }) => ({ label, value }));
    }

    get durationOptions() {
        return [15, 30, 45, 60, 90, 120, 150, 180, 210, 240].map((minutes) => ({ label: `${minutes} minutes`, value: String(minutes) }));
    }

    get startTimeOptions() {
        const options = [];
        for (let hour = 7; hour <= 21; hour += 1) {
            for (const minute of [0, 15, 30, 45]) {
                if (hour === 21 && minute > 0) continue;
                const value = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00.000`;
                const displayHour = hour % 12 || 12;
                options.push({ label: `${displayHour}:${String(minute).padStart(2, '0')} ${hour < 12 ? 'AM' : 'PM'}`, value });
            }
        }
        return options;
    }

    get meetings() {
        return (this.context?.meetings || []).map((meeting) => ({
            ...meeting,
            startLabel: meeting.scheduledStart ? new Intl.DateTimeFormat('en-US', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(meeting.scheduledStart)) : ''
        }));
    }

    get hasMeetings() {
        return this.meetings.length > 0;
    }

    handleInput(event) {
        this[event.target.dataset.field] = event.target.value;
    }

    handleSchedule() {
        if (!this.topic.trim() || !this.startDate || !this.startTime) {
            this.toast('Missing details', 'Enter a topic, start date, and start time.', 'error');
            return;
        }
        this.borrowerEmail = this.context?.leadEmail || '';
        this.additionalEmails = '';
        this.applyTemplate();
        this.showInvitationModal = true;
    }

    handleCloseInvitationModal() {
        if (!this.isSaving) this.showInvitationModal = false;
    }

    get templateOptions() {
        return [
            { label: 'Pre-Approval Review', value: 'preapproval' },
            { label: 'Realtor Agent Meeting', value: 'realtor' }
        ];
    }

    handleTemplateChange(event) {
        this.meetingTemplate = event.target.value;
        this.applyTemplate();
    }

    // Switching template rewrites both fields from scratch, so any hand-edits made to the
    // previous template's copy are deliberately discarded rather than merged.
    applyTemplate() {
        const invitation = this.buildInvitation(this.meetingTemplate);
        this.invitationSubject = invitation.subject;
        this.invitationBody = invitation.body;
    }

    buildInvitation(template) {
        const fullName = (this.context?.leadName || '').trim();
        const firstName = fullName.split(/\s+/)[0] || 'there';
        if (template === 'realtor') {
            return {
                subject: `Your Zoom with BranTheMortgageMan is Set${fullName ? ` - ${fullName}` : ''}`,
                body: `Hi ${firstName},\n\nThank you for taking the time to meet with Brandon! We're looking forward to connecting with you.\n\nJust a quick reminder that your meeting will be held via Zoom. I've included the Zoom information below for easy reference:\n\nWhen: ${this.formatMeetingDateTime()}\n\nZoom Link:\n{ZoomLink}\n\nIf you have any questions before the meeting or run into any scheduling conflicts, please reach out to me directly and I'll be happy to help.\n\nLooking forward to the conversation!`
            };
        }
        return {
            subject: 'Your Mortgage Pre-Approval Review Is Scheduled',
            body: `Hi ${firstName},\n\nI'm looking forward to connecting with you to review your mortgage pre-approval, answer any questions, and walk through the next steps toward your home purchase.\n\nHere are the details for our Zoom meeting:\n\nWhen: ${this.formatMeetingDateTime()}\nLength: ${this.duration} minutes\nJoin Zoom: {ZoomLink}\n\nPlease feel free to reply to this email if you need to reschedule or would like to add anyone else to the conversation.\n\nI'm excited to continue working with you and help make the mortgage process as clear and comfortable as possible.`
        };
    }

    formatMeetingDateTime() {
        const meetingDate = new Date(`${this.startDate}T${this.startTime}`);
        return new Intl.DateTimeFormat('en-US', {
            weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', hour: 'numeric', minute: '2-digit'
        }).format(meetingDate);
    }

    async handleConfirmSchedule() {
        if (!this.borrowerEmail.trim() && !this.additionalEmails.trim()) {
            this.toast('Recipient required', 'Enter the borrower email or at least one additional recipient.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            const result = await scheduleMeeting({
                leadId: this.recordId,
                topic: this.topic,
                startDateTime: new Date(`${this.startDate}T${this.startTime}`).toISOString(),
                durationMinutes: Number(this.duration),
                agenda: this.agenda,
                borrowerEmail: this.borrowerEmail,
                additionalEmails: this.additionalEmails,
                invitationSubject: this.invitationSubject,
                invitationBody: this.invitationBody,
                hostUserId: this.hostUserId
            });
            this.toast(
                result.invitationSent ? 'Zoom meeting scheduled and invitation sent' : 'Zoom meeting scheduled',
                result.invitationSent ? 'The borrower invitation email was sent.' : `The meeting was saved, but the email could not be sent: ${result.invitationError}`,
                result.invitationSent ? 'success' : 'warning'
            );
            this.showInvitationModal = false;
            this.startDate = '';
            this.startTime = '';
            this.agenda = '';
            await this.loadContext();
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.showError(error, 'Zoom meeting was not scheduled');
        } finally {
            this.isSaving = false;
        }
    }

    async handleStart(event) {
        try {
            const startUrl = await getFreshStartUrl({ zoomMeetingRecordId: event.currentTarget.dataset.id });
            window.open(startUrl, '_blank');
        } catch (error) {
            this.showError(error, 'Unable to launch Zoom');
        }
    }

    handleJoin(event) {
        window.open(event.currentTarget.dataset.url, '_blank');
    }

    async handleRefreshRecordings(event) {
        this.isSaving = true;
        try {
            const count = await refreshRecordings({ zoomMeetingRecordId: event.currentTarget.dataset.id });
            this.toast(
                'Zoom recordings refreshed',
                count ? `${count} recording file${count === 1 ? '' : 's'} imported for this meeting.` : 'No completed recording is available from Zoom yet.',
                count ? 'success' : 'info'
            );
            await this.loadContext();
        } catch (error) {
            this.showError(error, 'Unable to refresh Zoom recordings');
        } finally {
            this.isSaving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error, title) {
        this.toast(title, error?.body?.message || error?.message || 'An unexpected error occurred.', 'error');
    }

}