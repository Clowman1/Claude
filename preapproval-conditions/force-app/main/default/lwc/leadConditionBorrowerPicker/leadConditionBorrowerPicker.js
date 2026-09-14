import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent, FlowNavigationNextEvent } from 'lightning/flowSupport';
import getBorrowerOptions from '@salesforce/apex/LeadDocumentRequestService.getBorrowerOptions';

const ALL = 'ALL';

export default class LeadConditionBorrowerPicker extends LightningElement {
    @api recordId;
    @api availableActions = [];

    // Flow output. 'ALL' means the whole file, 'PRIMARY' the primary borrower alone, otherwise a
    // Borrower__c Id.
    @api assignment = ALL;

    cards = [];
    ineligibleNames = [];
    loadError;

    @wire(getBorrowerOptions, { leadId: '$recordId' })
    wiredOptions({ data, error }) {
        if (data) {
            const assignable = data.filter((option) => option.assignable);
            this.cards = assignable.map((option) => this.toCard(option));
            // A borrower with no email has no portal and cannot be sent anything, so they are
            // named as ineligible rather than silently missing from the list.
            this.ineligibleNames = data.filter((option) => !option.assignable).map((option) => option.label);
            this.loadError = undefined;

            // With no eligible co-borrower, "All borrowers" and "the primary" are the same set, so
            // the question is meaningless: skip straight past rather than charge an extra click.
            if (assignable.length <= 2) {
                this.select(ALL);
            }
        } else if (error) {
            this.loadError = error?.body?.message || 'Could not load the borrowers on this lead.';
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
        return `${names} ${single ? 'has' : 'have'} no email address, so ${
            single ? 'they cannot' : 'they cannot'
        } be assigned conditions yet. Add an email on the Borrowers panel first.`;
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
        this.dispatchEvent(new FlowAttributeChangeEvent('assignment', value));
        // Dispatched unguarded, exactly as leadConditionChoiceCards does. This screen hides the
        // flow footer, and with no footer the runtime reports no availableActions - so gating on
        // availableActions.includes('NEXT') silently swallows every click.
        this.dispatchEvent(new FlowNavigationNextEvent());
    }
}
