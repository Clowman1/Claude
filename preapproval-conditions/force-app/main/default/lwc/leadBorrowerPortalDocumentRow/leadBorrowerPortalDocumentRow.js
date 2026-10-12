import { LightningElement, api, track } from 'lwc';
import FORM_FACTOR from '@salesforce/client/formFactor';
import { loadScript } from 'lightning/platformResourceLoader';
import PDF_LIB from '@salesforce/resourceUrl/pdfLib';
import PDF_JS from '@salesforce/resourceUrl/pdfJs';
import uploadBorrowerDocument from '@salesforce/apex/LeadDocumentPortalController.uploadBorrowerDocument';
import removePendingDocument from '@salesforce/apex/LeadDocumentPortalController.removePendingDocument';
import { t, uploadingOne, uploadingMany, tooLarge, tooSmall, preparing, passwordProtected } from 'c/leadBorrowerPortalLabels';
import { splitPdf, rasterizePages, partName, PdfPartsError } from './pdfParts';

// Site guest users cannot upload through lightning-file-upload, so the borrower's browser reads
// each file and sends it as base64 to Apex, which writes it in system mode. A plain input plus
// drag-and-drop handlers replaces the component entirely.
// Not an arbitrary number. The whole file reaches Apex as a base64 string, which costs about
// 1.37 bytes of heap per byte of file - measured, not guessed - so 3.5 MB already uses 80% of
// the 6 MB synchronous limit. Raising it much further makes uploads fail on the server instead
// of in the browser, which is a worse failure.
const MAX_FILE_BYTES = 3500000;
// A PDF over the limit is cut into parts in the browser instead (see pdfParts.js), so the
// ceiling above never reaches the borrower for a statement. This one keeps a phone from
// grinding through something absurd: 50 MB is about fifteen parts.
const MAX_SPLIT_PDF_BYTES = 50000000;
// A document photograph is legible well below this. Phone cameras produce 3000-4000px images
// that are mostly wasted detail on a paystub.
const MAX_IMAGE_EDGE = 2400;
// A phone that offers a size when sharing produces 320x240 on Small and 640x480 on Medium.
// Either is unreadable as a paystub; Large is 1280x960 and is fine, so the line sits between.
const MIN_READABLE_EDGE = 1000;

export default class LeadBorrowerPortalDocumentRow extends LightningElement {
    @api leadId;
    @api portalHash;
    // Set by the parent from the Lead. Only switches wording.
    @api spanish = false;

    @track currentRequest;

    get labels() {
        const es = this.spanish;
        return {
            dragOrBrowse: t('Drag a file here, or browse', es),
            addAnother: t('Add another file', es),
            remove: t('Remove', es),
            removeThisFile: t('Remove this file', es),
            added: t('Added. Press Submit below when you have added everything.', es)
        };
    }
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
        const es = this.spanish;
        if (this.isUploading) {
            return t('Uploading...', es);
        }
        // The basket wins over the request status: what the borrower needs to know is that
        // these files have not gone anywhere yet.
        if (this.hasPendingFiles) {
            return t('Ready to submit', es);
        }
        switch (this.currentRequest?.status) {
            case 'Review':
                return t('Submitted for review', es);
            case 'Cleared':
            case 'Approved':
            case 'Completed':
                return t('Accepted', es);
            case 'In Progress':
                return t('More needed', es);
            default:
                return t('Needed', es);
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
            return this.uploadProgress || t('Uploading...', this.spanish);
        }
        return this.hasFiles ? this.labels.addAnother : this.labels.dragOrBrowse;
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

        // Photographs are shrunk rather than refused: a phone camera routinely produces 8 MB of
        // detail nobody needs to read a bank statement, and telling the borrower to go and
        // resize it themselves is how a file stalls for two days.
        // Long statements are cut into parts for the same reason.
        const prepared = [];
        for (const file of files) {
            try {
                // eslint-disable-next-line no-await-in-loop
                const shrunk = await this.shrinkIfOversizedImage(file);
                // eslint-disable-next-line no-await-in-loop
                prepared.push(...(await this.splitIfOversizedPdf(shrunk)));
            } catch (prepareError) {
                this.localError = prepareError instanceof PdfPartsError && prepareError.reason === 'password'
                    ? passwordProtected(file.name, this.spanish)
                    : tooLarge(file.name, this.spanish);
                return;
            }
        }
        files = prepared;

