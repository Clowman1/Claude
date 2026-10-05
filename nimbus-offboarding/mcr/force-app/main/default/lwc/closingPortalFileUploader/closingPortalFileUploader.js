import { LightningElement, api } from 'lwc';
import { showToast } from 'lightning/platformShowToastEvent'; 

import sendEmail from '@salesforce/apex/ClosingPortalController.sendEmail';

export default class FileUploaderLwc extends LightningElement {
    @api recordId;
    showToast = false;
    toastMessage = '';

    connectedCallback() {
        // const urlParams = new URLSearchParams(window.location.search);
        // const rid = urlParams.get('rid');
        // if (rid) {
        //     this.recordId = rid;
        // } else {
        //     alert('Invalid URL. Link you trying to use is broken.')
        // }
    }

    async handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        this.toastMessage = `${uploadedFiles.length} file(s) uploaded successfully.`;
        this.showToast = true;

        let fileNames = [];
        uploadedFiles.forEach((file) => {
            fileNames.push(file.name);
        });

        await sendEmail({ 
            recordId: this.recordId,
            fileNames: fileNames
        });

        // Auto-hide toast after 3 seconds
        setTimeout(() => {
            this.showToast = false;
        }, 3000);
    }
}