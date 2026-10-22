import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRecordSet from '@salesforce/apex/ExternalLoPortalController.getRecordSet';
import completeUpNextItem from '@salesforce/apex/PerfectDayHomeController.completeUpNextItem';
import deferUpNextItem from '@salesforce/apex/PerfectDayHomeController.deferUpNextItem';
import { PORTAL_VIEWS, dispatchPortalNavigate, showPortalToast } from 'c/portalUtils';

// Task-backed sets are excluded: a Task cannot be a WhatId/WhoId target for a new
// logged activity — communication is logged from the related lead or partner instead.
const LOGGABLE_SETS = new Set([
    'new-leads',
    'realtor-follow-ups',
    'pre-approvals',
    'milestone-loans'
]);

const LIST_ROUTES = {
    'new-leads': { view: PORTAL_VIEWS.LEADS, filter: 'new', label: 'Open My Leads', objectApiName: 'Lead' },
    'realtor-follow-ups': { view: PORTAL_VIEWS.REALTORS, filter: 'due', label: 'Open My Realtors', objectApiName: 'Account' },
    'pre-approvals': { view: PORTAL_VIEWS.PRE_APPROVALS, filter: 'weekly-touch', label: 'Open My Pre-Approvals', objectApiName: 'Lead' },
    'milestone-loans': { view: PORTAL_VIEWS.LOANS, filter: 'update', label: 'Open My Loans', objectApiName: 'Transaction__c' }
};

const PORTAL_OBJECT_ROUTES = {
    Lead: PORTAL_VIEWS.LEADS,
    Account: PORTAL_VIEWS.REALTORS,
    'Transaction__c': PORTAL_VIEWS.LOANS
};

export default class PortalRecordDrawer extends NavigationMixin(LightningElement) {
    @api embeddedInShell = false;
    @api recordSetKey;

    payload;
    loading = false;
    errorMessage;
    logRecordId;
    logObjectApiName;
    logSubjectName;
    logSubjectContext;
    isLogOpen = false;
    busyTaskId;

    connectedCallback() {
        if (this.recordSetKey) {
            this.loadRecords();
        }
    }

    renderedCallback() {
        if (this.recordSetKey && this.recordSetKey !== this._lastLoadedKey) {
            this._lastLoadedKey = this.recordSetKey;
            this.loadRecords();
        }
        if (!this.recordSetKey) {
            this._lastLoadedKey = null;
        }
    }

    _lastLoadedKey;

    @api
    async loadRecords() {
        if (!this.recordSetKey) {
            return;
        }
        this.loading = true;
        this.errorMessage = undefined;
        try {
            this.payload = await getRecordSet({ recordSetKey: this.recordSetKey });
        } catch (error) {
            this.payload = undefined;
            this.errorMessage = error?.body?.message || error?.message || 'Unexpected error';
        } finally {
            this.loading = false;
        }
    }

    get isOpen() {
        return !!this.recordSetKey;
    }

    get title() {
        return this.payload?.title || 'Records';
    }

    get subtitle() {
        return this.payload?.subtitle || '';
    }

    get records() {
        return (this.payload?.records || []).map((record) => ({
            ...record,
            tagClass: this.tagClass(record),
            showLog: this.canLogSet && !this.isCompleteTag(record.tag),
            isOpenTask: record.objectApiName === 'Task' && !this.isCompleteTag(record.tag),
            busy: this.busyTaskId === record.id
        }));
    }

    get canLogSet() {
        return LOGGABLE_SETS.has(this.recordSetKey);
    }

    get hasRecords() {
        return this.records.length > 0;
    }

    get showEmpty() {
        return !this.loading && !this.errorMessage && !this.hasRecords;
    }

    get listRoute() {
        return LIST_ROUTES[this.recordSetKey];
    }

    get showListButton() {
        return !!this.listRoute;
    }

    get listButtonLabel() {
        return this.listRoute?.label || 'Open full list';
    }

    tagClass(record) {
        const tag = (record.tag || '').toLowerCase();
        if (tag === 'completed' || tag === 'complete' || tag === 'logged') {
            return 'record-tag record-tag-complete';
        }
        if (record.urgency === 'urgent') {
            return 'record-tag record-tag-urgent';
        }
        if (record.urgency === 'attention') {
            return 'record-tag record-tag-attention';
        }
        return 'record-tag record-tag-normal';
    }

    isCompleteTag(tag) {
        const value = (tag || '').toLowerCase();
        return value === 'completed' || value === 'complete' || value === 'logged';
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdropClick() {
        this.handleClose();
    }

    handleRetry() {
        this.loadRecords();
    }

    handleOpenList() {
        const route = this.listRoute;
        if (!route) {
            return;
        }
        if (this.embeddedInShell) {
            dispatchPortalNavigate(this, {
                view: route.view,
                filter: route.filter,
                recordId: null
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: route.objectApiName,
                    actionName: 'list'
                }
            });
        }
        this.handleClose();
    }

    handleOpenRecord(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const objectApiName = event.currentTarget.dataset.objectApiName;
        const portalView = PORTAL_OBJECT_ROUTES[objectApiName];
        if (this.embeddedInShell && portalView && recordId) {
            dispatchPortalNavigate(this, {
                view: portalView,
                filter: 'all',
                recordId
            });
            this.handleClose();
            return;
        }
        // Outside the shell there is no portal workspace to route into — fall
        // back to the standard record page instead of dead-ending in a toast.
        if (recordId && objectApiName) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId,
                    objectApiName,
                    actionName: 'view'
                }
            });
            this.handleClose();
            return;
        }
        showPortalToast(this, 'Record', 'Open this record from the full list view.', 'info');
    }

    // Open follow-up Tasks close or move right here; there is no Task page to send the LO to.
    async handleTaskAction(event) {
        const { recordId, action } = event.currentTarget.dataset;
        if (!recordId || this.busyTaskId) {
            return;
        }
        this.busyTaskId = recordId;
        try {
            if (action === 'complete') {
                await completeUpNextItem({ recordId, objectApiName: 'Task' });
                showPortalToast(this, 'Completed', 'Follow-up marked complete.', 'success');
            } else {
                await deferUpNextItem({ recordId, objectApiName: 'Task', deferOption: 'tomorrow' });
                showPortalToast(this, 'Moved to tomorrow', 'The follow-up is now due tomorrow.', 'success');
            }
            await this.loadRecords();
            this.dispatchEvent(new CustomEvent('recordschanged'));
        } catch (error) {
            showPortalToast(this, 'Unable to update the task', error?.body?.message || error?.message || 'Unexpected error', 'error');
        } finally {
            this.busyTaskId = undefined;
        }
    }

    handleLogClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const objectApiName = event.currentTarget.dataset.objectApiName;
        const name = event.currentTarget.dataset.name;
        const primary = event.currentTarget.dataset.primary;
        this.logRecordId = recordId;
        this.logObjectApiName = objectApiName || 'Lead';
        this.logSubjectName = name;
        this.logSubjectContext = primary;
        this.isLogOpen = true;
    }

    closeLog() {
        this.isLogOpen = false;
    }

    handleLogged() {
        this.isLogOpen = false;
        this.loadRecords();
        this.dispatchEvent(new CustomEvent('recordschanged'));
    }
}