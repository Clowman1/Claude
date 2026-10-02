import { LightningElement, api } from 'lwc';
import searchLoggableRecords from '@salesforce/apex/ExternalLoPortalController.searchLoggableRecords';
import { reduceApexError } from 'c/portalUtils';
import EXTLO_LOG_CONTACT from '@salesforce/label/c.ExtLO_Log_Contact';

export default class PortalContactPicker extends LightningElement {
    @api selectedName;
    @api selectedId;
    @api disabled = false;
    search = '';
    hits = [];
    errorMessage;
    searching = false;

    labels = { contact: EXTLO_LOG_CONTACT };

    get hasHits() {
        return this.hits.length > 0;
    }

    get selectedLabel() {
        return this.selectedName || '';
    }

    handleSearch(event) {
        this.search = event.target.value;
        this.scheduleSearch();
    }

    scheduleSearch() {
        window.clearTimeout(this._timer);
        this._timer = window.setTimeout(() => {
            this.runSearch();
        }, 250);
    }

    async runSearch() {
        if (!this.search || this.search.trim().length < 2) {
            this.hits = [];
            return;
        }
        this.searching = true;
        try {
            this.hits = await searchLoggableRecords({ searchTerm: this.search.trim() });
            this.errorMessage = undefined;
        } catch (error) {
            this.errorMessage = reduceApexError(error);
            this.hits = [];
        } finally {
            this.searching = false;
        }
    }

    handleSelect(event) {
        const recordId = event.currentTarget.dataset.id;
        const hit = this.hits.find((row) => row.id === recordId);
        if (!hit) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('select', {
                detail: {
                    recordId: hit.id,
                    objectApiName: hit.objectApiName,
                    name: hit.name,
                    phone: hit.phone,
                    email: hit.email
                }
            })
        );
        this.search = '';
        this.hits = [];
    }

    handleClear() {
        this.dispatchEvent(new CustomEvent('select', { detail: { recordId: null } }));
    }
}