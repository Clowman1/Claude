import { LightningElement, wire, track } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import LEAD_OBJECT from '@salesforce/schema/Lead';
import LEAD_SOURCE_FIELD from '@salesforce/schema/Lead.LeadSource';

import getThroughputByOwnersV2 from '@salesforce/apex/LeadThroughputController.getThroughputByOwnersV2';
import getActiveLoanOfficers from '@salesforce/apex/LeadThroughputController.getActiveLoanOfficers';
import getTileDrilldown from '@salesforce/apex/LeadThroughputController.getTileDrilldown';

const NOW = new Date();
const LOAN_PURPOSE_SESSION_KEY = 'leadThroughputDashboard.loanPurpose';
const LOAN_PURPOSE_ALL = 'ALL';
const LOAN_PURPOSE_PURCHASE = 'PURCHASE';
const LOAN_PURPOSE_REFINANCE = 'REFINANCE';
const LOAN_PURPOSE_BOTH_PURCHASE_REFINANCE = 'BOTH_PURCHASE_REFINANCE';
const LOAN_PURPOSE_VALUES = new Set([
    LOAN_PURPOSE_ALL,
    LOAN_PURPOSE_PURCHASE,
    LOAN_PURPOSE_REFINANCE,
    LOAN_PURPOSE_BOTH_PURCHASE_REFINANCE
]);

export default class LeadThroughputDashboard extends LightningElement {
    leadSource = '';
    loanPurpose = LOAN_PURPOSE_ALL;

    @track leadSourceOptions = [{ label: 'All', value: '' }];
    isLeadSourceLoading = true;

    // ---- Loan Officers (multi-select) ----
    isLoanOfficersLoading = true;
    isOwnerMenuOpen = false;
    ownerOptions = []; // { label, value, selected }
    ownerSearchTerm = '';
    _ownerRefreshDebounce;
    _boundWindowPointerDown;

    isLoading = false;
    errorMessage = null;

    ownerTiles = [];
    hasDoneInitialRefresh = false;

    // ---- Drill-down modal ----
    isDrilldownOpen = false;
    drilldownOwnerId = null;
    drilldownOwnerName = '';
    drilldownTileKey = null; // enum name expected by Apex
    drilldownTileLabel = '';
    drilldownRows = [];
    drilldownTotalCount = 0;
    drilldownPageSize = '25'; // lightning-combobox expects string values
    drilldownPageNumber = 1;
    isDrilldownLoading = false;
    drilldownErrorMessage = null;

    // ---- Timeframe (mutually exclusive) ----
    timeframeType = 'QUARTER_YEAR'; // QUARTER_YEAR | YTD | LAST_YEAR | TWO_YEARS_AGO
    quarterOptions = []; // { label, value, selected }
    isQuarterMenuOpen = false;
    quarterSearchTerm = '';
    _boundQuarterWindowPointerDown;

    get timeframeTypeOptions() {
        return [
            { label: 'Quarter + Year', value: 'QUARTER_YEAR' },
            { label: 'Year-to-Date (YTD)', value: 'YTD' },
            { label: 'Last Year', value: 'LAST_YEAR' },
            { label: 'Two Years Ago', value: 'TWO_YEARS_AGO' }
        ];
    }

    get loanPurposeOptions() {
        return [
            { label: 'All', value: LOAN_PURPOSE_ALL },
            { label: 'Purchase', value: LOAN_PURPOSE_PURCHASE },
            { label: 'Refinance', value: LOAN_PURPOSE_REFINANCE },
            { label: 'Both Purchase and Refinance', value: LOAN_PURPOSE_BOTH_PURCHASE_REFINANCE }
        ];
    }

    get isQuarterYearMode() {
        return this.timeframeType === 'QUARTER_YEAR';
    }

    get selectedQuarterYearKeys() {
        return (this.quarterOptions || []).filter((o) => o.selected).map((o) => o.value);
    }

