import { LightningElement, api } from 'lwc';
import getTextSwitches from '@salesforce/apex/LoWsCommSettingsController.getTextSwitches';
import setTextsOff from '@salesforce/apex/LoWsCommSettingsController.setTextsOff';
import { reduceApexError, showPortalToast, isExperienceCloudContext } from 'c/portalUtils';
import { registerTourHooks } from 'c/loWsTourHooks';

// comms-settings: per-contact "automated texts" switch. Lead / Account page = that contact;
// Loan page = its borrower and buyer's agent (the same switches as on their own pages).
export default class LoWsTextsSwitch extends LightningElement {
    _recordId;
    switches = [];
    saving = false;
    confirmRow;

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
        try {
            this.switches = await getTextSwitches({ recordId: this._recordId });
        } catch (e) {
            this.switches = []; // no switch rather than a broken card
        }
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