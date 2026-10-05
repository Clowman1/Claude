import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkspace from '@salesforce/apex/RealtorEventWorkspaceController.getWorkspace';
import addInvitees from '@salesforce/apex/RealtorEventWorkspaceController.addInvitees';
import removeInvitee from '@salesforce/apex/RealtorEventWorkspaceController.removeInvitee';
import removeInvitees from '@salesforce/apex/RealtorEventWorkspaceController.removeInvitees';
import deleteRealtorEvent from '@salesforce/apex/RealtorEventWorkspaceController.deleteRealtorEvent';
import updateInviteStatus from '@salesforce/apex/RealtorEventWorkspaceController.updateInviteStatus';
import searchPersonAccounts from '@salesforce/apex/RealtorEventWorkspaceController.searchPersonAccounts';
import getInvitationDraft from '@salesforce/apex/RealtorEventWorkspaceController.getInvitationDraft';
import sendInvitations from '@salesforce/apex/RealtorEventWorkspaceController.sendInvitations';
import resendInvitation from '@salesforce/apex/RealtorEventWorkspaceController.resendInvitation';
import searchReachEmployees from '@salesforce/apex/RealtorEventWorkspaceController.searchReachEmployees';
import addCoHosts from '@salesforce/apex/RealtorEventWorkspaceController.addCoHosts';
import removeCoHost from '@salesforce/apex/RealtorEventWorkspaceController.removeCoHost';
import addAllNickleyTeamInvitees from '@salesforce/apex/RealtorEventWorkspaceController.addAllNickleyTeamInvitees';

