/**
 * Hourly sweep that pulls recordings for Zoom meetings which have already happened but
 * have no transcript yet. This is the reliable mechanism; the webhook is only an
 * accelerator, so a Zoom config change or a dropped event costs a delay, not data.
 *
 * MUST be executed with a scope of 1. Each meeting requires callouts, and Apex forbids a
 * callout once a transaction has uncommitted DML — so two meetings in one execute() would
 * fail on the second. ZoomRecordingSweepScheduler enforces this; use start() rather than
 * calling Database.executeBatch directly.
 *
 * Meetings with neither a Lead nor a Person Account are never swept: Zoom returns no
 * borrower emails for guest participants, so such a meeting cannot be attributed and
 * nothing is stored for it.
 */
public without sharing class ZoomRecordingSweepBatch
        implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    @TestVisible private static final Integer LOOKBACK_DAYS = 7;
    private static final Integer SCOPE = 1;

    private Integer ingested = 0;
    private Integer stillWaiting = 0;
    private Integer failed = 0;

    /** The only correct way to launch this batch. */
    public static Id start() {
        return Database.executeBatch(new ZoomRecordingSweepBatch(), SCOPE);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime cutoff = System.now().addDays(-LOOKBACK_DAYS);
        Datetime now = System.now();
        return Database.getQueryLocator([
            SELECT Id, Name, Topic__c, Scheduled_Start__c, Zoom_Meeting_Id__c, Lead__c, Account__c
            FROM Zoom_Meeting__c
            WHERE (Lead__c != NULL OR Account__c != NULL)
              AND Status__c = 'Scheduled'
              AND Scheduled_Start__c < :now
              AND Scheduled_Start__c >= :cutoff
            ORDER BY Scheduled_Start__c
        ]);
    }

    public void execute(Database.BatchableContext context, List<Zoom_Meeting__c> batch) {
        for (Zoom_Meeting__c meeting : batch) {
            ZoomIngestionService.Result result = ZoomIngestionService.ingest(meeting.Id);
            if (result.success) {
                ingested++;
            } else if (result.skipped) {
                stillWaiting++;
            } else {
                failed++;
            }
        }
    }

    /**
     * Anything past the lookback window that never produced a transcript is a permanent
     * miss. It is marked Error so it stops being retried and alerted on, and one email
     * goes out — the sweep having already tried for a week is what makes this signal
     * worth reading rather than noise.
     */
    public void finish(Database.BatchableContext context) {
        List<Zoom_Meeting__c> expired = [
            SELECT Id, Name, Topic__c, Scheduled_Start__c, Lead__r.Name, Account__r.Name
            FROM Zoom_Meeting__c
            WHERE (Lead__c != NULL OR Account__c != NULL)
              AND Status__c = 'Scheduled'
              AND Scheduled_Start__c < :System.now().addDays(-LOOKBACK_DAYS)
            LIMIT 50
        ];

        String summary = 'Zoom sweep: ' + ingested + ' ingested, ' + stillWaiting
            + ' awaiting Zoom, ' + failed + ' failed, ' + expired.size() + ' expired.';
        log('Zoom Recording Sweep', summary);

        if (expired.isEmpty()) return;

        List<String> lines = new List<String>();
        for (Zoom_Meeting__c meeting : expired) {
            meeting.Status__c = 'Error';
            lines.add(meeting.Name + ' — ' + meeting.Topic__c
                + ' (' + subjectName(meeting) + ')'
                + ' scheduled ' + meeting.Scheduled_Start__c);
        }
        update expired;
        notifyExpired(lines);
    }

    /** Whichever of Lead or Account the meeting hangs off, for the alert email. */
    private static String subjectName(Zoom_Meeting__c meeting) {
        if (meeting.Lead__r != null) return meeting.Lead__r.Name;
        if (meeting.Account__r != null) return meeting.Account__r.Name;
        return 'no Lead or Account';
    }

    private static void notifyExpired(List<String> lines) {
        Zoom_Webhook_Config__mdt config = Zoom_Webhook_Config__mdt.getInstance('Organization_Default');
        String recipient = config == null ? null : config.Alert_Email__c;
        if (String.isBlank(recipient)) recipient = UserInfo.getUserEmail();
        if (String.isBlank(recipient)) return;

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new List<String>{ recipient });
        message.setSubject('Zoom transcripts missing after ' + LOOKBACK_DAYS + ' days (' + lines.size() + ')');
        message.setPlainTextBody(
            'These Zoom meetings still have no transcript after ' + LOOKBACK_DAYS + ' days of retries. '
            + 'They have been marked Error so they stop being retried.\n\n'
            + String.join(lines, '\n')
            + '\n\nUsual causes: the host never recorded to the cloud, or the recording was deleted in Zoom '
            + 'before the sweep reached it.'
        );
        message.setSaveAsActivity(false);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ message });
        } catch (Exception error) {
            log('Zoom Recording Sweep', 'Could not send expiry alert: ' + error.getMessage());
        }
    }

    private static void log(String source, String data) {
        try {
            insert new Custom_Log__c(Source__c = source, Data__c = data);
        } catch (Exception ignored) {
            System.debug(LoggingLevel.WARN, 'ZoomRecordingSweepBatch: could not write Custom_Log__c.');
        }
    }
}