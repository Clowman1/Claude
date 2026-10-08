import { LightningElement, api } from 'lwc';
import getPastClientDetail from '@salesforce/apex/ExternalLoPortalController.getPastClientDetail';
// Same Apex as the lead Notes tab; Enhanced_Note__c has an Account__c lookup.
import getNotesRelatedToLoan from '@salesforce/apex/EnhancedNotesController.getNotesRelatedToLoan';
import { PORTAL_VIEWS, dispatchPortalNavigate, reduceApexError, showPortalToast } from 'c/portalUtils';

const TABS = [
    { id: 'overview', label: 'Overview' },
    { id: 'notes', label: 'Notes' },
    { id: 'calls', label: 'Calls/Zooms' }
];

/**
 * LO Workspace past client page (an imported past-client Person Account), opened from Past Clients
 * and from anywhere the shell routes a past-client Account. Mirrors the lead detail page.
 * LO Workspace only: the server refuses portal users.
 */
export default class LoWsPastClientDetail extends LightningElement {
    detail;
    activeTab = 'overview';
    logOpen = false;
    addOpen = false;
    notes = [];
    notesLoading = false;
    notesError;
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) return;
        this._recordId = value;
        this.activeTab = 'overview';
        this.detail = undefined;
        this.load();
    }

    async load() {
        if (!this._recordId) return;
        try {
            this.detail = await getPastClientDetail({ accountId: this._recordId });
        } catch (error) {
            showPortalToast(this, 'Past client not found', reduceApexError(error), 'error');
            this.handleBack();
        }
    }

    get tabs() {
        return TABS.map((tab) => ({
            ...tab,
            tabClass: tab.id === this.activeTab ? 'detail-tab detail-tab-active' : 'detail-tab',
            ariaCurrent: tab.id === this.activeTab ? 'page' : null
        }));
    }

    get isOverviewTab() {
        return this.activeTab === 'overview';
    }
    get isNotesTab() {
        return this.activeTab === 'notes';
    }
    get isCallsTab() {
        return this.activeTab === 'calls';
    }

    get headerPrimary() {
        const d = this.detail || {};
        return [d.recentLoanAmount, d.recentLoanPurpose, d.purchasePrice ? 'Purchase price ' + d.purchasePrice : null]
            .filter(Boolean)
            .join(' · ');
    }

    get headerMeta() {
        const d = this.detail || {};
        return d.recentClosingDate ? 'Most recent closing ' + d.recentClosingDate : 'No closing date on file';
    }

    get hasLoans() {
        return (this.detail?.loans || []).length > 0;
    }

    get hasRecentValues() {
        const d = this.detail || {};
        return !!(d.recentClosingDate || d.recentLoanAmount || d.recentLoanPurpose || d.purchasePrice);
    }

    get recentFields() {
        const d = this.detail || {};
        return [
            { label: 'Most recent closing', value: d.recentClosingDate },
            { label: 'Loan amount', value: d.recentLoanAmount },
            { label: 'Loan purpose', value: d.recentLoanPurpose },
            { label: 'Purchase price', value: d.purchasePrice }
        ].filter((f) => f.value);
    }

    get hasLoggedCalls() {
        return (this.detail?.loggedCalls || []).length > 0;
    }

    get hasNotes() {
        return this.notes.length > 0;
    }

    get ringSenseKey() {
        return `${this._recordId}-ringsense`;
    }
    get zoomKey() {
        return `${this._recordId}-zoom`;
    }

    get leadPrefill() {
        const d = this.detail || {};
        return { firstName: d.firstName, lastName: d.lastName, phone: d.phone, email: d.email };
    }

    handleBack() {
        dispatchPortalNavigate(this, { view: PORTAL_VIEWS.PAST_CLIENTS, recordId: null });
    }

    handleTabSelect(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        if (this.activeTab === 'notes') this.loadNotes();
    }

    handleOpenLoan(event) {
        dispatchPortalNavigate(this, { view: PORTAL_VIEWS.LOANS, filter: 'all', recordId: event.currentTarget.dataset.id });
    }

    // Contact card saved: keep the header / log modal phone and email in step.
    handleContactSaved(event) {
        const c = event.detail || {};
        if (this.detail) this.detail = { ...this.detail, phone: c.phone, email: c.email };
    }

    async loadNotes() {
        this.notesLoading = true;
        this.notesError = undefined;
        try {
            const rows = await getNotesRelatedToLoan({ loanId: this._recordId });
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
        window.open('/apex/AddNewNote?appId=' + this._recordId, 'Enhanced Notes', 'resizable,height=575,width=445');
    }

    handleLogOpen() {
        this.logOpen = true;
    }
    handleLogClose() {
        this.logOpen = false;
    }
    handleLogged(event) {
        showPortalToast(this, 'Activity logged', event.detail.message, 'success');
        this.load();
    }

    handleAddOpen() {
        this.addOpen = true;
    }
    handleAddClose() {
        this.addOpen = false;
    }
    handleLeadCreated(event) {
        this.addOpen = false;
        showPortalToast(this, 'Lead created', event.detail.message || 'The lead was added to your workspace.', 'success');
        if (event.detail.leadId) {
            dispatchPortalNavigate(this, { view: PORTAL_VIEWS.LEADS, filter: 'all', recordId: event.detail.leadId });
        }
    }
}