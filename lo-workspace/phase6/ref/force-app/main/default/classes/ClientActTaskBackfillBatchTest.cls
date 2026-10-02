@IsTest
private class ClientActTaskBackfillBatchTest {
    @IsTest
    static void backfillRoutesSmsTasksToActiveTransaction() {
        String sharedPhone = '321-555-6060';
        Account borrower = new Account(LastName = 'Task Backfill Borrower', PersonMobilePhone = sharedPhone);
        insert borrower;

        Id businessAccountRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Business_Account'
            LIMIT 1
        ].Id;
        Account lender = new Account(
            Name = 'Task Backfill Lender',
            RecordTypeId = businessAccountRecordTypeId,
            Type = 'Investor'
        );
        insert lender;

        Transaction__c transactionRecord = new Transaction__c(
            Name = 'Task Backfill Loan',
            Borrower_Name__c = borrower.Id,
            Status__c = 'Processing',
            Lender_lookup__c = lender.Id
        );
        insert transactionRecord;

        Contact borrowerContact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :borrower.Id
            LIMIT 1
        ];

        Task smsTask = new Task(
            Subject = 'Manual follow up',
            WhoId = borrowerContact.Id,
            Status = 'Completed',
            Priority = 'Normal'
        );
        insert smsTask;
        smsTask.InteractionType__c = 'Sms';

        Test.startTest();
        new ClientActTaskBackfillBatch().execute(null, new List<SObject>{ smsTask });
        Test.stopTest();

        Task routedTask = [
            SELECT WhoId, WhatId
            FROM Task
            WHERE Id = :smsTask.Id
        ];
        System.assertEquals(transactionRecord.Id, routedTask.WhatId, 'Backfill should attach RingCentral SMS tasks to the active transaction.');
    }

    @IsTest
    static void backfillRoutesOpportunityTasksToActiveTransaction() {
        Account borrower = new Account(LastName = 'Task Opp Backfill Borrower');
        insert borrower;

        Id businessAccountRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Business_Account'
            LIMIT 1
        ].Id;
        Account lender = new Account(
            Name = 'Task Opp Backfill Lender',
            RecordTypeId = businessAccountRecordTypeId,
            Type = 'Investor'
        );
        insert lender;

        Transaction__c transactionRecord = new Transaction__c(
            Name = 'Task Opp Backfill Loan',
            Borrower_Name__c = borrower.Id,
            Status__c = 'Processing',
            Lender_lookup__c = lender.Id
        );
        insert transactionRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Task Opp Backfill Opportunity',
            AccountId = borrower.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunityRecord;

        Contact borrowerContact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :borrower.Id
            LIMIT 1
        ];

        Task smsTask = new Task(
            Subject = 'Manual follow up',
            WhoId = borrowerContact.Id,
            WhatId = opportunityRecord.Id,
            Status = 'Completed',
            Priority = 'Normal'
        );
        insert smsTask;
        smsTask.InteractionType__c = 'Sms';

        Test.startTest();
        new ClientActTaskBackfillBatch().execute(null, new List<SObject>{ smsTask });
        Test.stopTest();

        Task routedTask = [
            SELECT WhatId
            FROM Task
            WHERE Id = :smsTask.Id
        ];
        System.assertEquals(transactionRecord.Id, routedTask.WhatId, 'Backfill should move Opportunity-linked client SMS to the active transaction.');
    }
}