import { LightningElement, api } from 'lwc';
import search from '@salesforce/apex/LoWsSearchService.search';
import { reduceApexError } from 'c/portalUtils';

const MIN_LENGTH = 2;
const DEBOUNCE_MS = 300;

/**
 * LO Workspace header search (2026-10-21): the LO's own leads, loans, borrowers and tagged partners.
 * Fires portalnavigate { view, recordId } for the shell; never navigates by itself.
 * compact: phone header, starts as an icon button and expands over the header.
 */
export default class LoWsSearch extends LightningElement {
    @api compact = false;

    term = '';
    groups = [];
    loading = false;
    error;
    open = false;
    expanded = false;
    activeIndex = -1;
    timer;
    requestSeq = 0;

    get showInput() {
        return !this.compact || this.expanded;
    }

    get hostClass() {
        return this.compact ? 'search search-compact' : 'search';
    }

    get options() {
        // One flat index across groups for the arrow keys and aria-activedescendant.
        let index = 0;
        return this.groups.map((g) => ({
            ...g,
            items: g.items.map((item) => {
                const i = index++;
                const active = i === this.activeIndex;
                return {
                    ...item,
                    index: i,
                    optionId: 'lows-search-opt-' + i,
                    selected: active ? 'true' : 'false',
                    cls: active ? 'option option-active' : 'option'
                };
            })
        }));
    }

    get flatItems() {
        return this.groups.flatMap((g) => g.items);
    }

    get showPanel() {
        return this.open && this.term.trim().length >= MIN_LENGTH;
    }

    get isEmpty() {
        return !this.loading && !this.error && this.groups.length === 0;
    }

    get ariaExpanded() {
        return this.showPanel ? 'true' : 'false';
    }

    get activeDescendant() {
        return this.activeIndex >= 0 ? 'lows-search-opt-' + this.activeIndex : null;
    }

    disconnectedCallback() {
        clearTimeout(this.timer);
    }

    expand() {
        this.expanded = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => this.refs.input?.focus());
    }

    handleInput(event) {
        this.term = event.target.value || '';
        this.open = true;
        this.activeIndex = -1;
        clearTimeout(this.timer);
        const trimmed = this.term.trim();
        if (trimmed.length < MIN_LENGTH) {
            this.requestSeq++;
            this.groups = [];
            this.loading = false;
            this.error = undefined;
            return;
        }
        this.loading = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(() => this.runSearch(trimmed), DEBOUNCE_MS);
    }

    async runSearch(trimmed) {
        const seq = ++this.requestSeq;
        try {
            const groups = await search({ term: trimmed });
            if (seq === this.requestSeq) {
                this.groups = groups || [];
                this.error = undefined;
            }
        } catch (e) {
            if (seq === this.requestSeq) {
                this.groups = [];
                this.error = reduceApexError(e);
            }
        } finally {
            if (seq === this.requestSeq) {
                this.loading = false;
            }
        }
    }

    handleKeydown(event) {
        const items = this.flatItems;
        if (event.key === 'Escape') {
            event.preventDefault();
            this.close();
        } else if (event.key === 'ArrowDown' && items.length) {
            event.preventDefault();
            this.open = true;
            this.activeIndex = (this.activeIndex + 1) % items.length;
        } else if (event.key === 'ArrowUp' && items.length) {
            event.preventDefault();
            this.activeIndex = this.activeIndex <= 0 ? items.length - 1 : this.activeIndex - 1;
        } else if (event.key === 'Enter') {
            event.preventDefault();
            const item = items[this.activeIndex >= 0 ? this.activeIndex : 0];
            if (item && !this.loading) {
                this.select(item);
            }
        }
    }

    handleFocus() {
        this.open = true;
    }

    // Leaving the box (keyboard or a click elsewhere) closes the list; options keep focus via mousedown.
    handleFocusOut(event) {
        if (!this.template.contains(event.relatedTarget)) {
            this.open = false;
            if (this.compact && !this.term) {
                this.expanded = false;
            }
        }
    }

    keepFocus(event) {
        event.preventDefault();
    }

    handleOptionClick(event) {
        const item = this.flatItems[Number(event.currentTarget.dataset.index)];
        if (item) {
            this.select(item);
        }
    }

    clear() {
        this.term = '';
        this.groups = [];
        this.error = undefined;
        this.activeIndex = -1;
        this.requestSeq++;
        clearTimeout(this.timer);
        this.refs.input?.focus();
    }

    close() {
        this.open = false;
        this.activeIndex = -1;
        if (this.compact && this.expanded) {
            this.expanded = false;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => this.refs.iconBtn?.focus());
        }
    }

    select(item) {
        this.dispatchEvent(new CustomEvent('portalnavigate', { detail: { view: item.view, recordId: item.id } }));
        this.term = '';
        this.groups = [];
        this.close();
        this.refs.input?.blur();
    }
}
