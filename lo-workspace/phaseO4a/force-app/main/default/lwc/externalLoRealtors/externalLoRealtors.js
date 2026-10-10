import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getPartnersByKind from '@salesforce/apex/ExternalLoPortalController.getPartnersByKind';
import getPartnerDetail from '@salesforce/apex/ExternalLoPortalController.getPartnerDetail';
import searchPartners from '@salesforce/apex/ExternalLoPortalController.searchPartners';
import linkPartner from '@salesforce/apex/ExternalLoPortalController.linkPartner';
import createPartner from '@salesforce/apex/ExternalLoPortalController.createPartner';
import tagPartner from '@salesforce/apex/ExternalLoPortalController.tagPartner';
import untagPartner from '@salesforce/apex/ExternalLoPortalController.untagPartner';
import setPartnerStage from '@salesforce/apex/ExternalLoPortalController.setPartnerStage';
import { PORTAL_VIEWS, dispatchPortalNavigate, isExperienceCloudContext, reduceApexError, readFormFields, showPortalToast, toGenericListRow } from 'c/portalUtils';

// LO Workspace partner tags (Phase 5). Rows carry a stage only when they are my tags.
const STAGES = ['Prospect', 'Contacted', 'Meeting Set', 'Met', 'Active Partner', 'Dormant'];
// Fred's BD industries (Account.BD_Industry__c).
const PARTNER_TYPES = ['Realtor', 'Title Agent', 'Insurance Agent', 'Home Inspector', 'Appraiser', 'CPA', 'Financial Planner', 'Attorney', 'Builder', 'Other'];

const FILTERS = [
    { id: '30', label: 'Last 30 days' },
    { id: '60', label: 'Last 60 days' },
    { id: '90', label: 'Last 90 days' },
    { id: 'due', label: 'Follow-up due' },
    { id: 'all', label: 'All partners' }
];

export default class ExternalLoRealtors extends NavigationMixin(LightningElement) {
    @api embeddedInShell = false;
    // 'realtor' = My Realtors; 'other' = Other Contacts (LO Workspace, 2026-10-08): every non-realtor partner.
    @api contactKind = 'realtor';

    get isOtherContacts() {
        return this.contactKind === 'other';
    }

    get ownView() {
        return this.isOtherContacts ? PORTAL_VIEWS.OTHER_CONTACTS : PORTAL_VIEWS.REALTORS;
    }

    get pageTitle() {
        return this.isOtherContacts ? 'Other Contacts' : 'My Realtors';
    }

    get defaultPartnerType() {
        return this.isOtherContacts ? 'Insurance Agent' : 'Realtor';
    }

    connectedCallback() {
        this.form = { ...this.form, partnerType: this.defaultPartnerType };
    }
    @api recordId;
    _filterKey = 'all';
    _pageDetailId;
    _lastLoadedDetailId;
    _refreshKey;

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(value) {
        this._refreshKey = value;
        if (value && this.wiredPartnersResult) {
            this.refreshPartnerLists().catch(() => {});
        }
    }

    @api
    get filterKey() {
        return this._filterKey;
    }

    set filterKey(value) {
        this._filterKey = value || 'all';
    }

    partners = [];
    allPartners = [];
    detail;
    detailLoading = false;
    searchResults = [];
    filter = 'all';
    errorMessage;
    matchResults = [];
    tagging = false;
    stagePartner;
    stageValue;
    stageSaving = false;
    isInternal = !isExperienceCloudContext();
    leadRealtor;

    handleNewLeadFromDetail() {
        this.leadRealtor = { id: this.detail.summary.id, name: this.detail.summary.name };
    }

    handleLeadFormClose() {
        this.leadRealtor = undefined;
    }

    handleLeadCreated(event) {
        this.leadRealtor = undefined;
        this.showToast('Lead created', event.detail.message || 'The lead was added to your workspace.', 'success');
        if (event.detail.leadId) {
            dispatchPortalNavigate(this, { view: PORTAL_VIEWS.LEADS, filter: 'all', recordId: event.detail.leadId });
        }
    }

