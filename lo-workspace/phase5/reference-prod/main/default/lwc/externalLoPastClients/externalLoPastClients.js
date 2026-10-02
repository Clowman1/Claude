import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPastClientRows from '@salesforce/apex/ExternalLoPortalController.getPastClientRows';
import { PORTAL_VIEWS, dispatchPortalNavigate, reduceApexError, toGenericListRow } from 'c/portalUtils';

export default class ExternalLoPastClients extends LightningElement {
    search = '';
    clients = [];
    loading = true;
    errorMessage;
    wiredClientsResult;
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
                    actions: [
                        { name: 'view', label: 'Open', variant: 'outline' }
                    ]
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

    handleRowAction(event) {
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LEADS,
            recordId: event.detail.recordId
        });
    }
}