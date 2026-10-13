import { LightningElement, api, wire } from 'lwc';
import getCocContext from '@salesforce/apex/ExternalLoPortalCocFacade.getCocContext';
import submitPortalCocRequest from '@salesforce/apex/ExternalLoPortalCocFacade.submitCocRequest';
import { reduceApexError, showPortalToast } from 'c/portalUtils';

// Reason chips are grouped for scanning; a picklist value not listed here lands in "More".
const GROUPS = [
    { key: 'pricing', label: 'Rate & lock', reasons: ['Float to Lock', 'Rate Change', 'Float Down', 'Extension', 'Investor Change', 'Program Change', 'Term'] },
    { key: 'loan', label: 'Loan & value', reasons: ['Loan Amount', 'Appraisal/LTV', 'Purchase Price Change', 'FICO', 'Restructure'] },
    { key: 'costs', label: 'Costs & dates', reasons: ['Fees Costs Change', 'Seller Credit Change', 'Insurance Taxes HOA Change', 'Closing Date Change'] },
    { key: 'borrower', label: 'Borrower & property', reasons: ['Borrower Change', 'Income Employment Change', 'Assets Reserves Change', 'Property Change', 'Occupancy Change'] }
];

// Step 2 fields and the reasons that show them: the visibility / required rules of the COC_Request flow.
const VALUE_FIELDS = [
    { key: 'newBaseLoanAmount', label: 'New loan amount', kind: 'currency', required: true, reasons: ['Loan Amount'], current: 'loanAmount' },
    { key: 'newAppraisedValue', label: 'New appraised value', kind: 'currency', required: true, reasons: ['Appraisal/LTV'], current: 'appraisedValue' },
    { key: 'newRate', label: 'New rate (%)', kind: 'rate', required: true, reasons: ['Rate Change', 'Float Down', 'Float to Lock'], current: 'rate' },
    { key: 'lockPeriod', label: 'Lock period', kind: 'select', options: 'lockPeriods', reasons: ['Float to Lock'] },
    { key: 'amount', label: 'Amount', kind: 'currency', reasons: ['Purchase Price Change', 'Seller Credit Change', 'Fees Costs Change'], help: 'New purchase price, seller credit, or fee amount.' },
    { key: 'daysExtended', label: 'Days extended', kind: 'number', reasons: ['Extension'] },
    { key: 'newLockExpiration', label: 'New lock expiration', kind: 'date', reasons: ['Extension'], current: 'lockExpiration' },
    { key: 'newProgram', label: 'New program', kind: 'text', reasons: ['Program Change'], current: 'program' },
    { key: 'newInvestor', label: 'New investor', kind: 'select', options: 'investors', reasons: ['Investor Change'], current: 'lender' },
    { key: 'newTerm', label: 'New term (months)', kind: 'number', reasons: ['Term'], current: 'term' },
    { key: 'newFico', label: 'New FICO', kind: 'number', reasons: ['FICO'], current: 'fico' },
    { key: 'reasonForRestructure', label: 'Reason for restructure', kind: 'textarea', reasons: ['Restructure'] },
    { key: 'otherReason', label: 'Other reason', kind: 'textarea', reasons: ['Other'] }
];

const STEPS = ['What changed', 'New values', 'Review'];
const MONEY = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

export default class ExternalLoPortalCocModal extends LightningElement {
    @api contextLoanKey;

    context;
    loadError;
    step = 1;
    selected = [];
    values = {};
    notes = '';
    saving = false;

    @wire(getCocContext, { contextLoanKey: '$contextLoanKey' })
    wiredContext({ data, error }) {
        if (data) {
            this.context = data;
            this.loadError = undefined;
        } else if (error) {
            this.loadError = reduceApexError(error);
        }
    }

    // ---------------------------------------------------------------- header / progress

    get greeting() {
        const name = this.context?.firstName;
        return name ? `Hi ${name}, what's changing?` : "What's changing?";
    }

    get subtitle() {
        const borrower = this.context?.borrower;
        return borrower
            ? `Change of circumstance for ${borrower}'s loan. The COC desk takes it from here.`
            : 'Change of circumstance request. The COC desk takes it from here.';
    }

    get steps() {
        return STEPS.map((label, i) => {
            const n = i + 1;
            let state = 'todo';
            if (n < this.step) state = 'done';
            else if (n === this.step) state = 'current';
            return { n, label, className: `step step-${state}`, ariaCurrent: n === this.step ? 'step' : null };
        });
    }

    get isStep1() {
        return this.step === 1;
    }

    get isStep2() {
        return this.step === 2;
    }

    get isStep3() {
        return this.step === 3;
    }

    get isLoading() {
        return !this.context && !this.loadError;
    }

    // ---------------------------------------------------------------- step 1: reasons

