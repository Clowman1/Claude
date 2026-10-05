import { LightningElement, api } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import isMyPartner from '@salesforce/apex/BdCommandCenterController.isMyPartner';
import getIntakeLink from '@salesforce/apex/BdCommandCenterController.getIntakeLink';
import { copyText } from 'c/bdUtils';

// Account-page strip: shows only on partners in the viewing BD rep's book.
export default class BdLogTouchCard extends LightningElement {
    _recordId;
    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        this.check();
    }

    show = false;
    open = false;
    intakeUrl;

    async check() {
        if (!this._recordId) return;
        try {
            this.show = await isMyPartner({ accountId: this._recordId });
            this.intakeUrl = this.show ? await getIntakeLink({ accountId: this._recordId }) : null;
        } catch (e) {
            this.show = false;
        }
    }

    async copyLink() {
        const ok = await copyText(this.intakeUrl);
        this.dispatchEvent(new ShowToastEvent({
            title: ok ? 'Intake link copied' : 'Copy failed: select the link and copy it',
            variant: ok ? 'success' : 'warning'
        }));
    }

    openModal() { this.open = true; }
    closeModal() { this.open = false; }
    logged() {
        this.open = false;
        this.dispatchEvent(new RefreshEvent());
    }
}