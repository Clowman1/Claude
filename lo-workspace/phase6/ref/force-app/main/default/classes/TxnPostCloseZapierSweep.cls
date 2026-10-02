/**
 * Retries post-closed Zapier webhooks that never landed.
 *
 * The record-triggered flow only fires on the transition into Post-Closed, and
 * TxnPostCloseZapierHook swallows a failed callout, so a file whose send fails
 * once is lost from the feed permanently. This sweep re-picks those up.
 */
public without sharing class TxnPostCloseZapierSweep implements Schedulable {

    // Flow activation date. Files that reached Post-Closed before this never had
    // a webhook and must not be blasted at Zapier now (~1,725 historical records).
    private static final Date BACKFILL_CUTOFF = Date.newInstance(2026, 7, 16);

    // Queueable does one callout per record; Apex allows 100 per transaction.
    private static final Integer BATCH_LIMIT = 50;

    private static final String ALERT_RECIPIENT = 'clowman@reachhomeloans.com';
    private static final String ALERT_SENDER = 'reachus@reachhomeloans.com';

    // Files still unsent a day after post-closing are stuck, not in flight.
    private static final Integer STUCK_AFTER_DAYS = 1;

    // Digest hour (UTC). The sweep runs hourly; the alert should not.
    private static final Integer ALERT_HOUR_UTC = 13;

    public void execute(SchedulableContext context) {
        sweep();
        if (Datetime.now().hour() == ALERT_HOUR_UTC) {
            alertIfBacklogged();
        }
    }

    /**
     * Emails when files are still unsent a day after post-closing. Without this the
     * sweep retries a broken endpoint silently forever, which is how the original
     * six-week outage went unnoticed.
     *
     * @return number of stuck files reported, 0 when nothing was sent
     */
    public static Integer alertIfBacklogged() {
        List<Transaction__c> stuck = [
            SELECT Name, Post_Closed_Date__c
            FROM Transaction__c
            WHERE Status__c = 'Post-Closed'
              AND Biz_Dev__c = 'Biz Dev - Reach'
              AND Loan_Purpose__c = 'Purchase'
              AND Zapier_Post_Closed_Webhook_Sent_At__c = NULL
              AND Post_Closed_Date__c >= :BACKFILL_CUTOFF
              AND Post_Closed_Date__c <= :Date.today().addDays(-STUCK_AFTER_DAYS)
            ORDER BY Post_Closed_Date__c
            LIMIT 200
        ];

        if (stuck.isEmpty()) {
            return 0;
        }

        List<OrgWideEmailAddress> sender = [
            SELECT Id FROM OrgWideEmailAddress WHERE Address = :ALERT_SENDER LIMIT 1
        ];

        String body = 'The post-closed Zapier feed is backing up.\n\n' +
            stuck.size() + ' Reach purchase file(s) reached Post-Closed but have no ' +
            'recorded webhook send. The hourly sweep is retrying them; if this ' +
            'message repeats, the Zapier endpoint is likely rejecting requests ' +
            '(check the Catch Hook URL in the Zap against TxnPostCloseZapierHook).\n\n';
        for (Transaction__c t : stuck) {
            body += '  - ' + t.Name + '  (post-closed ' + t.Post_Closed_Date__c + ')\n';
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ ALERT_RECIPIENT });
        mail.setSubject('Zapier post-closed feed backlog: ' + stuck.size() + ' file(s) unsent');
        mail.setPlainTextBody(body);
        if (!sender.isEmpty()) {
            mail.setOrgWideEmailAddressId(sender[0].Id);
        }

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        return stuck.size();
    }

    public static Integer sweep() {
        List<Transaction__c> pending = [
            SELECT Id
            FROM Transaction__c
            WHERE Status__c = 'Post-Closed'
              AND Biz_Dev__c = 'Biz Dev - Reach'
              AND Loan_Purpose__c = 'Purchase'
              AND Zapier_Post_Closed_Webhook_Sent_At__c = NULL
              AND Post_Closed_Date__c >= :BACKFILL_CUTOFF
            ORDER BY Post_Closed_Date__c
            LIMIT :BATCH_LIMIT
        ];

        if (pending.isEmpty()) {
            return 0;
        }

        List<Id> ids = new List<Id>(new Map<Id, Transaction__c>(pending).keySet());
        System.enqueueJob(new TxnPostCloseZapierHook.TxnPostCloseZapierQueueable(ids));
        return ids.size();
    }
}