    get reasonGroups() {
        const available = (this.context?.reasons || []).map((o) => o.value);
        const grouped = new Set();
        const groups = GROUPS.map((g) => {
            const reasons = g.reasons.filter((r) => available.includes(r));
            reasons.forEach((r) => grouped.add(r));
            return { ...g, reasons };
        });
        groups.push({ key: 'more', label: 'More', reasons: available.filter((r) => !grouped.has(r)) });
        return groups
            .filter((g) => g.reasons.length)
            .map((g) => ({
                key: g.key,
                label: g.label,
                chips: g.reasons.map((r) => {
                    const on = this.selected.includes(r);
                    return { value: r, className: on ? 'chip chip-on' : 'chip', pressed: on ? 'true' : 'false' };
                })
            }));
    }

    get selectionLabel() {
        const n = this.selected.length;
        return n ? `${n} selected` : 'Pick everything that applies.';
    }

    get noReasons() {
        return this.selected.length === 0;
    }

    handleChip(event) {
        const value = event.currentTarget.dataset.value;
        this.selected = this.selected.includes(value)
            ? this.selected.filter((v) => v !== value)
            : [...this.selected, value];
    }

    // ---------------------------------------------------------------- step 2: values

    get visibleFields() {
        return VALUE_FIELDS.filter((f) => f.reasons.some((r) => this.selected.includes(r))).map((f) => ({
            ...f,
            value: this.values[f.key] ?? null,
            isCurrency: f.kind === 'currency',
            isRate: f.kind === 'rate',
            isNumber: f.kind === 'number',
            isDate: f.kind === 'date',
            isText: f.kind === 'text',
            isSelect: f.kind === 'select',
            isTextarea: f.kind === 'textarea',
            options: f.options ? this.context?.[f.options] || [] : [],
            currentLabel: this.currentLabel(f)
        }));
    }

    get hasFields() {
        return this.visibleFields.length > 0;
    }

    currentLabel(field) {
        const raw = field.current ? this.context?.[field.current] : null;
        return raw == null || raw === '' ? null : `Currently ${this.format(field.kind, raw)}`;
    }

    format(kind, raw) {
        if (raw == null || raw === '') return '—';
        if (kind === 'currency') return MONEY.format(Number(raw));
        if (kind === 'rate') return `${raw}%`;
        if (kind === 'date') {
            const [y, m, d] = String(raw).split('-');
            return d ? `${Number(m)}/${Number(d)}/${y}` : String(raw);
        }
        return String(raw);
    }

    handleValue(event) {
        const { key, kind } = event.target.dataset;
        const raw = event.detail?.value ?? event.target.value;
        let value = raw === '' || raw == null ? null : raw;
        if (value != null && ['currency', 'rate', 'number'].includes(kind)) value = Number(value);
        this.values = { ...this.values, [key]: value };
    }

    // ---------------------------------------------------------------- step 3: review

    get summaryReasons() {
        return this.selected.map((r) => ({ key: r, label: r }));
    }

    get summaryRows() {
        return this.visibleFields
            .filter((f) => f.value != null && f.value !== '')
            .map((f) => {
                const current = f.current ? this.context?.[f.current] : null;
                return {
                    key: f.key,
                    label: f.label,
                    from: current == null || current === '' ? null : this.format(f.kind, current),
                    to: this.format(f.kind, f.value)
                };
            });
    }

    get hasSummaryRows() {
        return this.summaryRows.length > 0;
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    // ---------------------------------------------------------------- navigation

    get showBack() {
        return this.step > 1;
    }

    get nextDisabled() {
        return this.step === 1 && this.noReasons;
    }

    handleBack() {
        this.step -= 1;
    }

    handleNext() {
        if (this.step === 1) {
            if (!this.noReasons) this.step = 2;
            return;
        }
        const inputs = [...this.template.querySelectorAll('[data-key]')];
        const valid = inputs.reduce((ok, input) => (input.reportValidity ? input.reportValidity() && ok : ok), true);
        if (valid) this.step = 3;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSubmit() {
        this.saving = true;
        try {
            // Only values for reasons still selected (a value typed, then its reason unticked, is dropped).
            const request = { reason: this.selected.join(';'), notes: this.notes };
            this.visibleFields.forEach((f) => {
                request[f.key] = f.value;
            });
            const result = await submitPortalCocRequest({ contextLoanKey: this.contextLoanKey, request });
            if (result.success) {
                showPortalToast(this, 'COC submitted', 'The COC desk has your request.', 'success');
                this.dispatchEvent(new CustomEvent('submitted'));
                return;
            }
            showPortalToast(this, 'COC not submitted', result.userMessage, 'warning');
        } catch (error) {
            showPortalToast(this, 'COC failed', reduceApexError(error), 'error');
        } finally {
            this.saving = false;
        }
    }
}
