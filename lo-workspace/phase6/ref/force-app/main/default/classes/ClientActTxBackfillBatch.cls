public without sharing class ClientActTxBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String TARGET_CALL_INSIGHTS = 'CallInsights';
    public static final String TARGET_SMS_HISTORY = 'SmsHistory';

    private String targetObject;
    private Integer scannedCount = 0;
    private Integer updatedCount = 0;

    public ClientActTxBackfillBatch(String targetObject) {
        this.targetObject = targetObject;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (targetObject == TARGET_SMS_HISTORY) {
            return Database.getQueryLocator([
                SELECT Id,
                    smagicinteract__Account__c,
                    smagicinteract__Contact__c,
                    smagicinteract__Lead__c,
                    Transaction__c,
                    smagicinteract__PhoneNumber__c,
                    smagicinteract__Unformatted_Phone_Number__c
                FROM smagicinteract__smsMagic__c
                WHERE Transaction__c = null
                AND (
                    smagicinteract__Lead__c != null
                    OR smagicinteract__Account__c != null
                    OR smagicinteract__Contact__c != null
                    OR smagicinteract__PhoneNumber__c != null
                    OR smagicinteract__Unformatted_Phone_Number__c != null
                )
                AND CreatedDate = LAST_N_DAYS:180
            ]);
        }

        return Database.getQueryLocator([
            SELECT Id, Account__c, Lead__c, Transaction__c, Recipient_Phone_Number__c
            FROM Call_Insight__c
            WHERE Transaction__c = null
            AND (Lead__c != null OR Account__c != null OR Recipient_Phone_Number__c != null)
            AND CreatedDate = LAST_N_DAYS:180
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        scannedCount += scope.size();
        if (targetObject == TARGET_SMS_HISTORY) {
            backfillSmsHistory(scope);
        } else {
            backfillCallInsights(scope);
        }
    }

    public void finish(Database.BatchableContext context) {
        insert new Custom_Log__c(
            Source__c = 'Client Activity Routing Backfill',
            Data__c = 'target=' + targetObject + '; scanned=' + scannedCount + '; updated=' + updatedCount
        );
    }

    private void backfillCallInsights(List<SObject> scope) {
        List<Call_Insight__c> rows = new List<Call_Insight__c>();
        for (SObject row : scope) {
            rows.add((Call_Insight__c) row);
        }

        Map<Id, String> beforeValues = new Map<Id, String>();
        for (Call_Insight__c row : rows) {
            beforeValues.put(row.Id, routeKey(row.Transaction__c, row.Account__c, row.Lead__c));
        }

        ClientActivityTransactionRouter.routeCallInsights(rows);

        List<Call_Insight__c> updates = new List<Call_Insight__c>();
        for (Call_Insight__c row : rows) {
            if (routeKey(row.Transaction__c, row.Account__c, row.Lead__c) != beforeValues.get(row.Id)) {
                updates.add(row);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
            updatedCount += updates.size();
        }
    }

    private void backfillSmsHistory(List<SObject> scope) {
        List<smagicinteract__smsMagic__c> rows = new List<smagicinteract__smsMagic__c>();
        for (SObject row : scope) {
            rows.add((smagicinteract__smsMagic__c) row);
        }

        Map<Id, String> beforeValues = new Map<Id, String>();
        for (smagicinteract__smsMagic__c row : rows) {
            beforeValues.put(row.Id, routeKey(row.Transaction__c, row.smagicinteract__Account__c, row.smagicinteract__Lead__c));
        }

        ClientActivityTransactionRouter.routeSmsHistory(rows);

        List<smagicinteract__smsMagic__c> updates = new List<smagicinteract__smsMagic__c>();
        for (smagicinteract__smsMagic__c row : rows) {
            if (routeKey(row.Transaction__c, row.smagicinteract__Account__c, row.smagicinteract__Lead__c) != beforeValues.get(row.Id)) {
                updates.add(row);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
            updatedCount += updates.size();
        }
    }

    private static String routeKey(Id transactionId, Id accountId, Id leadId) {
        return String.valueOf(transactionId) + '|' + String.valueOf(accountId) + '|' + String.valueOf(leadId);
    }
}