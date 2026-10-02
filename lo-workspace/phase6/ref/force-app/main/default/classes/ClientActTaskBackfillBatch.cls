public without sharing class ClientActTaskBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Integer scannedCount = 0;
    private Integer updatedCount = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id,
                WhoId,
                WhatId,
                Subject,
                TaskSubtype,
                InteractionType__c
            FROM Task
            WHERE WhoId != null
            AND CreatedDate = LAST_N_DAYS:180
            AND (
                InteractionType__c = 'Sms'
                OR TaskSubtype = 'Call'
                OR Subject LIKE '% texted %'
                OR Subject LIKE '% called %'
                OR Subject LIKE 'Call on %'
                OR Subject LIKE '%RingCentral%'
                OR Subject LIKE '%ACE call details%'
            )
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        scannedCount += scope.size();
        List<Task> tasks = new List<Task>();
        for (SObject row : scope) {
            tasks.add((Task) row);
        }

        Map<Id, String> beforeValues = new Map<Id, String>();
        for (Task taskRecord : tasks) {
            beforeValues.put(taskRecord.Id, routeKey(taskRecord.WhoId, taskRecord.WhatId));
        }

        ClientActivityTransactionRouter.routeTasks(tasks);

        List<Task> updates = new List<Task>();
        for (Task taskRecord : tasks) {
            if (routeKey(taskRecord.WhoId, taskRecord.WhatId) != beforeValues.get(taskRecord.Id)) {
                updates.add(taskRecord);
            }
        }

        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);
            for (Database.SaveResult result : results) {
                if (result.isSuccess()) {
                    updatedCount++;
                }
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        insert new Custom_Log__c(
            Source__c = 'Client Activity Task Backfill',
            Data__c = 'scanned=' + scannedCount + '; updated=' + updatedCount
        );
    }

    private static String routeKey(Id whoId, Id whatId) {
        return String.valueOf(whoId) + '|' + String.valueOf(whatId);
    }
}