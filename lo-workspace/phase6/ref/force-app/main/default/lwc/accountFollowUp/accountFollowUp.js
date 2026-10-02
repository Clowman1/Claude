import { LightningElement, track } from 'lwc';
import getAccountsForFollowUp from '@salesforce/apex/AccountFollowUpController.getAccountsForFollowUp';
import assignFollowUpLO from '@salesforce/apex/AccountFollowUpController.assignFollowUpLO';
import getUsers from '@salesforce/apex/AccountFollowUpController.getActiveUsers';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AccountFollowUp extends LightningElement {
    // @track accounts = [];
    // @track selectedAccounts = [];
    // @track userOptions = [];
    // selectedUser;

    // @track sortBy;
    // @track sortDirection = 'asc';
    // @track sortedData = [];


    // // columns = [
    // //     { label: 'Name', fieldName: 'Name', type: 'text' },
    // //     { label: 'Loan Purpose', fieldName: 'Most_Recent_Loan_Purpose__c', type: 'text' },
    // //     { label: 'Current Follow Up LO', fieldName: 'userName', type: 'text' },
    // //     { label: 'Phone', fieldName: 'Phone', type: 'text' },
    // //     { label: '# of Closed Transactions', fieldName: 'of_Closed_Transactions__c', type: 'text' },
    // //     { label: 'Loan Officer', fieldName: 'Loan_Officer__pc', type: 'text' },
    // //     { label: 'Most Recent Closing Date', fieldName: 'Most_Recent_Closing_Date__c', type: 'text' },
    // //     { label: 'Most Recent Loan Amount', fieldName: 'Most_Recent_Loan_Amount__c', type: 'text' },
    // //     { label: 'Most Recent LTV', fieldName: 'Most_Recent_LTV__c', type: 'text' },
    // //     { label: 'Most Recent Rate', fieldName: 'Most_Recent_Rate__c', type: 'text' },
    // //     { label: 'Most Recent Loan Program (1st)', fieldName: 'Most_Recent_Loan_Program_1st__c', type: 'text' },
    // //     { label: 'Most Recent Rate BuyDown', fieldName: 'Most_Recent_Rate_BuyDown__c', type: 'text' },
    // //     { label: 'Most Recent Buydown', fieldName: 'Most_Recent_Buydown__c', type: 'text' },
    // //     { label: 'Most Recent DPA', fieldName: 'Most_Recent_DPA__c', type: 'text' },
    // // ];

    // columns = [
    //     { label: 'Name', fieldName: 'Name', type: 'text', sortable: true },
    //     { label: 'Loan Purpose', fieldName: 'Most_Recent_Loan_Purpose__c', type: 'text', sortable: true },
    //     { label: 'Current Follow Up LO', fieldName: 'userName', type: 'text', sortable: true },
    //     { label: 'Phone', fieldName: 'Phone', type: 'phone', sortable: true },
    //     { label: '# of Closed Transactions', fieldName: 'of_Closed_Transactions__c', type: 'number', sortable: true },
    //     { label: 'Loan Officer', fieldName: 'Loan_Officer__pc', type: 'text', sortable: true },
    //     { label: 'Most Recent Closing Date', fieldName: 'Most_Recent_Closing_Date__c', type: 'date', sortable: true },
    //     { label: 'Most Recent Loan Amount', fieldName: 'Most_Recent_Loan_Amount__c', type: 'currency', sortable: true },
    //     { label: 'Most Recent LTV', fieldName: 'Most_Recent_LTV__c', type: 'number', sortable: true },
    //     { label: 'Most Recent Rate', fieldName: 'Most_Recent_Rate__c', type: 'number', sortable: true },
    //     { label: 'Most Recent Loan Program (1st)', fieldName: 'Most_Recent_Loan_Program_1st__c', type: 'text', sortable: true },
    //     { label: 'Most Recent Rate BuyDown', fieldName: 'Most_Recent_Rate_BuyDown__c', type: 'boolean', sortable: true },
    //     { label: 'Most Recent Buydown', fieldName: 'Most_Recent_Buydown__c', type: 'text', sortable: true },
    //     { label: 'Most Recent DPA', fieldName: 'Most_Recent_DPA__c', type: 'boolean', sortable: true },
    // ];


    // connectedCallback() {
    //     this.loadUsers();
    //     this.loadAccounts();
    // }

    // loadUsers() {
    //     getUsers()
    //         .then(data => {
    //             this.userOptions = data.map(user => ({ label: user.Name, value: user.Id }));
    //         })
    //         .catch(error => {
    //             console.log(error);
    //             //this.showToast('Error', error.body.message, 'error');
    //         });
    // }

    // loadAccounts() {
    //     getAccountsForFollowUp()
    //         .then(result => {
    //             //console.log(JSON.stringify(result));
    //             this.accounts = result.map(r => {
    //                 return {
    //                     ...r,
    //                     userName: r.Follow_Up_LO__r ? (r.Follow_Up_LO__r?.FirstName + ' ' + r.Follow_Up_LO__r?.LastName) : ''
                        
    //                 };
    //             });

    //             this.sortedData = [...this.accounts];
    //         })
    //         .catch(error => {
    //             alert(error);
    //             //this.showToast('Error', error.body.message, 'error');
    //         });
    // }

    // handleSort(event) {
    //     try {
    //     const { fieldName: sortedBy, sortDirection } = event.detail;
    //     this.sortBy = sortedBy;
    //     this.sortDirection = sortDirection;
    //     this.sortedData = this.sortData([...this.accounts], sortedBy, sortDirection);
    //     } catch (e) {
    //         console.log(e.message);
    //     }
    // }

    // sortData(data, field, direction) {
    //     return data.sort((a, b) => {
    //         let val1 = a[field] || '';
    //         let val2 = b[field] || '';
    //         let result = 0;

    //         if (typeof val1 === 'string') {
    //             result = val1.localeCompare(val2);
    //         } else {
    //             result = val1 > val2 ? 1 : val1 < val2 ? -1 : 0;
    //         }

    //         return direction === 'asc' ? result : -result;
    //     });
    // }

    // handleUserChange(event) {
    //     this.selectedUser = event.detail.value;
    // }

    // handleRowSelection(event) {
    //     this.selectedAccounts = event.detail.selectedRows.map(row => row.Id);
    // }

    // assignFollowUp() {
    //     if (!this.selectedUser || this.selectedAccounts.length === 0) {
    //         this.showToast('Error', 'Select a user and at least one account.', 'error');
    //         return;
    //     }

    //     assignFollowUpLO({ accountIds: this.selectedAccounts, userId: this.selectedUser })
    //         .then(() => {
    //             this.showToast('Success', 'Follow-Up LO assigned successfully', 'success');
    //             this.loadAccounts(); // refresh data after assignment
    //         })
    //         .catch(error => {
    //             this.showToast('Error', error.body.message, 'error');
    //         });
    // }

    // showToast(title, message, variant) {
    //     this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    // }
}