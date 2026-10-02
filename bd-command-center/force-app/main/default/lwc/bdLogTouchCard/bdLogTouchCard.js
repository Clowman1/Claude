import { LightningElement, api } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import isMyPartner from '@salesforce/apex/BdCommandCenterController.isMyPartner';

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

    async check() {
        if (!this._recordId) return;
        try {
            this.show = await isMyPartner({ accountId: this._recordId });
        } catch (e) {
            this.show = false;
        }
    }

    openModal() { this.open = true; }
    closeModal() { this.open = false; }
    logged() {
        this.open = false;
        this.dispatchEvent(new RefreshEvent());
    }
}
