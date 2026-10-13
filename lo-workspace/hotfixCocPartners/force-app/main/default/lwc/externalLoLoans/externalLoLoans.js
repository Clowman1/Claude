import { LightningElement, api, wire } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getLoans from '@salesforce/apex/ExternalLoPortalController.getLoans';
import getLoanTabCounts from '@salesforce/apex/ExternalLoPortalController.getLoanTabCounts';
import getLoanDetail from '@salesforce/apex/ExternalLoPortalController.getLoanDetail';
// Same Apex as the Transaction page's Notes tab (Aura EnhancedNotes, which an LWC cannot host).
import getNotesRelatedToLoan from '@salesforce/apex/EnhancedNotesController.getNotesRelatedToLoan';
import { PORTAL_VIEWS, dispatchPortalNavigate, isExperienceCloudContext, reduceApexError, showPortalToast, toGenericListRow } from 'c/portalUtils';

// Mirrors ExternalLoPortalService: the real Status__c pipeline.
const IN_PROCESS_STATUSES = new Set(['Pre-Processing', 'Processing', 'Submitted', 'Suspended', 'Waiting On Loan Officer', 'Conditionally Approved', 'Re-Submitted']);
const FUNDED_OR_LATER = new Set(['Funding', 'PC Review', 'Post-Closed']);

// My Loans tabs (2026-10-08). Older links that pass 'all' / 'update' / 'processing' / 'ctc' land on Active.
const TABS = [
    { id: 'active', label: 'My Active Loans' },
    { id: 'closed', label: 'My Closed Loans' },
    { id: 'cancelled', label: 'My Cancelled Loans' }
];
const TAB_IDS = new Set(TABS.map((t) => t.id));

// Active board columns, keyed by LoanRow.boardStage (computed in ExternalLoPortalService.boardStage).
const BOARD_COLUMNS = [
    { id: 'application', label: 'Application' },
    { id: 'processing', label: 'Processing' },
    { id: 'approved', label: 'Conditionally Approved' },
    { id: 'ctc', label: 'Clear to Close' },
    { id: 'closing', label: 'Closing' }
];
const VIEW_STORAGE_KEY = 'loWs.myLoans.view';

function readStoredView() {
    try {
        return window.localStorage.getItem(VIEW_STORAGE_KEY) === 'list' ? 'list' : 'board';
    } catch (e) {
        return 'board';
    }
}

const DETAIL_TABS = [
    { id: 'details', label: 'Details' },
    { id: 'notes', label: 'Notes' },
    { id: 'calls', label: 'Calls/Zooms' },
    // LO Workspace only (2026-10-08): read-only calls / SMS / emails with this borrower.
    { id: 'comms', label: 'Communications', internalOnly: true },
    { id: 'documents', label: 'Documents' },
    { id: 'conditions', label: 'Conditions' },
    // LO Workspace only: portal users have no access to the appraisal code.
    { id: 'appraisal', label: 'Appraisal', internalOnly: true }
];

