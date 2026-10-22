@isTest
private class LoWsCommunicationsServiceTest {

    private static Lead borrowerLead() {
        Id consumer = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND DeveloperName = 'Consumer_Lead_record_type' LIMIT 1].Id;
        Lead l = new Lead(
            RecordTypeId = consumer,
            FirstName = 'Comms',
            LastName = 'Borrower',
            Company = 'Comms Co',
            Status = 'New',
            Phone = '407-745-8484',
            Email = 'Comms.Borrower@example.com'
        );
        insert l;
        return l;
    }

    @isTest
    static void leadShowsCallsTextsAndEmailsFromEveryMatchingSource() {
        Lead l = borrowerLead();
        // RingCentral text with no WhoId: found by the borrower's number.
        insert new Task(
            Subject = 'SMS', Status = 'Completed', InteractionType__c = 'Sms',
            rcsfl__from_number__c = '+14077458484', rcsfl__to_number__c = '+17342742004',
            Description = 'Can we close earlier?', rcsfl__call_start_time__c = System.now().addHours(-2)
        );
        // Hand-logged call on the lead.
        insert new Task(
            Subject = 'Call', Status = 'Completed', TaskSubtype = 'Call', WhoId = l.Id,
            Description = 'Went over FHA vs Conventional'
        );
        // A task unrelated to the borrower must not appear.
        insert new Task(
            Subject = 'SMS', Status = 'Completed', InteractionType__c = 'Sms',
            rcsfl__from_number__c = '+15555550123', rcsfl__to_number__c = '+17342742004', Description = 'Other person'
        );
        EmailMessage msg = new EmailMessage(
            Subject = 'Re: Pre-approval letter', Status = '3', Incoming = false,
            MessageDate = System.now().addDays(-1), FromName = 'Jordan LO', FromAddress = 'lo@example.com',
            ToAddress = 'comms.borrower@example.com', TextBody = 'Attached is your letter.'
        );
        insert msg;
        insert new EmailMessageRelation(
            EmailMessageId = msg.Id, RelationAddress = 'comms.borrower@example.com', RelationType = 'ToAddress'
        );

        Test.startTest();
        LoWsCommunicationsService.Result r = LoWsCommunicationsService.getCommunications(l.Id);
        Test.stopTest();

        System.assertEquals('Comms Borrower', r.borrowerName);
        System.assertEquals(1, r.sms.size(), 'Only the borrower text, matched by number.');
        System.assertEquals(true, r.sms[0].fromBorrower);
        System.assertEquals('in', r.sms[0].direction);
        System.assertEquals(1, r.calls.size());
        System.assertEquals(true, r.calls[0].logged, 'No RingCentral data and no duration = logged by hand.');
        System.assertEquals(1, r.emails.size());
        System.assertEquals('Pre-approval letter', r.emails[0].subject, 'Re: is stripped from the thread subject.');
        System.assertEquals('Jordan LO', r.emails[0].messages[0].fromLabel);
    }

    @isTest
    static void loanResolvesToTheBorrowerAccount() {
        Id personRt = new PersonAccountRepository().selectPersonAccountRecordTypeId();
        if (personRt == null) {
            return;
        }
        Account a = new Account(RecordTypeId = personRt, FirstName = 'Loan', LastName = 'Borrower', PersonMobilePhone = '561-613-3270');
        insert a;
        Transaction__c t = new Transaction__c(Name = 'Comms Loan', Borrower_Name__c = a.Id, Status__c = 'Submitted');
        insert t;
        insert new Task(
            Subject = 'Call', Status = 'Completed', InteractionType__c = 'Call',
            rcsfl__from_number__c = '+17342742004', rcsfl__to_number__c = '+15616133270',
            rcsfl__call_start_time__c = System.now().addDays(-1), Description = 'Rate lock'
        );

        Test.startTest();
        LoWsCommunicationsService.Result r = LoWsCommunicationsService.getCommunications(t.Id);
        Test.stopTest();

        System.assertEquals(1, r.calls.size(), 'The loan finds calls by the borrower account phone.');
        System.assertEquals('out', r.calls[0].direction);
    }

    @isTest
    static void helpers() {
        System.assertEquals('+14077458484', LoWsCommunicationsService.toE164('(407) 745-8484'));
        System.assertEquals('+14077458484', LoWsCommunicationsService.toE164('1-407-745-8484'));
        System.assertEquals(null, LoWsCommunicationsService.toE164('745-8484'));
        System.assertEquals('Docs needed', LoWsCommunicationsService.threadSubject('RE: Fwd: Docs needed'));
        System.assertEquals('45s', LoWsCommunicationsService.durationLabel(45));
        System.assertEquals('2m 05s', LoWsCommunicationsService.durationLabel(125));
        System.assertEquals(null, LoWsCommunicationsService.durationLabel(0));
    }
}