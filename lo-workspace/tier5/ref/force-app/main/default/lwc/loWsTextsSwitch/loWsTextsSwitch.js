import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getTextSwitches from '@salesforce/apex/LoWsCommSettingsController.getTextSwitches';
import setTextsOff from '@salesforce/apex/LoWsCommSettingsController.setTextsOff';
import { reduceApexError, showPortalToast, isExperienceCloudContext } from 'c/portalUtils';
import { registerTourHooks } from 'c/loWsTourHooks';

// comms-settings: per-contact "automated texts" switch. Lead / Account page = that contact;
// Loan page = its borrower and buyer's agent (the same switches as on their own pages).
// A realtor/title agent's flag sits on their shared Account, so it applies to every Reach LO.
const ACCOUNT_TYPE = 'Account.Type__c';
const SHARED_ACCOUNT_TYPES = new Set(['Realtor Account', 'Title Agent Account']);

export default class LoWsTextsSwitch extends LightningElement {
    _recordId;
    switches = [];
    saving = false;
    confirmRow;
    loadError;

    get accountId() {
        return String(this._recordId || '').startsWith('001') ? this._recordId : undefined;
    }

    @wire(getRecord, { recordId: '$accountId', optionalFields: [ACCOUNT_TYPE] })
    account;

    isShared(row) {
        return row.label === "Buyer's agent"
            || (row.recordId === this.accountId && SHARED_ACCOUNT_TYPES.has(getFieldValue(this.account?.data, ACCOUNT_TYPE)));
    }

    connectedCallback() {
        if (!isExperienceCloudContext()) registerTourHooks(this); // O4h guided tour stop M-05 (spotlight only)
    }

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) return;
        this._recordId = value;
        this.switches = [];
        this.load();
    }

    async load() {
        if (!this._recordId || isExperienceCloudContext()) return; // LO Workspace only
        this.loadError = undefined;
        try {
            this.switches = await getTextSwitches({ recordId: this._recordId });
        } catch (e) {
            this.switches = [];
            this.loadError = 'Automated texts setting could not be loaded: ' + reduceApexError(e);
        }
    }

    get confirmShared() {
        return this.confirmRow && this.isShared(this.confirmRow);
    }

    get hasSwitches() {
        return this.switches.length > 0;
    }

    get rows() {
        return this.switches.map((s) => ({
            ...s,
            ariaOn: String(!s.off),
            onLabel: s.off ? 'Off' : 'On',
            aria: `Automated texts to ${s.name}`,
            noteKey: s.recordId + '-note',
            sharedNote: !this.isShared(s) ? null : s.off
                ? 'Automated texts to this contact are off for all Reach loan officers.'
                : 'Turning this off stops automated texts from all Reach loan officers.',
            switchClass: s.off ? 'switch' : 'switch switch-on'
        }));
    }

    handleToggle(event) {
        const row = this.switches.find((s) => s.recordId === event.currentTarget.dataset.id);
        if (row.off) {
            this.save(row, false);
        } else {
            this.confirmRow = row;
        }
    }

    cancelConfirm() {
        this.confirmRow = undefined;
    }

    handleBackdrop(event) {
        if (event.target === event.currentTarget) this.cancelConfirm();
    }

    confirmOff() {
        const row = this.confirmRow;
        this.confirmRow = undefined;
        this.save(row, true);
    }

    async save(row, off) {
        this.saving = true;
        try {
            this.switches = await setTextsOff({ contextId: this._recordId, targetId: row.recordId, off });
            showPortalToast(this, off ? 'Automated texts off' : 'Automated texts on', row.name, 'success');
        } catch (e) {
            showPortalToast(this, 'Not saved', reduceApexError(e), 'error');
        } finally {
            this.saving = false;
        }
    }
}