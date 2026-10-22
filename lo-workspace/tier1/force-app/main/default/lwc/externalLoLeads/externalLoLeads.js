import { LightningElement, api, wire } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getLeads from '@salesforce/apex/ExternalLoPortalController.getLeads';
import getLeadDetail from '@salesforce/apex/ExternalLoPortalController.getLeadDetail';
import findLeadDuplicates from '@salesforce/apex/ExternalLoPortalController.findLeadDuplicates';
import createLead from '@salesforce/apex/ExternalLoPortalController.createLead';
// Same Apex as the Lead page's Notes tab (Aura EnhancedNotes, which an LWC cannot host).
import getLeadStatusOptions from '@salesforce/apex/ExternalLoPortalController.getLeadStatusOptions';
import updateLeadStatus from '@salesforce/apex/ExternalLoPortalController.updateLeadStatus';
import linkToArive from '@salesforce/apex/ExternalLoPortalController.linkToArive';
import getNotesRelatedToLoan from '@salesforce/apex/EnhancedNotesController.getNotesRelatedToLoan';
import getLetterBlockedReason from '@salesforce/apex/LeadPreApprovalLetterController.getLetterBlockedReason';
import { PORTAL_VIEWS, dispatchPortalNavigate, isExperienceCloudContext, reduceApexError, readFormFields, showPortalToast, toGenericListRow } from 'c/portalUtils';

const FILTERS = [
    { id: 'all', label: 'All' },
    { id: 'new', label: 'New' },
    { id: 'working', label: 'Working' },
    { id: 'pre-approval', label: 'Pre-Approval' },
    { id: 'nurture', label: 'Nurture' },
    { id: 'converted', label: 'Converted' }
];

const STATUS_CLASS = {
    new: 'badge status-new',
    working: 'badge status-working',
    'pre-approval': 'badge status-pre-approval',
    nurture: 'badge status-nurture',
    contacting: 'badge status-working',
    'docs-requested': 'badge status-pre-approval',
    'docs-received': 'badge status-pre-approval',
    converted: 'badge status-converted',
    closed: 'badge badge-neutral'
};

const DETAIL_TABS = [
    { id: 'overview', label: 'Overview' },
    { id: 'documents', label: 'Documents' },
    { id: 'requests', label: 'Document requests' },
    { id: 'calls', label: 'Calls/Zooms' },
    // LO Workspace only (2026-10-08): read-only calls / SMS / emails with this borrower.
    { id: 'comms', label: 'Communications', internalOnly: true },
    // LO Workspace only: EnhancedNotesController and /apex/AddNewNote are not in the portal.
    { id: 'notes', label: 'Notes', internalOnly: true }
];

const LAYOUT_KEY = 'loWorkspace.myLeads.layout';
const BOARD_COLUMNS = FILTERS.filter((f) => f.id !== 'all');
// LO Workspace: My Active Leads = New / Working / Pre-Approval. Nurture has its own page; converted leads show nowhere.
// Columns come from the exact Lead Status. Pre-Approval lives in My Pre-Approvals, Nurture statuses
// in Nurtured Leads (30 Day + Follow Up stays Working), converted leads nowhere.
const ACTIVE_COLUMNS = [
    { id: 'new', label: 'New' },
    { id: 'contacting', label: 'Contacting' },
    { id: 'working', label: 'Working' },
    { id: 'docs-requested', label: 'Docs Requested' },
    { id: 'docs-received', label: 'Docs Received' }
];
const ACTIVE_FILTERS = [{ id: 'all', label: 'All' }, ...ACTIVE_COLUMNS];
const MOVE_TARGETS = [...ACTIVE_COLUMNS, { id: 'pre-approval', label: 'Pre-Approval' }, { id: 'nurture', label: 'Nurture' }];
const THIRTY_DAY = '30 Day + Follow Up';

function isNurtureStatus(status) {
    return /^nurtur/i.test(status || '') && status !== THIRTY_DAY;
}

