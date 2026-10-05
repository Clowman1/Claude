import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import ApprovedInvestorsModal from 'c/approvedInvestorsModal';

/**
 * "Approved Investors" nav tab in LO Workspace: every visit to the tab opens the same investor list
 * every Command Center uses, without its "Open list view" link (outside LOs have no Account tab).
 * Closing the list returns to Perfect Day.
 */
export default class LoWsApprovedInvestors extends NavigationMixin(LightningElement) {
    _modalOpen = false;

    // Fires on each navigation to this tab, including returning to a cached tab.
    @wire(CurrentPageReference)
    pageChanged(pageRef) {
        if (pageRef) {
            this.openList();
        }
    }

    async openList() {
        if (this._modalOpen) {
            return;
        }
        this._modalOpen = true;
        try {
            await ApprovedInvestorsModal.open({ size: 'large', label: 'Approved Investors', hideListView: true });
        } finally {
            this._modalOpen = false;
        }
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'LO_Workspace' } });
    }
}
