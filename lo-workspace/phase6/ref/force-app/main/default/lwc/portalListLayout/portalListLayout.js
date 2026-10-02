import { LightningElement, api } from 'lwc';

export default class PortalListLayout extends LightningElement {
    @api title;
    @api subtitle;
    @api searchValue = '';
    @api searchPlaceholder = 'Search';
    @api filters = [];
    @api loading = false;
    @api isEmpty = false;
    @api emptyTitle = 'No records match this view';
    @api emptyMessage = 'Try a different filter or clear your search.';
    @api resultLabel = '';
    @api rowType = 'generic';
    @api items = [];
    @api showBanner = false;

    get normalizedFilters() {
        return (this.filters || []).map((filter) => ({
            ...filter,
            chipClass: filter.isActive ? 'filter-chip filter-chip-active' : 'filter-chip',
            countClass: filter.isActive ? 'filter-count filter-count-active' : 'filter-count',
            showCount: typeof filter.count === 'number'
        }));
    }

    get showFooterLabel() {
        return !this.loading && !this.isEmpty && this.resultLabel;
    }

    get isGenericRows() {
        return true;
    }

    get skeletonRows() {
        return ['0', '1', '2', '3', '4'];
    }

    handleSearchChange(event) {
        this.dispatchEvent(
            new CustomEvent('searchchange', {
                detail: { value: event.target.value }
            })
        );
    }

    handleFilterClick(event) {
        this.dispatchEvent(
            new CustomEvent('filterchange', {
                detail: { filterId: event.currentTarget.dataset.filter }
            })
        );
    }

    handleRowAction(event) {
        const action = event.currentTarget.dataset.action;
        const recordId = event.currentTarget.dataset.id;
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { action, recordId }
            })
        );
    }
}