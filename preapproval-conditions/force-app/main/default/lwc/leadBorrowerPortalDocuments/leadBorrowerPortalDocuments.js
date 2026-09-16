import { LightningElement, wire, api, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';
import { loadStyle } from 'lightning/platformResourceLoader';
import pulseResources from '@salesforce/resourceUrl/PULSEResources';
import reachInverseLogo from '@salesforce/resourceUrl/reachInverseLogo';
import getData from '@salesforce/apex/LeadDocumentPortalController.initializeData';
import { t, documentsReadyToSend, showCompleted, submitButton } from 'c/leadBorrowerPortalLabels';
import submitPendingDocuments from '@salesforce/apex/LeadDocumentPortalController.submitPendingDocuments';

export default class LeadBorrowerPortalDocuments extends LightningElement {
    @api tableHeaderColor;
    @api tableHeaderTextColor;
    _portalHash;
    @track hashRecordId;
    @track pendingSubmissionCount = 0;
    @track isSubmitting = false;
    @track showSubmittedConfirmation = false;
    isPhone = false;
    requests = [];
    recordId;
    borrowerName;
    contacts = [];
    clearedRequests = [];
    showCleared = false;
    error;
    isLoading = false;
    documentStatus = {
        approved: 0,
        needed: 0,
        requested: 0,
        pending: 0
    };
    reachLogoUrl = reachInverseLogo;

    @api
    get portalHash() {
        return this._portalHash;
    }

    set portalHash(value) {
        this._portalHash = value;
        if (value && value !== this.hashRecordId) {
            this.hashRecordId = value;
            this.loadPortalData();
        }
    }

    connectedCallback() {
        loadStyle(this, pulseResources + '/css/dropZoneStyle.css').catch(error => {
            // The portal remains usable if the shared drop-zone CSS is unavailable.
            console.log(error);
        });

        const root = this.template.host;
        root.style.setProperty('--portal-table-row-header-color', this.tableHeaderColor);
        root.style.setProperty('--portal-table-row-header-text-color', this.tableHeaderTextColor);

        if (FORM_FACTOR === 'Small') {
            this.isPhone = true;
        }

        if (this.portalHash && !this.hashRecordId) {
            this.hashRecordId = this.portalHash;
            this.loadPortalData();
        }
    }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        const hashFromPage = currentPageReference?.state?.id || this.portalHash;
        if (hashFromPage) {
            this.hashRecordId = hashFromPage;
            this.loadPortalData();
        }
    }

    async loadPortalData() {
        if (!this.hashRecordId || this.isLoading) {
            return;
        }

        this.isLoading = true;
        try {
            const data = await getData({
                hashFromURL: this.hashRecordId,
                isInSitePreview: false
            });
            if (data.redirectUrl) {
                window.location.assign(data.redirectUrl);
                return;
            }

            this.applyPortalData(data);
        } catch (error) {
            this.error = error;
        } finally {
            this.isLoading = false;
        }
    }

    async handleRequestUpdated(event) {
        const updatedRequest = event.detail?.request;
        if (updatedRequest?.id) {
            this.requests = this.sortRequests(
                this.requests.map(request => request.id === updatedRequest.id ? updatedRequest : request)
            );
        }

        try {
            await this.refreshPortalData();
        } catch (error) {
            this.showError(error);
        }
    }

    get hasPendingSubmissions() {
        return this.pendingSubmissionCount > 0;
    }

    get labels() {
        const es = this.spanish;
        return {
            welcomeBack: t('Welcome Back', es),
            manageHere: t('You can manage your documents here', es),
            documentsNeeded: t('Documents Needed', es),
            documentsUploaded: t('Documents Uploaded', es),
            documentsApproved: t('Documents Approved', es),
            documentsRequired: t('Documents Required', es),
            intro: t('The documents requested below help your loan team keep your file moving before your loan is converted to a transaction.', es),
            documentName: t('Document Name', es),
            documentDescription: t('Document Description', es),
            status: t('Status', es),
            actions: t('Actions', es),
            submittedTitle: t('Documents Submitted for Review', es),
            submittedSub: t('Your loan team has been notified and will review them shortly.', es),
            dismiss: t('Dismiss', es),
            howToTitle: t('Upload everything, then press Submit', es),
            howToBody: t('Add as many documents as you like - take your time and come back if you need to. Your loan team is not notified until you press Submit Docs for Review, so please remember to press it when you have finished.', es)
        };
    }

    get submitButtonLabel() {
        return submitButton(this.pendingSubmissionCount, this.spanish);
    }

    get pendingSummaryLabel() {
        return documentsReadyToSend(this.pendingSubmissionCount, this.spanish);
    }

    // Removing a file from the basket changes the count without changing any request.
    async handleBasketChange() {
        try {
            await this.refreshPortalData();
        } catch (error) {
            this.showError(error);
        }
    }

    async handleSubmitPending() {
        if (!this.hasPendingSubmissions || this.isSubmitting) {
            return;
        }
        this.isSubmitting = true;
        try {
            const data = await submitPendingDocuments({ hashFromURL: this.hashRecordId });
            this.applyPortalData(data);
            this.showSubmittedConfirmation = true;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    dismissSubmittedConfirmation() {
        this.showSubmittedConfirmation = false;
    }

    handleUploadError(event) {
        this.showError(event.detail?.error);
    }

    spanish = false;

    applyPortalData(data) {
        this.recordId = data.recordId;
        // Set by the Lead. The condition text arrives already translated; this only switches
        // the page chrome around it.
        this.spanish = data.spanish === true;
        this.borrowerName = data.borrowerName;
        this.contacts = this.decorateContacts(data.contacts || []);
        this.clearedRequests = this.decorateCleared(data.clearedRequests || []);
        this.requests = this.sortRequests(data.requests || []);
        this.documentStatus.approved = data.approvedDocuments;
        this.documentStatus.needed = this.calculateDocumentsNeeded(this.requests);
        this.documentStatus.requested = data.requestedDocuments;
        this.documentStatus.pending = data.pendingReviewDocuments;
        this.pendingSubmissionCount = data.pendingSubmissionCount || 0;
        this.error = undefined;
    }

    async refreshPortalData() {
        await this.loadPortalData();
    }

    sortRequests(requests) {
        const statusOrder = {
            New: 1,
            Requested: 2,
            Review: 3,
            Approved: 4,
            Cleared: 5,
            Submitted: 6
        };
        return [...requests].sort((a, b) => (statusOrder[a.status] || 7) - (statusOrder[b.status] || 7));
    }

    calculateDocumentsNeeded(requests) {
        return (requests || []).filter(request => request.status === 'New' || request.status === 'Requested').length;
    }

    showToast() {
        this.dispatchEvent(new ShowToastEvent({
            title: t('File Upload Complete', this.spanish),
            message: t('Your file(s) have been successfully uploaded.', this.spanish),
            variant: 'success',
            mode: 'dismissable'
        }));
    }

    showError(error) {
        this.dispatchEvent(new ShowToastEvent({
            title: t('Upload Failed', this.spanish),
            message: this.reduceError(error),
            variant: 'error',
            mode: 'sticky'
        }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map(item => item.message).join(', ');
        }
        return error?.body?.message || error?.message
            || t('Your upload could not be processed. Please try again or contact your loan team.', this.spanish);
    }

    get displayBorrowerName() {
        return this.borrowerName || 'there';
    }

    get showTeam() {
        return this.contacts.length > 0;
    }

    // The portal keeps finished items visible in a collapsed list rather than letting them vanish,
    // so the borrower can see what they have already satisfied.
    get hasClearedRequests() {
        return this.clearedRequests.length > 0;
    }

    get clearedToggleLabel() {
        return this.showCleared
            ? t('Hide completed', this.spanish)
            : showCompleted(this.clearedRequests.length, this.spanish);
    }

    toggleCleared() {
        this.showCleared = !this.showCleared;
    }

    decorateContacts(contacts) {
        return contacts.map(contact => ({
            ...contact,
            key: contact.email || contact.name || contact.role,
            showPhoto: Boolean(contact.photoUrl),
            displayTitle: contact.title || contact.role,
            nmlsLabel: contact.nmls ? `NMLS # ${contact.nmls}` : ''
        }));
    }

    decorateCleared(clearedRequests) {
        return clearedRequests.map(request => ({
            ...request,
            clearedDateLabel: request.clearedDate
                ? new Date(request.clearedDate).toLocaleDateString()
                : ''
        }));
    }
}