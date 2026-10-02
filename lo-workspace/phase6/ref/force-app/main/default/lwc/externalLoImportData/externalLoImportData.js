import { LightningElement } from 'lwc';
import EXTLO_IMPORT_RESULT_TITLE from '@salesforce/label/c.ExtLO_Import_Result_Title';

export default class ExternalLoImportData extends LightningElement {
    title = 'Import Data';
    subtitle = 'Bring in leads, past clients, realtor partners, and prospects any time — after a brokerage move, a CRM switch, or when you buy a new list. Same importer used in My Perfect Week setup.';
    resultLabel = EXTLO_IMPORT_RESULT_TITLE;
}