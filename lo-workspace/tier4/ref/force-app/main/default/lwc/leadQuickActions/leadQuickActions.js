import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import PROFILE_NAME_FIELD from '@salesforce/schema/User.Profile.Name';
import IS_CONVERTED_FIELD from '@salesforce/schema/Lead.IsConverted';
import RECORD_TYPE_DEVELOPER_NAME_FIELD from '@salesforce/schema/Lead.RecordType.DeveloperName';
import FOLLOW_UP_ACCOUNT_FIELD from '@salesforce/schema/Lead.Follow_Up_Account__c';
import ARIVE_ID_FIELD from '@salesforce/schema/Lead.AriveId__c';
import STATUS_FIELD from '@salesforce/schema/Lead.Status';
import OWNER_ID_FIELD from '@salesforce/schema/Lead.OwnerId';
import LOAN_PARTNER_FIELD from '@salesforce/schema/Lead.Loan_Partner__c';

const FIELDS = [
    IS_CONVERTED_FIELD, RECORD_TYPE_DEVELOPER_NAME_FIELD, FOLLOW_UP_ACCOUNT_FIELD, ARIVE_ID_FIELD,
    STATUS_FIELD, OWNER_ID_FIELD, LOAN_PARTNER_FIELD
];
const ARIVE_LOAN_URL = 'https://98765.myarive.com/app/loans/';
const OPEN_ARIVE = 'openArive';
const CONVERT = 'convertToTransaction';
const CONVERTIBLE_STATUSES = ['Pre-Approval', 'Under Contract'];
const USER_FIELDS = [PROFILE_NAME_FIELD];

const ACTIONS = [
    { label: 'Convert to Transaction', apiName: CONVERT, tone: 'green', convertOnly: true },
    { label: 'Application Summary', apiName: 'Lead.Leads_Notes_Form', tone: 'orange' },
    { label: 'Sync ARIVE', apiName: 'Lead.Sync_With_Arive', tone: 'blue' },
    { label: 'Open in ARIVE', apiName: OPEN_ARIVE, tone: 'blue', ariveOnly: true },
    { label: 'Pre-Approval Letter', apiName: 'Lead.Pre_Approval_Letter', tone: 'green' },
    { label: 'Realtor Convert', apiName: 'Lead.Realtor_Convert', tone: 'slate', realtorOnly: true },
    { label: 'Manual Convert', apiName: 'Lead.Manual_lead_convert', tone: 'slate', adminOnly: true }
];

export default class LeadQuickActions extends NavigationMixin(LightningElement) {
    @api recordId;

    isConverted = false;
    recordTypeDeveloperName;
    followUpAccountId;
    ariveId;
    status;
    ownerId;
    loanPartnerId;
    profileName;
    showConversion = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data }) {
        if (!data) {
            return;
        }

        this.isConverted = Boolean(data.fields.IsConverted?.value);
        this.recordTypeDeveloperName = data.fields.RecordType?.value?.fields?.DeveloperName?.value;
        this.followUpAccountId = data.fields.Follow_Up_Account__c?.value;
        this.ariveId = data.fields.AriveId__c?.value;
        this.status = data.fields.Status?.value;
        this.ownerId = data.fields.OwnerId?.value;
        this.loanPartnerId = data.fields.Loan_Partner__c?.value;
    }

    @wire(getRecord, { recordId: USER_ID, fields: USER_FIELDS })
    wiredUser({ data }) {
        if (!data) {
            return;
        }

        const profile = data.fields.Profile;
        this.profileName = profile?.displayValue || profile?.value?.fields?.Name?.value || '';
    }

    get isAdminProfile() {
        return (this.profileName || '').toLowerCase().includes('admin');
    }

    get isRealtorLead() {
        return this.recordTypeDeveloperName === 'Realtor_Lead_record_type';
    }

    // Same modal as the LO Workspace; the server only lets the lead's Owner or Loan Partner convert.
    get canConvert() {
        return !this.isConverted
            && CONVERTIBLE_STATUSES.includes(this.status)
            && (USER_ID === this.ownerId || USER_ID === this.loanPartnerId);
    }

    get visibleActions() {
        return ACTIONS
            .filter((action) => {
                if (action.convertOnly && !this.canConvert) {
                    return false;
                }
                if (action.adminOnly && !this.isAdminProfile) {
                    return false;
                }
                if (action.ariveOnly && !this.ariveId) {
                    return false;
                }
                if (action.realtorOnly && (!this.isRealtorLead || this.isConverted || this.followUpAccountId)) {
                    return false;
                }
                return true;
            })
            .map((action) => ({
                ...action,
                key: action.apiName,
                className: `pill pill-${action.tone}`
            }));
    }

    openQuickAction(event) {
        const apiName = event.currentTarget.dataset.api;
        if (!apiName) {
            return;
        }

        if (apiName === CONVERT) {
            this.showConversion = true;
            return;
        }

        if (apiName === OPEN_ARIVE) {
            window.open(ARIVE_LOAN_URL + encodeURIComponent(this.ariveId) + '/loan-info', '_blank', 'noopener');
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: {
                apiName
            },
            state: {
                recordId: this.recordId
            }
        });
    }

    closeConversion() {
        this.showConversion = false;
    }

    handleConverted(event) {
        this.showConversion = false;
        const transactionId = event.detail?.transactionKey;
        if (!transactionId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: transactionId, objectApiName: 'Transaction__c', actionName: 'view' }
        });
    }
}