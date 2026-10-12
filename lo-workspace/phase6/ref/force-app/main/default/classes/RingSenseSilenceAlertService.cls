/**
 * Emails ops when no Call_Insight__c has been created in 24 hours (RingSense feed silence).
 */
public without sharing class RingSenseSilenceAlertService {
    private static final String LOG_SOURCE = 'RingSense Silence Alert';
    private static final Integer SILENCE_HOURS = 24;
    // ~30% of calls produce an insight, so 10 calls with none is a real outage, not a quiet weekend.
    @TestVisible
    private static Integer minCallsForAlert = 10;

    public class RunResult {
        public Boolean alerted;
        public Datetime latestCreatedDate;
        public String message;
        public RunResult() {
            this.alerted = false;
        }
    }

    public static RunResult run() {
        RunResult result = new RunResult();
        result.latestCreatedDate = CallInsightRepository.selectLatestCreatedDate();
        Datetime cutoff = Datetime.now().addHours(-SILENCE_HOURS);
        Boolean isSilent = result.latestCreatedDate == null || result.latestCreatedDate < cutoff;

        if (!isSilent) {
            result.message = 'Feed healthy. Latest Call Insight at ' + String.valueOf(result.latestCreatedDate);
            insertLog(result.message);
            return result;
        }

        Integer callsSince = countCallsSince(result.latestCreatedDate == null ? cutoff : result.latestCreatedDate);
        if (callsSince < minCallsForAlert) {
            result.message =
                'Quiet period, no alert. Only ' + callsSince + ' RingCentral calls since the latest Call Insight at ' +
                String.valueOf(result.latestCreatedDate);
            insertLog(result.message);
            return result;
        }

        String lastSeen = result.latestCreatedDate == null
            ? 'never'
            : String.valueOf(result.latestCreatedDate);
        result.message =
            'No Call_Insight__c created in the last ' +
            SILENCE_HOURS +
            ' hours, despite ' +
            callsSince +
            ' RingCentral calls since. Last created: ' +
            lastSeen +
            '. Org: ' +
            UserInfo.getOrganizationName() +
            '. Check Custom_Log__c (RingSense Webhook / RingSense Webhook Error) and Home Tools > RingSense Webhook.';

        sendAlert(result.message);
        result.alerted = true;
        insertLog(result.message);
        return result;
    }

    // RingCentral logs texts as Tasks too; only calls can produce an insight.
    private static Integer countCallsSince(Datetime since) {
        return [
            SELECT COUNT()
            FROM Task
            WHERE CreatedDate > :since
                AND rcsfl__from_number__c != NULL
                AND (NOT Subject LIKE '%SMS%')
                AND (NOT Subject LIKE '%texted%')
        ];
    }

    private static void sendAlert(String body) {
        String raw = Label.RingSense_Silence_Alert_Addresses;
        if (String.isBlank(raw)) {
            return;
        }
        List<String> toAddresses = new List<String>();
        for (String part : raw.split(',')) {
            String email = part == null ? null : part.trim();
            if (!String.isBlank(email)) {
                toAddresses.add(email);
            }
        }
        if (toAddresses.isEmpty()) {
            return;
        }
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(toAddresses);
        mail.setSubject('RingSense feed silence — no Call Insights in 24 hours');
        mail.setPlainTextBody(body);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
    }

    private static void insertLog(String data) {
        insert new Custom_Log__c(Source__c = LOG_SOURCE, Data__c = data);
    }
}