/** Board column for an active lead, or null when it belongs elsewhere. */
function workspaceColumn(lead) {
    const status = lead.statusLabel || 'New';
    if (lead.status === 'converted' || status === 'Pre-Approval' || isNurtureStatus(status)) return null;
    if (status === 'New') return 'new';
    if (status.startsWith('Contact Attempt')) return 'contacting';
    if (status === 'Documents Requested') return 'docs-requested';
    if (status === 'Documents Received for Review') return 'docs-received';
    // Working, Contacted/Call Back, 30 Day + Follow Up and any legacy status.
    return 'working';
}
// Board drop target -> the Lead Status it sets. Converted is not a target (Convert to transaction).
const COLUMN_STATUS = {
    new: 'New',
    contacting: 'Contact Attempt 1',
    working: 'Working',
    'docs-requested': 'Documents Requested',
    'docs-received': 'Documents Received for Review',
    'pre-approval': 'Pre-Approval',
    nurture: 'Nurturing'
};

function readLayout() {
    try {
        return window.localStorage.getItem(LAYOUT_KEY) === 'list' ? 'list' : 'board';
    } catch (e) {
        return 'board';
    }
}

function decorateLead(lead) {
    return {
        ...lead,
        statusClass: STATUS_CLASS[lead.status] || 'badge status-nurture',
        neverContacted: lead.lastContactLabel == null
    };
}

