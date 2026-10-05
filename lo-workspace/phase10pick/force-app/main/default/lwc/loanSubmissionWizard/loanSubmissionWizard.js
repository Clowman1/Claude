import { LightningElement, api } from 'lwc';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getWizardData from '@salesforce/apex/LoanSubmissionWizardController.getWizardData';
import submit from '@salesforce/apex/LoanSubmissionWizardController.submit';
import addBorrower from '@salesforce/apex/LoanSubmissionWizardController.addBorrower';

/*
 * Guided replacement for the screen flow Loan_Origination_Submission_Form (v45).
 * Field keys are the flow's screen-field names; required/visible rules copy its visibilityRule
 * and required settings one for one (LoanSubmissionWizardController re-checks them on save).
 */

// Partner pickers search the whole org by kind; '+ Add new' flips the section to its "Can't find" fields.
const PICKERS = {
    InvestorLookup: { kind: 'investor' },
    InvestorLookup2nd: { kind: 'investor' },
    BuyersNameLookup: { kind: 'agent', addNew: '+ Add new agent', toggle: 'Cant_Find_My_Contact_Buyers', first: 'First_Name_BA', last: 'Last_Name_BA' },
    SellersNameLookup: { kind: 'agent', addNew: '+ Add new agent', toggle: 'Cant_Find_My_Contact_Sellers', first: 'First_Name_SA', last: 'Last_Name_SA' },
    Buying_Agent_Assistant: { kind: 'assistant', addNew: '+ Add new assistant', toggle: 'Cant_Find_BuyersAgentAssistant', first: 'First_Name_BAA', last: 'Last_Name_BAA' },
    Seller_Agent_Assistant: { kind: 'assistant', addNew: '+ Add new assistant', toggle: 'Cant_Find_SellersAgentAssistant', first: 'First_Name_SAA', last: 'Last_Name_SAA' },
    NameTCLookup: { kind: 'title', addNew: '+ Add new title company', toggle: 'Cant_Find_My_Company', company: 'CompanyTC' }
};

const BOOL_KEYS = [
    'Borrower_and_Co_Borrower_are_spouses', 'Borrower_Has_a_Spouse', 'Co_Borrower_Has_a_Spouse', 'Speaks_Spanish_Only',
    'No_Realtor', 'Cant_Find_My_Contact_Buyers', 'Cant_Find_BuyersAgentAssistant', 'Cant_Find_My_Contact_Sellers',
    'Cant_Find_SellersAgentAssistant', 'Cant_Find_My_Company', 'Same_as_Listing_Agent'
];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const buyerSellerRequired = (v) => v.Loan_Purpose === 'Purchase' && !v.No_Realtor;
const isCondo = (v) => v.Property_Type === 'Condo';
const isDpa = (v) => v.DPA_Grant === 'Yes';

