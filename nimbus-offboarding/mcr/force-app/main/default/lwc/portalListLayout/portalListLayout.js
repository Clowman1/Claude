import { LightningElement, api } from 'lwc';

const AVATAR_TONES = 5;

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

    // Colour pass: an initials circle per row, its tint picked from the title so it stays stable.
    get decoratedItems() {
        return (this.items || []).map((item) => {
            // Fixed: was /s+/ (split on the letter "s"), which gave wrong initials.
            const words = String(item.title || '').trim().split(/\s+/).filter(Boolean);
            const initials = words.length ? (words[0][0] + (words.length > 1 ? words[words.length - 1][0] : '')).toUpperCase() : '?';
            let hash = 0;
            for (const ch of String(item.title || '')) hash = (hash * 31 + ch.charCodeAt(0)) % 997;
            // Left accent in the row's status colour: taken from its first badge's tone class.
            const tone = String(item.badges?.[0]?.toneClass || '').split(' ').find((c) => c.startsWith('status-') || c.startsWith('badge-')) || 'badge-neutral';
            return {
                ...item,
                initials,
                avatarClass: `record-avatar record-avatar-${hash % AVATAR_TONES}`,
                rowClass: `record-row record-row-${tone}`
            };
        });
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