        const oversized = files.filter(file => file.size > MAX_FILE_BYTES);
        if (oversized.length) {
            this.localError = tooLarge(oversized[0].name, this.spanish);
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
                    ? uploadingOne(files[index].name, this.spanish)
                    : uploadingMany(index + 1, files.length, this.spanish);
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
                this.localError = t('We could not save that file. Please try again, or email it to your loan team.', this.spanish);
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

    /**
     * Returns a smaller version of an oversized photograph, or the original file untouched.
     *
     * Only images, and only when they are over the limit - a file already small enough is never
     * re-encoded, so nothing is degraded for no reason. A format the browser cannot decode
     * comes back unchanged and is refused by the size check as before.
     */
    async shrinkIfOversizedImage(file) {
        if (file.size <= MAX_FILE_BYTES || !String(file.type || '').startsWith('image/')) {
            return file;
        }
        const smaller = await this.downscaleImage(file);
        return smaller && smaller.size < file.size ? smaller : file;
    }

    /**
     * Returns the file in parts that each fit under the limit, or the original file alone.
     *
     * Pages are copied as they are; only a page too big to fit by itself, or a PDF pdf-lib cannot
     * open, is rendered to images (see pdfParts.js). Anything that goes wrong here throws, and the
     * caller tells the borrower the file is too large, which is what they saw before this existed.
     */
    async splitIfOversizedPdf(file) {
        const isPdf = file.type === 'application/pdf' || /\.pdf$/i.test(file.name || '');
        if (file.size <= MAX_FILE_BYTES || !isPdf) {
            return [file];
        }
        if (file.size > MAX_SPLIT_PDF_BYTES) {
            throw new PdfPartsError('too-large');
        }
        this.isUploading = true;
        this.uploadProgress = preparing(file.name, this.spanish);
        try {
            const PDFLib = await this.loadPdfLib();
            const bytes = new Uint8Array(await file.arrayBuffer());
            const parts = await splitPdf(bytes, MAX_FILE_BYTES, {
                PDFLib,
                rasterize: async (source, pageNumbers) =>
                    rasterizePages(source, pageNumbers, { PDFLib, pdfjsLib: await this.loadPdfJs() })
            });
            return parts.map((part, index) =>
                new File([part], partName(file.name, index, parts.length), { type: 'application/pdf' })
            );
        } finally {
            this.isUploading = false;
            this.uploadProgress = '';
        }
    }

    // Both loaded only when a borrower actually has an oversized PDF; nobody else downloads them.
    async loadPdfLib() {
        await loadScript(this, PDF_LIB);
        return window.PDFLib;
    }

    async loadPdfJs() {
        // The worker script goes first: with it already on the page, pdf.js runs in the page
        // instead of starting a Web Worker, which the Lightning sandbox may not allow.
        await loadScript(this, `${PDF_JS}/pdf.worker.min.js`);
        await loadScript(this, `${PDF_JS}/pdf.min.js`);
        return window.pdfjsLib;
    }

    downscaleImage(file) {
        const objectUrl = URL.createObjectURL(file);
        return new Promise(resolve => {
            const source = new Image();
            source.onload = () => {
                try {
                    const longest = Math.max(source.naturalWidth, source.naturalHeight);
                    const scale = Math.min(1, MAX_IMAGE_EDGE / longest);
                    const canvas = document.createElement('canvas');
                    canvas.width = Math.round(source.naturalWidth * scale);
                    canvas.height = Math.round(source.naturalHeight * scale);
                    canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height);
                    canvas.toBlob(
                        blob => {
                            URL.revokeObjectURL(objectUrl);
                            resolve(
                                blob
                                    ? new File([blob], file.name, { type: 'image/jpeg' })
                                    : null
                            );
                        },
                        'image/jpeg',
                        0.85
                    );
                } catch (resizeFailure) {
                    URL.revokeObjectURL(objectUrl);
                    resolve(null);
                }
            };
            source.onerror = () => {
                URL.revokeObjectURL(objectUrl);
                resolve(null);
            };
            source.src = objectUrl;
        });
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
        // Only the first file is named. Listing six filenames on a phone helps nobody.
        return tooSmall(first.name, first.width, first.height, this.spanish);
    }

    readAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = reader.result || '';
                const commaIndex = result.indexOf(',');
                resolve(commaIndex >= 0 ? result.substring(commaIndex + 1) : result);
            };
            reader.onerror = () => reject(reader.error || new Error(t('That file could not be read.', this.spanish)));
            reader.readAsDataURL(file);
        });
    }

    readableError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            t('Something went wrong uploading that file. Please try again.', this.spanish)
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