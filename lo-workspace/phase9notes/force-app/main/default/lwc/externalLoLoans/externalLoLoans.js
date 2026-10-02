import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getLoans from '@salesforce/apex/ExternalLoPortalController.getLoans';
import getLoanDetail from '@salesforce/apex/ExternalLoPortalController.getLoanDetail';
// Same Apex as the Transaction page's Notes tab (Aura EnhancedNotes, which an LWC cannot host).
import getNotesRelatedToLoan from '@salesforce/apex/EnhancedNotesController.getNotesRelatedToLoan';
import { PORTAL_VIEWS, dispatchPortalNavigate, isExperienceCloudContext, reduceApexError, showPortalToast, toGenericListRow } from 'c/portalUtils';

// Mirrors ExternalLoPortalService: the real Status__c pipeline.
const IN_PROCESS_STATUSES = new Set(['Pre-Processing', 'Processing', 'Submitted', 'Suspended', 'Waiting On Loan Officer', 'Conditionally Approved', 'Re-Submitted']);
const FUNDED_OR_LATER = new Set(['Funding', 'PC Review', 'Post-Closed']);

const FILTERS = [
    { id: 'all', label: 'All' },
    { id: 'update', label: 'Needs update' },
    { id: 'processing', label: 'In process' },
    { id: 'ctc', label: 'Clear to close' }
];

const DETAIL_TABS = [
    { id: 'details', label: 'Details' },
    { id: 'notes', label: 'Notes' },
    { id: 'calls', label: 'Calls' },
    { id: 'documents', label: 'Documents' },
    { id: 'conditions', label: 'Conditions' },
    // LO Workspace only: portal users have no access to the appraisal code.
    { id: 'appraisal', label: 'Appraisal', internalOnly: true }
];

export default class ExternalLoLoans extends NavigationMixin(LightningElement) {
    @api embeddedInShell = false;
    @api recordId;
    _filterKey = 'all';
    _pageDetailId;
    _lastLoadedDetailId;
    _refreshKey;
    wiredLoansResult;
    wiredAllLoansResult;

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(value) {
        this._refreshKey = value;
        if (value) {
            if (this.wiredLoansResult) {
                refreshApex(this.wiredLoansResult);
            }
            if (this.wiredAllLoansResult) {
                refreshApex(this.wiredAllLoansResult);
            }
        }
    }

    @api
    get filterKey() {
        return this._filterKey;
    }

    set filterKey(value) {
        this._filterKey = value || 'all';
    }

    loans = [];
    allLoans = [];
    detail;
    filter = 'all';
    search = '';
    loading = true;
    activeTab = 'details';
    cocOpen = false;
    submissionOpen = false;

    @wire(CurrentPageReference)
    parsePageReference(pageRef) {
        if (this.embeddedInShell) {
            return;
        }
        this._pageDetailId = pageRef?.state?.c__recordId ?? null;
        if (pageRef?.state?.c__filter) {
            this.filter = pageRef.state.c__filter;
        }
        if (this._pageDetailId) {
            this.loadDetail();
        } else {
            this.detail = undefined;
        }
    }

    get effectiveFilter() {
        return this.embeddedInShell ? this._filterKey : this.filter;
    }

    get detailId() {
        return this.embeddedInShell ? this.recordId : this._pageDetailId;
    }

    @wire(getLoans, { filterKey: '$effectiveFilter', searchTerm: '$search' })
    wiredLoans(result) {
        this.wiredLoansResult = result;
        this.loading = !result.data && !result.error;
        if (result.data) {
            this.loans = result.data.map((loan) => ({
                ...loan,
                statusClass: loan.needsUpdate ? 'badge status-warn' : 'badge status-working'
            }));
            this.loading = false;
        }
    }

    get listItems() {
        return this.loans.map((loan) =>
            toGenericListRow({
                id: loan.id,
                title: loan.borrower,
                badges: [
                    { key: 'milestone', label: loan.milestone, toneClass: loan.statusClass },
                    ...(loan.needsUpdate
                        ? [{ key: 'update', label: 'Needs update', toneClass: 'badge badge-warn' }]
                        : [])
                ],
                primary: [loan.amount, loan.program].filter(Boolean).join(' · '),
                meta: [loan.idLabel, loan.closingLabel, loan.processor, loan.realtorLabel]
                    .filter(Boolean)
                    .join(' · '),
                actions: [{ name: 'view', label: 'View', variant: 'outline' }]
            })
        );
    }

    @wire(getLoans, { filterKey: 'all', searchTerm: '$search' })
    wiredAllLoans(result) {
        this.wiredAllLoansResult = result;
        if (result.data) {
            this.allLoans = result.data;
        }
    }

    renderedCallback() {
        if (!this.embeddedInShell || this._lastLoadedDetailId === this.detailId) {
            return;
        }
        this._lastLoadedDetailId = this.detailId;
        if (this.detailId) {
            this.loadDetail();
        } else {
            this.detail = undefined;
        }
    }

    get isDetailView() {
        return !!this.detailId;
    }