    get quarterSelectionLabel() {
        const total = (this.quarterOptions || []).length;
        const selected = this.selectedQuarterYearKeys.length;
        if (total === 0) {
            return 'Loading...';
        }
        if (selected === 0) {
            return 'Select quarter(s)';
        }
        if (selected === total) {
            return `All (${total})`;
        }
        return `${selected} selected`;
    }

    get filteredQuarterOptions() {
        const term = (this.quarterSearchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.quarterOptions || [];
        }
        return (this.quarterOptions || []).filter((o) => (o.label || '').toLowerCase().includes(term));
    }

    // ---- LeadSource picklist ----
    objectInfo;

    get selectedOwnerIds() {
        return (this.ownerOptions || []).filter((o) => o.selected).map((o) => o.value);
    }

    get hasTiles() {
        return (this.ownerTiles || []).length > 0;
    }

    get ownerSelectionLabel() {
        const total = (this.ownerOptions || []).length;
        const selected = this.selectedOwnerIds.length;
        if (total === 0) {
            return 'Loading...';
        }
        if (selected === 0) {
            return 'None selected';
        }
        if (selected === total) {
            return `All (${total})`;
        }
        return `${selected} selected`;
    }

    get filteredOwnerOptions() {
        const term = (this.ownerSearchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.ownerOptions || [];
        }
        return (this.ownerOptions || []).filter((o) => (o.label || '').toLowerCase().includes(term));
    }

    get showSelectOwnersHint() {
        return !this.isLoading && !this.isLoanOfficersLoading && this.selectedOwnerIds.length === 0;
    }

    get showSelectQuartersHint() {
        return (
            !this.isLoading &&
            !this.isLoanOfficersLoading &&
            this.isQuarterYearMode &&
            this.selectedQuarterYearKeys.length === 0
        );
    }

    get showPostClosedColumn() {
        return this.drilldownTileKey === 'NEW_TO_POST_CLOSED' || this.drilldownTileKey === 'PRE_APPROVAL_TO_POST_CLOSED';
    }

    get isPostClosedDrilldownTile() {
        return this.showPostClosedColumn;
    }

    get drilldownHasRows() {
        return (this.drilldownRows || []).length > 0;
    }

    get drilldownTotalPages() {
        const total = this.drilldownTotalCount || 0;
        const size = Number(this.drilldownPageSize || 25);
        return size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    }

    get canDrilldownPrev() {
        return (this.drilldownPageNumber || 1) > 1 && !this.isDrilldownLoading;
    }

    get canDrilldownNext() {
        return (this.drilldownPageNumber || 1) < this.drilldownTotalPages && !this.isDrilldownLoading;
    }

    get drilldownPageSizeOptions() {
        return [
            { label: '25', value: '25' },
            { label: '50', value: '50' }
        ];
    }

    get disableDrilldownPrev() {
        return !this.canDrilldownPrev;
    }

