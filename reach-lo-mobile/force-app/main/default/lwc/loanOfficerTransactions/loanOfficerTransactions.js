import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTransactions from '@salesforce/apex/LOMobileTransactionsController.getTransactions';

export default class LoanOfficerTransactions extends NavigationMixin(LightningElement) {
    @api cardTitle = 'Transactions';
    @api mode = 'active';          // 'active' | 'closed'
    @api iconName = 'standard:opportunity';

    rows = [];
    error;

    @wire(getTransactions, { mode: '$mode' })
    wired({ data, error }) {
        if (data) {
            this.rows = data.map((t) => ({
                id: t.Id,
                name: t.Name,
                status: t.Status__c,
                borrower: t.Borrower_Name__r ? t.Borrower_Name__r.Name : '',
                address: t.Property_Address__c,
                amount: t.Loan_Amount__c,
                closingDate: t.Closing_Date__c
            }));
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Unable to load transactions.';
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
        return this.mode === 'closed'
            ? 'No loans closed this year.'
            : 'No active transactions assigned to you.';
    }

    get count() {
        return this.rows.length;
    }

    handleOpen(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'Transaction__c',
                actionName: 'view'
            }
        });
    }
}