const STEPS = [
    {
        name: 'Loan',
        sections: [
            {
                title: 'Investor & channel', tone: 'navy',
                fields: [
                    { key: 'InvestorLookup', label: 'Investor', type: 'lookup', object: 'Account', required: true },
                    { key: 'Channel', label: 'Channel', type: 'chips', options: 'Channel', required: true }
                ]
            },
            {
                title: 'Loan', tone: 'blue',
                fields: [
                    { key: 'Loan_Purpose', label: 'Loan Purpose', type: 'combo', options: 'Loan_Purpose', required: true },
                    { key: 'Refinance_Purpose', label: 'Refinance Purpose', type: 'combo', options: 'Refinance_Purpose', required: true, visible: (v) => v.Loan_Purpose === 'Refinance' },
                    { key: 'Loan_Type', label: 'Loan Type', type: 'combo', options: 'Loan_Type', required: true },
                    { key: 'Program_Type', label: 'Program Type', type: 'combo', options: 'Program_Type', required: true },
                    { key: 'Occupancy', label: 'Occupancy', type: 'combo', options: 'Occupancy', required: true },
                    { key: 'New_Build_Bank_Owned', label: 'New Build/Bank Owned?', type: 'chips', options: 'New_Build_Bank_Owned', required: true }
                ]
            },
            {
                title: 'Property', tone: 'teal',
                fields: [
                    { key: 'Property_Type', label: 'Property Type', type: 'combo', options: 'Property_Type', required: true },
                    { key: 'Condo_Review_Type', label: 'Condo Review Type', type: 'chips', options: 'Condo_Review_Type', required: true, visible: isCondo },
                    {
                        key: 'LimitedReviewMessage', type: 'info', visible: (v) => isCondo(v) && v.Condo_Review_Type === 'Limited Review',
                        label: 'Limited Review Guidelines: Primary residence LTV < 75% LTV; 2nd Home/Investment < 70% LTV'
                    }
                ]
            },
            {
                title: 'Appraisal & underwriting', tone: 'amber',
                fields: [
                    { key: 'Appraisal', label: 'Appraisal', type: 'chips', options: 'Appraisal', required: true },
                    { key: 'Waiving_Escrow', label: 'Waiving Escrow?', type: 'chips', options: 'YesNo', required: true },
                    { key: 'DU_LP_MANUAL', label: 'DU/LP/MANUAL', type: 'chips', options: 'DU_LP_MANUAL' }
                ]
            }
        ]
    },
    {
        name: 'Borrowers',
        borrowers: true,
        sections: [
            {
                title: 'Borrower', tone: 'navy',
                fields: [
                    { key: 'Borrower_First_Name', label: 'Borrower First Name', type: 'text', required: true },
                    { key: 'Borrower_Last_Name', label: 'Borrower Last Name', type: 'text', required: true },
                    { key: 'Speaks_Spanish_Only', label: 'Speaks Spanish Only', type: 'bool' }
                ]
            },
            {
                title: 'Co-borrower', tone: 'blue',
                fields: [
                    { key: 'Co_Borrower_First_Name', label: 'Co-Borrower First Name', type: 'text' },
                    { key: 'Co_Borrower_Last_Name', label: 'Co-Borrower Last Name', type: 'text' },
                    { key: 'BorrowerCoPhone', label: 'Co-Borrower Phone', type: 'tel' },
                    { key: 'BorrowerCoEmail', label: 'Co-Borrower Email', type: 'email' }
                ]
            },
            {
                title: 'Spouses', tone: 'teal',
                fields: [
                    { key: 'Borrower_and_Co_Borrower_are_spouses', label: 'Borrower and Co-Borrower are spouses', type: 'bool', wide: true },
                    { key: 'Borrower_Has_a_Spouse', label: 'Borrower Has a Spouse', type: 'bool', visible: (v) => !v.Borrower_and_Co_Borrower_are_spouses },
                    { key: 'Spouse_Borrower', label: "Borrower's Spouse", type: 'text', visible: (v) => !v.Borrower_and_Co_Borrower_are_spouses && v.Borrower_Has_a_Spouse },
                    { key: 'SpousePhoneBorrower', label: "Borrower's Spouse Phone", type: 'tel', visible: (v) => !v.Borrower_and_Co_Borrower_are_spouses && v.Borrower_Has_a_Spouse },
                    { key: 'SpouseEmailBorrower', label: "Borrower's Spouse Email", type: 'email', visible: (v) => !v.Borrower_and_Co_Borrower_are_spouses && v.Borrower_Has_a_Spouse },
                    { key: 'Co_Borrower_Has_a_Spouse', label: 'Co-Borrower Has a Spouse', type: 'bool', visible: (v) => !v.Borrower_and_Co_Borrower_are_spouses },
                    { key: 'Spouse_CoBorrower', label: "Co-Borrower's Spouse", type: 'text', visible: (v) => !v.Borrower_and_Co_Borrower_are_spouses && v.Co_Borrower_Has_a_Spouse },
                    { key: 'SpousePhoneCoBorrower', label: "Co-Borrower's Spouse Phone", type: 'tel', visible: (v) => !v.Borrower_and_Co_Borrower_are_spouses && v.Co_Borrower_Has_a_Spouse },
                    { key: 'SpouseEmailCoBorrower', label: "Co-Borrower's Spouse Email", type: 'email', visible: (v) => !v.Borrower_and_Co_Borrower_are_spouses && v.Co_Borrower_Has_a_Spouse }
                ]
            }
        ]
    },
    {
        name: 'Partners',
        sections: [
            {
                title: 'Realtors', tone: 'navy',
                fields: [{ key: 'No_Realtor', label: 'No Realtor', type: 'bool', help: "Agents are required on a Purchase unless this is Yes." }]
            },
            {
                title: "Buyer's agent", tone: 'blue',
                fields: [
                    { key: 'Cant_Find_My_Contact_Buyers', label: "Can't find my contact", type: 'toggle', wide: true },
                    { key: 'BuyersNameLookup', label: "Buyer's Agent", type: 'lookup', object: 'Account', required: buyerSellerRequired, visible: (v) => !v.Cant_Find_My_Contact_Buyers },
                    { key: 'First_Name_BA', label: 'First Name', type: 'text', required: buyerSellerRequired, visible: (v) => v.Cant_Find_My_Contact_Buyers },
                    { key: 'Last_Name_BA', label: 'Last Name', type: 'text', required: buyerSellerRequired, visible: (v) => v.Cant_Find_My_Contact_Buyers },
                    { key: 'BuyersCellPhone', label: 'Cell Phone', type: 'tel', required: buyerSellerRequired, visible: (v) => v.Cant_Find_My_Contact_Buyers },
                    { key: 'BuyersEmail', label: 'Email', type: 'email', required: buyerSellerRequired, visible: (v) => v.Cant_Find_My_Contact_Buyers },
                    { key: 'Cant_Find_BuyersAgentAssistant', label: "Assistant: can't find my contact", type: 'toggle', wide: true },
                    { key: 'Buying_Agent_Assistant', label: "Buyer's Agent Assistant", type: 'lookup', object: 'Account', visible: (v) => !v.Cant_Find_BuyersAgentAssistant },
                    { key: 'First_Name_BAA', label: 'Assistant First Name', type: 'text', required: true, visible: (v) => v.Cant_Find_BuyersAgentAssistant },
                    { key: 'Last_Name_BAA', label: 'Assistant Last Name', type: 'text', required: true, visible: (v) => v.Cant_Find_BuyersAgentAssistant },
                    { key: 'PhoneBAA', label: 'Assistant Phone', type: 'tel', required: true, visible: (v) => v.Cant_Find_BuyersAgentAssistant },
                    { key: 'EmailBAA', label: 'Assistant Email', type: 'email', required: true, visible: (v) => v.Cant_Find_BuyersAgentAssistant }
                ]
            },
            {
                title: "Seller's agent", tone: 'teal',
                fields: [
                    { key: 'Cant_Find_My_Contact_Sellers', label: "Can't find my contact", type: 'toggle', wide: true },
                    { key: 'SellersNameLookup', label: "Seller's Agent", type: 'lookup', object: 'Account', required: buyerSellerRequired, visible: (v) => !v.Cant_Find_My_Contact_Sellers },
                    { key: 'First_Name_SA', label: 'First Name', type: 'text', required: buyerSellerRequired, visible: (v) => v.Cant_Find_My_Contact_Sellers },
                    { key: 'Last_Name_SA', label: 'Last Name', type: 'text', required: buyerSellerRequired, visible: (v) => v.Cant_Find_My_Contact_Sellers },
                    { key: 'SellersCellPhone', label: 'Cell Phone', type: 'tel', required: buyerSellerRequired, visible: (v) => v.Cant_Find_My_Contact_Sellers },
                    { key: 'SellersEmail', label: 'Email', type: 'email', required: buyerSellerRequired, visible: (v) => v.Cant_Find_My_Contact_Sellers },
                    { key: 'Cant_Find_SellersAgentAssistant', label: "Assistant: can't find my contact", type: 'toggle', wide: true },
                    { key: 'Seller_Agent_Assistant', label: "Seller's Agent Assistant", type: 'lookup', object: 'Contact', visible: (v) => !v.Cant_Find_SellersAgentAssistant },
                    { key: 'First_Name_SAA', label: 'Assistant First Name', type: 'text', required: true, visible: (v) => v.Cant_Find_SellersAgentAssistant },
                    { key: 'Last_Name_SAA', label: 'Assistant Last Name', type: 'text', required: true, visible: (v) => v.Cant_Find_SellersAgentAssistant },
                    { key: 'PhoneSAA', label: 'Assistant Phone', type: 'tel', required: true, visible: (v) => v.Cant_Find_SellersAgentAssistant },
                    { key: 'EmailSAA', label: 'Assistant Email', type: 'email', required: true, visible: (v) => v.Cant_Find_SellersAgentAssistant }
                ]
            },
            {
                title: 'Title company', tone: 'amber',
                fields: [
                    { key: 'Cant_Find_My_Company', label: "Can't find my company", type: 'toggle', wide: true },
                    { key: 'NameTCLookup', label: 'Title Company', type: 'lookup', object: 'Account', required: true, visible: (v) => !v.Cant_Find_My_Company },
                    { key: 'CompanyTC', label: 'Company', type: 'text', required: true, visible: (v) => v.Cant_Find_My_Company },
                    { key: 'PhoneTC', label: 'Phone', type: 'tel', required: true, visible: (v) => v.Cant_Find_My_Company },
                    { key: 'EmailTC', label: 'Email', type: 'email', required: true, visible: (v) => v.Cant_Find_My_Company }
                ]
            },
            {
                title: "Homeowner's association", tone: 'violet', visible: isCondo,
                fields: [
                    { key: 'NameHOA', label: 'HOA Name', type: 'text', required: true },
                    { key: 'CompanyHOA', label: 'HOA Company', type: 'text', required: true },
                    { key: 'PhoneHOA', label: 'HOA Phone', type: 'tel', required: true }
                ]
            },
            {
                title: 'Contact for appraisal entry', tone: 'navy',
                fields: [
                    { key: 'Same_as_Listing_Agent', label: "Same as Seller's Agent", type: 'bool', wide: true },
                    { key: 'NameContactForEntry', label: 'Name', type: 'text', required: true, visible: (v) => !v.Same_as_Listing_Agent },
                    { key: 'PhoneContactForEntry', label: 'Phone', type: 'tel', required: true, visible: (v) => !v.Same_as_Listing_Agent },
                    { key: 'EmailContactForEntry', label: 'Email', type: 'email', required: true, visible: (v) => !v.Same_as_Listing_Agent }
                ]
            }
        ]
    },
    {
        name: 'Pricing & lock',
        sections: [
            {
                title: 'Cash to close & buydown', tone: 'navy',
                fields: [
                    { key: 'Expected_Cash_To_Close', label: 'Expected Cash To Close', type: 'currency', step: '1', required: true },
                    { key: 'Rate_Buydown', label: 'Rate Buydown', type: 'chips', options: 'YesNo', required: true },
                    { key: 'Contributor', label: 'Contributor', type: 'chips', options: 'Contributor', required: true, visible: (v) => v.Rate_Buydown === 'Yes' },
                    { key: 'Buydown', label: 'Buydown', type: 'chips', options: 'Buydown', required: true, visible: (v) => v.Rate_Buydown === 'Yes' }
                ]
            },
            {
                title: 'DPA / grant', tone: 'teal',
                fields: [
                    { key: 'DPA_Grant', label: 'DPA/Grant', type: 'chips', options: 'YesNo', required: true },
                    { key: 'DPA_Grant_Program_Name', label: 'DPA/Grant Program Name', type: 'text', required: true, visible: isDpa },
                    { key: 'DPA_Grant_Number_of_Persons_in_Household', label: 'Number of Persons in Household', type: 'text', visible: isDpa },
                    { key: 'DPA_Grant_Household_Income', label: 'Household Income', type: 'text', visible: isDpa }
                ]
            },
            {
                title: 'Attached 2nd transaction', tone: 'violet', visible: isDpa,
                fields: [
                    { key: 'InvestorLookup2nd', label: 'Investor', type: 'lookup', object: 'Account', required: true },
                    { key: 'Loan_Type_2nd', label: 'Loan Type 2nd', type: 'combo', options: 'Loan_Type', required: true },
                    { key: 'Rate_2nd', label: 'Rate 2nd', type: 'number', step: '0.001', required: true },
                    { key: 'Loan_Amount_2nd', label: 'Loan Amount 2nd', type: 'currency', step: '0.01', required: true },
                    { key: 'Loan_Program_2nd', label: 'Loan Program 2nd', type: 'combo', options: 'Program_Type', required: true }
                ]
            },
            {
                title: 'Dates & rate lock', tone: 'amber',
                fields: [
                    { key: 'Commitment', label: 'Commitment Date', type: 'date' },
                    { key: 'Closing', label: 'Closing Date', type: 'date', required: true },
                    { key: 'Rate_Lock_Status', label: 'Rate Lock Status', type: 'chips', options: 'Rate_Lock_Status', required: true },
                    { key: 'Lock_Date', label: 'Lock Exp Date', type: 'date', required: true, visible: (v) => v.Rate_Lock_Status === 'Locked' }
                ]
            }
        ]
    },
    {
        name: 'Notes & needs',
        sections: [
            {
                title: 'Income & assets', tone: 'navy',
                fields: [
                    { key: 'Income_Multi', label: 'Income', type: 'multi', options: 'Income_Multi', required: true, wide: true },
                    { key: 'Assets_Multi', label: 'Assets', type: 'multi', options: 'Assets_Multi', required: true, wide: true },
                    { key: 'Intentions_for_Current_Home', label: 'Intentions for Current Home', type: 'combo', options: 'Intentions_for_Current_Home' }
                ]
            },
            {
                title: 'Notes', tone: 'blue',
                fields: [
                    { key: 'General_Notes', label: 'General Notes', type: 'textarea', wide: true },
                    { key: 'Needs_List', label: 'Pending Documents Requested', type: 'textarea', wide: true },
                    { key: 'Credit', label: 'Credit Notes', type: 'textarea', wide: true }
                ]
            }
        ]
    },
    { name: 'Review & submit', review: true, sections: [] }
];

