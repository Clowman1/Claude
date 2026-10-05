import { LightningElement, api } from 'lwc';

/** The "Upcoming" events card from the BD command center; also used by the LO Workspace. */
export default class BdUpcomingCard extends LightningElement {
    @api heading = 'Upcoming';
    @api emptyText = 'Nothing scheduled. Invite a partner for coffee.';
    @api canEdit = false;
    @api events = [];   // rows already shaped by bdUtils.eventRow

    get hasEvents() { return (this.events || []).length > 0; }
    openTracker(event) {
        this.dispatchEvent(new CustomEvent('opentracker', { detail: { campaignId: event.currentTarget.dataset.id } }));
    }
    openCalendar() { this.dispatchEvent(new CustomEvent('opencalendar')); }
}