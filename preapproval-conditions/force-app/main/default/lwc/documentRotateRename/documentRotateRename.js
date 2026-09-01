import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDocumentContent from '@salesforce/apex/DocumentViewerController.getDocumentContent';
import saveRotatedDocument from '@salesforce/apex/DocumentViewerController.saveRotatedDocument';
import renameFile from '@salesforce/apex/DocumentViewerController.renameFile';

const IMAGE_EXTENSIONS = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif'];

/**
 * One rotate-and-rename modal, used by the Pre-Approval Conditions modal, the Pending Review tray
 * and the Documents tab. The reviewer sees the document, turns it, and saves it the right way up.
 *
 * Rotation is done in the browser because Apex cannot re-encode either format: a canvas for images,
 * pdf-lib for PDFs. Saving adds a NEW VERSION of the same file rather than a new file, so every
 * link, the condition it belongs to and its folder all survive.
 */
export default class DocumentRotateRename extends LightningElement {
    @api contentDocumentId;
    @api documentTitle;

    @track previewUrl;
    @track rotation = 0;
    @track workingTitle = '';
    extension = '';
    originalBase64 = '';
    isLoading = false;
    isSaving = false;
    errorMessage = '';
    pdfLibReady = false;

    connectedCallback() {
        this.workingTitle = this.documentTitle || '';
        this.loadDocument();
    }

    disconnectedCallback() {
        this.releasePreview();
    }

    // ---------- state ----------

    get isImage() {
        return IMAGE_EXTENSIONS.includes(this.extension);
    }

    get isPdf() {
        return this.extension === 'pdf';
    }

    get canRotate() {
        return this.isImage || (this.isPdf && this.pdfLibReady);
    }

    get rotateDisabledReason() {
        if (this.canRotate || this.isLoading) {
            return '';
        }
        if (this.isPdf) {
            return 'PDF rotation needs the pdfLib static resource, which is not available in this org yet.';
        }
        return `Rotation is not supported for .${this.extension} files.`;
    }

    get hasRotateDisabledReason() {
        return Boolean(this.rotateDisabledReason);
    }

    // The preview is turned with CSS so the reviewer sees the result immediately. The bytes are only
    // re-encoded on save, which keeps turning it four times free.
    get previewStyle() {
        return `transform: rotate(${this.rotation}deg);`;
    }

    get previewWrapperClass() {
        return this.rotation % 180 === 0 ? 'preview-stage' : 'preview-stage preview-stage--quarter';
    }

    get isDirty() {
        return this.rotation % 360 !== 0 || this.workingTitle.trim() !== (this.documentTitle || '').trim();
    }

