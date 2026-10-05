import { LightningElement, api } from 'lwc';
import getBorrowerOptions from '@salesforce/apex/LeadDocumentRequestService.getBorrowerOptions';

const ALL = 'ALL';

export default class LeadPortalDocRequestBorrowerPicker extends LightningElement {
    @api leadId;

    assignment = ALL;
    cards = [];
    ineligibleNames = [];
    loadError;

    connectedCallback() {
        this.loadOptions();
    }

    async loadOptions() {
        if (!this.leadId) {
            return;
        }
        try {
            const data = await getBorrowerOptions({ leadId: this.leadId });
            this.applyOptions(data);
        } catch (error) {
            this.loadError = error?.body?.message || 'Could not load the borrowers on this lead.';
        }
    }

    applyOptions(data) {
        const assignable = (data || []).filter((option) => option.assignable);
        this.cards = assignable.map((option) => this.toCard(option));
        this.ineligibleNames = (data || []).filter((option) => !option.assignable).map((option) => option.label);
        this.loadError = undefined;

        if (assignable.length <= 2) {
            this.select(ALL);
        }
    }

    toCard(option) {
        const isAll = option.value === ALL;
        return {
            value: option.value,
            kicker: isAll ? 'Shared' : option.isPrimary ? 'Primary Borrower' : 'Co-Borrower',
            title: option.label,
            copy: isAll
                ? 'Items the whole file shares, like a purchase contract. Everyone sees them, and the first upload satisfies them for all.'
                : `Only ${option.label} sees these in their portal, and only they are asked for them.`,
            cssClass: 'choice-card'
        };
    }

    get hasIneligible() {
        return this.ineligibleNames.length > 0;
    }

    get ineligibleMessage() {
        const names = this.ineligibleNames.join(', ');
        const single = this.ineligibleNames.length === 1;
        return `${names} ${single ? 'has' : 'have'} no email address, so they cannot be assigned conditions yet. Add an email on the Borrowers panel first.`;
    }

    handleSelect(event) {
        this.select(event.currentTarget.dataset.value);
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleSelect(event);
        }
    }

    select(value) {
        this.assignment = value;
        this.dispatchEvent(
            new CustomEvent('portaladvance', {
                detail: { assignment: value },
                bubbles: true,
                composed: true
            })
        );
    }
}