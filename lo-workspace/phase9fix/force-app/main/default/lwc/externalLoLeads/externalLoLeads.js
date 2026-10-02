import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getLeads from '@salesforce/apex/ExternalLoPortalController.getLeads';
import getLeadDetail from '@salesforce/apex/ExternalLoPortalController.getLeadDetail';
import findLeadDuplicates from '@salesforce/apex/ExternalLoPortalController.findLeadDuplicates';
import createLead from '@salesforce/apex/ExternalLoPortalController.createLead';
// Same Apex as the Lead page's Notes tab (Aura EnhancedNotes, which an LWC cannot host).
import getNotesRelatedToLoan from '@salesforce/apex/EnhancedNotesController.getNotesRelatedToLoan';
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
    'pre-approval': 'badge status-working',
    nurture: 'badge status-nurture',
    converted: 'badge status-working',
    closed: 'badge badge-neutral'
};

const DETAIL_TABS = [
    { id: 'overview', label: 'Overview' },
    { id: 'documents', label: 'Documents' },
    { id: 'requests', label: 'Document requests' },
    { id: 'calls', label: 'Calls' },
    // LO Workspace only: EnhancedNotesController and /apex/AddNewNote are not in the portal.
    { id: 'notes', label: 'Notes', internalOnly: true }
];

function decorateLead(lead) {
    return {
        ...lead,
        statusClass: STATUS_CLASS[lead.status] || 'badge status-nurture',
        neverContacted: lead.lastContactLabel == null
    };
}

export default class ExternalLoLeads extends NavigationMixin(LightningElement) {
    @api embeddedInShell = false;
    @api recordId;
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

    get effectiveFilter() {
        return this.embeddedInShell ? this._filterKey : this.filter;
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

    @wire(getLeads, { filterKey: '$effectiveFilter', searchTerm: '$search' })
    wiredLeads(result) {
        this.wiredLeadsResult = result;
        this.loading = !result.data && !result.error;
        if (result.data) {
            this.leads = result.data.map(decorateLead);
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
            this.loadDetail();
        } else {
            this.detail = undefined;
        }
    }

    @wire(getLeads, { filterKey: 'all', searchTerm: '$search' })
    wiredAllLeads(result) {
        this.wiredAllLeadsResult = result;
        if (result.data) {
            this.allLeads = result.data;
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
        return !this.loading && this.leads.length === 0;
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
                        : [])
                ],
                primary: lead.primary,
                meta: [lead.idLabel, lead.source, lead.assignedLabel, lead.lastContactLabel]
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

    get isCallsTab() {
        return this.activeTab === 'calls';
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
                    created: note.CreatedDate
                }));
        } catch (error) {
            this.notes = [];
            this.notesError = reduceApexError(error);
        } finally {
            this.notesLoading = false;
        }
    }

    // The same note form the Lead page's New button opens.
    handleNewNote() {
        window.open('/apex/AddNewNote?appId=' + this.detailId, 'Enhanced Notes', 'resizable,height=575,width=445');
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
        // Finalizing moves the Lead to Pre-Approval and saves the terms.
        this.loadDetail();
    }

    handleCloseConversion() {
        this.conversionOpen = false;
    }

    handleLeadConverted(event) {
        this.conversionOpen = false;
        const transactionKey = event.detail?.transactionKey;
        if (transactionKey) {
            dispatchPortalNavigate(this, {
                view: PORTAL_VIEWS.LOANS,
                filter: 'all',
                recordId: transactionKey
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
        this.search = event.detail.value;
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
            view: PORTAL_VIEWS.LEADS,
            filter: this.effectiveFilter,
            recordId: leadId
        });
    }

    handleBack() {
        this.activeTab = 'overview';
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LEADS,
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

    async loadDetail() {
        if (!this.detailId) {
            return;
        }
        this.loading = true;
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