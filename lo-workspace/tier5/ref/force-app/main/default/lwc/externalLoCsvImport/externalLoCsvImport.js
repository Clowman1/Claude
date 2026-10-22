import { LightningElement } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';
import importCsv from '@salesforce/apex/ExternalLoWorkspaceController.importCsv';
import { reduceApexError } from 'c/portalUtils';
import EXTLO_IMPORT_CONSUMER_TITLE from '@salesforce/label/c.ExtLO_Import_Consumer_Title';
import EXTLO_IMPORT_PARTNER_TITLE from '@salesforce/label/c.ExtLO_Import_Partner_Title';
import EXTLO_IMPORT_CONSUMER_HELP from '@salesforce/label/c.ExtLO_Import_Consumer_Help';
import EXTLO_IMPORT_PARTNER_HELP from '@salesforce/label/c.ExtLO_Import_Partner_Help';
import EXTLO_IMPORT_UPLOAD from '@salesforce/label/c.ExtLO_Import_Upload';
import EXTLO_IMPORT_RESULT_TITLE from '@salesforce/label/c.ExtLO_Import_Result_Title';
import EXTLO_IMPORT_CONSUMER_COLUMNS from '@salesforce/label/c.ExtLO_Import_Consumer_Columns';
import EXTLO_IMPORT_PARTNER_COLUMNS from '@salesforce/label/c.ExtLO_Import_Partner_Columns';
import EXTLO_IMPORT_COLUMNS_HEADING from '@salesforce/label/c.ExtLO_Import_Columns_Heading';
import EXTLO_IMPORT_DROP_HINT from '@salesforce/label/c.ExtLO_Import_Drop_Hint';

export default class ExternalLoCsvImport extends LightningElement {
    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
    }

    uploadingFamily;
    errorMessage;
    result;
    draggingFamily;
    labels = {
        consumerTitle: EXTLO_IMPORT_CONSUMER_TITLE,
        partnerTitle: EXTLO_IMPORT_PARTNER_TITLE,
        consumerHelp: EXTLO_IMPORT_CONSUMER_HELP,
        partnerHelp: EXTLO_IMPORT_PARTNER_HELP,
        upload: EXTLO_IMPORT_UPLOAD,
        resultTitle: EXTLO_IMPORT_RESULT_TITLE,
        consumerColumns: EXTLO_IMPORT_CONSUMER_COLUMNS,
        partnerColumns: EXTLO_IMPORT_PARTNER_COLUMNS,
        columnsHeading: EXTLO_IMPORT_COLUMNS_HEADING,
        dropHint: EXTLO_IMPORT_DROP_HINT
    };

    get isUploading() {
        return !!this.uploadingFamily;
    }

    get consumerBusy() {
        return this.uploadingFamily === 'consumer';
    }

    get partnerBusy() {
        return this.uploadingFamily === 'partner';
    }

    get consumerCardClass() {
        return this.draggingFamily === 'consumer' ? 'import-card import-card-active' : 'import-card';
    }

    get partnerCardClass() {
        return this.draggingFamily === 'partner' ? 'import-card import-card-active' : 'import-card';
    }

    get hasResult() {
        return !!this.result;
    }

    get hasSuccesses() {
        return (this.result?.successes || []).length > 0;
    }

    get hasErrors() {
        return (this.result?.errors || []).length > 0;
    }

    handlePickConsumer() {
        this.refs.consumerFile.click();
    }

    handlePickPartner() {
        this.refs.partnerFile.click();
    }

    handleConsumerChange(event) {
        this.readAndUpload(event, 'consumer');
    }

    handlePartnerChange(event) {
        this.readAndUpload(event, 'partner');
    }

    handleDragOver(event) {
        event.preventDefault();
        this.draggingFamily = event.currentTarget.dataset.family;
    }

    handleDragLeave(event) {
        if (event.currentTarget.dataset.family === this.draggingFamily) {
            this.draggingFamily = undefined;
        }
    }

    handleDrop(event) {
        event.preventDefault();
        const family = event.currentTarget.dataset.family;
        this.draggingFamily = undefined;
        const file = event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files[0];
        this.processFile(file, family);
    }

    readAndUpload(event, family) {
        const file = event.target.files && event.target.files[0];
        event.target.value = '';
        this.processFile(file, family);
    }

    processFile(file, family) {
        if (!file) {
            return;
        }
        if (!file.name.toLowerCase().endsWith('.csv')) {
            this.errorMessage = 'Only .csv files are supported. Export your list as CSV first.';
            this.result = undefined;
            return;
        }
        if (file.size > 120000) {
            this.errorMessage = 'That file is too large. Export 200 rows or fewer and try again.';
            this.result = undefined;
            return;
        }
        this.uploadingFamily = family;
        this.errorMessage = undefined;
        const reader = new FileReader();
        reader.onload = async () => {
            try {
                this.result = await importCsv({ family, csvBody: decodeCsv(reader.result) });
                this.dispatchEvent(new CustomEvent('importdone', { bubbles: true, composed: true }));
            } catch (error) {
                this.result = undefined;
                this.errorMessage = reduceApexError(error);
            } finally {
                this.uploadingFamily = undefined;
            }
        };
        reader.onerror = () => {
            this.uploadingFamily = undefined;
            this.errorMessage = 'The file could not be read. Try exporting it as CSV again.';
        };
        if (typeof TextDecoder === 'undefined') {
            reader.readAsText(file);
        } else {
            reader.readAsArrayBuffer(file);
        }
    }
}

// Excel's "CSV (Comma delimited)" export is Windows-1252, not UTF-8, so accented names used to
// arrive as replacement characters. Strict UTF-8 first; anything that is not valid UTF-8 is 1252.
function decodeCsv(content) {
    if (typeof content === 'string') {
        return content;
    }
    try {
        return new TextDecoder('utf-8', { fatal: true }).decode(content);
    } catch (error) {
        return new TextDecoder('windows-1252').decode(content);
    }
}