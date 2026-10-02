import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getPreApprovals from '@salesforce/apex/ExternalLoPortalController.getPreApprovals';
import { PORTAL_VIEWS, dispatchPortalNavigate, toGenericListRow } from 'c/portalUtils';

const FILTERS = [
    { id: 'all', label: 'All' },
    { id: 'ready-to-review', label: 'On track' },
    { id: 'docs-outstanding', label: 'No contact 6+ days' },
    { id: 'expiring', label: 'Credit expired' },
    { id: 'weekly-touch', label: 'Weekly touch due' }
];

const STATUS_LABELS = {
    'ready-to-review': 'On track',
    'docs-outstanding': 'No contact 6+ days',
    expiring: 'Credit expired'
};

const STATUS_CLASS = {
    'ready-to-review': 'badge status-ok',
    'docs-outstanding': 'badge status-working',
    expiring: 'badge status-warn'
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
            weeklyTouchDue: !row.weeklyTouchDone
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
                    ...(row.weeklyTouchDue
                        ? [{ key: 'touch', label: 'Weekly touch due', toneClass: 'badge badge-warn' }]
                        : [])
                ],
                primary: [row.amount, row.program].filter(Boolean).join(' · '),
                meta: [row.idLabel, row.realtorLabel, row.expiresLabel, row.lastTouchLabel]
                    .filter(Boolean)
                    .join(' · '),
                actions: [{ name: 'view', label: 'View', variant: 'outline' }]
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

    handleRowAction(event) {
        if (event.detail.action !== 'view') {
            return;
        }
        dispatchPortalNavigate(this, {
            view: PORTAL_VIEWS.LEADS,
            filter: 'all',
            recordId: event.detail.recordId
        });
    }
}