    // LO Workspace only: the shared BD In Person Invite (c-lo-ws-in-person-events) opens its modal.
    handleInPersonInvite() {
        const events = this.template.querySelector('c-lo-ws-in-person-events');
        if (events) events.openInvite();
    }
    search = '';
    partnerSearch = '';
    addOpen = false;
    logOpen = false;
    saving = false;
    searching = false;
    linkingId;
    formError;
    searchError;
    loading = true;
    _searchToken = 0;
    _searchTimer;
    listLogPartner;
    wiredPartnersResult;
    wiredAllPartnersResult;

    form = {
        name: '',
        phone: '',
        email: '',
        company: '',
        market: '',
        partnerType: 'Realtor'
    };

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

    @wire(getPartnersByKind, { filterKey: '$effectiveFilter', searchTerm: '$search', kind: '$contactKind' })
    wiredPartners(result) {
        this.wiredPartnersResult = result;
        this.loading = !result.data && !result.error;
        if (result.data) {
            this.partners = result.data.map((partner) => this.decoratePartner(partner));
            this.errorMessage = undefined;
            this.loading = false;
        } else if (result.error) {
            // Used to fail silently as "No partners in this window".
            this.partners = [];
            this.errorMessage = reduceApexError(result.error);
            this.loading = false;
        }
    }

    decoratePartner(partner) {
        const touch = partner.lastTouchLabel || 'No communication logged by you';
        const buyers = partner.sharedBuyers ?? 0;
        const buyersLabel = `${buyers} shared buyer${buyers === 1 ? '' : 's'}`;
        return { ...partner, metaLabel: `${touch} · ${buyersLabel}` };
    }

