import { LightningElement } from 'lwc';
import ApprovedInvestorsModal from 'c/approvedInvestorsModal';

/**
 * "Approved Investors" nav tab in LO Workspace: opens the same investor list every Command Center
 * uses. "Open list view" results are ignored (outside LOs have no Account tab).
 */
export default class LoWsApprovedInvestors extends LightningElement {
    _opened = false;

    renderedCallback() {
        if (!this._opened) {
            this._opened = true;
            this.openList();
        }
    }

    async openList() {
        await ApprovedInvestorsModal.open({ size: 'large', label: 'Approved Investors' });
    }
}
