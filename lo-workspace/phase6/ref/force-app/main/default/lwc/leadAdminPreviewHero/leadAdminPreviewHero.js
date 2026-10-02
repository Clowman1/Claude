import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const REQUIRED_FIELDS = ['Lead.Name', 'Lead.Status'];

const OPTIONAL_FIELDS = [
    'Lead.Owner.Name',
    'Lead.Loan_Partner__r.Name',
    'Lead.LeadSource',
    'Lead.Biz_Dev__c',
    'Lead.Realtor_Buying_Agent__r.Name',
    'Lead.Rating',
    'Lead.Loan_Purpose__c',
    'Lead.Appointment_Date_Time__c',
    'Lead.Number_of_Calls__c',
    'Lead.Number_of_Notes__c',
    'Lead.Number_of_Activities_in_Last_7_Days__c',
    'Lead.Last_Call_DateTime__c'
];

export default class LeadAdminPreviewHero extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: REQUIRED_FIELDS, optionalFields: OPTIONAL_FIELDS })
    record;

    get displayName() {
        return this.valueOrFallback(this.fieldValue('Name'), 'Lead');
    }

    get statusLabel() {
        return this.valueOrFallback(this.fieldValue('Status'), 'No status');
    }

    get ownerName() {
        return this.valueOrFallback(this.relationshipFieldValue('Owner.Name'), 'Unassigned');
    }

    get loanPartnerName() {
        return this.valueOrFallback(this.relationshipFieldValue('Loan_Partner__r.Name'), 'Not assigned');
    }

    get leadSource() {
        return this.fieldValue('LeadSource');
    }

    get bizDev() {
        return this.valueOrFallback(this.fieldValue('Biz_Dev__c'), 'Not provided');
    }

    get rating() {
        return this.fieldValue('Rating');
    }

    get loanPurpose() {
        return this.fieldValue('Loan_Purpose__c');
    }

    get buyersAgent() {
        return this.valueOrFallback(this.relationshipFieldValue('Realtor_Buying_Agent__r.Name'), 'Not provided');
    }

    get appointmentDisplay() {
        return this.formatDateTime(this.fieldValue('Appointment_Date_Time__c'));
    }

    get appointmentStatText() {
        return this.valueOrFallback(this.appointmentDisplay, 'No appointment set');
    }

    get appointmentSupportText() {
        return this.appointmentDisplay
            ? 'Next scheduled meeting or callback time.'
            : 'No meeting or callback is currently scheduled.';
    }

    get callsText() {
        return this.formatWholeNumber(this.fieldValue('Number_of_Calls__c'));
    }

    get notesText() {
        return this.formatWholeNumber(this.fieldValue('Number_of_Notes__c'));
    }

    get recentActivityText() {
        return this.formatWholeNumber(this.fieldValue('Number_of_Activities_in_Last_7_Days__c'));
    }

    get lastCallSummary() {
        const lastCall = this.formatDateTime(this.fieldValue('Last_Call_DateTime__c'));
        return lastCall ? `Last call ${lastCall}.` : 'No recent call logged.';
    }

    fieldValue(apiName) {
        const fieldNode = this.record?.data?.fields?.[apiName];
        if (!fieldNode) {
            return null;
        }

        return fieldNode.displayValue ?? fieldNode.value ?? null;
    }

    relationshipFieldValue(path) {
        const fields = this.record?.data?.fields;
        if (!fields || !path) {
            return null;
        }

        const parts = path.split('.');
        let cursor = { fields };

        for (const part of parts) {
            const fieldNode = cursor?.fields?.[part];
            if (!fieldNode) {
                return null;
            }

            if (fieldNode.value && typeof fieldNode.value === 'object' && fieldNode.value.fields) {
                cursor = fieldNode.value;
                continue;
            }

            return fieldNode.displayValue ?? fieldNode.value ?? null;
        }

        return null;
    }

    formatWholeNumber(value) {
        if (value === null || value === undefined || value === '') {
            return '0';
        }

        return new Intl.NumberFormat('en-US', {
            maximumFractionDigits: 0
        }).format(value);
    }

    formatDateTime(value) {
        if (!value) {
            return null;
        }

        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(new Date(value));
    }

    valueOrFallback(value, fallback) {
        return value ? value : fallback;
    }
}