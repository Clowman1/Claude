import { LightningElement, wire } from 'lwc';
import getHomeToolsData from '@salesforce/apex/HomeToolsController.getHomeToolsData';

/**
 * The Command Center drawer, extracted so it can sit on any record or app page.
 *
 * It titles itself from the server rather than a hardcoded user list, so a user gets the same
 * drawer everywhere without this component needing to know who they are.
 */
export default class HomeToolsDrawer extends LightningElement {
    isOpen = false;
    isRunningTodoUser = false;
    isLoanPartnerChecklistUser = false;
    hasTrackers = false;

    @wire(getHomeToolsData)
    wiredHomeTools({ data }) {
        if (data) {
            this.isRunningTodoUser = data.isRunningTodoUser === true;
            this.isLoanPartnerChecklistUser = data.isLoanPartnerChecklistUser === true;
            this.hasTrackers = (data.trackers || []).length > 0;
        }
    }

    toggleDrawer() {
        this.isOpen = !this.isOpen;
    }

    get drawerTitle() {
        if (this.isLoanPartnerChecklistUser) return 'LP Daily Checklist';
        // Only a to-do only drawer is called To Do List. Users who also see production and
        // lead boxes keep Trackers, since the checklist is one section among several.
        return this.isRunningTodoUser && !this.hasTrackers ? 'To Do List' : 'Trackers';
    }

    get drawerAriaLabel() {
        if (this.isLoanPartnerChecklistUser) return 'Loan Partner Daily Checklist';
        return this.isRunningTodoUser && !this.hasTrackers ? 'My To Do List' : 'Home trackers';
    }

    get toggleLabel() {
        const name = this.drawerTitle;
        return this.isOpen ? `Hide ${name}` : name;
    }

    get drawerClass() {
        return this.isOpen ? 'htd-drawer htd-drawer-open' : 'htd-drawer';
    }

    get toggleClass() {
        return this.isOpen ? 'htd-toggle htd-toggle-open' : 'htd-toggle';
    }
}