    get filterChips() {
        const activeFilter = this.effectiveFilter;
        return FILTERS.map((item) => ({
            id: item.id,
            label: item.label,
            count: this.countForFilter(item.id),
            isActive: item.id === activeFilter
        }));
    }

    get isListEmpty() {
        return !this.loading && this.loans.length === 0;
    }

    get resultLabel() {
        const total = this.allLoans.length || this.loans.length;
        return `Showing ${this.loans.length} of ${total} loans`;
    }

    countForFilter(filterId) {
        const source = this.allLoans.length ? this.allLoans : this.loans;
        if (filterId === 'all') {
            return source.length;
        }
        if (filterId === 'update') {
            return source.filter((loan) => loan.needsUpdate).length;
        }
        if (filterId === 'ctc') {
            return source.filter((loan) => loan.clearToClose && !FUNDED_OR_LATER.has(loan.milestone)).length;
        }
        return source.filter((loan) => IN_PROCESS_STATUSES.has(loan.milestone)).length;
    }

    handleFilterChangeEvent(event) {
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LOANS,
            filter: event.detail.filterId,
            recordId: null
        });
    }

    handleSearchChangeEvent(event) {
        this.search = event.detail.value;
    }

    handleRowAction(event) {
        if (event.detail.action !== 'view') {
            return;
        }
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LOANS,
            filter: this.effectiveFilter,
            recordId: event.detail.recordId
        });
    }

    handleBack() {
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LOANS,
            filter: this.effectiveFilter,
            recordId: null
        });
    }

    async loadDetail() {
        if (!this.detailId) {
            return;
        }
        try {
            this.detail = await getLoanDetail({ loanId: this.detailId });
            if (this.isNotesTab) {
                this.loadNotes();
            }
        } catch (error) {
            showPortalToast(this, 'Loan not found', reduceApexError(error), 'error');
            this.handleBack();
        }
    }

    get detailTabs() {
        return DETAIL_TABS.filter((tab) => !tab.internalOnly || !isExperienceCloudContext()).map((tab) => ({
            ...tab,
            tabClass: tab.id === this.activeTab ? 'detail-tab detail-tab-active' : 'detail-tab',
            ariaCurrent: tab.id === this.activeTab ? 'page' : null
        }));
    }

    get isDetailsTab() {
        return this.activeTab === 'details';
    }

    get isNotesTab() {
        return this.activeTab === 'notes';
    }

    get isCallsTab() {
        return this.activeTab === 'calls';
    }

    get isDocumentsTab() {
        return this.activeTab === 'documents';
    }

    get isAppraisalTab() {
        return this.activeTab === 'appraisal';
    }

    get showFullLoanLink() {
        return !isExperienceCloudContext();
    }

    handleOpenFullLoan() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.detailId, objectApiName: 'Transaction__c', actionName: 'view' }
        });
    }

    get isConditionsTab() {
        return this.activeTab === 'conditions';
    }

    get hasActivityEntries() {
        return (this.detail?.activityEntries || []).length > 0;
    }

    get hasConditionRows() {
        return (this.detail?.conditionRows || []).length > 0;
    }

    get ringSenseInsightKey() {
        return `${this.detailId}-ringsense`;
    }

    get zoomInsightKey() {
        return `${this.detailId}-zoom`;
    }

    handleTabSelect(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        if (this.activeTab === 'notes') {
            this.loadNotes();
        }
    }

    // ---------- Notes (mirrors the Transaction page Notes tab: notes typed Note or blank) ----------
    // LO Workspace only: EnhancedNotesController and /apex/AddNewNote are not in the portal.

    notes = [];
    notesLoading = false;
    notesError;

    get showEnhancedNotes() {
        return !isExperienceCloudContext();
    }

    get hasNotes() {
        return this.notes.length > 0;
    }

    async loadNotes() {
        if (!this.detailId || !this.showEnhancedNotes) {
            return;
        }
        this.notesLoading = true;
        this.notesError = undefined;
        try {
            const rows = await getNotesRelatedToLoan({ loanId: this.detailId });
            this.notes = (rows || [])
                .filter((note) => !note.Type__c || note.Type__c === 'Note')
                .map((note) => ({
                    id: note.Id,
                    subject: note.Subject__c,
                    body: note.Body__c,
                    author: note.CreatedBy?.Name,
                    created: note.CreatedDate
                }));
        } catch (error) {
            this.notes = [];
            this.notesError = reduceApexError(error);
        } finally {
            this.notesLoading = false;
        }
    }

    // The same note form the Transaction page's New button opens.
    handleNewNote() {
        window.open('/apex/AddNewNote?appId=' + this.detailId, 'Enhanced Notes', 'resizable,height=575,width=445');
    }

    handleOpenCoc() {
        this.cocOpen = true;
    }

    handleCloseCoc() {
        this.cocOpen = false;
    }

    handleCocSubmitted() {
        this.cocOpen = false;
        this.loadDetail();
    }

    handleOpenSubmission() {
        this.submissionOpen = true;
    }

    handleCloseSubmission() {
        this.submissionOpen = false;
    }

    handleSubmissionComplete() {
        this.submissionOpen = false;
        this.loadDetail();
    }
}