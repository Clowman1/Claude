import { LightningElement, api } from 'lwc';
import searchLoggableRecords from '@salesforce/apex/ExternalLoPortalController.searchLoggableRecords';
import { reduceApexError } from 'c/portalUtils';
import EXTLO_LOG_CONTACT from '@salesforce/label/c.ExtLO_Log_Contact';

export default class PortalContactPicker extends LightningElement {
    @api selectedName;
    @api selectedId;
    @api disabled = false;
    /** The chosen category needs a contact: shows the helper text under the field. */
    @api required = false;
    search = '';
    hits = [];
    errorMessage;
    searching = false;
    searchedTerm;
    _searchSeq = 0;

    labels = { contact: EXTLO_LOG_CONTACT };

    get hasHits() {
        return this.hits.length > 0;
    }

    get selectedLabel() {
        return this.selectedName || '';
    }

    // Only after a finished search for what is typed now, so typed text never reads as a pick.
    get showNoMatch() {
        const term = (this.search || '').trim();
        return !this.selectedId && !this.errorMessage && term.length >= 2 && this.searchedTerm === term && !this.hasHits;
    }

    handleSearch(event) {
        this.search = event.target.value;
        this.scheduleSearch();
    }

    scheduleSearch() {
        window.clearTimeout(this._timer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = window.setTimeout(() => {
            this.runSearch();
        }, 250);
    }

    async runSearch() {
        const term = (this.search || '').trim();
        const seq = ++this._searchSeq;
        if (term.length < 2) {
            this.hits = [];
            this.searching = false;
            this.searchedTerm = undefined;
            return;
        }
        this.searching = true;
        try {
            const rows = await searchLoggableRecords({ searchTerm: term });
            if (seq !== this._searchSeq) {
                return;
            }
            this.hits = rows || [];
            this.errorMessage = undefined;
        } catch (error) {
            if (seq !== this._searchSeq) {
                return;
            }
            this.errorMessage = reduceApexError(error);
            this.hits = [];
        } finally {
            if (seq === this._searchSeq) {
                this.searching = false;
                this.searchedTerm = term;
            }
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
                    email: hit.email,
                    activityKey: hit.activityKey,
                    allowedKeys: hit.allowedKeys
                }
            })
        );
        this.search = '';
        this.hits = [];
        this.searchedTerm = undefined;
    }

    handleClear() {
        this.dispatchEvent(new CustomEvent('select', { detail: { recordId: null } }));
    }
}
