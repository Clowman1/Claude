import { LightningElement, api } from 'lwc';
import searchRecords from '@salesforce/apex/LoanSubmissionWizardController.searchRecords';

// Search-as-you-type partner picker. The selection shows as a removable chip.
export default class LoanSubmissionLookup extends LightningElement {
    @api objectName = 'Account';
    @api placeholder = 'Type 2+ letters to search';
    @api value;
    @api displayName;
    @api disabled = false;

    term = '';
    results = [];
    searching = false;
    open = false;
    timer;
    seq = 0;

    get hasValue() {
        return !!this.value;
    }

    get chipLabel() {
        return this.displayName || 'Selected record';
    }

    get showList() {
        return this.open && (this.results.length > 0 || this.searching || this.term.length >= 2);
    }

    get noResults() {
        return !this.searching && this.results.length === 0 && this.term.length >= 2;
    }

    handleInput(event) {
        this.term = event.target.value || '';
        this.open = true;
        clearTimeout(this.timer);
        if (this.term.trim().length < 2) {
            this.results = [];
            return;
        }
        this.searching = true;
        const mySeq = ++this.seq;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(async () => {
            try {
                const rows = await searchRecords({ objectName: this.objectName, term: this.term });
                if (mySeq === this.seq) {
                    this.results = rows;
                }
            } catch (e) {
                if (mySeq === this.seq) {
                    this.results = [];
                }
            } finally {
                if (mySeq === this.seq) {
                    this.searching = false;
                }
            }
        }, 250);
    }

    handleFocus() {
        this.open = true;
    }

    handleBlur() {
        // let a click on a result land before closing
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.open = false;
        }, 200);
    }

    handlePick(event) {
        const { id, name } = event.currentTarget.dataset;
        this.term = '';
        this.results = [];
        this.open = false;
        this.dispatchEvent(new CustomEvent('select', { detail: { value: id, label: name } }));
    }

    handleClear() {
        this.dispatchEvent(new CustomEvent('select', { detail: { value: null, label: null } }));
    }
}