    @wire(getPartnersByKind, { filterKey: 'all', searchTerm: '$search', kind: '$contactKind' })
    wiredAllPartners(result) {
        this.wiredAllPartnersResult = result;
        if (result.data) {
            this.allPartners = result.data;
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
        return !this.loading && this.partners.length === 0;
    }

    get resultLabel() {
        const total = this.allPartners.length || this.partners.length;
        return `Showing ${this.partners.length} of ${total} partners`;
    }

    get listItems() {
        return this.partners.map((partner) =>
            toGenericListRow({
                id: partner.id,
                title: partner.name,
                badges: [
                    ...(partner.stage ? [{ key: 'stage', label: partner.stage, toneClass: 'badge badge-stage' }] : []),
                    { key: 'type', label: partner.partnerType, toneClass: 'badge badge-neutral' },
                    ...(partner.houseLocked
                        ? [{ key: 'house', label: 'House account', toneClass: 'badge badge-dark' }]
                        : []),
                    ...(partner.followUpDue
                        ? [{ key: 'due', label: 'Follow-up due', toneClass: 'badge badge-warn' }]
                        : [])
                ],
                primary: [partner.company, partner.market].filter(Boolean).join(' · '),
                meta: partner.metaLabel,
                note: partner.houseLocked ? 'Managed by the Reach house team — view only.' : undefined,
                actions: partner.houseLocked
                    ? [{ name: 'view', label: 'View', variant: 'outline' }]
                    : [
                          { name: 'log', label: 'Log touch', variant: 'brand' },
                          ...(partner.stage ? [{ name: 'stage', label: 'Change stage', variant: 'outline' }] : []),
                          // LO Workspace: Add lead with this realtor pre-filled and locked.
                          ...(this.isInternal && !this.isOtherContacts ? [{ name: 'newlead', label: 'New lead', variant: 'outline' }] : []),
                          { name: 'view', label: 'View', variant: 'outline' }
                      ]
            })
        );
    }

    get createPartnerLabel() {
        return this.saving ? 'Creating…' : 'Create partner';
    }

    get decoratedSearchResults() {
        return this.searchResults.map((result) => ({
            ...result,
            linkLabel: this.linkingId === result.id ? 'Linking…' : 'Link',
            linkDisabled: !!this.linkingId || this.saving
        }));
    }

    get canLog() {
        return this.detail?.summary && !this.detail.summary.houseLocked;
    }

    get showLogModal() {
        return this.logOpen && (this.canLog || this.listLogPartner);
    }

    get logRecordId() {
        return this.detail?.summary?.id || this.listLogPartner?.id;
    }

    get logSubjectName() {
        return this.detail?.summary?.name || this.listLogPartner?.name;
    }

    get logSubjectContext() {
        return this.detail?.summary?.company || this.listLogPartner?.company;
    }

    get logPhone() {
        return this.detail?.summary?.phone || this.listLogPartner?.phone;
    }

    get logEmail() {
        return this.detail?.summary?.email || this.listLogPartner?.email;
    }

    get logGoalCredit() {
        const partnerType = this.detail?.summary?.partnerType || this.listLogPartner?.partnerType;
        return partnerType === 'Realtor'
            ? 'your Realtor touches goal'
            : 'your title & insurance partner touches goal';
    }

    countForFilter(filterId) {
        const source = this.allPartners.length ? this.allPartners : this.partners;
        if (filterId === 'all') {
            return source.length;
        }
        if (filterId === 'due') {
            return source.filter((partner) => partner.followUpDue).length;
        }
        const maxDays = Number(filterId);
        return source.filter(
            (partner) => partner.daysSinceMyTouch != null && partner.daysSinceMyTouch <= maxDays
        ).length;
    }

    handleFilterChangeEvent(event) {
        if (this.embeddedInShell) {
            dispatchPortalNavigate(this, {
                view: this.ownView,
                filter: event.detail.filterId,
                recordId: null
            });
            return;
        }
        this.filter = event.detail.filterId;
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
        const partner = this.partners.find((item) => item.id === recordId);
        if (action === 'stage' && partner) {
            this.openStage(partner);
            return;
        }
        if (action === 'newlead' && partner) {
            this.leadRealtor = { id: partner.id, name: partner.name };
            return;
        }
        if (partner && !partner.houseLocked) {
            this.listLogPartner = partner;
            this.logOpen = true;
        }
    }

    openDetail(partnerId) {
        dispatchPortalNavigate(this, {
            view: this.ownView,
            filter: this.effectiveFilter,
            recordId: partnerId
        });
    }

    handlePartnerSearchChange(event) {
        this.partnerSearch = event.target.value;
        // Debounce so we do not fire an Apex search on every keystroke.
        window.clearTimeout(this._searchTimer);
        if (this.partnerSearch.length < 2) {
            this._searchToken++;
            this.searchResults = [];
            this.searching = false;
            return;
        }
        this.searching = true;
        this._searchTimer = window.setTimeout(() => this.runPartnerSearch(), 300);
    }

    async runPartnerSearch() {
        // Sequence guard: only the response for the latest keystroke may land.
        const token = ++this._searchToken;
        this.searching = true;
        try {
            const results = await searchPartners({ searchTerm: this.partnerSearch });
            if (token !== this._searchToken) {
                return;
            }
            this.searchResults = results;
            this.searchError = undefined;
        } catch (error) {
            if (token !== this._searchToken) {
                return;
            }
            this.searchResults = [];
            this.searchError = reduceApexError(error);
        } finally {
            if (token === this._searchToken) {
                this.searching = false;
            }
        }
    }

    handleAddOpen() {
        this.formError = undefined;
        this.searchError = undefined;
        this.addOpen = true;
    }

    handleAddClose() {
        window.clearTimeout(this._searchTimer);
        this._searchToken++;
        this.addOpen = false;
        this.searching = false;
        this.searchResults = [];
        this.matchResults = [];
        this.formError = undefined;
        this.searchError = undefined;
    }

    handleFormChange(event) {
        const field = event.target.dataset.field;
        this.form = { ...this.form, [field]: event.target.value };
        this.formError = undefined;
    }

    async handleLinkPartner(event) {
        const partnerId = event.currentTarget.dataset.id;
        if (this.linkingId) {
            return;
        }
        this.searchError = undefined;
        this.linkingId = partnerId;
        try {
            await linkPartner({ accountId: partnerId });
            this.showToast('Partner linked', 'The partner was added to your list.', 'success');
            this.handleAddClose();
            await this.refreshPartnerLists();
        } catch (error) {
            this.searchError = reduceApexError(error);
            this.showToast('Unable to link partner', this.searchError, 'error');
        } finally {
            this.linkingId = undefined;
        }
    }

    refreshPartnerLists() {
        return Promise.all([
            refreshApex(this.wiredPartnersResult),
            refreshApex(this.wiredAllPartnersResult)
        ]);
    }

    handleCreatePartnerSubmit(event) {
        event.preventDefault();
        event.stopPropagation();
        this.form = { ...this.form, ...readFormFields(event.currentTarget) };
        this.handleCreatePartner();
    }

    async handleCreatePartner() {
        if (this.saving) {
            return;
        }
        this.saving = true;
        this.formError = undefined;
        try {
            const result = await createPartner({
                name: this.form.name,
                phone: this.form.phone,
                email: this.form.email,
                company: this.form.company,
                market: this.form.market,
                partnerType: this.form.partnerType
            });
            if (result?.status === 'match') {
                // Already at Reach as a partner: offer Tag me instead of creating a duplicate.
                this.matchResults = result.matches || [];
                this.formError = result.userMessage;
                return;
            }
            this.showToast('Partner created', 'The partner was added to your list.', 'success');
            this.handleAddClose();
            await this.refreshPartnerLists();
        } catch (error) {
            this.formError = reduceApexError(error);
            this.showToast('Unable to create partner', this.formError, 'error');
        } finally {
            this.saving = false;
        }
    }

    get partnerTypeOptions() {
        return PARTNER_TYPES.filter((value) => !this.isOtherContacts || value !== 'Realtor').map((value) => ({ value, selected: value === this.form.partnerType }));
    }

    get decoratedMatchResults() {
        return this.matchResults.map((match) => ({
            ...match,
            tagLabel: this.tagging ? 'Adding…' : 'Tag me',
            tagDisabled: this.tagging
        }));
    }

    async handleTagMatch(event) {
        if (this.tagging) {
            return;
        }
        this.tagging = true;
        try {
            await tagPartner({
                accountId: event.currentTarget.dataset.id,
                email: this.form.email,
                phone: this.form.phone
            });
            this.showToast('Partner added', 'The partner is now on your list.', 'success');
            this.handleAddClose();
            await this.refreshPartnerLists();
        } catch (error) {
            this.formError = reduceApexError(error);
        } finally {
            this.tagging = false;
        }
    }

    get hasStage() {
        return !!this.detail?.summary?.stage;
    }

    get stageOptions() {
        const current = this.stagePartner ? this.stageValue : this.detail?.summary?.stage;
        return STAGES.map((value) => ({ value, selected: value === current }));
    }

    openStage(partner) {
        this.stagePartner = partner;
        this.stageValue = partner.stage;
    }

    handleStageSelect(event) {
        this.stageValue = event.target.value;
    }

    handleStageClose() {
        this.stagePartner = undefined;
    }

    async handleStageSave() {
        await this.saveStage(this.stagePartner.id, this.stageValue);
        this.stagePartner = undefined;
    }

    async handleDetailStageChange(event) {
        await this.saveStage(this.detail.summary.id, event.target.value);
        this.loadDetail();
    }

    async saveStage(accountId, stage) {
        this.stageSaving = true;
        try {
            await setPartnerStage({ accountId, stage });
            this.showToast('Stage updated', stage, 'success');
            await this.refreshPartnerLists();
        } catch (error) {
            this.showToast('Unable to update stage', reduceApexError(error), 'error');
        } finally {
            this.stageSaving = false;
        }
    }

    async handleUntag() {
        try {
            await untagPartner({ accountId: this.detail.summary.id });
            this.showToast('Removed', 'The partner is no longer on your list.', 'success');
            await this.refreshPartnerLists();
            this.handleBack();
        } catch (error) {
            this.showToast('Unable to remove partner', reduceApexError(error), 'error');
        }
    }

    get listSubtitle() {
        if (this.isOtherContacts) {
            return 'Insurance, title, attorneys, inspectors and other partners you are tagged on. Realtors live in My Realtors.';
        }
        return this.isInternal
            ? 'Realtor and business partners you are tagged on, with your own stage for each.'
            : 'Realtor, title, and insurance partners you’ve logged communication with.';
    }

    get emptyMessage() {
        return this.isInternal
            ? 'Use Add partner to tag yourself on a Reach partner or add a new one, or import a list from Import Data.'
            : 'Log a call, text, or visit against a partner and they’ll show up here. Use Add partner to search the shared database.';
    }

    handleLogOpen() {
        this.listLogPartner = undefined;
        this.logOpen = true;
    }

    handleLogClose() {
        this.logOpen = false;
        this.listLogPartner = undefined;
    }

    handleLogged(event) {
        this.showToast('Activity logged', event.detail.message, 'success');
        if (this.detailId) {
            this.loadDetail();
        } else {
            this.refreshPartnerLists().catch(() => {});
        }
    }

    // LO Workspace contact card saved: patch the summary (getPartnerDetail is cacheable) and refresh the lists.
    handleContactSaved(event) {
        const c = event.detail || {};
        if (this.detail) {
            this.detail = {
                ...this.detail,
                summary: { ...this.detail.summary, phone: c.phone || c.mobile, email: c.email }
            };
        }
        this.refreshPartnerLists().catch(() => {});
    }

    handleBack() {
        dispatchPortalNavigate(this, {
            view: this.ownView,
            filter: this.effectiveFilter,
            recordId: null
        });
    }

    async loadDetail() {
        if (!this.detailId) {
            return;
        }
        this.detailLoading = true;
        try {
            this.detail = await getPartnerDetail({ accountId: this.detailId });
        } catch (error) {
            this.showToast('Partner not found', reduceApexError(error), 'error');
            this.handleBack();
        } finally {
            this.detailLoading = false;
        }
    }

    get daysSinceTouchLabel() {
        const days = this.detail?.summary?.daysSinceMyTouch;
        if (days == null) {
            return 'No communication logged by you yet';
        }
        return `${days} day${days === 1 ? '' : 's'} since your last touch`;
    }

    get sharedBuyersLabel() {
        const buyers = this.detail?.summary?.sharedBuyers ?? 0;
        return `${buyers} shared buyer${buyers === 1 ? '' : 's'} in your pipeline`;
    }

    get relatedLeads() {
        return (this.detail?.relatedLeads || []).map((lead) => ({
            ...lead,
            statusClass: `badge status-${lead.status}` || 'badge status-nurture'
        }));
    }

    get hasRelatedLeads() {
        return this.relatedLeads.length > 0;
    }

    get detailPhoneHref() {
        const phone = this.detail?.summary?.phone?.replace(/[^0-9]/g, '');
        return phone ? `tel:${phone}` : undefined;
    }

    get detailEmailHref() {
        const email = this.detail?.summary?.email;
        return email ? `mailto:${email}` : undefined;
    }

    handleOpenLead(event) {
        const leadId = event.currentTarget.dataset.id;
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LEADS,
            filter: 'all',
            recordId: leadId
        });
    }

    showToast(title, message, variant) {
        showPortalToast(this, title, message, variant);
    }
}