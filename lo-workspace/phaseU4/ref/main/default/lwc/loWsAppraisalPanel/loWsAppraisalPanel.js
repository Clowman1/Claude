import { LightningElement, api } from 'lwc';
import getActiveAppraisalOrder from '@salesforce/apex/AppraisalOrderController.getActiveAppraisalOrder';
import getAppraisalTimeline from '@salesforce/apex/AppraisalOrderController.getAppraisalTimeline';
import callGetCommentsList from '@salesforce/apex/AppraisalOrderController.callGetCommentsList';
import callAddOrderComment from '@salesforce/apex/AppraisalOrderController.callAddOrderComment';
import callGetDocumentsList from '@salesforce/apex/AppraisalOrderController.callGetDocumentsList';
import downloadSingleFile from '@salesforce/apex/AppraisalOrderController.downloadSingleFile';
import { reduceApexError, showPortalToast } from 'c/portalUtils';

// Same browser key and embeds as the Lightning AppraisalOrder component.
const GOOGLE_MAPS_KEY = 'AIzaSyDliLquGXGts9S8YtkWVolSQEJdBL1ZuWc';

/**
 * Appraisal tab on the LO Workspace "My Loans" detail: view the active order, its timeline,
 * documents and comments, and send a comment. No ordering (owner decision, 2026-09-30).
 */
export default class LoWsAppraisalPanel extends LightningElement {
    _loanId;
    order;
    timeline = [];
    comments = [];
    documents = [];
    loading = true;
    noOrder = false;
    errorMessage;
    newComment = '';
    sending = false;

    @api
    get loanId() {
        return this._loanId;
    }
    set loanId(value) {
        if (value && value !== this._loanId) {
            this._loanId = value;
            this.load();
        }
    }

    // On a Transaction record page the platform supplies recordId; the My Loans drawer passes loanId.
    @api
    get recordId() {
        return this._loanId;
    }
    set recordId(value) {
        this.loanId = value;
    }

    async load() {
        this.loading = true;
        this.errorMessage = undefined;
        this.noOrder = false;
        try {
            this.order = await getActiveAppraisalOrder({ loanId: this._loanId });
        } catch (error) {
            // A loan with no active order makes the controller's order lookup fail.
            this.order = undefined;
            this.noOrder = true;
            this.loading = false;
            return;
        }
        if (!this.order || !this.order.appraisalOrderId) {
            this.noOrder = true;
            this.loading = false;
            return;
        }
        const [timeline, comments, documents] = await Promise.allSettled([
            getAppraisalTimeline({ loanId: this._loanId }),
            callGetCommentsList({ loanId: this._loanId }),
            callGetDocumentsList({ loanId: this._loanId })
        ]);
        this.timeline = (timeline.value || []).map((item, index) => ({ ...item, key: 't' + index }));
        this.comments = (comments.value || []).map((c, index) => ({ ...c, key: 'c' + index }));
        this.documents = (documents.value || []).map((d) => ({ ...d, key: d.OrderDocumentID }));
        if (comments.status === 'rejected' || documents.status === 'rejected') {
            this.errorMessage = 'The appraisal company did not respond. Comments or documents may be missing; try again shortly.';
        }
        this.loading = false;
    }

    mapView = 'satellite';

    get mapUrl() {
        const q = encodeURIComponent(this.address);
        return this.mapView === 'street'
            ? 'https://www.google.com/maps/embed/v1/streetview?key=' + GOOGLE_MAPS_KEY + '&location=' + q + '&fov=80'
            : 'https://www.google.com/maps/embed/v1/place?key=' + GOOGLE_MAPS_KEY + '&q=' + q + '&zoom=20&maptype=satellite';
    }
    get satelliteClass() {
        return this.mapView === 'satellite' ? 'view-btn view-btn-active' : 'view-btn';
    }
    get streetClass() {
        return this.mapView === 'street' ? 'view-btn view-btn-active' : 'view-btn';
    }
    handleMapView(event) {
        this.mapView = event.currentTarget.dataset.view;
    }

    get hasTimeline() {
        return this.timeline.length > 0;
    }
    get hasComments() {
        return this.comments.length > 0;
    }
    get hasDocuments() {
        return this.documents.length > 0;
    }
    get address() {
        if (!this.order) {
            return '';
        }
        return [this.order.street, this.order.city, this.order.state, this.order.zip].filter(Boolean).join(', ');
    }
    get sendLabel() {
        return this.sending ? 'Sending…' : 'Send comment';
    }
    get cannotSend() {
        return this.sending || !this.newComment.trim();
    }

    handleCommentInput(event) {
        this.newComment = event.target.value || '';
    }

    async handleSendComment() {
        const comment = this.newComment.trim();
        if (!comment) {
            return;
        }
        this.sending = true;
        try {
            await callAddOrderComment({ loanId: this._loanId, comment });
            this.newComment = '';
            this.comments = ((await callGetCommentsList({ loanId: this._loanId })) || []).map((c, index) => ({
                ...c,
                key: 'c' + index
            }));
            showPortalToast(this, 'Comment sent', 'The appraisal company will see your comment.', 'success');
        } catch (error) {
            showPortalToast(this, 'Comment not sent', reduceApexError(error), 'error');
        } finally {
            this.sending = false;
        }
    }

    async handleDownload(event) {
        const fileId = event.currentTarget.dataset.fileid;
        try {
            const file = await downloadSingleFile({ fileId, loanId: this._loanId });
            const link = document.createElement('a');
            link.href = 'data:application/octet-stream;base64,' + file.OrderDocument;
            link.download = file.DocumentFileName || 'appraisal-document.pdf';
            document.body.appendChild(link);
            link.click();
            link.remove();
        } catch (error) {
            showPortalToast(this, 'Download failed', reduceApexError(error), 'error');
        }
    }
}