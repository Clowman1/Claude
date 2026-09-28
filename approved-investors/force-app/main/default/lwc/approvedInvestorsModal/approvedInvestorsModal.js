import { wire } from 'lwc';
import LightningModal from 'lightning/modal';
import getInvestors from '@salesforce/apex/ApprovedInvestorsController.getInvestors';

const NON_DEL = 'Non-Delegated Correspondent';
export const OPEN_LIST_VIEW = 'openListView';

const splitPicklist = (value) => (value ? value.split(';') : []);

// First AE line for the collapsed card, e.g. "A.E.: Brandon Dobos · 248-833-4937 bdobos@uwm.com".
// Description is free text, so skip URL lines and join a bare "A.E.:" label with the line after it.
export function aeHeadline(description) {
    const lines = (description || '')
        .split(/\r?\n/)
        .map((line) => line.replace(/\s+/g, ' ').trim())
        .filter((line) => line && !/^https?:\/\//i.test(line));
    if (!lines.length) {
        return '';
    }
    const isBareLabel = /^(A\.?\s?E\.?|AE|Account Executive)\s*:?$/i.test(lines[0]);
    return isBareLabel ? `${lines[0]} ${lines.slice(1, 3).join(' · ')}` : lines.slice(0, 2).join(' · ');
}

// Tile avatar: a short all-caps first word (UWM, NMSI, A&D) or the first letters of two words.
const MONOGRAM_SKIP = new Set(['the', 'a']);
export function monogram(name) {
    const words = (name || '').split(/[\s/,]+/).filter((word) => word && !MONOGRAM_SKIP.has(word.toLowerCase()));
    if (!words.length) {
        return '?';
    }
    if (words[0].length <= 4 && words[0] === words[0].toUpperCase()) {
        return words[0];
    }
    return words
        .slice(0, 2)
        .map((word) => word[0].toUpperCase())
        .join('');
}

const PREVIEW_CHIP_COUNT = 4;

export default class ApprovedInvestorsModal extends LightningModal {
    investors = [];
    error;
    searchTerm = '';
    selectedProducts = [];
    expandedIds = new Set();

    @wire(getInvestors)
    wiredInvestors({ data, error }) {
        if (data) {
            this.investors = data.map((account) => {
                const isNonDel = account.Investor_Channel__c === NON_DEL;
                const brokerProducts = splitPicklist(account.Broker_Channel_Products__c);
                const products = splitPicklist(account.Area_of_Specialty__c).sort((a, b) => a.localeCompare(b));
                const chips = products.map((product) => {
                    const viaBroker = !isNonDel || brokerProducts.includes(product);
                    return {
                        key: product,
                        label: product,
                        className: viaBroker ? 'ai-pill ai-pill-broker' : 'ai-pill ai-pill-nondel',
                        title: viaBroker ? 'Broker · 2.75% Comp (LPC or BPC)' : 'Non-Delegated Correspondent · 0.00 = Par'
                    };
                });
                return {
                    monogram: monogram(account.Name),
                    chips,
                    previewChips: chips.slice(0, PREVIEW_CHIP_COUNT),
                    moreText: chips.length > PREVIEW_CHIP_COUNT ? `+${chips.length - PREVIEW_CHIP_COUNT} more` : '',
                    id: account.Id,
                    name: account.Name,
                    website: account.Website,
                    description: account.Description,
                    summary: account.Investor_Summary__c,
                    aeHeadline: aeHeadline(account.Description),
                    isPrimary: account.Primary_Investor__c === true,
                    isNonDel,
                    products,
                    searchText: [account.Name, account.Investor_Summary__c, account.Description, products.join(' ')]
                        .join(' ')
                        .toLowerCase(),
                    brokerCarveOut: isNonDel && brokerProducts.length ? brokerProducts.join(', ') : ''
                };
            });
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : 'Unable to load investors.';
        }
    }

    get isLoading() {
        return !this.error && !this.investors.length;
    }

    get productOptions() {
        const all = new Set();
        this.investors.forEach((investor) => investor.products.forEach((product) => all.add(product)));
        return [...all]
            .sort((a, b) => a.localeCompare(b))
            .map((product) => ({
                key: product,
                label: product,
                pressed: this.selectedProducts.includes(product) ? 'true' : 'false',
                className: this.selectedProducts.includes(product) ? 'ai-filter ai-filter-on' : 'ai-filter'
            }));
    }

    get filtered() {
        const term = this.searchTerm.trim().toLowerCase();
        return this.investors
            .filter((investor) => !term || investor.searchText.includes(term))
            .filter((investor) => this.selectedProducts.every((product) => investor.products.includes(product)))
            .map((investor) => {
                const expanded = this.expandedIds.has(investor.id);
                return {
                    ...investor,
                    expanded,
                    ariaExpanded: expanded ? 'true' : 'false',
                    toggleLabel: expanded ? 'Hide details' : 'Details and AE contacts',
                    toggleIcon: expanded ? 'utility:chevronup' : 'utility:chevrondown',
                    tileClass: `ai-tile ${investor.isNonDel ? 'ai-tile-nondel' : 'ai-tile-broker'}${expanded ? ' ai-tile-open' : ''}`
                };
            });
    }

    get primaryInvestors() {
        return this.filtered.filter((i) => i.isPrimary);
    }

    get sections() {
        const filtered = this.filtered;
        return [
            {
                key: 'nondel',
                title: 'Non-Delegated Correspondent',
                badge: '0.00 = Par',
                badgeClass: 'ai-pill ai-pill-nondel',
                investors: filtered.filter((i) => !i.isPrimary && i.isNonDel)
            },
            {
                key: 'broker',
                title: 'Broker',
                badge: '2.75% Comp (LPC or BPC)',
                badgeClass: 'ai-pill ai-pill-broker',
                investors: filtered.filter((i) => !i.isPrimary && !i.isNonDel)
            }
        ].filter((section) => section.investors.length);
    }

    get headerSubtitle() {
        const nonDel = this.investors.filter((i) => i.isNonDel).length;
        return `${this.investors.length} partners · ${nonDel} correspondent · ${this.investors.length - nonDel} broker`;
    }

    get noMatches() {
        return !this.isLoading && !this.error && !this.filtered.length;
    }

    get hasFilters() {
        return this.searchTerm || this.selectedProducts.length;
    }

    get resultCountText() {
        return `${this.filtered.length} of ${this.investors.length} investors`;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    toggleProduct(event) {
        const product = event.currentTarget.dataset.product;
        this.selectedProducts = this.selectedProducts.includes(product)
            ? this.selectedProducts.filter((selected) => selected !== product)
            : [...this.selectedProducts, product];
    }

    clearFilters() {
        this.searchTerm = '';
        this.selectedProducts = [];
    }

    toggleExpanded(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.expandedIds);
        if (next.has(id)) {
            next.delete(id);
        } else {
            next.add(id);
        }
        this.expandedIds = next;
    }

    openListView() {
        this.close(OPEN_LIST_VIEW);
    }

    handleClose() {
        this.close();
    }
}
