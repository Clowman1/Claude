import { LightningElement } from 'lwc';
import updateTransactionStatus from '@salesforce/apex/ClosingPortalController.updateTransactionStatus';
import getTransactionStatus from '@salesforce/apex/ClosingPortalController.getTransactionStatus';

export default class ClosingPackageConfirmation extends LightningElement {
  recordId;
  hasResponded = false;
  showRejectNote = false;
  rejectionNote = '';
  thankYouMessage = '';
  error;
  inputError;

  async connectedCallback() {
    const params = new URLSearchParams(window.location.search);
    this.recordId = params.get('rid');
    
    if (this.recordId) {
      let result;
      try { 
        result = await getTransactionStatus({ recordId: this.recordId });
      } catch (e) {
        this.error = 'Invalid URL. Link you trying to use is broken.'
      }
      if (result === 'Accepted' || result === 'Rejected') {
        this.thankYouMessage = 'Thank you for your continued partnership.'
        this.hasResponded = true;
      }
    } else {
      this.error = 'Invalid URL. Link you trying to use is broken.'
    }
  }

  async handleAccept() {
    await this.updateStatus('Accepted');
    if (this.error) {
      return
    }

    this.thankYouMessage = 'Thank you for your continued partnership.';
    this.hasResponded = true;
  }

  showRejectInput() {
    this.showRejectNote = true;
  }

  handleNoteInput(event) {
    this.rejectionNote = event.target.value;
  }

  async handleReject() {
    if (!this.rejectionNote.trim()) {
      this.inputError = 'Please provide an explanation for the rejection.';
      return;
    }

    await this.updateStatus('Rejected', this.rejectionNote);
    if (this.error) {
      return;
    }

    this.thankYouMessage = 'Thank you for giving us your updated notes. We will be looking at this as soon as possible.';
    this.hasResponded = true;
  }

  async updateStatus(status, notes) {
    try {
      await updateTransactionStatus({ recordId: this.recordId, status, rejectionNotes: notes });
      this.error = null;
    } catch (e) {
      this.error = e.body?.message || e.message;
      if (!this.error) {
        this.error = 'An unexpected error occurred. Please try again later.';
      }
    }
  }
}