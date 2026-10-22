import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getRealtorProspects from '@salesforce/apex/ExternalLoPortalController.getRealtorProspects';
import { PORTAL_VIEWS, dispatchPortalNavigate, reduceApexError, toGenericListRow } from 'c/portalUtils';

export default class ExternalLoRealtorProspects extends LightningElement {
    search = '';
    partners = [];
    loading = true;
    errorMessage;
    wiredPartnersResult;
    _refreshKey;

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(value) {
        this._refreshKey = value;
        if (value && this.wiredPartnersResult) {
            refreshApex(this.wiredPartnersResult);
        }
    }

    @wire(getRealtorProspects, { searchTerm: '$search' })
    wiredPartners(result) {
        this.wiredPartnersResult = result;
        this.loading = !result.data && !result.error;
        if (result.data) {
            this.partners = result.data.map((row) =>
                toGenericListRow({
                    id: row.id,
                    title: row.name,
                    badges: [
                        // LO Workspace tags carry my stage; the portal shows the partner type only.
                        ...(row.stage ? [{ key: 'stage', label: row.stage, toneClass: 'badge badge-neutral' }] : []),
                        { key: 'type', label: row.partnerType || 'Realtor Prospect', toneClass: 'badge badge-neutral' }
                    ],
                    primary: [row.company, row.market].filter(Boolean).join(' · '),
                    meta: row.lastTouchLabel || 'No communication logged by you',
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
        return !this.loading && this.partners.length === 0;
    }

    get resultLabel() {
        return `${this.partners.length} realtor prospects`;
    }

    handleSearchChange(event) {
        this.search = event.detail.value;
    }

    handleRowAction(event) {
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.REALTORS,
            filter: 'prospects',
            recordId: event.detail.recordId
        });
    }
}