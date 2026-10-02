/**
 * Hourly trigger for the Zoom recording sweep.
 *
 * Schedule with:
 *   System.schedule('Zoom Recording Sweep', '0 5 * * * ?', new ZoomRecordingSweepScheduler());
 *
 * Zoom cloud recordings usually finish processing within an hour of a meeting ending, so
 * hourly means a transcript is normally in Salesforce the same morning.
 */
global without sharing class ZoomRecordingSweepScheduler implements Schedulable {
    global void execute(SchedulableContext context) {
        ZoomRecordingSweepBatch.start();
    }
}