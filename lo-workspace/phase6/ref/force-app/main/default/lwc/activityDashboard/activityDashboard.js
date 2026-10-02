import { LightningElement } from 'lwc';

export default class ActivityDashboard extends LightningElement {
    refreshDashboard() {
        let dailyProgress = this.template.querySelector("c-activity-daily-progress");
        let weeklyProgress = this.template.querySelector("c-activity-weekly-progress");
        let eventCalendar = this.template.querySelector("c-event-calendar");

        dailyProgress.refresh();
        weeklyProgress.refresh();
        eventCalendar.refresh();
    }
}