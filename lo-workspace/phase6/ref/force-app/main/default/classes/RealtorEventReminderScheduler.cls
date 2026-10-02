global class RealtorEventReminderScheduler implements Schedulable {
    global void execute(SchedulableContext context) {
        RealtorEventWorkspaceController.startReminderBatch();
    }
}