export default class ExternalLoLoans extends NavigationMixin(LightningElement) {
    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
    }

    @api embeddedInShell = false;
    @api recordId;
    _filterKey = 'all';
    _pageDetailId;
    _lastLoadedDetailId;
    _refreshKey;
    wiredLoansResult;
    wiredCountsResult;
    viewMode = readStoredView();

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
            if (this.wiredCountsResult) {
                refreshApex(this.wiredCountsResult);
            }
        }
    }

    @api
    get filterKey() {
        return this._filterKey;
    }

    set filterKey(value) {
        this._filterKey = value || 'active';
    }

    loans = [];
    tabCounts = {};
    detail;
    filter = 'active';
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
        const key = this.embeddedInShell ? this._filterKey : this.filter;
        return TAB_IDS.has(key) ? key : 'active';
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

    @wire(getLoanTabCounts)
    wiredCounts(result) {
        this.wiredCountsResult = result;
        if (result.data) {
            this.tabCounts = result.data;
        }
    }

    // ---------- Board (Active tab only; closed and cancelled are always a list) ----------

    get isActiveTab() {
        return this.effectiveFilter === 'active';
    }

    get showBoard() {
        return this.isActiveTab && this.viewMode === 'board';
    }

    get boardPressed() {
        return String(this.viewMode === 'board');
    }

    get listPressed() {
        return String(this.viewMode === 'list');
    }

    get boardToggleClass() {
        return this.viewMode === 'board' ? 'view-btn view-btn-on' : 'view-btn';
    }

    get listToggleClass() {
        return this.viewMode === 'list' ? 'view-btn view-btn-on' : 'view-btn';
    }

    get boardColumns() {
        return BOARD_COLUMNS.map((col) => {
            const cards = this.loans
                .filter((loan) => (loan.boardStage || 'processing') === col.id)
                .map((loan) => ({
                    ...loan,
                    cardClass: loan.needsUpdate ? 'board-card board-card-flag' : 'board-card',
                    metaLine: [loan.milestone, loan.closingLabel].filter(Boolean).join(' · ')
                }));
            return { ...col, cards, count: cards.length, isEmpty: cards.length === 0 };
        });
    }

    handleViewToggle(event) {
        this.viewMode = event.currentTarget.dataset.view === 'list' ? 'list' : 'board';
        try {
            window.localStorage.setItem(VIEW_STORAGE_KEY, this.viewMode);
        } catch (e) {
            // Storage blocked: the choice just isn't remembered.
        }
    }

    handleCardOpen(event) {
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LOANS,
            filter: this.effectiveFilter,
            recordId: event.currentTarget.dataset.id
        });
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
        return TABS.map((item) => ({
            id: item.id,
            label: item.label,
            count: this.tabCounts[item.id] ?? (item.id === activeFilter ? this.loans.length : undefined),
            isActive: item.id === activeFilter
        }));
    }

    get isListEmpty() {
        return !this.loading && this.loans.length === 0;
    }

    get resultLabel() {
        const total = this.tabCounts[this.effectiveFilter] ?? this.loans.length;
        return `Showing ${this.loans.length} of ${total} loans`;
    }

    get listSubtitle() {
        if (this.effectiveFilter === 'closed') return 'Funded and closed files.';
        if (this.effectiveFilter === 'cancelled') return 'Cancelled and lost files.';
        return 'Active borrower files in your pipeline.';
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

    // Header chip in the stage colour: closed (funded or later) navy, clear to close green,
    // needs update amber, in process blue, anything else neutral.
    get milestoneChipClass() {
        const s = this.detail?.summary || {};
        if (FUNDED_OR_LATER.has(s.milestone)) return 'milestone-chip milestone-chip-closed';
        if (s.clearToClose) return 'milestone-chip milestone-chip-ctc';
        if (s.needsUpdate) return 'milestone-chip milestone-chip-warn';
        if (IN_PROCESS_STATUSES.has(s.milestone)) return 'milestone-chip milestone-chip-progress';
        return 'milestone-chip';
    }

    get detailTabs() {
        return DETAIL_TABS.filter((tab) => !tab.internalOnly || !isExperienceCloudContext()).map((tab) => ({
            ...tab,
            tabClass: tab.id === this.activeTab ? 'detail-tab detail-tab-active' : 'detail-tab',
            tourHook: 'loan-tab-' + tab.id, // O4b: the tour opens tabs by clicking them
            ariaCurrent: tab.id === this.activeTab ? 'page' : null
        }));
    }

    get isDetailsTab() {
        return this.activeTab === 'details';
    }

    get isNotesTab() {
        return this.activeTab === 'notes';
    }

    get isCommsTab() {
        return this.activeTab === 'comms';
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

    // LO Workspace only (the Apex returns nothing to portal users).
    get showLoggedCalls() {
        return !isExperienceCloudContext();
    }

    get hasLoggedCalls() {
        return (this.detail?.loggedCalls || []).length > 0;
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
                    created: note.CreatedDate,
                    pinned: note.Is_Pinned__c === true
                }))
                // Pinned first; otherwise newest first as the server returns them.
                .sort((a, b) => Number(b.pinned) - Number(a.pinned));
        } catch (error) {
            this.notes = [];
            this.notesError = reduceApexError(error);
        } finally {
            this.notesLoading = false;
        }
    }

    // Slim New Note modal (c-lo-ws-note-modal), replacing the /apex/AddNewNote pop-up window.
    noteModalOpen = false;

    get noteRecordId() {
        return this.detailId;
    }

    handleNewNote() {
        this.noteModalOpen = true;
    }

    handleNoteModalClose() {
        this.noteModalOpen = false;
    }

    handleNoteSaved() {
        this.noteModalOpen = false;
        this.loadNotes();
    }

    handleOpenCoc() {
        this.cocOpen = true;
    }

    handleCloseCoc() {
        this.cocOpen = false;
    }

    get cocRows() {
        return (this.detail?.cocHistory || []).map((coc) => ({
            ...coc,
            statusClass: `coc-status coc-status-${(coc.status || 'submitted').toLowerCase()}`,
            metaLabel: [coc.submittedLabel, coc.specialist ? `Specialist: ${coc.specialist}` : null, coc.completedLabel]
                .filter(Boolean)
                .join(' · ')
        }));
    }

    get hasCocRows() {
        return this.cocRows.length > 0;
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