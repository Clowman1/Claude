import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getPastClientRows from '@salesforce/apex/ExternalLoPortalController.getPastClientRows';
import { PORTAL_VIEWS, dispatchPortalNavigate, reduceApexError, toGenericListRow } from 'c/portalUtils';

export default class ExternalLoPastClients extends NavigationMixin(LightningElement) {
    search = '';
    clients = [];
    loading = true;
    errorMessage;
    wiredClientsResult;
    viewById;
    nameById;
    contactRow;
    _refreshKey;

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(value) {
        this._refreshKey = value;
        if (value && this.wiredClientsResult) {
            refreshApex(this.wiredClientsResult);
        }
    }

    @wire(getPastClientRows, { searchTerm: '$search' })
    wiredClients(result) {
        this.wiredClientsResult = result;
        this.loading = !result.data && !result.error;
        if (result.data) {
            // LO Workspace: loan rows open the loan, imported clients open their Person Account.
            // Portal rows are leads.
            this.viewById = new Map(result.data.map((row) => [row.id, row.openView || PORTAL_VIEWS.LEADS]));
            this.nameById = new Map(result.data.map((row) => [row.id, row.name]));
            this.clients = result.data.map((row) =>
                toGenericListRow({
                    id: row.id,
                    title: row.name,
                    badges: [
                        {
                            key: row.status,
                            label: row.statusLabel || row.status
                        }
                    ],
                    primary: row.primary,
                    meta: [row.source, row.lastContactLabel].filter(Boolean).join(' · '),
                    // LO Workspace rows (openView set) also get the contact card; portal rows are unchanged.
                    actions: row.openView
                        ? [
                              { name: 'contact', label: 'Contact', variant: 'outline' },
                              { name: 'view', label: 'Open', variant: 'outline' }
                          ]
                        : [{ name: 'view', label: 'Open', variant: 'outline' }]
                })
            );
            this.errorMessage = undefined;
            this.loading = false;
        } else if (result.error) {
            this.errorMessage = reduceApexError(result.error);
            this.loading = false;
        }
    }

    get isEmpty() {
        return !this.loading && this.clients.length === 0;
    }

    get resultLabel() {
        return `${this.clients.length} past clients`;
    }

    handleSearchChange(event) {
        this.search = event.detail.value;
    }

    handleContactClose() {
        this.contactRow = undefined;
    }

    handleContactSaved() {
        if (this.wiredClientsResult) {
            refreshApex(this.wiredClientsResult);
        }
    }

    handleRowAction(event) {
        const recordId = event.detail.recordId;
        if (event.detail.action === 'contact') {
            // Loan rows pass the loan Id: the card shows its borrower (read-only unless I own them).
            this.contactRow = { id: recordId, name: this.nameById?.get(recordId) };
            return;
        }
        const view = this.viewById?.get(recordId) || PORTAL_VIEWS.LEADS;
        if (view === 'record') {
            // Only produced in LO Workspace (internal Lightning), where record pages exist.
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId, actionName: 'view' }
            });
            return;
        }
        dispatchPortalNavigate(this, { view, recordId });
    }
}