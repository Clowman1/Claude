import { LightningElement, api, track } from 'lwc';
import FORM_FACTOR from '@salesforce/client/formFactor';
import uploadBorrowerDocument from '@salesforce/apex/LeadDocumentPortalController.uploadBorrowerDocument';
import removePendingDocument from '@salesforce/apex/LeadDocumentPortalController.removePendingDocument';

// Site guest users cannot upload through lightning-file-upload, so the borrower's browser reads
// each file and sends it as base64 to Apex, which writes it in system mode. A plain input plus
// drag-and-drop handlers replaces the component entirely.
const MAX_FILE_BYTES = 3500000;
// A phone that offers a size when sharing produces 320x240 on Small and 640x480 on Medium.
// Either is unreadable as a paystub; Large is 1280x960 and is fine, so the line sits between.
const MIN_READABLE_EDGE = 1000;

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
    lowResWarning = '';

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

    get hasLowResWarning() {
        return Boolean(this.lowResWarning);
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
        this.lowResWarning = '';
        this.justUploaded = false;

        const oversized = files.filter(file => file.size > MAX_FILE_BYTES);
        if (oversized.length) {
            this.localError = `${oversized[0].name} is larger than 3.5 MB. Please upload a smaller file, or email it to your loan team.`;
            return;
        }

        // Measured before anything is sent, so the borrower is told about a thumbnail while the
        // photo is still in front of them rather than after the loan team gives up on it.
        const tooSmall = [];
        for (const file of files) {
            // eslint-disable-next-line no-await-in-loop
            const size = await this.imageDimensions(file);
            if (size && Math.max(size.width, size.height) < MIN_READABLE_EDGE) {
                tooSmall.push({ name: file.name, ...size });
            }
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

            // Confirm from what the server says it holds, not from the call returning. A message
            // saying the document arrived when nothing was saved is worse than an error: the
            // borrower stops trying and the loan team waits for a file that does not exist.
            const savedCount = this.currentRequest?.pendingFiles?.length || 0;
            if (savedCount === 0) {
                this.localError =
                    'We could not save that file. Please try again, or email it to your loan team.';
                this.dispatchUploadError(new Error('Upload returned no stored document.'));
                return;
            }

            this.justUploaded = true;
            // Said after the upload rather than instead of it: the file is theirs to replace,
            // and a small photo is still better than no photo while they find a better one.
            this.lowResWarning = this.describeSmallImages(tooSmall);
            // Nothing is sent to the lead team here. The files sit in the basket until the
            // borrower submits, so one sitting produces one notification rather than one per
            // condition they touch.
            this.dispatchEvent(new CustomEvent('basketchange', { bubbles: true, composed: true }));
        } catch (error) {
            this.localError = this.readableError(error);
            this.dispatchUploadError(error);
        } finally {
            this.isUploading = false;
            this.uploadProgress = '';
        }
    }

    /** Pixel size of an image the browser can decode, or null for anything else. */
    imageDimensions(file) {
        if (!String(file.type || '').startsWith('image/')) {
            return Promise.resolve(null);
        }
        const objectUrl = URL.createObjectURL(file);
        return new Promise(resolve => {
            const probe = new Image();
            // A format this browser cannot decode - HEIC on most desktops - measures as nothing
            // rather than as a small photo, so it never triggers the warning.
            probe.onload = () => {
                resolve({ width: probe.naturalWidth, height: probe.naturalHeight });
                URL.revokeObjectURL(objectUrl);
            };
            probe.onerror = () => {
                resolve(null);
                URL.revokeObjectURL(objectUrl);
            };
            probe.src = objectUrl;
        });
    }

    describeSmallImages(smallImages) {
        if (!smallImages.length) {
            return '';
        }
        const first = smallImages[0];
        const measured = `${first.name} came through at ${first.width} x ${first.height} pixels`;
        const subject = smallImages.length === 1
            ? measured
            : `${measured}, and ${smallImages.length - 1} more are about the same`;
        return `${subject}. That is usually too small for us to read. If your phone asked you to`
            + ' pick a size when you attached it, choose Actual Size or Large and add it again.';
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