    get disableDrilldownNext() {
        return !this.canDrilldownNext;
    }

    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.objectInfo = data;
        } else if (error) {
            // Non-fatal; fallback is still usable with the default "All" option.
            this.isLeadSourceLoading = false;
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.defaultRecordTypeId', fieldApiName: LEAD_SOURCE_FIELD })
    wiredLeadSourcePicklist({ data, error }) {
        if (data) {
            const values = (data.values || []).map((v) => ({ label: v.label, value: v.value }));
            this.leadSourceOptions = [{ label: 'All', value: '' }, ...values];
        }
        // If error, keep default All-only option.
        this.isLeadSourceLoading = false;

        // Once picklist is ready (or failed), do initial load (exactly once).
        this.initIfReady();
    }

    connectedCallback() {
        this.restoreLoanPurposeFromSession();
        this.initQuarterOptions();
        this.loadLoanOfficers();
    }

    disconnectedCallback() {
        if (this._boundWindowPointerDown) {
            window.removeEventListener('pointerdown', this._boundWindowPointerDown, true);
        }
        if (this._boundQuarterWindowPointerDown) {
            window.removeEventListener('pointerdown', this._boundQuarterWindowPointerDown, true);
        }
    }

    // ---- UI handlers ----
    handleTimeframeTypeChange(event) {
        this.timeframeType = event.detail.value;
        if (this.isQuarterYearMode && this.selectedQuarterYearKeys.length === 0) {
            this.selectDefaultQuarter();
        }
        this.refresh();
    }

    toggleQuarterMenu(event) {
        if (event) {
            event.stopPropagation();
        }
        this.isQuarterMenuOpen = !this.isQuarterMenuOpen;
    }

    closeQuarterMenu() {
        this.isQuarterMenuOpen = false;
    }

    handleQuarterMenuClick(event) {
        if (event) {
            event.stopPropagation();
        }
    }

    handleQuarterSearchChange(event) {
        if (event) {
            event.stopPropagation();
        }
        this.quarterSearchTerm = event.target.value;
    }

    handleQuarterToggle(event) {
        const key = event.target?.dataset?.id;
        const checked = !!event.target?.checked;
        if (!key) {
            return;
        }
        this.quarterOptions = (this.quarterOptions || []).map((o) => (o.value === key ? { ...o, selected: checked } : o));
        this.debouncedRefresh();
    }

    selectAllQuarters() {
        this.quarterOptions = (this.quarterOptions || []).map((o) => ({ ...o, selected: true }));
        this.debouncedRefresh();
    }

    clearAllQuarters() {
        this.quarterOptions = (this.quarterOptions || []).map((o) => ({ ...o, selected: false }));
        this.quarterSearchTerm = '';
        this.refresh();
    }

    // ---- Drill-down handlers ----
    async handleTileClick(event) {
        const ownerId = event?.currentTarget?.dataset?.ownerId;
        const ownerName = event?.currentTarget?.dataset?.ownerName || '';
        const tileKey = event?.currentTarget?.dataset?.tileKey;
        if (!ownerId || !tileKey) {
            return;
        }
        this.drilldownOwnerId = ownerId;
        this.drilldownOwnerName = ownerName;
        this.drilldownTileKey = tileKey;
        this.drilldownTileLabel = this.getTileLabel(tileKey);
        this.drilldownPageNumber = 1;
        this.isDrilldownOpen = true;
        await this.loadDrilldownPage();
    }

    closeDrilldown() {
        this.isDrilldownOpen = false;
        this.drilldownRows = [];
        this.drilldownTotalCount = 0;
        this.drilldownErrorMessage = null;
    }

    async handleDrilldownPrev() {
        if (!this.canDrilldownPrev) {
            return;
        }
        this.drilldownPageNumber = Math.max(1, (this.drilldownPageNumber || 1) - 1);
        await this.loadDrilldownPage();
    }

    async handleDrilldownNext() {
        if (!this.canDrilldownNext) {
            return;
        }
        this.drilldownPageNumber = (this.drilldownPageNumber || 1) + 1;
        await this.loadDrilldownPage();
    }

    async handleDrilldownPageSizeChange(event) {
        const nextSize = String(event.detail.value);
        this.drilldownPageSize = nextSize === '50' ? '50' : '25';
        this.drilldownPageNumber = 1;
        await this.loadDrilldownPage();
    }

    async loadDrilldownPage() {
        this.isDrilldownLoading = true;
        this.drilldownErrorMessage = null;

        try {
            const quarterYearKeys = this.isQuarterYearMode ? this.selectedQuarterYearKeys : [];
            const resp = await getTileDrilldown({
                timeframeType: this.timeframeType,
                quarterYearKeys,
                ownerId: this.drilldownOwnerId,
                leadSource: this.leadSource,
                loanPurpose: this.loanPurpose,
                tileKey: this.drilldownTileKey,
                pageSize: Number(this.drilldownPageSize),
                pageNumber: this.drilldownPageNumber
            });
            this.drilldownRows = (resp?.rows || []).map((r) => ({
                ...r,
                recordUrl: this.buildDrilldownRecordUrl(r)
            }));
            this.drilldownTotalCount = resp?.totalCount || 0;
        } catch (e) {
            this.drilldownRows = [];
            this.drilldownTotalCount = 0;
            this.drilldownErrorMessage = this.normalizeError(e);
        } finally {
            this.isDrilldownLoading = false;
        }
    }

    getTileLabel(tileKey) {
        switch (tileKey) {
            case 'NEW_TO_PRE_APPROVAL':
                return 'New → Pre-Approval';
            case 'NEW_TO_POST_CLOSED':
                return 'New → Post-Closed';
            case 'PRE_APPROVAL_TO_POST_CLOSED':
                return 'Pre-Approval → Post-Closed';
            default:
                return 'Details';
        }
    }

    toggleOwnerMenu(event) {
        if (event) {
            event.stopPropagation();
        }
        this.isOwnerMenuOpen = !this.isOwnerMenuOpen;
    }

    closeOwnerMenu() {
        this.isOwnerMenuOpen = false;
    }

    handleOwnerSearchChange(event) {
        if (event) {
            event.stopPropagation();
        }
        this.ownerSearchTerm = event.target.value;
    }

    handleOwnerMenuClick(event) {
        // Prevent inside clicks from bubbling to document click handler.
        if (event) {
            event.stopPropagation();
        }
    }

    selectAllOwners() {
        this.ownerOptions = (this.ownerOptions || []).map((o) => ({ ...o, selected: true }));
        this.debouncedRefresh();
    }

    clearAllOwners() {
        this.ownerOptions = (this.ownerOptions || []).map((o) => ({ ...o, selected: false }));
        this.ownerSearchTerm = '';
        this.debouncedRefresh();
    }

    handleOwnerToggle(event) {
        const ownerId = event.target?.dataset?.id;
        const checked = !!event.target?.checked;
        if (!ownerId) {
            return;
        }
        this.ownerOptions = (this.ownerOptions || []).map((o) =>
            o.value === ownerId ? { ...o, selected: checked } : o
        );
        this.debouncedRefresh();
    }

    debouncedRefresh() {
        window.clearTimeout(this._ownerRefreshDebounce);
        this._ownerRefreshDebounce = window.setTimeout(() => this.refresh(), 250);
    }

    handleLeadSourceChange(event) {
        this.leadSource = event.detail.value;
        this.refresh();
    }

    handleLoanPurposeChange(event) {
        this.loanPurpose = this.normalizeLoanPurpose(event.detail.value);
        this.persistLoanPurposeToSession();
        this.refresh();
    }

    // ---- Data fetching ----
    async refresh() {
        this.isLoading = true;
        this.errorMessage = null;

        try {
            const ownerIds = this.selectedOwnerIds;
            if (!ownerIds || ownerIds.length === 0) {
                this.ownerTiles = [];
                return;
            }

            const quarterYearKeys = this.isQuarterYearMode ? this.selectedQuarterYearKeys : [];
            if (this.isQuarterYearMode && (!quarterYearKeys || quarterYearKeys.length === 0)) {
                this.ownerTiles = [];
                return;
            }

            const result = await getThroughputByOwnersV2({
                timeframeType: this.timeframeType,
                quarterYearKeys,
                ownerIds,
                leadSource: this.leadSource,
                loanPurpose: this.loanPurpose
            });
            this.ownerTiles = this.buildTileViewModels(result || []);
        } catch (e) {
            this.ownerTiles = [];
            this.errorMessage = this.normalizeError(e);
        } finally {
            this.isLoading = false;
        }
    }

    initIfReady() {
        if (this.hasDoneInitialRefresh) {
            return;
        }
        if (this.isLoanOfficersLoading) {
            return;
        }
        this.hasDoneInitialRefresh = true;
        this.refresh();
    }

    async loadLoanOfficers() {
        this.isLoanOfficersLoading = true;
        try {
            const options = await getActiveLoanOfficers({ limitSize: 2000 });
            const normalized = (options || []).map((o) => ({
                label: o.label,
                value: o.value,
                avatarUrl: o.avatarUrl,
                selected: true
            }));
            this.ownerOptions = normalized;
            this.ownerSearchTerm = '';
        } catch (e) {
            this.ownerOptions = [];
            this.errorMessage = this.normalizeError(e);
        } finally {
            this.isLoanOfficersLoading = false;
            this.initIfReady();
        }
    }

    normalizeError(e) {
        if (e && e.body && e.body.message) {
            return e.body.message;
        }
        if (e && e.message) {
            return e.message;
        }
        return 'Unable to load throughput metrics.';
    }

    buildDrilldownRecordUrl(row) {
        if (this.isPostClosedDrilldownTile && row?.transactionId) {
            return `/lightning/r/Transaction__c/${row.transactionId}/view`;
        }
        return `/lightning/r/Lead/${row?.recordId}/view`;
    }

    normalizeLoanPurpose(value) {
        return LOAN_PURPOSE_VALUES.has(value) ? value : LOAN_PURPOSE_ALL;
    }

    restoreLoanPurposeFromSession() {
        try {
            const stored = window?.sessionStorage?.getItem(LOAN_PURPOSE_SESSION_KEY);
            this.loanPurpose = this.normalizeLoanPurpose(stored);
        } catch (e) {
            this.loanPurpose = LOAN_PURPOSE_ALL;
        }
    }

    persistLoanPurposeToSession() {
        try {
            if (window?.sessionStorage) {
                window.sessionStorage.setItem(LOAN_PURPOSE_SESSION_KEY, this.loanPurpose);
            }
        } catch (e) {
            // Ignore storage write failures and continue with in-memory state.
        }
    }

    pad2(value) {
        return String(value).padStart(2, '0');
    }

    initQuarterOptions() {
        const now = NOW;
        const currentYear = now.getFullYear();
        const currentMonth = now.getMonth() + 1; // 1-12
        const currentQuarter = Math.floor((currentMonth - 1) / 3) + 1; // 1-4
        const currentKey = `${currentYear}-Q${currentQuarter}`;

        const options = [];
        for (let y = currentYear; y >= currentYear - 5; y -= 1) {
            for (let q = 4; q >= 1; q -= 1) {
                const value = `${y}-Q${q}`;
                options.push({
                    label: `Q${q} ${y}`,
                    value,
                    selected: value === currentKey
                });
            }
        }
        this.quarterOptions = options;
    }

    selectDefaultQuarter() {
        // Select the current quarter if present; otherwise select the first option.
        const now = NOW;
        const currentYear = now.getFullYear();
        const currentMonth = now.getMonth() + 1;
        const currentQuarter = Math.floor((currentMonth - 1) / 3) + 1;
        const currentKey = `${currentYear}-Q${currentQuarter}`;
        let found = false;
        this.quarterOptions = (this.quarterOptions || []).map((o) => {
            const selected = o.value === currentKey;
            if (selected) {
                found = true;
            }
            return { ...o, selected };
        });
        if (!found && (this.quarterOptions || []).length > 0) {
            this.quarterOptions = this.quarterOptions.map((o, idx) => ({ ...o, selected: idx === 0 }));
        }
    }

    // ---- Display helpers ----
    formatPct(metric) {
        const pct = metric && metric.percent != null ? metric.percent : 0;
        return Number(pct).toFixed(1);
    }

    formatRatio(metric) {
        const num = metric && metric.numerator != null ? metric.numerator : 0;
        const den = metric && metric.denominator != null ? metric.denominator : 0;
        return `${num} / ${den}`;
    }

    buildTileViewModels(rows) {
        return (rows || []).map((r) => {
            const newToPreApprovalPct = this.formatPct(r.newToPreApproval);
            const newToPreApprovalRatio = this.formatRatio(r.newToPreApproval);
            const newToPostClosedPct = this.formatPct(r.newToPostClosed);
            const newToPostClosedRatio = this.formatRatio(r.newToPostClosed);
            const preApprovalToPostClosedPct = this.formatPct(r.preApprovalToPostClosed);
            const preApprovalToPostClosedRatio = this.formatRatio(r.preApprovalToPostClosed);

            return {
                ...r,
                newToPreApprovalPct,
                newToPreApprovalRatio,
                newToPostClosedPct,
                newToPostClosedRatio,
                preApprovalToPostClosedPct,
                preApprovalToPostClosedRatio
            };
        });
    }
}