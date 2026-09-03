import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLeads from '@salesforce/apex/LOMobileTransactionsController.getLeads';

export default class LoanOfficerLeads extends NavigationMixin(LightningElement) {
    @api cardTitle = 'Active Leads';
    @api mode = 'active';          // 'active' | 'preapproved'
    @api iconName = 'standard:lead';

    rows = [];
    error;

    @wire(getLeads, { mode: '$mode' })
    wired({ data, error }) {
        if (data) {
            this.rows = data.map((l) => ({
                id: l.Id,
                name: l.Name,
                status: l.Status,
                phone: l.Phone,
                lastActivity: l.LastActivityDate
            }));
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Unable to load leads.';
            this.rows = [];
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return !this.error && this.rows.length === 0;
    }

    get emptyMessage() {
        return this.mode === 'preapproved'
            ? 'No pre-approved leads assigned to you.'
            : 'No active leads assigned to you.';
    }

    get count() {
        return this.rows.length;
    }

    handleOpen(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'Lead',
                actionName: 'view'
            }
        });
    }
}
