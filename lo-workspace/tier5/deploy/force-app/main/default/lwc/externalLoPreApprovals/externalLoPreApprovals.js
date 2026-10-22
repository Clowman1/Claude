import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getPreApprovals from '@salesforce/apex/ExternalLoPortalController.getPreApprovals';
import updateLeadStatus from '@salesforce/apex/ExternalLoPortalController.updateLeadStatus';
import getLetterBlockedReason from '@salesforce/apex/LeadPreApprovalLetterController.getLetterBlockedReason';
import {
    PORTAL_VIEWS,
    dispatchPortalNavigate,
    isExperienceCloudContext,
    reduceApexError,
    showPortalToast,
    toGenericListRow
} from 'c/portalUtils';

// Weekly touch (2026-10-08): a call, text, meeting or email in the last 7 days. The server sorts
// touch-due rows first, longest without a touch at the top.
const FILTERS = [
    { id: 'all', label: 'All' },
    { id: 'weekly-touch', label: 'Weekly touch due' },
    { id: 'ready-to-review', label: 'On track' },
    { id: 'expired', label: 'Expired' }
];

// Same status the lead header / board sets (LoWsContactService.updateLeadStatus).
const NURTURE_STATUS = 'Nurture - Preapproval';

const STATUS_LABELS = {
    'ready-to-review': 'On track',
    'touch-due': 'Weekly touch due'
};

const STATUS_CLASS = {
    'ready-to-review': 'badge status-ok',
    'touch-due': 'badge badge-warn'
};

export default class ExternalLoPreApprovals extends NavigationMixin(LightningElement) {
    @api embeddedInShell = false;
    _filterKey = 'all';
    _refreshKey;
    wiredRowsResult;
    wiredAllRowsResult;

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(value) {
        this._refreshKey = value;
        if (value) {
            if (this.wiredRowsResult) {
                refreshApex(this.wiredRowsResult);
            }
            if (this.wiredAllRowsResult) {
                refreshApex(this.wiredAllRowsResult);
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

    rows = [];
    allRows = [];
    filter = 'all';
    search = '';
    loading = true;
    letterOpen = false;
    letterCtor;
    letterLeadId;

    @wire(CurrentPageReference)
    parsePageReference(pageRef) {
        if (this.embeddedInShell) {
            return;
        }
        if (pageRef?.state?.c__filter) {
            this.filter = pageRef.state.c__filter;
        }
    }

    get effectiveFilter() {
        return this.embeddedInShell ? this._filterKey : this.filter;
    }

    @wire(getPreApprovals, { filterKey: '$effectiveFilter', searchTerm: '$search' })
    wiredRows(result) {
        this.wiredRowsResult = result;
        this.loading = !result.data && !result.error;
        if (result.data) {
            this.rows = result.data.map((row) => this.decorateRow(row));
            this.loading = false;
        }
    }

    @wire(getPreApprovals, { filterKey: 'all', searchTerm: '$search' })
    wiredAllRows(result) {
        this.wiredAllRowsResult = result;
        if (result.data) {
            this.allRows = result.data;
        }
    }

    decorateRow(row) {
        return {
            ...row,
            statusLabel: STATUS_LABELS[row.statusKey] || row.statusKey,
            statusClass: STATUS_CLASS[row.statusKey] || 'badge status-nurture',
            weeklyTouchDue: !row.weeklyTouchDone,
            ageLabel: row.expired ? 'Expired' : row.daysSinceIssued == null ? null : `Issued ${row.daysSinceIssued} days ago`
        };
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
        return !this.loading && this.rows.length === 0;
    }

    get resultLabel() {
        const total = this.allRows.length || this.rows.length;
        return `Showing ${this.rows.length} of ${total} pre-approvals`;
    }

    get listItems() {
        return this.rows.map((row) =>
            toGenericListRow({
                id: row.id,
                title: row.borrower,
                badges: [
                    { key: row.statusKey, label: row.statusLabel, toneClass: row.statusClass },
                    ...(row.ageLabel
                        ? [{ key: 'age', label: row.ageLabel, toneClass: row.expired ? 'badge badge-danger' : 'badge badge-neutral' }]
                        : [])
                ],
                primary: [row.amount, row.program].filter(Boolean).join(' · '),
                meta: [row.realtorLabel, row.lastTouchLabel] // no raw Lead Id
                    .filter(Boolean)
                    .join(' · '),
                actions: [
                    ...(row.expired && this.isLoWorkspace
                        ? [
                              { name: 'reissue', label: 'Re-issue letter', variant: 'brand' },
                              { name: 'nurture', label: 'Move to Nurture', variant: 'outline' }
                          ]
                        : []),
                    { name: 'view', label: 'View', variant: 'outline' }
                ]
            })
        );
    }

    countForFilter(filterId) {
        const source = this.allRows.length ? this.allRows : this.rows;
        if (filterId === 'all') {
            return source.length;
        }
        if (filterId === 'weekly-touch') {
            return source.filter((row) => !row.weeklyTouchDone).length;
        }
        if (filterId === 'expired') {
            return source.filter((row) => row.expired).length;
        }
        return source.filter((row) => row.statusKey === filterId).length;
    }

    handleFilterChangeEvent(event) {
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.PRE_APPROVALS,
            filter: event.detail.filterId,
            recordId: null
        });
    }

    handleSearchChangeEvent(event) {
        this.search = event.detail.value;
    }

    // Re-issue / Move to Nurture are LO Workspace only (the letter and status Apex are not in the portal).
    get isLoWorkspace() {
        return !isExperienceCloudContext();
    }

    handleRowAction(event) {
        if (event.detail.action === 'reissue') {
            this.openLetter(event.detail.recordId);
            return;
        }
        if (event.detail.action === 'nurture') {
            this.moveToNurture(event.detail.recordId);
            return;
        }
        if (event.detail.action !== 'view') {
            return;
        }
        // Filter 'pre-approval' tells the lead page it was opened from here: its Back returns to My Pre-Approvals.
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LEADS,
            filter: 'pre-approval',
            recordId: event.detail.recordId
        });
    }

    async moveToNurture(leadId) {
        try {
            await updateLeadStatus({ leadId, status: NURTURE_STATUS });
            showPortalToast(this, 'Moved to Nurture', 'Lead moved to ' + NURTURE_STATUS + '.', 'success');
            this.refreshRows();
        } catch (error) {
            showPortalToast(this, 'Status not changed', reduceApexError(error), 'error');
        }
    }

    // Same letter (and the same on-demand import) as the lead page's Pre-Approval Letter button.
    async openLetter(leadId) {
        let blocked;
        try {
            blocked = await getLetterBlockedReason({ leadId });
        } catch (error) {
            blocked = reduceApexError(error);
        }
        if (blocked) {
            showPortalToast(this, 'Pre-Approval Letter locked', blocked, 'warning');
            return;
        }
        this.letterLeadId = leadId;
        this.letterOpen = true;
        if (!this.letterCtor) {
            try {
                const { default: ctor } = await import('c/leadPreApprovalLetter');
                this.letterCtor = ctor;
            } catch (error) {
                this.letterOpen = false;
                showPortalToast(this, 'Pre-Approval Letter unavailable', reduceApexError(error), 'error');
            }
        }
    }

    renderedCallback() {
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
        // Finalizing stamps a new Pre_Approval_Date__c, so the age chip resets.
        this.refreshRows();
    }

    refreshRows() {
        if (this.wiredRowsResult) {
            refreshApex(this.wiredRowsResult);
        }
        if (this.wiredAllRowsResult) {
            refreshApex(this.wiredAllRowsResult);
        }
    }
}