export default class RealtorEventWorkspace extends LightningElement {
    @api recordId; workspace; isLoading = true; selectedIds = []; selectedInviteeIds = []; searchTerm = ''; isDeletingEvent = false;
    personSearchTerm = ''; personSearchResults = []; isSearchingPeople = false; personSearchTimer;
    coHostSearchTerm = ''; coHostSearchResults = []; isSearchingCoHosts = false; coHostSearchTimer; isAddingAllNickleyTeam = false;
    showInvitationModal = false; invitationDraft; isSendingInvitations = false; summaryModalGroup;
    connectedCallback() { this.loadWorkspace(); }
    async loadWorkspace() {
        this.isLoading = true;
        try { this.workspace = await getWorkspace({ campaignId: this.recordId }); this.selectedIds = []; this.selectedInviteeIds = []; }
        catch (error) { this.handleError(error, 'Unable to load event workspace'); }
        finally { this.isLoading = false; }
    }
    get isEvent() { return this.workspace?.isEvent; }
    get hostMessage() { return `${this.workspace?.hostName || 'Campaign owner'}'s assigned Nickley Realtors`; }
    get availableRealtors() {
        const term = this.searchTerm.trim().toLowerCase();
        return (this.workspace?.realtors || []).filter((r) => !r.campaignMemberId).filter((r) => !term || `${r.name} ${r.phone || ''} ${r.email || ''}`.toLowerCase().includes(term)).map((r) => ({ ...r, checked: this.selectedIds.includes(r.contactId) }));
    }
    get invitees() {
        return (this.workspace?.invitees || []).map((invitee) => ({
            ...invitee,
            disableResend: !invitee.hasEmail,
            checked: this.selectedInviteeIds.includes(invitee.campaignMemberId),
            emailBadgeClass: invitee.emailDelivered ? 'delivery-badge delivery-badge-ok' : 'delivery-badge delivery-badge-idle',
            smsBadgeClass: invitee.smsDelivered
                ? 'delivery-badge delivery-badge-ok'
                : (invitee.smsFailed ? 'delivery-badge delivery-badge-fail' : 'delivery-badge delivery-badge-idle'),
            // Hovering a failed text shows the provider's reason rather than just "Text failed".
            smsBadgeTitle: invitee.smsError || invitee.smsDeliveredText
        }));
    }
    get isSummaryModalOpen() { return Boolean(this.summaryModalGroup); }
    get summaryModalPeople() {
        const people = this.invitees;
        let filtered = people;
        if (this.summaryModalGroup === 'confirmed') {
            filtered = people.filter((person) => person.memberStatus === 'Yes - Attending');
        } else if (this.summaryModalGroup === 'declined') {
            filtered = people.filter((person) => person.memberStatus === 'No - Unable to Attend');
        } else if (this.summaryModalGroup === 'awaiting') {
            filtered = people.filter((person) => person.memberStatus !== 'Yes - Attending' && person.memberStatus !== 'No - Unable to Attend');
        }
        return filtered.map((person) => ({
            ...person,
            displayEmail: person.email || 'No email on file',
            displayPhone: person.phone || 'No phone on file',
            statusClass: person.memberStatus === 'Yes - Attending'
                ? 'response-pill response-pill_confirmed'
                : person.memberStatus === 'No - Unable to Attend'
                    ? 'response-pill response-pill_declined'
                    : 'response-pill response-pill_awaiting'
        }));
    }
    get hasSummaryModalPeople() { return this.summaryModalPeople.length > 0; }
    get summaryModalTitle() {
        return { invited: 'Invited People', confirmed: 'Confirmed Attendees', declined: 'Declined Invitations', awaiting: 'Awaiting Response' }[this.summaryModalGroup] || 'Event Responses';
    }
    get summaryModalSubtitle() {
        return { invited: 'Everyone currently included on this event.', confirmed: 'People who responded Yes — attending.', declined: 'People who responded that they cannot attend.', awaiting: 'People whose invitation is pending or who have not responded.' }[this.summaryModalGroup] || '';
    }
    get summaryModalCountLabel() {
        const count = this.summaryModalPeople.length;
        return `${count} ${count === 1 ? 'person' : 'people'}`;
    }
    get selectedCountLabel() { return `${this.selectedIds.length} selected`; }
    get hasSelectedInvitees() { return this.selectedIds.length > 0; }
    get disableAddInvitees() { return !this.hasSelectedInvitees; }
    get noAvailableRealtors() { return this.availableRealtors.length === 0; }
    get noInvitees() { return this.invitees.length === 0; }
    get selectedInviteeCountLabel() { return `${this.selectedInviteeIds.length} selected`; }
    get hasSelectedInvitedMembers() { return this.selectedInviteeIds.length > 0; }
    get hasInvitedMembers() { return this.invitees.length > 0; }
    get disableInviteeSelectAll() { return !this.hasInvitedMembers; }
    get disableRemoveSelectedInvitees() { return !this.hasSelectedInvitedMembers; }
    get allInviteesSelected() { return this.hasInvitedMembers && this.invitees.every((invitee) => this.selectedInviteeIds.includes(invitee.campaignMemberId)); }
    get hasAvailableRealtors() { return this.availableRealtors.length > 0; }
    get allAvailableSelected() { return this.hasAvailableRealtors && this.availableRealtors.every((realtor) => this.selectedIds.includes(realtor.contactId)); }
    get disableSelectAll() { return !this.hasAvailableRealtors; }
    get showPersonSearchResults() { return this.personSearchTerm.trim().length >= 2; }
    get noPersonSearchResults() { return this.showPersonSearchResults && !this.isSearchingPeople && this.personSearchResults.length === 0; }
    get coHosts() { return this.workspace?.coHosts || []; }
    get hasCoHosts() { return this.coHosts.length > 0; }
    get showCoHostSearchResults() { return this.coHostSearchTerm.trim().length >= 2; }
    get noCoHostSearchResults() { return this.showCoHostSearchResults && !this.isSearchingCoHosts && this.coHostSearchResults.length === 0; }
    get nickleyTeamButtonLabel() { return this.workspace?.allNickleyTeamInvited ? 'All Nickley Team Added' : `Invite All Nickley Team (${this.workspace?.nickleyTeamCount || 0})`; }
    get disableNickleyTeamButton() { return this.isAddingAllNickleyTeam || this.workspace?.allNickleyTeamInvited || !(this.workspace?.nickleyTeamCount > 0); }
    get statusOptions() { return this.workspace?.statusOptions || []; }
    get noPendingInvitees() { return !(this.workspace?.pendingInviteeCount > 0); }
    get sendDisabled() { return this.isSendingInvitations || this.noPendingInvitees || !this.invitationDraft?.emailSubject || !this.invitationDraft?.emailBody || !this.invitationDraft?.smsBody; }
    handleSearch(event) { this.searchTerm = event.target.value; }
    handlePersonSearch(event) {
        this.personSearchTerm = event.target.value;
        clearTimeout(this.personSearchTimer);
        if (this.personSearchTerm.trim().length < 2) { this.personSearchResults = []; return; }
        this.personSearchTimer = setTimeout(() => this.runPersonSearch(), 250);
    }
    async runPersonSearch() {
        this.isSearchingPeople = true;
        try {
            const results = await searchPersonAccounts({ campaignId: this.recordId, searchTerm: this.personSearchTerm });
            this.personSearchResults = (results || []).filter((person) => !person.campaignMemberId);
        } catch (error) { this.handleError(error, 'Unable to search Person Accounts'); }
        finally { this.isSearchingPeople = false; }
    }
    handleCoHostSearch(event) {
        this.coHostSearchTerm = event.target.value;
        clearTimeout(this.coHostSearchTimer);
        if (this.coHostSearchTerm.trim().length < 2) { this.coHostSearchResults = []; return; }
        this.coHostSearchTimer = setTimeout(() => this.runCoHostSearch(), 250);
    }
    async runCoHostSearch() {
        this.isSearchingCoHosts = true;
        try {
            const results = await searchReachEmployees({ searchTerm: this.coHostSearchTerm });
            this.coHostSearchResults = (results || []).filter((person) => !this.coHosts.some((coHost) => coHost.userId === person.userId));
        } catch (error) { this.handleError(error, 'Unable to search Reach employees'); }
        finally { this.isSearchingCoHosts = false; }
    }
    handleSelect(event) { const id = event.target.dataset.id; this.selectedIds = event.target.checked ? [...new Set([...this.selectedIds, id])] : this.selectedIds.filter((value) => value !== id); }
    handleSelectAll(event) {
        const visibleIds = this.availableRealtors.map((realtor) => realtor.contactId);
        this.selectedIds = event.target.checked
            ? [...new Set([...this.selectedIds, ...visibleIds])]
            : this.selectedIds.filter((id) => !visibleIds.includes(id));
    }
    async handleAddInvitees() { try { await addInvitees({ campaignId: this.recordId, contactIds: this.selectedIds }); this.toast('Invitees added', 'The selected realtors are now on this event invite list.', 'success'); await this.loadWorkspace(); } catch (error) { this.handleError(error, 'Unable to add invitees'); } }
    async handleAddPersonAccount(event) { try { await addInvitees({ campaignId: this.recordId, contactIds: [event.currentTarget.dataset.id] }); this.toast('Invitee added', 'The Person Account was added to this event.', 'success'); await this.loadWorkspace(); await this.runPersonSearch(); } catch (error) { this.handleError(error, 'Unable to add Person Account'); } }
    async handleAddCoHost(event) {
        try {
            await addCoHosts({ campaignId: this.recordId, userIds: [event.currentTarget.dataset.id] });
            this.coHostSearchTerm = ''; this.coHostSearchResults = [];
            this.toast('Co-host added', 'This team member will be CC’d on invitations and their signature card will be included.', 'success');
            await this.loadWorkspace();
        } catch (error) { this.handleError(error, 'Unable to add co-host'); }
    }
    async handleRemoveCoHost(event) {
        try { await removeCoHost({ coHostRecordId: event.currentTarget.dataset.id }); this.toast('Co-host removed', 'This person will no longer be CC’d on future invitations.', 'success'); await this.loadWorkspace(); }
        catch (error) { this.handleError(error, 'Unable to remove co-host'); }
    }
    async handleInviteAllNickleyTeam() {
        try {
            this.isAddingAllNickleyTeam = true;
            const added = await addAllNickleyTeamInvitees({ campaignId: this.recordId });
            this.toast('Nickley team added', `${added} additional Nickley team member(s) were added to the invite list.`, 'success');
            await this.loadWorkspace();
        } catch (error) { this.handleError(error, 'Unable to add the Nickley team'); }
        finally { this.isAddingAllNickleyTeam = false; }
    }
    async handleRemove(event) { try { await removeInvitee({ campaignMemberId: event.currentTarget.dataset.id }); this.toast('Invitee removed', 'The person was removed from this event.', 'success'); await this.loadWorkspace(); } catch (error) { this.handleError(error, 'Unable to remove invitee'); } }
    handleInviteeSelect(event) {
        const id = event.target.dataset.id;
        if (!id) return;
        this.selectedInviteeIds = event.target.checked
            ? [...new Set([...this.selectedInviteeIds, id])]
            : this.selectedInviteeIds.filter((value) => value !== id);
    }
    handleSelectAllInvitees(event) {
        this.selectedInviteeIds = event.target.checked
            ? this.invitees.map((invitee) => invitee.campaignMemberId).filter(Boolean)
            : [];
    }
    async handleRemoveSelectedInvitees() {
        const ids = [...this.selectedInviteeIds];
        if (!ids.length) return;
        const plural = ids.length === 1 ? '' : 's';
        if (!window.confirm(`Remove ${ids.length} selected invitee${plural} from this event?`)) return;
        try {
            await removeInvitees({ campaignMemberIds: ids });
            this.toast('Invitees removed', `${ids.length} invitee${plural} removed from this event.`, 'success');
            await this.loadWorkspace();
        } catch (error) { this.handleError(error, 'Unable to remove selected invitees'); }
    }
    async handleDeleteEvent() {
        const name = this.workspace?.campaignName || 'this event';
        if (!window.confirm(`Delete ${name}? This removes the event, invite list, co-host links, and any linked Salesforce calendar event. This cannot be undone.`)) return;
        this.isDeletingEvent = true;
        try {
            await deleteRealtorEvent({ campaignId: this.recordId });
            this.toast('Event deleted', `${name} was deleted.`, 'success');
            window.location.assign('/lightning/o/Campaign/list?filterName=Recent');
        } catch (error) { this.handleError(error, 'Unable to delete event'); }
        finally { this.isDeletingEvent = false; }
    }
    async handleStatus(event) { try { await updateInviteStatus({ campaignMemberId: event.target.dataset.id, status: event.detail.value }); await this.loadWorkspace(); } catch (error) { this.handleError(error, 'Unable to update RSVP status'); } }
    async handleEventSaved() { this.toast('Event details saved', 'The event details were updated.', 'success'); await this.loadWorkspace(); }
    handleEventSaveError(event) { this.handleError(event.detail, 'Unable to save event details'); }
    async handleResendInvitation(event) { try { const result = await resendInvitation({ campaignMemberId: event.currentTarget.dataset.id }); this.toast('Invitation resent', result.message, 'success'); } catch (error) { this.handleError(error, 'Unable to resend invitation'); } }
    async handleOpenInvitationModal() {
        try {
            this.isLoading = true;
            this.invitationDraft = await getInvitationDraft({ campaignId: this.recordId });
            this.showInvitationModal = true;
        } catch (error) { this.handleError(error, 'Unable to prepare invitations'); }
        finally { this.isLoading = false; }
    }
    handleInvitationFieldChange(event) { this.invitationDraft = { ...this.invitationDraft, [event.target.name]: event.target.value }; }
    openSummaryModal(event) { this.summaryModalGroup = event.currentTarget.dataset.group; }
    closeSummaryModal() { this.summaryModalGroup = null; }
    handleCloseInvitationModal() { if (!this.isSendingInvitations) this.showInvitationModal = false; }
    async handleSendInvitations() {
        try {
            this.isSendingInvitations = true;
            const result = await sendInvitations({ campaignId: this.recordId, emailSubject: this.invitationDraft.emailSubject, emailBody: this.invitationDraft.emailBody, smsBody: this.invitationDraft.smsBody });
            this.toast('Invitations queued', result.message, 'success');
            this.showInvitationModal = false;
            await this.loadWorkspace();
        } catch (error) { this.handleError(error, 'Unable to send invitations'); }
        finally { this.isSendingInvitations = false; }
    }
    toast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
    handleError(error, title) { this.toast(title, error?.body?.message || error?.message || 'An unexpected error occurred.', 'error'); }
}