export default class ExternalLoLeads extends NavigationMixin(LightningElement) {
    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
    }

    @api embeddedInShell = false;
    @api recordId;
    /** 'active' (My Active Leads) or 'nurtured' (Nurtured Leads). The portal ignores it. */
    @api mode = 'active';
    /** Detail tab to open on when the shell navigates here with one (e.g. 'requests'). */
    @api initialTab;
    commsTab; // comms-settings: Communications sub-tab to open on
    _filterKey = 'all';
    _pageDetailId;
    _refreshKey;

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(value) {
        this._refreshKey = value;
        if (value && this.wiredLeadsResult) {
            this.refreshLeadLists().catch(() => {});
        }
    }

    @api
    get filterKey() {
        return this._filterKey;
    }

    set filterKey(value) {
        this._filterKey = value || 'all';
        if (this.isActiveMode && this.allLeads.length) {
            this.applyActiveChip();
        }
    }

    get activeChip() {
        return (this.embeddedInShell ? this._filterKey : this.filter) || 'all';
    }

    applyActiveChip() {
        const chip = this.activeChip;
        this.leads = this.allLeads.filter((lead) => chip === 'all' || lead.status === chip).map(decorateLead);
    }

    leads = [];
    allLeads = [];
    detail;
    duplicates = [];
    filter = 'all';
    search = '';
    loading = true;
    addOpen = false;
    logOpen = false;
    conversionOpen = false;
    letterOpen = false;
    letterCtor;
    summaryOpen = false;
    summaryCtor;
    saving = false;
    formError;
    listLogLead;
    wiredLeadsResult;
    wiredAllLeadsResult;
    _lastLoadedDetailId;
    activeTab = 'overview';

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

    get isLoWorkspace() {
        return !isExperienceCloudContext();
    }

    get isNurturedMode() {
        return this.isLoWorkspace && this.mode === 'nurtured';
    }

    get isActiveMode() {
        return this.isLoWorkspace && !this.isNurturedMode;
    }

    get listTitle() {
        if (this.isNurturedMode) return 'Nurtured Leads';
        return this.isLoWorkspace ? 'My Active Leads' : 'My Leads';
    }

    get listSubtitle() {
        return this.isNurturedMode
            ? 'Leads in a Nurture status. Change the status to bring one back to your active list.'
            : 'Consumer leads assigned to you. Log every touch manually — outbound calls from your own phone aren’t tracked automatically.';
    }

    // Active mode drops nurture and converted rows; nurtured mode is the server's nurture filter.
    // Active mode re-keys each lead to its board column; nurtured mode drops 30 Day + Follow Up (it's Working).
    workspaceRows(rows) {
        if (this.isActiveMode) {
            return rows
                .map((lead) => ({ ...lead, status: workspaceColumn(lead) }))
                .filter((lead) => lead.status);
        }
        if (this.isNurturedMode) {
            return rows.filter((lead) => lead.statusLabel !== THIRTY_DAY);
        }
        return rows;
    }

    get effectiveFilter() {
        if (this.isNurturedMode) return 'nurture';
        // Active mode filters by column on the client; the server returns every non-Nurture lead.
        return this.isActiveMode ? 'active' : this.embeddedInShell ? this._filterKey : this.filter;
    }

    // Counts and the board come from the same scope in LO Workspace (one cached call); the portal counts 'all'.
    get countFilter() {
        return this.isLoWorkspace ? this.effectiveFilter : 'all';
    }

    // Nurtured Leads loads 200 at a time; Load more asks for the next 200.
    nurtureLimit = 200;

    get rowLimit() {
        return this.isNurturedMode ? this.nurtureLimit : null;
    }

    get showLoadMore() {
        return this.isNurturedMode && !this.loading && (this.allLeads.length || this.leads.length) >= this.nurtureLimit;
    }

    handleLoadMore() {
        this.nurtureLimit += 200;
    }

    get detailId() {
        return this.embeddedInShell ? this.recordId : this._pageDetailId;
    }

    form = {
        name: '',
        phone: '',
        email: '',
        purpose: '',
        loanAmount: '',
        loanProgram: 'Conventional',
        market: '',
        leadSource: 'Realtor referral',
        notes: ''
    };

    @wire(getLeads, { filterKey: '$effectiveFilter', searchTerm: '$search', rowLimit: '$rowLimit' })
    wiredLeads(result) {
        this.wiredLeadsResult = result;
        this.loading = !result.data && !result.error;
        if (result.data) {
            const chip = this.activeChip;
            this.leads = this.workspaceRows(result.data)
                .filter((lead) => !this.isActiveMode || !chip || chip === 'all' || lead.status === chip)
                .map(decorateLead);
            this.loading = false;
        }
    }

    renderedCallback() {
        this.renderLetterListeners();
        if (!this.embeddedInShell || this._lastLoadedDetailId === this.detailId) {
            return;
        }
        this._lastLoadedDetailId = this.detailId;
        if (this.detailId) {
            if (this.initialTab) {
                // comms-settings: 'texts' = the Communications tab opened on Texts.
                this.commsTab = this.initialTab === 'texts' ? 'texts' : null;
                this.activeTab = this.initialTab === 'texts' ? 'comms' : this.initialTab;
            }
            this.loadDetail();
        } else {
            this.detail = undefined;
        }
    }

    @wire(getLeads, { filterKey: '$countFilter', searchTerm: '$search', rowLimit: '$rowLimit' })
    wiredAllLeads(result) {
        this.wiredAllLeadsResult = result;
        if (result.data) {
            this.allLeads = this.workspaceRows(result.data);
        }
    }

    get isDetailView() {
        return !!this.detailId;
    }

    get filterChips() {
        const activeFilter = this.isActiveMode ? this.activeChip : this.effectiveFilter;
        if (this.isNurturedMode) return [];
        return (this.isActiveMode ? ACTIVE_FILTERS : FILTERS).map((item) => ({
            id: item.id,
            label: item.label,
            count: this.countForFilter(item.id),
            isActive: item.id === activeFilter
        }));
    }

    get isListEmpty() {
        return !this.loading && this.leads.length === 0;
    }

    get searchPlaceholder() {
        return this.isLoWorkspace ? 'Search leads by name, email, or phone' : 'Search leads by name, ID, or source';
    }

    get resultLabel() {
        const total = this.allLeads.length || this.leads.length;
        return `Showing ${this.leads.length} of ${total} leads`;
    }

    get listItems() {
        return this.leads.map((lead) =>
            toGenericListRow({
                id: lead.id,
                title: lead.name,
                badges: [
                    { key: lead.status, label: lead.statusLabel || lead.status, toneClass: lead.statusClass },
                    ...(lead.neverContacted
                        ? [{ key: 'never', label: 'Never contacted', toneClass: 'badge badge-danger' }]
                        : []),
                    // LO Workspace only (null in the portal). Indicator: it never changes the status.
                    ...(lead.nextAppointment
                        ? [{
                              key: 'appt',
                              label: lead.nextAppointment.replace('Next appointment: ', 'Next appt ').split(' — ')[0],
                              toneClass: 'badge badge-appt'
                          }]
                        : [])
                ],
                primary: lead.primary,
                // No raw Salesforce Id (owner, 2026-10-02).
                meta: [lead.source, lead.assignedLabel, lead.lastContactLabel]
                    .filter(Boolean)
                    .join(' · '),
                actions: [
                    { name: 'log', label: 'Log communication', variant: 'brand' },
                    { name: 'view', label: 'View', variant: 'outline' }
                ]
            })
        );
    }

    get createLeadLabel() {
        return this.saving ? 'Creating…' : 'Create lead';
    }

    get showLogModal() {
        return this.logOpen && (this.detail?.summary || this.listLogLead);
    }

    get logRecordId() {
        return this.detail?.summary?.id || this.listLogLead?.id;
    }

    get logSubjectName() {
        return this.detail?.summary?.name || this.listLogLead?.name;
    }

    get logSubjectContext() {
        return this.detail?.summary?.primary || this.listLogLead?.primary;
    }

    get logPhone() {
        return this.detail?.summary?.phone || this.listLogLead?.phone;
    }

    get logEmail() {
        return this.detail?.summary?.email || this.listLogLead?.email;
    }

    get scenarioFields() {
        return (this.detail?.scenarioFields || []).filter((field) => field.value);
    }

    get hasScenarioFields() {
        return this.scenarioFields.length > 0;
    }

    get hasOpenTasks() {
        return this.openTasks.length > 0;
    }

    get openTasks() {
        return (this.detail?.openTasks || []).map((task) => ({
            ...task,
            taskClass: task.urgent ? 'task-item task-urgent' : 'task-item'
        }));
    }

    get lastContactDisplay() {
        return this.detail?.summary?.lastContactLabel || 'No communication logged';
    }

    get phoneHref() {
        const phone = this.detail?.summary?.phone?.replace(/[^0-9]/g, '');
        return phone ? `tel:${phone}` : undefined;
    }

    get emailHref() {
        const email = this.detail?.summary?.email;
        return email ? `mailto:${email}` : undefined;
    }

    get hasAriveUrl() {
        return !!this.detail?.ariveUrl;
    }

    get detailTabs() {
        const internal = !isExperienceCloudContext();
        return DETAIL_TABS.filter((tab) => internal || !tab.internalOnly).map((tab) => ({
            ...tab,
            tabClass: tab.id === this.activeTab ? 'detail-tab detail-tab-active' : 'detail-tab',
            tourHook: 'lead-tab-' + tab.id, // O4b: the tour opens tabs by clicking them
            isActive: tab.id === this.activeTab,
            ariaCurrent: tab.id === this.activeTab ? 'page' : null
        }));
    }

    get isOverviewTab() {
        return this.activeTab === 'overview';
    }

    get isDocumentsTab() {
        return this.activeTab === 'documents';
    }

    get isRequestsTab() {
        return this.activeTab === 'requests';
    }

    get isCommsTab() {
        return this.activeTab === 'comms';
    }

    get isCallsTab() {
        return this.activeTab === 'calls';
    }

    get ringSenseInsightKey() {
        return `${this.detailId}-ringsense`;
    }

    get zoomInsightKey() {
        return `${this.detailId}-zoom`;
    }

    // LO Workspace only: the editable contact card. The portal keeps its phone/email list.
    get showContactCard() {
        return !isExperienceCloudContext();
    }

    get showSideContactList() {
        return !this.showContactCard;
    }

    get sideCardTitle() {
        return this.showContactCard ? 'Lead info' : 'Contact';
    }

    // getLeadDetail is cacheable, so patch the summary (log modal phone/email) from the saved card
    // instead of re-fetching, and refresh the list wires. City / State are on both cards.
    handleContactSaved(event) {
        const c = event.detail || {};
        if (c.isBorrower) {
            this.refs.borrowerPills?.refresh(); // the pill shows the name
            return;
        }
        if (this.detail) {
            this.detail = {
                ...this.detail,
                summary: { ...this.detail.summary, phone: c.phone, email: c.email }
            };
        }
        this.refs.detailsCard?.refresh();
        this.refreshLeadLists().catch(() => {});
    }

    get headerMeta() {
        const s = this.detail?.summary || {};
        return [s.source, s.assignedLabel].filter(Boolean).join(' · ');
    }

    // Borrower switcher: the Contact card follows the selected pill (the Lead, or a Borrower__c).
    selectedBorrower;

    get contactRecordId() {
        const sel = this.selectedBorrower;
        return sel && sel.leadId === this.detailId ? sel.recordId : this.detailId;
    }

    handleBorrowerSelect(event) {
        this.selectedBorrower = { leadId: this.detailId, recordId: event.detail.recordId };
    }

    handleBorrowerRemoved() {
        this.selectedBorrower = undefined;
        this.showToast('Borrower removed', 'The co-borrower was removed from this lead.', 'success');
        this.refs.borrowerPills?.refresh();
    }

    handleDetailsSaved() {
        this.refs.contactCard?.refresh();
        this.refreshLeadLists().catch(() => {});
    }

    handleOpenRealtor(event) {
        dispatchPortalNavigate(this, { view: PORTAL_VIEWS.REALTORS, filter: 'all', recordId: event.detail.recordId });
    }

    handleLeadCreated(event) {
        this.addOpen = false;
        this.showToast('Lead created', event.detail.message || 'The lead was added to your workspace.', 'success');
        this.refreshLeadLists().catch(() => {});
        if (event.detail.leadId) {
            dispatchPortalNavigate(this, { view: PORTAL_VIEWS.LEADS, filter: this.effectiveFilter, recordId: event.detail.leadId, refresh: true });
        }
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

    // ---------- Notes (mirrors the Lead page Notes tab: notes typed Note or blank) ----------

    notes = [];
    notesLoading = false;
    notesError;

    get isNotesTab() {
        return this.activeTab === 'notes';
    }

    get hasNotes() {
        return this.notes.length > 0;
    }

    async loadNotes() {
        if (!this.detailId) {
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

    handleOpenConversion() {
        this.conversionOpen = true;
    }

    // LO Workspace only: the letter's controller and Lead access are not in the portal.
    get showPreApprovalLetter() {
        return !isExperienceCloudContext();
    }

    // Imported on demand so the portal bundle never loads the letter (or lightning/actions).
    async handleOpenLetter() {
        // 48.1: the button stays visible; the server's one status rule decides (it refuses again on every step).
        let blocked;
        try {
            blocked = await getLetterBlockedReason({ leadId: this.detailId });
        } catch (error) {
            blocked = reduceApexError(error);
        }
        if (blocked) {
            this.showToast('Pre-Approval Letter locked', blocked, 'warning');
            return;
        }
        this.letterOpen = true;
        if (!this.letterCtor) {
            try {
                const { default: ctor } = await import('c/leadPreApprovalLetter');
                this.letterCtor = ctor;
            } catch (error) {
                this.letterOpen = false;
                this.showToast('Pre-Approval Letter unavailable', reduceApexError(error), 'error');
            }
        }
    }

    // The letter closes itself (Cancel, or after finalize) with the quick-action and flow close events.
    renderLetterListeners() {
        const letter = this.refs?.letter;
        if (letter && letter !== this._letterEl) {
            this._letterEl = letter;
            const close = () => this.handleCloseLetter();
            letter.addEventListener('lightning__actionsclosescreen', close);
            letter.addEventListener('lightning__flownavigationfinish', close);
        }
    }

    handleCloseLetter() {
        this.letterOpen = false;
        this._letterEl = undefined;
        // Generating saves the terms back to the Lead.
        this.loadDetail();
    }

    // Application Summary: imported on demand, like the letter, so the portal bundle never loads it.
    async handleOpenSummary() {
        this.summaryOpen = true;
        if (!this.summaryCtor) {
            try {
                const { default: ctor } = await import('c/loWsApplicationSummary');
                this.summaryCtor = ctor;
            } catch (error) {
                this.summaryOpen = false;
                this.showToast('Application Summary unavailable', reduceApexError(error), 'error');
            }
        }
    }

    handleCloseSummary() {
        this.summaryOpen = false;
    }

    // A Zoom booked from the Overview is an Event on this lead: refresh the "Next appt" line and badges.
    handleZoomScheduled() {
        this.refs.contactCard?.refresh();
        this.refreshLeadLists().catch(() => {});
    }

    handleCloseConversion() {
        this.conversionOpen = false;
    }

    handleLeadConverted(event) {
        this.conversionOpen = false;
        const transactionKey = event.detail?.transactionKey;
        if (transactionKey) {
            // refresh: lists and badges reload (the lead leaves Active Leads); submission: the loan opens on its next step.
            dispatchPortalNavigate(this, {
                view: PORTAL_VIEWS.LOANS,
                filter: 'all',
                recordId: transactionKey,
                tab: 'submission',
                refresh: true
            });
            return;
        }
        this.loadDetail();
    }

    countForFilter(filterId) {
        const source = this.allLeads.length ? this.allLeads : this.leads;
        if (filterId === 'all') {
            return source.length;
        }
        if (filterId === 'uncontacted') {
            return source.filter((lead) => lead.lastContactLabel == null).length;
        }
        return source.filter((lead) => lead.status === filterId).length;
    }

    handleFilterChangeEvent(event) {
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LEADS,
            filter: event.detail.filterId,
            recordId: null
        });
    }

    handleSearchChangeEvent(event) {
        this.setSearch(event.detail.value);
    }

    // Search runs on the server now: wait for a pause in typing before re-querying.
    setSearch(value) {
        window.clearTimeout(this._searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = window.setTimeout(() => {
            this.search = value;
        }, 300);
    }

    // ---- Board / List (LO Workspace only; remembered per browser, default List) ----
    layout = isExperienceCloudContext() ? 'list' : readLayout();

    get showLayoutToggle() {
        return this.isActiveMode;
    }

    get isBoard() {
        return this.layout === 'board' && this.showLayoutToggle;
    }

    get listBtnClass() {
        return this.isBoard ? 'layout-btn' : 'layout-btn layout-btn-on';
    }

    get boardBtnClass() {
        return this.isBoard ? 'layout-btn layout-btn-on' : 'layout-btn';
    }

    get listPressed() {
        return String(!this.isBoard);
    }

    get boardPressed() {
        return String(this.isBoard);
    }

    setLayout(value) {
        this.layout = value;
        try {
            window.localStorage.setItem(LAYOUT_KEY, value);
        } catch (e) {
            // private window / blocked storage: the choice just isn't remembered
        }
    }

    showList() {
        this.setLayout('list');
    }

    showBoard() {
        this.setLayout('board');
    }

    handleBoardSearch(event) {
        this.setSearch(event.target.value);
    }

    // ---- Status: header dropdown (list/detail) and Board drag-and-drop. LO Workspace only; the server checks ownership.
    statusValues = [];
    statusSaving = false;
    _dragId;

    get showStatusPicker() {
        return !isExperienceCloudContext() && this.detail?.summary?.status !== 'converted' && this.statusValues.length > 0;
    }

    get statusOptions() {
        const current = this.detail?.summary?.statusLabel;
        const values = this.statusValues.includes(current) || !current ? this.statusValues : [current, ...this.statusValues];
        return values.map((value) => ({ value, selected: value === current }));
    }

    async loadStatusValues() {
        if (isExperienceCloudContext() || this.statusValues.length) {
            return;
        }
        try {
            this.statusValues = await getLeadStatusOptions();
        } catch (e) {
            this.statusValues = [];
        }
    }

    async handleStatusChange(event) {
        await this.saveStatus(this.detailId, event.target.value);
    }

    async saveStatus(leadId, status) {
        if (!leadId || !status) {
            return;
        }
        this.statusSaving = true;
        try {
            await updateLeadStatus({ leadId, status });
            this.showToast('Status updated', 'Lead moved to ' + status + '.', 'success');
        } catch (error) {
            this.showToast('Status not changed', reduceApexError(error), 'error');
        } finally {
            this.statusSaving = false;
            if (this.detailId) {
                this.loadDetail();
            }
            this.refreshLeadLists().catch(() => {});
        }
    }

    handleDragStart(event) {
        this._dragId = event.currentTarget.dataset.id;
        event.dataTransfer.setData('text/plain', this._dragId);
        event.dataTransfer.effectAllowed = 'move';
    }

    handleDragOver(event) {
        if (COLUMN_STATUS[event.currentTarget.dataset.col]) {
            event.preventDefault();
            event.currentTarget.classList.add('board-col-drop');
        }
    }

    handleDragLeave(event) {
        event.currentTarget.classList.remove('board-col-drop');
    }

    handleDrop(event) {
        event.preventDefault();
        event.currentTarget.classList.remove('board-col-drop');
        const status = COLUMN_STATUS[event.currentTarget.dataset.col];
        const leadId = event.dataTransfer.getData('text/plain') || this._dragId;
        this._dragId = undefined;
        const lead = (this.allLeads || []).find((item) => item.id === leadId);
        if (!status || !lead || lead.status === event.currentTarget.dataset.col) {
            return;
        }
        this.saveStatus(leadId, status);
    }

    handleMoveTo(event) {
        const status = COLUMN_STATUS[event.target.value];
        const leadId = event.target.dataset.id;
        event.target.value = '';
        this.saveStatus(leadId, status);
    }

    handleCardOpen(event) {
        this.openDetail(event.currentTarget.dataset.id);
    }

    // Columns = the My Leads stages (not All). Uses the unfiltered, searched list.
    get boardColumns() {
        const leads = (this.allLeads || []).map(decorateLead);
        return ACTIVE_COLUMNS.map((col) => {
            const cards = leads
                .filter((lead) => lead.status === col.id)
                .map((lead) => ({
                    id: lead.id,
                    name: lead.name,
                    primary: [lead.amount, lead.purpose].filter((v) => v && v !== '—').join(' · '),
                    source: lead.source,
                    statusLabel: lead.statusLabel,
                    statusClass: STATUS_CLASS[lead.status] || 'badge status-nurture',
                    realtorName: lead.realtorName,
                    moveOptions: MOVE_TARGETS.filter((c) => c.id !== lead.status).map((c) => ({ id: c.id, label: c.label })),
                    apptLabel: lead.nextAppointment
                        ? lead.nextAppointment.replace('Next appointment: ', 'Next appt ').split(' — ')[0]
                        : null
                }));
            return {
                id: col.id,
                label: col.label,
                count: cards.length,
                cards,
                empty: cards.length === 0,
                colClass: `board-col board-col-${col.id}`
            };
        });
    }

    handleRowAction(event) {
        const { action, recordId } = event.detail;
        if (action === 'view') {
            this.openDetail(recordId);
            return;
        }
        const lead = this.leads.find((item) => item.id === recordId);
        if (lead) {
            this.listLogLead = lead;
            this.logOpen = true;
        }
    }

    openDetail(leadId) {
        this.activeTab = 'overview';
        dispatchPortalNavigate(this, {
            view: this.isNurturedMode ? PORTAL_VIEWS.NURTURED : PORTAL_VIEWS.LEADS,
            filter: this.effectiveFilter,
            recordId: leadId
        });
    }

    handleBack() {
        this.activeTab = 'overview';
        dispatchPortalNavigate(this, {
            view: this.isNurturedMode ? PORTAL_VIEWS.NURTURED : PORTAL_VIEWS.LEADS,
            filter: this.effectiveFilter,
            recordId: null
        });
    }

    handleAddOpen() {
        this.formError = undefined;
        this.addOpen = true;
    }

    handleAddClose() {
        this.addOpen = false;
        this.duplicates = [];
        this.formError = undefined;
    }

    handleFormChange(event) {
        const field = event.target.dataset.field;
        this.form = { ...this.form, [field]: event.target.value };
        this.formError = undefined;
        if (['name', 'phone', 'email'].includes(field)) {
            this.checkDuplicates();
        }
    }

    async checkDuplicates() {
        if (this.form.name.length < 3 && this.form.phone.length < 7 && this.form.email.length < 5) {
            this.duplicates = [];
            return;
        }
        try {
            this.duplicates = await findLeadDuplicates({
                name: this.form.name,
                phone: this.form.phone,
                email: this.form.email
            });
        } catch (error) {
            this.duplicates = [];
            this.formError = reduceApexError(error);
        }
    }

    handleCreateLeadSubmit(event) {
        event.preventDefault();
        event.stopPropagation();
        this.form = { ...this.form, ...readFormFields(event.currentTarget) };
        this.handleCreateLead();
    }

    async handleCreateLead() {
        if (this.saving) {
            return;
        }
        this.saving = true;
        this.formError = undefined;
        try {
            const amountDigits = (this.form.loanAmount || '').replace(/[^0-9.]/g, '');
            await createLead({
                name: this.form.name,
                phone: this.form.phone,
                email: this.form.email,
                purpose: this.form.purpose,
                loanAmount: amountDigits ? Number(amountDigits) : null,
                loanProgram: this.form.loanProgram,
                leadSource: this.form.leadSource,
                market: this.form.market,
                notes: this.form.notes,
                forceCreate: true
            });
            this.showToast('Lead created', 'The lead was added to your workspace.', 'success');
            this.handleAddClose();
            await this.refreshLeadLists();
        } catch (error) {
            this.formError = reduceApexError(error);
            this.showToast('Unable to create lead', this.formError, 'error');
        } finally {
            this.saving = false;
        }
    }

    handleLogOpen() {
        this.listLogLead = undefined;
        this.logOpen = true;
    }

    handleLogClose() {
        this.logOpen = false;
        this.listLogLead = undefined;
    }

    refreshLeadLists() {
        return Promise.all([
            refreshApex(this.wiredLeadsResult),
            refreshApex(this.wiredAllLeadsResult)
        ]);
    }

    handleLogged(event) {
        this.showToast('Activity logged', event.detail.message, 'success');
        if (this.detailId) {
            this.loadDetail();
        } else {
            this.refreshLeadLists().catch(() => {});
        }
    }

    handleOpenArive() {
        if (this.detail?.ariveUrl) {
            window.open(this.detail.ariveUrl, '_blank', 'noopener');
            return;
        }
        this.showToast(
            'Arive is not linked',
            'This lead has no Arive ID yet, so there is nothing to open. Ask an admin to sync the lead to Arive, then try again.',
            'error'
        );
    }

    ariveLinkOpen = false;
    ariveLinkSaving = false;
    ariveIdInput = '';
    ariveLinkError = '';

    handleOpenAriveLink() {
        this.ariveIdInput = '';
        this.ariveLinkError = '';
        this.ariveLinkOpen = true;
    }

    handleCloseAriveLink() {
        this.ariveLinkOpen = false;
    }

    handleAriveIdInput(event) {
        this.ariveIdInput = event.target.value;
    }

    async handleAriveLinkSubmit(event) {
        event.preventDefault();
        this.ariveLinkSaving = true;
        this.ariveLinkError = '';
        try {
            const ariveId = await linkToArive({ recordId: this.detailId, ariveId: this.ariveIdInput });
            this.ariveLinkOpen = false;
            this.showToast('Linked to ARIVE', 'This lead is now linked to ARIVE loan ' + ariveId + '.', 'success');
            this.loadDetail();
        } catch (error) {
            this.ariveLinkError = reduceApexError(error);
        } finally {
            this.ariveLinkSaving = false;
        }
    }

    async loadDetail() {
        if (!this.detailId) {
            return;
        }
        this.loading = true;
        this.loadStatusValues();
        try {
            const detail = await getLeadDetail({ leadId: this.detailId });
            this.detail = {
                ...detail,
                summary: decorateLead(detail.summary)
            };
        } catch (error) {
            this.showToast('Lead not found', reduceApexError(error), 'error');
            this.handleBack();
        } finally {
            this.loading = false;
        }
    }

    showToast(title, message, variant) {
        showPortalToast(this, title, message, variant);
    }
}