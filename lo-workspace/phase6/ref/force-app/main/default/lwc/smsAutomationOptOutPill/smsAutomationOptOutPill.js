import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// The field that the automation actually respects differs by object: Lead is handled by
// LeadSmsOptOutSchMsgTrigHandler, Account by the "Account: Remove From SMS Campaign On Opt Out"
// flow. Both block unsent Scheduled_Message__c records, so writing through LDS is enough - this
// component adds no automation of its own.
const OPT_OUT_FIELD_BY_OBJECT = {
    Lead: 'Lead.Opt_Out_from_SMS_Automation__c',
    Account: 'Account.SMS_Opt_Out__c'
};
const NAME_FIELD_BY_OBJECT = {
    Lead: 'Lead.Name',
    Account: 'Account.Name'
};

export default class SmsAutomationOptOutPill extends LightningElement {
    @api recordId;
    @api objectApiName;

    isConfirmOpen = false;
    isSaving = false;
    record;

    @wire(getRecord, { recordId: '$recordId', fields: '$requestedFields' })
    wiredRecord({ data, error }) {
        if (data) {
            this.record = data;
        } else if (error) {
            this.record = undefined;
        }
    }

    get requestedFields() {
        const optOut = OPT_OUT_FIELD_BY_OBJECT[this.objectApiName];
        const name = NAME_FIELD_BY_OBJECT[this.objectApiName];
        return optOut ? [optOut, name] : [];
    }

    get isSupportedObject() {
        return !!OPT_OUT_FIELD_BY_OBJECT[this.objectApiName];
    }

    get optOutFieldApiName() {
        const qualified = OPT_OUT_FIELD_BY_OBJECT[this.objectApiName];
        return qualified ? qualified.split('.')[1] : undefined;
    }

    get isOptedOut() {
        const field = OPT_OUT_FIELD_BY_OBJECT[this.objectApiName];
        return field && this.record ? getFieldValue(this.record, field) === true : false;
    }

    get recordName() {
        const field = NAME_FIELD_BY_OBJECT[this.objectApiName];
        return field && this.record ? getFieldValue(this.record, field) || 'this person' : 'this person';
    }

    get pillLabel() {
        return this.isOptedOut ? 'Auto-Text Opted Out' : 'Auto-Text Active';
    }

    get pillClass() {
        return this.isOptedOut ? 'optout-pill optout-pill-off' : 'optout-pill optout-pill-on';
    }

    get pillTitle() {
        return this.isOptedOut
            ? 'Automated texting is off. Click to resume automated texts.'
            : 'Automated texting is on. Click to opt this person out.';
    }

    get actionLabel() {
        return this.isOptedOut ? 'Resume auto-texts' : 'Opt out';
    }

    // Opting out blocks every queued message, so it asks first. Resuming is reversible and
    // immediate, so it does not.
    handlePillClick() {
        if (this.isSaving) {
            return;
        }
        if (this.isOptedOut) {
            this.saveOptOut(false);
        } else {
            this.isConfirmOpen = true;
        }
    }

    closeConfirm() {
        this.isConfirmOpen = false;
    }

    confirmOptOut() {
        this.isConfirmOpen = false;
        this.saveOptOut(true);
    }

    async saveOptOut(optOut) {
        const fieldName = this.optOutFieldApiName;
        if (!fieldName) {
            return;
        }
        this.isSaving = true;
        const fields = { Id: this.recordId };
        fields[fieldName] = optOut;
        try {
            await updateRecord({ fields });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: optOut ? 'Opted out of auto-texts' : 'Auto-texts resumed',
                    message: optOut
                        ? `${this.recordName} will not receive automated texts. Queued messages are blocked.`
                        : `${this.recordName} will receive automated texts again. Blocked messages are released.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            const detail = error && error.body && error.body.message ? error.body.message : 'Please try again.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not update the opt-out setting',
                    message: detail,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }
}