const LAST = STEPS.length - 1;

export default class LoanSubmissionWizard extends LightningElement {
    @api recordId;
    @api availableActions; // set only when running as a flow screen component

    loading = true;
    loadError;
    saving = false;
    saveError;
    done = false;
    transactionName;
    lockedMessage;
    values = {};
    original = {};
    labels = {};
    prefilled = new Set();
    options = {};
    borrowers = [];
    errors = {};
    step = 0;
    furthest = 0;
    draftBorrower;
    addingBorrower = false;
    borrowerError;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const data = await getWizardData({ transactionId: this.recordId });
            const values = { ...(data.values || {}) };
            BOOL_KEYS.forEach((k) => {
                values[k] = values[k] === true;
            });
            this.values = values;
            this.original = { ...values };
            this.labels = { ...(data.lookupLabels || {}) };
            this.prefilled = new Set(data.prefilledKeys || []);
            this.options = data.options || {};
            this.borrowers = data.borrowers || [];
            // co-borrower fields came from this row; submit writes the LO's edits back to it
            if (this.borrowers.length) {
                this.values = { ...this.values, CoBorrowerRowId: this.borrowers[0].Id };
            }
            this.lockedMessage = data.lockedMessage;
            this.transactionName = data.transactionName;
        } catch (e) {
            this.loadError = this.message(e);
        } finally {
            this.loading = false;
        }
    }

    // ------------------------------------------------------------ view model

    get isReady() {
        return !this.loading && !this.loadError && !this.done;
    }

    get stepper() {
        return STEPS.map((s, i) => {
            const state = i === this.step ? 'current' : i <= this.furthest ? 'done' : 'todo';
            return {
                index: i,
                number: i + 1,
                name: s.name,
                cls: `stp stp-${state}`,
                disabled: i > this.furthest,
                ariaCurrent: i === this.step ? 'step' : null
            };
        });
    }

    get stepLabel() {
        return `Step ${this.step + 1} of ${STEPS.length} · ${this.percent}%`;
    }

    get stepName() {
        return STEPS[this.step].name;
    }

    /** Share of the currently required questions that are answered. */
    get percent() {
        let total = 0;
        let filled = 0;
        STEPS.forEach((s) => this.visibleFields(s).forEach((f) => {
            if (this.isRequired(f)) {
                total++;
                if (!this.isEmpty(this.values[f.key])) {
                    filled++;
                }
            }
        }));
        return total ? Math.round((filled / total) * 100) : 100;
    }

    get progressStyle() {
        return `width:${this.percent}%`;
    }

    get isReview() {
        return !!STEPS[this.step].review;
    }

    get isBorrowerStep() {
        return !!STEPS[this.step].borrowers;
    }

    get showBack() {
        return this.step > 0;
    }

    get isLast() {
        return this.step === LAST;
    }

    get submitDisabled() {
        return this.saving || !!this.lockedMessage;
    }

    get submitLabel() {
        return this.saving ? 'Submitting…' : 'Submit form';
    }

    get currentSections() {
        return this.sectionsFor(STEPS[this.step]);
    }

    sectionsFor(step) {
        const v = this.values;
        return step.sections
            .filter((sec) => !sec.visible || sec.visible(v))
            .map((sec) => ({
                key: sec.title,
                title: sec.title,
                cls: `card card-${sec.tone}`,
                fields: sec.fields.filter((f) => !f.visible || f.visible(v)).map((f) => this.fieldView(f))
            }));
    }

    visibleFields(step) {
        const v = this.values;
        const out = [];
        step.sections.forEach((sec) => {
            if (!sec.visible || sec.visible(v)) {
                sec.fields.forEach((f) => {
                    if ((!f.visible || f.visible(v)) && f.type !== 'info') {
                        out.push(f);
                    }
                });
            }
        });
        return out;
    }

    isRequired(f) {
        return typeof f.required === 'function' ? f.required(this.values) : !!f.required;
    }

    isEmpty(val) {
        return val === undefined || val === null || (typeof val === 'string' && val.trim() === '');
    }

    fieldView(f) {
        const value = this.values[f.key];
        const error = this.errors[f.key];
        const isPrefilled = this.prefilled.has(f.key) && value === this.original[f.key] && !this.isEmpty(value);
        const opts = (this.options[f.options] || []).map((o) => {
            const on = f.type === 'multi'
                ? (value || '').split(';').includes(o.value)
                : value === o.value;
            return { ...o, key: `${f.key}-${o.value}`, on, cls: on ? 'chip chip-on' : 'chip', pressed: on ? 'true' : 'false' };
        });
        return {
            key: f.key,
            label: f.label,
            help: f.help,
            value,
            displayName: this.labels[f.key],
            object: f.object,
            kind: PICKERS[f.key]?.kind,
            addNewLabel: PICKERS[f.key]?.addNew,
            step: f.step,
            options: opts,
            comboOptions: this.options[f.options] || [],
            required: this.isRequired(f),
            error,
            prefilled: isPrefilled,
            wrapCls: `fld${f.wide || f.type === 'textarea' || f.type === 'info' || f.type === 'multi' ? ' fld-wide' : ''}${error ? ' fld-err' : ''}`,
            yesCls: value === true ? 'chip chip-on' : 'chip',
            noCls: value === false ? 'chip chip-on' : 'chip',
            yesPressed: value === true ? 'true' : 'false',
            noPressed: value === false ? 'true' : 'false',
            toggleCls: value ? 'toggle toggle-on' : 'toggle',
            isLookup: f.type === 'lookup',
            isInput: ['text', 'tel', 'email', 'date', 'currency', 'number'].includes(f.type),
            inputType: f.type === 'currency' ? 'number' : f.type,
            formatter: f.type === 'currency' ? 'currency' : undefined,
            isCombo: f.type === 'combo',
            isChips: f.type === 'chips',
            isMulti: f.type === 'multi',
            isBool: f.type === 'bool',
            isToggle: f.type === 'toggle',
            isTextarea: f.type === 'textarea',
            isInfo: f.type === 'info'
        };
    }

    get reviewGroups() {
        return STEPS.slice(0, LAST).map((s, i) => {
            const rows = [];
            let missing = 0;
            this.visibleFields(s).forEach((f) => {
                const val = this.values[f.key];
                if (this.isRequired(f) && this.isEmpty(val)) {
                    missing++;
                }
                if (this.isEmpty(val) || ((f.type === 'bool' || f.type === 'toggle') && !val)) {
                    return;
                }
                rows.push({ key: f.key, label: f.label, text: this.display(f, val) });
            });
            return {
                index: i,
                name: s.name,
                rows,
                missing,
                missingText: missing ? `${missing} required ${missing === 1 ? 'answer' : 'answers'} missing` : '',
                cls: missing ? 'rv-card rv-missing' : 'rv-card',
                empty: rows.length === 0,
                extraBorrowers: s.borrowers ? this.extraBorrowers.map((b) => b.label).join(', ') : ''
            };
        });
    }

    display(f, val) {
        if (f.type === 'lookup') {
            return this.labels[f.key] || 'Selected';
        }
        if (f.type === 'bool' || f.type === 'toggle') {
            return val ? 'Yes' : 'No';
        }
        if (f.type === 'multi') {
            return String(val).split(';').join(', ');
        }
        if (f.type === 'currency') {
            const n = Number(val);
            return Number.isNaN(n) ? val : n.toLocaleString('en-US', { style: 'currency', currency: 'USD' });
        }
        const text = String(val);
        return text.length > 160 ? `${text.slice(0, 157)}…` : text;
    }

    // ------------------------------------------------------------- borrowers

    get borrowerCards() {
        return this.borrowers.map((b, i) => ({
            id: b.Id,
            label: b.Name || [b.First_Name__c, b.Last_Name__c].filter(Boolean).join(' '),
            detail: [b.Relationship__c, b.Email__c || '(no email)', b.Phone__c].filter(Boolean).join(' · '),
            tag: i === 0 ? 'Co-borrower on this form' : 'Additional borrower · stays on the file',
            cls: i === 0 ? 'bcard bcard-co' : 'bcard'
        }));
    }

    get extraBorrowers() {
        return this.borrowerCards.slice(1);
    }

    get primaryBorrowerName() {
        return [this.values.Borrower_First_Name, this.values.Borrower_Last_Name].filter(Boolean).join(' ') || 'Primary borrower';
    }

    get hasBorrowers() {
        return this.borrowers.length > 0;
    }

    handleAddBorrower() {
        this.borrowerError = null;
        this.draftBorrower = { first: '', last: '', email: '', phone: '' };
    }

    handleDraftBorrower(event) {
        this.draftBorrower = { ...this.draftBorrower, [event.target.dataset.field]: event.target.value };
    }

    handleCancelBorrower() {
        this.draftBorrower = null;
    }

    async handleSaveBorrower() {
        const d = this.draftBorrower;
        if (!d.first.trim() || !d.last.trim()) {
            this.borrowerError = 'First and last name are required.';
            return;
        }
        this.addingBorrower = true;
        try {
            const row = await addBorrower({
                transactionId: this.recordId, firstName: d.first, lastName: d.last, email: d.email, phone: d.phone
            });
            const wasEmpty = this.borrowers.length === 0;
            this.borrowers = [...this.borrowers, row];
            if (wasEmpty && this.isEmpty(this.values.Co_Borrower_First_Name) && this.isEmpty(this.values.Co_Borrower_Last_Name)) {
                this.values = {
                    ...this.values,
                    Co_Borrower_First_Name: row.First_Name__c,
                    Co_Borrower_Last_Name: row.Last_Name__c,
                    BorrowerCoEmail: row.Email__c,
                    BorrowerCoPhone: row.Phone__c,
                    CoBorrowerRowId: row.Id
                };
            }
            this.draftBorrower = null;
        } catch (e) {
            this.borrowerError = this.message(e);
        } finally {
            this.addingBorrower = false;
        }
    }

    // ---------------------------------------------------------------- edits

    setValue(key, value) {
        this.values = { ...this.values, [key]: value };
        if (this.errors[key]) {
            const errors = { ...this.errors };
            delete errors[key];
            this.errors = errors;
        }
    }

    handleInput(event) {
        const key = event.target.dataset.key;
        let value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.setValue(key, value === '' ? null : value);
    }

    handleChip(event) {
        const { key, value } = event.currentTarget.dataset;
        this.setValue(key, this.values[key] === value ? null : value);
    }

    handleMulti(event) {
        const { key, value } = event.currentTarget.dataset;
        const set = new Set((this.values[key] || '').split(';').filter(Boolean));
        if (set.has(value)) {
            set.delete(value);
        } else {
            set.add(value);
        }
        // keep picklist order
        const ordered = (this.options[this.optionKeyFor(key)] || []).map((o) => o.value).filter((v) => set.has(v));
        this.setValue(key, ordered.length ? ordered.join(';') : null);
    }

    optionKeyFor(key) {
        for (const s of STEPS) {
            for (const sec of s.sections) {
                const f = sec.fields.find((x) => x.key === key);
                if (f) {
                    return f.options;
                }
            }
        }
        return key;
    }

    handleBool(event) {
        const { key, value } = event.currentTarget.dataset;
        this.setValue(key, value === 'true');
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.setValue(key, !this.values[key]);
    }

    handleAddNew(event) {
        const picker = PICKERS[event.target.dataset.key];
        if (!picker?.toggle) {
            return;
        }
        const typed = (event.detail.term || '').trim();
        this.setValue(picker.toggle, true);
        if (picker.company) {
            this.setValue(picker.company, typed || null);
        } else if (typed) {
            const parts = typed.split(' ').filter(Boolean);
            this.setValue(picker.first, parts.length > 1 ? parts.slice(0, -1).join(' ') : null);
            this.setValue(picker.last, parts[parts.length - 1]);
        }
    }

    handleLookup(event) {
        const key = event.target.dataset.key;
        this.labels = { ...this.labels, [key]: event.detail.label };
        this.setValue(key, event.detail.value);
    }

    // ----------------------------------------------------------- navigation

    validate(stepIndexes) {
        const errors = {};
        stepIndexes.forEach((i) => this.visibleFields(STEPS[i]).forEach((f) => {
            const val = this.values[f.key];
            if (this.isRequired(f) && this.isEmpty(val)) {
                errors[f.key] = 'Required';
            } else if (f.type === 'email' && !this.isEmpty(val) && !EMAIL_RE.test(String(val).trim())) {
                errors[f.key] = 'Enter a valid email address';
            }
        }));
        this.errors = errors;
        return Object.keys(errors).length === 0;
    }

    firstStepWithErrors() {
        for (let i = 0; i < LAST; i++) {
            if (this.visibleFields(STEPS[i]).some((f) => this.errors[f.key])) {
                return i;
            }
        }
        return -1;
    }

    goTo(index) {
        this.step = index;
        this.furthest = Math.max(this.furthest, index);
        this.saveError = null;
        const top = this.template.querySelector('.wiz');
        if (top && top.scrollIntoView) {
            top.scrollIntoView({ block: 'start', behavior: 'smooth' });
        }
    }

    handleNext() {
        if (!this.validate([this.step])) {
            return;
        }
        this.goTo(this.step + 1);
    }

    handleBack() {
        this.errors = {};
        this.goTo(this.step - 1);
    }

    handleJump(event) {
        const index = Number(event.currentTarget.dataset.index);
        if (index <= this.furthest) {
            this.errors = {};
            this.goTo(index);
        }
    }

    async handleSubmit() {
        if (!this.validate([0, 1, 2, 3, 4])) {
            this.goTo(this.firstStepWithErrors());
            return;
        }
        this.saving = true;
        this.saveError = null;
        try {
            await submit({ transactionId: this.recordId, payloadJson: JSON.stringify(this.values) });
            this.done = true;
            try {
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            } catch (e) {
                // not available in every container; the parent reloads anyway
            }
            this.dispatchEvent(new CustomEvent('submitted'));
        } catch (e) {
            this.saveError = this.message(e);
        } finally {
            this.saving = false;
        }
    }

    handleClose() {
        if (Array.isArray(this.availableActions)) {
            // Flow screen component (Experience Cloud quick action): unguarded, see memory flow-screen-component-navigation.
            this.dispatchEvent(new FlowNavigationFinishEvent());
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }

    message(e) {
        return (e && e.body && (e.body.message || (e.body.pageErrors && e.body.pageErrors[0] && e.body.pageErrors[0].message))) ||
            (e && e.message) || 'Something went wrong.';
    }
}