    get saveDisabled() {
        return this.isSaving || this.isLoading || !this.isDirty || !this.workingTitle.trim();
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get showSpinner() {
        return this.isLoading || this.isSaving;
    }

    // ---------- load ----------

    async loadDocument() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const content = await getDocumentContent({ contentDocumentId: this.contentDocumentId });
            this.extension = (content.extension || '').toLowerCase();
            this.originalBase64 = content.base64Data;
            if (!this.workingTitle) {
                this.workingTitle = content.title || '';
            }
            this.previewUrl = this.buildObjectUrl(content.base64Data, this.mimeType());

            if (this.isPdf) {
                await this.ensurePdfLib();
            }
        } catch (error) {
            this.errorMessage = this.readableError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async ensurePdfLib() {
        if (this.pdfLibReady || window.PDFLib) {
            this.pdfLibReady = Boolean(window.PDFLib);
            return;
        }
        try {
            // Referenced by path rather than imported: a static-resource import is compile-checked,
            // so the whole component would fail to deploy in an org that has not uploaded pdfLib
            // yet. This way rotation simply stays unavailable until the resource exists.
            await loadScript(this, '/resource/pdfLib');
            this.pdfLibReady = Boolean(window.PDFLib);
        } catch (error) {
            // Rotation is unavailable but viewing and renaming still work, so this is not fatal.
            this.pdfLibReady = false;
        }
    }

    mimeType() {
        if (this.isPdf) {
            return 'application/pdf';
        }
        if (this.extension === 'png') {
            return 'image/png';
        }
        if (this.isImage) {
            return `image/${this.extension === 'jpg' ? 'jpeg' : this.extension}`;
        }
        return 'application/octet-stream';
    }

    buildObjectUrl(base64Data, mime) {
        const binary = atob(base64Data);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        this.releasePreview();
        return URL.createObjectURL(new Blob([bytes], { type: mime }));
    }

    releasePreview() {
        if (this.previewUrl) {
            URL.revokeObjectURL(this.previewUrl);
            this.previewUrl = undefined;
        }
    }

    // ---------- actions ----------

    handleRotateLeft() {
        this.rotation = (this.rotation + 270) % 360;
    }

    handleRotateRight() {
        this.rotation = (this.rotation + 90) % 360;
    }

    handleTitleChange(event) {
        this.workingTitle = event.target.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        this.isSaving = true;
        this.errorMessage = '';
        try {
            const degrees = ((this.rotation % 360) + 360) % 360;
            if (degrees !== 0) {
                const rotatedBase64 = this.isPdf
                    ? await this.rotatePdf(degrees)
                    : await this.rotateImage(degrees);
                await saveRotatedDocument({
                    contentDocumentId: this.contentDocumentId,
                    base64Data: rotatedBase64,
                    fileName: null
                });
            }

            const trimmedTitle = this.workingTitle.trim();
            if (trimmedTitle && trimmedTitle !== (this.documentTitle || '').trim()) {
                await renameFile({ fileId: this.contentDocumentId, newFileName: trimmedTitle });
            }

            this.dispatchEvent(new ShowToastEvent({ message: 'Document saved.', variant: 'success' }));
            this.dispatchEvent(new CustomEvent('saved', {
                detail: { contentDocumentId: this.contentDocumentId, title: trimmedTitle }
            }));
        } catch (error) {
            this.errorMessage = this.readableError(error);
        } finally {
            this.isSaving = false;
        }
    }

    // ---------- rotation ----------

    // pdf-lib turns each page by the requested amount on top of whatever rotation the page already
    // declares, so a page that was already sideways ends up where the reviewer expects.
    async rotatePdf(degrees) {
        if (!window.PDFLib) {
            throw new Error('PDF rotation is unavailable because the pdfLib resource did not load.');
        }
        const { PDFDocument, degrees: toDegrees } = window.PDFLib;
        const pdfDoc = await PDFDocument.load(this.base64ToBytes(this.originalBase64));
        pdfDoc.getPages().forEach(page => {
            const existing = page.getRotation().angle || 0;
            page.setRotation(toDegrees((existing + degrees) % 360));
        });
        const saved = await pdfDoc.save();
        return this.bytesToBase64(saved);
    }

    rotateImage(degrees) {
        return new Promise((resolve, reject) => {
            const image = new Image();
            image.onload = () => {
                try {
                    const swap = degrees % 180 !== 0;
                    const canvas = document.createElement('canvas');
                    canvas.width = swap ? image.height : image.width;
                    canvas.height = swap ? image.width : image.height;
                    const ctx = canvas.getContext('2d');
                    ctx.translate(canvas.width / 2, canvas.height / 2);
                    ctx.rotate((degrees * Math.PI) / 180);
                    ctx.drawImage(image, -image.width / 2, -image.height / 2);
                    const mime = this.extension === 'png' ? 'image/png' : 'image/jpeg';
                    const dataUrl = canvas.toDataURL(mime, 0.92);
                    resolve(dataUrl.substring(dataUrl.indexOf(',') + 1));
                } catch (error) {
                    reject(error);
                }
            };
            image.onerror = () => reject(new Error('That image could not be read for rotation.'));
            image.src = this.previewUrl;
        });
    }

    base64ToBytes(base64Data) {
        const binary = atob(base64Data);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        return bytes;
    }

    bytesToBase64(bytes) {
        let binary = '';
        const chunk = 0x8000;
        for (let i = 0; i < bytes.length; i += chunk) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
        }
        return btoa(binary);
    }

    readableError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Something went wrong. Please try again.'
        );
    }
}
