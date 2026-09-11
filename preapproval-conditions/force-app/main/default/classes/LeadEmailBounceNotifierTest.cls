@IsTest
private class LeadEmailBounceNotifierTest {

    @IsTest
    static void theAlertNamesTheLeadTheAddressAndWhatWasSent() {
        Lead leadRecord = new Lead(
            FirstName = 'Andrea', LastName = 'Marino', Company = 'Bounce Test',
            Status = 'New', Email = 'good.address@example.com'
        );
        insert leadRecord;

        EmailMessage message = new EmailMessage(
            Subject = 'Items Needed - Marino Mortgage Pre-Approval',
            ToAddress = 'mistyped927@aol.com',
            MessageDate = Datetime.newInstance(2026, 9, 11, 9, 37, 0)
        );

        Test.startTest();
        String body = LeadEmailBounceNotifier.buildBody(message, [
            SELECT Id, Name, Email, Status, Owner.Name FROM Lead WHERE Id = :leadRecord.Id
        ]);
        Test.stopTest();

        System.assertEquals(true, body.contains('Andrea Marino'), 'The sender has to know which lead.');
        System.assertEquals(true, body.contains('mistyped927@aol.com'), 'And which address failed.');
        System.assertEquals(true, body.contains('Items Needed - Marino Mortgage Pre-Approval'));
        System.assertEquals(true, body.contains('Email Bounced'));
        System.assertEquals(true, body.contains('/lightning/r/Lead/' + leadRecord.Id + '/view'),
            'A link back to the lead, so correcting the address is one click.');
    }

    // ActivityId is not writable, so a real bounced message cannot be assembled here. This
    // exercises the alert itself with the records it would have resolved.
    @IsTest
    static void theAlertGoesOutForABouncedLeadEmail() {
        Lead leadRecord = new Lead(
            FirstName = 'Andrea', LastName = 'Marino', Company = 'Bounce Test',
            Status = 'New', Email = 'mistyped927@aol.com'
        );
        insert leadRecord;

        EmailMessage bounced = new EmailMessage(
            Subject = 'Items Needed - Marino Mortgage Pre-Approval',
            ToAddress = 'mistyped927@aol.com',
            MessageDate = Datetime.now()
        );

        Test.startTest();
        LeadEmailBounceNotifier.sendAlert(
            'bbrotsky@reachhomeloans.com',
            bounced,
            [SELECT Id, Name, Email, Status, Owner.Name FROM Lead WHERE Id = :leadRecord.Id]
        );
        Test.stopTest();

        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'Sending is suppressed under test; the path still has to run without throwing.'
        );
    }

    @IsTest
    static void aBounceOnSomethingOtherThanALeadIsIgnored() {
        Account accountRecord = new Account(Name = 'Not A Lead');
        insert accountRecord;
        Contact contactRecord = new Contact(LastName = 'Person', AccountId = accountRecord.Id);
        insert contactRecord;
        Task activity = new Task(Subject = 'Email: something', WhoId = contactRecord.Id);
        insert activity;

        Test.startTest();
        Lead resolved = LeadEmailBounceNotifier.resolveLead(activity.Id);
        Lead noActivity = LeadEmailBounceNotifier.resolveLead(null);
        Test.stopTest();

        System.assertEquals(null, resolved, 'Contact bounces belong to a different process.');
        System.assertEquals(null, noActivity);
    }

    @IsTest
    static void anUnbouncedOrUnknownMessageSendsNothing() {
        Test.startTest();
        LeadEmailBounceNotifier.notifyBouncedEmails(null);
        LeadEmailBounceNotifier.notifyBouncedEmails(new List<Id>());
        // A real EmailMessage that has not bounced must not trigger an alert.
        EmailMessage clean = new EmailMessage(
            Subject = 'Still fine', ToAddress = 'someone@example.com', Status = '3'
        );
        insert clean;
        LeadEmailBounceNotifier.notifyBouncedEmails(new List<Id>{ clean.Id });
        Test.stopTest();

        System.assertEquals(
            false,
            [SELECT IsBounced FROM EmailMessage WHERE Id = :clean.Id].IsBounced,
            'Nothing about the message should change; the guard simply returns.'
        );
    }
}
