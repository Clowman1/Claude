import { LightningElement, api, track } from 'lwc';
import FORM_FACTOR from '@salesforce/client/formFactor';
import uploadBorrowerDocument from '@salesforce/apex/LeadDocumentPortalController.uploadBorrowerDocument';
import removePendingDocument from '@salesforce/apex/LeadDocumentPortalController.removePendingDocument';

// Site guest users cannot upload through lightning-file-upload, so the borrower's browser reads
// each file and sends it as base64 to Apex, which writes it in system mode. A plain input plus
// drag-and-drop handlers replaces the component entirely.
const MAX_FILE_BYTES = 3500000;

export default class LeadBorrowerPortalDocumentRow extends LightningElement {
    @api leadId;
    @api portalHash;

    @track currentRequest;
    isPhone = false;
    isDragging = false;
    isUploading = false;
    uploadProgress = '';
    justUploaded = false;
    localError = '';

    @api
    get request() {
        return this.currentRequest;
    }
    set request(value) {
        this.currentRequest = value;
    }

    connectedCallback() {
        if (FORM_FACTOR === 'Small') {
            this.isPhone = true;
        }
    }

    // ---------- borrower-facing state ----------

    get fileCount() {
        return this.currentRequest?.fileCount || 0;
    }

    get hasFiles() {
        return this.fileCount > 0;
    }

    get fileCountLabel() {
        const count = this.fileCount;
        return count === 1 ? '1 file attached' : `${count} files attached`;
    }

    get pendingFiles() {
        return this.currentRequest?.pendingFiles || [];
    }

    get hasPendingFiles() {
        return this.pendingFiles.length > 0;
    }

    get pendingCountLabel() {
        const count = this.pendingFiles.length;
        return count === 1 ? '1 file ready to submit' : `${count} files ready to submit`;
    }

    async handleRemovePending(event) {
        const contentDocumentId = event.currentTarget?.dataset?.documentId;
        if (!contentDocumentId) {
            return;
        }
        this.localError = undefined;
        try {
            await removePendingDocument({
                hashFromURL: this.portalHash,
                contentDocumentId
            });
            this.dispatchEvent(new CustomEvent('basketchange', { bubbles: true, composed: true }));
        } catch (error) {
            this.localError = this.readableError(error);
        }
    }

    get isSubmitted() {
        return this.currentRequest?.status === 'Review';
    }

    // What the borrower reads in the status column. "Requested" means nothing to them; whether we
    // have their document does.
    get statusLabel() {
        if (this.isUploading) {
            return 'Uploading...';
        }
        // The basket wins over the request status: what the borrower needs to know is that
        // these files have not gone anywhere yet.
        if (this.hasPendingFiles) {
            return 'Ready to submit';
        }
        switch (this.currentRequest?.status) {
            case 'Review':
                return 'Submitted for review';
            case 'Cleared':
            case 'Approved':
            case 'Completed':
                return 'Accepted';
            case 'In Progress':
                return 'More needed';
            default:
                return 'Needed';
        }
    }

    get statusClass() {
        const base = 'imbus-status-text status-pill';
        if (this.isUploading) {
            return `${base} status-uploading`;
        }
        if (this.isSubmitted) {
            return `${base} status-submitted`;
        }
        if (this.hasPendingFiles) {
            return `${base} status-ready`;
        }
        if (this.hasFiles) {
            return `${base} status-partial`;
        }
        return `${base} status-needed`;
    }

    get dropZoneClass() {
        let dropZoneClass = 'drop-zone';
        if (this.isDragging) {
            dropZoneClass += ' drop-zone--active';
        }
        if (this.isUploading) {
            dropZoneClass += ' drop-zone--busy';
        }
        return dropZoneClass;
    }

    get dropZoneLabel() {
        if (this.isUploading) {
            return this.uploadProgress || 'Uploading...';
        }
        return this.hasFiles ? 'Add another file' : 'Drag a file here, or browse';
    }

    get showConfirmation() {
        return this.justUploaded && !this.isUploading;
    }

    get hasLocalError() {
        return Boolean(this.localError);
    }

    // ---------- drag and drop ----------

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        if (!this.isUploading) {
            this.isDragging = true;
        }
    }

    handleDragLeave(event) {
        event.preventDefault();
        event.stopPropagation();
        this.isDragging = false;
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        this.isDragging = false;
        if (this.isUploading) {
            return;
        }
        this.uploadFiles(Array.from(event.dataTransfer?.files || []));
    }

    handleBrowseClick() {
        if (this.isUploading) {
            return;
        }
        this.template.querySelector('input[type="file"]')?.click();
    }

    handleBrowseKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleBrowseClick();
        }
    }

    handleFileInputChange(event) {
        const files = Array.from(event.target.files || []);
        // Clear the input so re-picking the same file still fires a change event.
        event.target.value = null;
        this.uploadFiles(files);
    }

    // ---------- upload ----------

    async uploadFiles(files) {
        if (!files.length) {
            return;
        }

        this.localError = '';
        this.justUploaded = false;

        const oversized = files.filter(file => file.size > MAX_FILE_BYTES);
        if (oversized.length) {
            this.localError = `${oversized[0].name} is larger than 3.5 MB. Please upload a smaller file, or email it to your loan team.`;
            return;
        }

        this.isUploading = true;
        let uploadedCount = 0;

        try {
            for (let index = 0; index < files.length; index++) {
                this.uploadProgress = files.length === 1
                    ? `Uploading ${files[index].name}...`
                    : `Uploading ${index + 1} of ${files.length}...`;
                // Sequential on purpose: each file is its own Apex transaction, and a borrower on a
                // phone connection fares better with one request at a time than with a burst.
                // eslint-disable-next-line no-await-in-loop
                const updated = await uploadBorrowerDocument({
                    hashFromURL: this.portalHash,
                    requestId: this.currentRequest.id,
                    fileName: files[index].name,
                    base64Data: await this.readAsBase64(files[index])
                });
                this.currentRequest = updated;
                uploadedCount++;
                this.publishRequestUpdate(updated);
            }

            this.justUploaded = true;
            // Nothing is sent to the lead team here. The files sit in the basket until the
            // borrower submits, so one sitting produces one notification rather than one per
            // condition they touch.
        } catch (error) {
            this.localError = this.readableError(error);
            this.dispatchUploadError(error);
        } finally {
            this.isUploading = false;
            this.uploadProgress = '';
        }
    }

    readAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = reader.result || '';
                const commaIndex = result.indexOf(',');
                resolve(commaIndex >= 0 ? result.substring(commaIndex + 1) : result);
            };
            reader.onerror = () => reject(reader.error || new Error('That file could not be read.'));
            reader.readAsDataURL(file);
        });
    }

    readableError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Something went wrong uploading that file. Please try again.'
        );
    }

    publishRequestUpdate(request) {
        this.dispatchEvent(new CustomEvent('requestupdated', {
            detail: { request },
            bubbles: true,
            composed: true
        }));
    }

    dispatchUploadError(error) {
        this.dispatchEvent(new CustomEvent('uploaderror', {
            detail: { error },
            bubbles: true,
            composed: true
        }));
    }
}