import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPastClientRows from '@salesforce/apex/ExternalLoPortalController.getPastClientRows';
import importCsv from '@salesforce/apex/ExternalLoWorkspaceController.importCsv';
import { PORTAL_VIEWS, dispatchPortalNavigate, reduceApexError, toGenericListRow } from 'c/portalUtils';

export default class ExternalLoPastClients extends LightningElement {
    /** LO Workspace: an imported past client (Person Account) opens its detail page here. */
    @api recordId;
    search = '';
    clients = [];
    loading = true;
    errorMessage;
    wiredClientsResult;
    viewById;
    nameById;
    contactRow;
    addOpen = false;
    adding = false;
    addError;
    addForm = {};
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
            // LO Workspace: loan rows open the loan, imported clients open the past client detail.
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

    get showDetail() {
        return !!this.recordId;
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
        dispatchPortalNavigate(this, { view, recordId });
    }

    get addLabel() {
        return this.adding ? 'Saving…' : 'Add past client';
    }

    handleBulkImport() {
        dispatchPortalNavigate(this, { view: PORTAL_VIEWS.IMPORT_DATA });
    }

    handleAddOpen() {
        this.addForm = {};
        this.addError = undefined;
        this.addOpen = true;
    }

    handleAddClose() {
        this.addOpen = false;
    }

    handleAddField(event) {
        this.addForm = { ...this.addForm, [event.target.dataset.field]: event.target.value };
    }

    // One row through the bulk importer: same dedupe, ownership and past-client mapping as a CSV.
    async handleAddSubmit(event) {
        event.preventDefault();
        const f = this.addForm;
        if (!f.phone && !f.email) {
            this.addError = 'Add a phone or an email so we can check for duplicates.';
            return;
        }
        const cols = ['firstName', 'lastName', 'phone', 'email', 'closingDate', 'loanAmount', 'street', 'city', 'state', 'zip'];
        const csvCell = (v) => '"' + String(v || '').replace(/"/g, '""') + '"';
        const csvBody = [...cols, 'type'].join(',') + '\n' + [...cols.map((c) => csvCell(f[c])), 'Past Client'].join(',');
        this.adding = true;
        this.addError = undefined;
        try {
            const result = await importCsv({ family: 'consumer', csvBody });
            if (!result.successCount && !(result.links || []).length) {
                const firstError = (result.errors || [])[0];
                this.addError = firstError?.message || result.userMessage || 'That client could not be added.';
                return;
            }
            this.addOpen = false;
            this.handleContactSaved();
        } catch (error) {
            this.addError = reduceApexError(error);
        } finally {
            this.adding = false;
        }
    }
}