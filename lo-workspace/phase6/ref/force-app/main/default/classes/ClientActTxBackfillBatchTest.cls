@IsTest
private class ClientActTxBackfillBatchTest {
    @IsTest
    static void callInsightBatchRoutesOrphanRows() {
        String sharedPhone = '321-555-7001';
        Account borrower = new Account(LastName = 'Batch Insight Borrower', PersonMobilePhone = sharedPhone);
        insert borrower;
        Transaction__c transactionRecord = createTransaction('Batch Insight Active', borrower.Id);

        Lead staleLead = new Lead(
            FirstName = 'Batch',
            LastName = 'Insight',
            Company = 'N/A',
            Status = 'Application',
            MobilePhone = sharedPhone,
            RecordTypeId = leadRecordTypeId('Consumer_Lead_record_type')
        );
        insert staleLead;

        Call_Insight__c insight = new Call_Insight__c(
            Lead__c = staleLead.Id,
            Recipient_Phone_Number__c = '+13215557001',
            Title__c = 'Outbound call with Batch Insight',
            Recording_Start_DateTime__c = System.now()
        );
        insert insight;

        Call_Insight__c orphanedInsight = [
            SELECT Id, Account__c, Lead__c, Transaction__c, Recipient_Phone_Number__c
            FROM Call_Insight__c
            WHERE Id = :insight.Id
        ];
        orphanedInsight.Transaction__c = null;
        orphanedInsight.Account__c = null;
        orphanedInsight.Lead__c = staleLead.Id;

        Test.startTest();
        new ClientActTxBackfillBatch(ClientActTxBackfillBatch.TARGET_CALL_INSIGHTS).execute(
            null,
            new List<SObject>{ orphanedInsight }
        );
        Test.stopTest();

        Call_Insight__c routed = [SELECT Transaction__c, Account__c, Lead__c FROM Call_Insight__c WHERE Id = :insight.Id];
        System.assertEquals(transactionRecord.Id, routed.Transaction__c);
        System.assertEquals(borrower.Id, routed.Account__c);
        System.assertEquals(null, routed.Lead__c);
    }

    @IsTest
    static void smsBatchRoutesOrphanRows() {
        String sharedPhone = '321-555-7002';
        Account borrower = new Account(LastName = 'Batch Sms Borrower', PersonMobilePhone = sharedPhone);
        insert borrower;
        Transaction__c transactionRecord = createTransaction('Batch Sms Active', borrower.Id);

        smagicinteract__smsMagic__c sms = new smagicinteract__smsMagic__c(
            smagicinteract__PhoneNumber__c = '+13215557002'
        );
        insert sms;

        smagicinteract__smsMagic__c orphanedSms = [
            SELECT Id,
                smagicinteract__Account__c,
                smagicinteract__Contact__c,
                smagicinteract__Lead__c,
                Transaction__c,
                smagicinteract__PhoneNumber__c,
                smagicinteract__Unformatted_Phone_Number__c
            FROM smagicinteract__smsMagic__c
            WHERE Id = :sms.Id
        ];
        orphanedSms.Transaction__c = null;
        orphanedSms.smagicinteract__Account__c = null;

        Test.startTest();
        new ClientActTxBackfillBatch(ClientActTxBackfillBatch.TARGET_SMS_HISTORY).execute(
            null,
            new List<SObject>{ orphanedSms }
        );
        Test.stopTest();

        smagicinteract__smsMagic__c routed = [
            SELECT Transaction__c, smagicinteract__Account__c
            FROM smagicinteract__smsMagic__c
            WHERE Id = :sms.Id
        ];
        System.assertEquals(transactionRecord.Id, routed.Transaction__c);
        System.assertEquals(borrower.Id, routed.smagicinteract__Account__c);
    }

    private static Id leadRecordTypeId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead' AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    private static Transaction__c createTransaction(String name, Id borrowerId) {
        Id businessAccountRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Business_Account'
            LIMIT 1
        ].Id;

        Account lender = new Account(
            Name = name + ' Lender',
            RecordTypeId = businessAccountRecordTypeId,
            Type = 'Investor'
        );
        insert lender;

        Transaction__c transactionRecord = new Transaction__c(
            Name = name,
            Status__c = 'Processing',
            Borrower_Name__c = borrowerId,
            Borrower_First_Name__c = 'Batch',
            Borrower_Last_Name__c = 'Borrower',
            Lender_lookup__c = lender.Id
        );
        insert transactionRecord;
        return transactionRecord;
    }
}