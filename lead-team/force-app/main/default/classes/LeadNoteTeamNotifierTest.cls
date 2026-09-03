@IsTest
private class LeadNoteTeamNotifierTest {
    private static Id consumerRecordTypeId() {
        return Lead.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('Consumer_Lead_record_type')
            .getRecordTypeId();
    }

    private static Id realtorRecordTypeId() {
        return Lead.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('Realtor_Lead_record_type')
            .getRecordTypeId();
    }

    /** Distinctive names so an @mention in a test body can only match the user we intend. */
    private static List<User> buildUsers(Integer count) {
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        List<User> users = new List<User>();
        for (Integer i = 0; i < count; i++) {
            users.add(new User(
                FirstName = 'Zeta' + i,
                LastName = 'Teammate' + i,
                Alias = 'zt' + i,
                Email = 'lead.team.test' + i + '@example.com',
                Username = 'lead.team.test' + i + '.' + Datetime.now().getTime() + '@example.invalid',
                ProfileId = p.Id,
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            ));
        }
        insert users;
        return users;
    }

    private static Enhanced_Note__c insertNote(Id leadId, String type, String body) {
        Enhanced_Note__c note = new Enhanced_Note__c(
            Lead__c = leadId,
            Type__c = type,
            Subject__c = 'Test subject',
            Body__c = body,
            AuthorRole__c = 'Loan Officer'
        );
        insert note;
        return note;
    }

    private static Set<String> toAddresses(Messaging.SingleEmailMessage mail) {
        Set<String> addresses = new Set<String>();
        for (String address : mail.getToAddresses()) {
            addresses.add(address.toLowerCase());
        }
        return addresses;
    }

    // ---------- mention matching (no DML) ----------

    @IsTest
    static void mentionMatchesTheVariantsPeopleActuallyType() {
        User byron = new User(
            FirstName = 'Byron', LastName = 'Richie',
            Alias = 'brichie', Email = 'byron@reachhomeloans.com'
        );

        System.assert(
            LeadNoteTeamNotifier.mentions('<p>@Byron can you review this scenario?</p>', byron),
            'First name'
        );
        System.assert(
            LeadNoteTeamNotifier.mentions('<p>@byron lowercase works too</p>', byron),
            'Case insensitive'
        );
        System.assert(
            LeadNoteTeamNotifier.mentions('<p>Looping in @Byron Richie for the structure.</p>', byron),
            'Full name'
        );
        System.assert(
            LeadNoteTeamNotifier.mentions('<p>@Byron.Richie please advise</p>', byron),
            'Dotted handle'
        );
    }

    @IsTest
    static void mentionIgnoresOrdinaryProseAndEmailAddresses() {
        User byron = new User(
            FirstName = 'Byron', LastName = 'Richie',
            Alias = 'brichie', Email = 'byron@reachhomeloans.com'
        );

        System.assert(
            !LeadNoteTeamNotifier.mentions('<p>called &amp; texted again @ 5:20 No contact made</p>', byron),
            'A bare @ before a time is not a mention -- this is real note text from prod'
        );
        System.assert(
            !LeadNoteTeamNotifier.mentions('<p>Emailed byron@reachhomeloans.com this morning.</p>', byron),
            'An email address in the body is not a mention'
        );
        System.assert(
            !LeadNoteTeamNotifier.mentions('<p>Spoke with the borrower about rate lock timing.</p>', byron),
            'No @ at all'
        );
        System.assert(
            !LeadNoteTeamNotifier.mentions('<p>@Byronson is a different person</p>', byron),
            'Handle must not run into more word characters'
        );
        System.assert(!LeadNoteTeamNotifier.mentions(null, byron), 'Null body is safe');
        System.assert(!LeadNoteTeamNotifier.mentions('<p>@Byron</p>', null), 'Null user is safe');
    }

    // ---------- recipient selection ----------

    @IsTest
    static void authorIsNotEmailedTheirOwnNote() {
        List<User> users = buildUsers(1);
        Lead theLead = new Lead(
            LastName = 'Webb', FirstName = 'Marcus', Company = 'Test', Status = 'New',
            RecordTypeId = consumerRecordTypeId(),
            OwnerId = UserInfo.getUserId(),          // the running user also writes the note
            Other_Lead_Team_Member__c = users[0].Id
        );
        insert theLead;

        Test.startTest();
        Enhanced_Note__c note = insertNote(theLead.Id, 'Note', '<p>Rate lock discussed.</p>');
        List<Messaging.SingleEmailMessage> emails =
            LeadNoteTeamNotifier.buildEmails(new List<Enhanced_Note__c>{ note });
        Test.stopTest();

        System.assertEquals(1, emails.size(), 'Still one email for the rest of the team');
        Set<String> addresses = toAddresses(emails[0]);
        System.assert(
            !addresses.contains([SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email.toLowerCase()),
            'Author (also the Owner) must not be emailed their own note'
        );
        System.assert(addresses.contains(users[0].Email.toLowerCase()), 'Other is still emailed');
    }

    @IsTest
    static void scenarioManagerIsSkippedWithoutAMention() {
        List<User> users = buildUsers(2);
        Lead theLead = new Lead(
            LastName = 'Quiet', Company = 'Test', Status = 'New',
            RecordTypeId = consumerRecordTypeId(),
            OwnerId = users[0].Id,
            Scenario_Manager__c = users[1].Id
        );
        insert theLead;

        Test.startTest();
        Enhanced_Note__c note = insertNote(theLead.Id, 'Note', '<p>Left a voicemail, no answer.</p>');
        List<Messaging.SingleEmailMessage> emails =
            LeadNoteTeamNotifier.buildEmails(new List<Enhanced_Note__c>{ note });
        Test.stopTest();

        System.assertEquals(1, emails.size(), 'Owner still gets it');
        Set<String> addresses = toAddresses(emails[0]);
        System.assert(addresses.contains(users[0].Email.toLowerCase()), 'Owner emailed');
        System.assert(
            !addresses.contains(users[1].Email.toLowerCase()),
            'Scenario Manager must NOT be emailed on an unmentioned note'
        );
    }

    @IsTest
    static void scenarioManagerIsEmailedWhenMentioned() {
        List<User> users = buildUsers(2);
        Lead theLead = new Lead(
            LastName = 'Flagged', Company = 'Test', Status = 'New',
            RecordTypeId = consumerRecordTypeId(),
            OwnerId = users[0].Id,
            Scenario_Manager__c = users[1].Id
        );
        insert theLead;

        Test.startTest();
        Enhanced_Note__c note = insertNote(
            theLead.Id, 'Note',
            '<p>@' + users[1].FirstName + ' can you look at this structure?</p>'
        );
        List<Messaging.SingleEmailMessage> emails =
            LeadNoteTeamNotifier.buildEmails(new List<Enhanced_Note__c>{ note });
        Test.stopTest();

        System.assertEquals(1, emails.size(), 'One email');
        Set<String> addresses = toAddresses(emails[0]);
        System.assert(
            addresses.contains(users[1].Email.toLowerCase()),
            'Scenario Manager IS emailed once @mentioned'
        );
        System.assert(addresses.contains(users[0].Email.toLowerCase()), 'Owner still emailed');
    }

    @IsTest
    static void addressesAreDedupedAndSubjectAndBodyAreShaped() {
        List<User> users = buildUsers(1);
        Lead theLead = new Lead(
            LastName = 'Webb', FirstName = 'Marcus', Company = 'Test', Status = 'New',
            RecordTypeId = consumerRecordTypeId(),
            OwnerId = users[0].Id,
            // Same person in two slots -- must collapse to a single address.
            Other_Lead_Team_Member__c = users[0].Id
        );
        insert theLead;

        Test.startTest();
        Enhanced_Note__c note = insertNote(
            theLead.Id, 'Note', '<p>Spoke with Marcus about rate lock timing.</p>'
        );
        List<Messaging.SingleEmailMessage> emails =
            LeadNoteTeamNotifier.buildEmails(new List<Enhanced_Note__c>{ note });
        Test.stopTest();

        Messaging.SingleEmailMessage mail = emails[0];
        System.assertEquals(
            mail.getToAddresses().size(),
            toAddresses(mail).size(),
            'No address appears twice: ' + mail.getToAddresses()
        );
        System.assert(mail.getSubject().startsWith('Marcus Webb - Note Update - '), 'Subject: ' + mail.getSubject());

        String body = mail.getHtmlBody();
        System.assert(body.contains('rate lock timing'), 'Body carries the note text');
        System.assert(body.contains('/lightning/r/Lead/' + theLead.Id + '/view'), 'Body links the lead');
        System.assert(body.contains('Loan Officer'), 'Body carries the author role');
    }

    // ---------- filters ----------

    @IsTest
    static void notifiesOnBlankTypeNotesFromTheAddNoteModal() {
        List<User> users = buildUsers(1);
        Lead theLead = new Lead(
            LastName = 'Testiana', FirstName = 'Test', Company = 'Test', Status = 'New',
            RecordTypeId = consumerRecordTypeId(),
            OwnerId = users[0].Id
        );
        insert theLead;

        Test.startTest();
        // The Add New Note modal saved with Type__c blank -- these must still notify.
        Enhanced_Note__c note = insertNote(theLead.Id, null, '<p>File Update Test</p>');
        List<Messaging.SingleEmailMessage> emails =
            LeadNoteTeamNotifier.buildEmails(new List<Enhanced_Note__c>{ note });
        Test.stopTest();

        System.assertEquals(1, emails.size(), 'A blank-type note is a hand-typed note, not automation');
        System.assert(
            toAddresses(emails[0]).contains(users[0].Email.toLowerCase()),
            'Owner is notified on a blank-type note'
        );
    }

    @IsTest
    static void skipsAutomationNoteTypes() {
        List<User> users = buildUsers(1);
        Lead theLead = new Lead(
            LastName = 'Skipped', Company = 'Test', Status = 'New',
            RecordTypeId = consumerRecordTypeId(), OwnerId = users[0].Id
        );
        insert theLead;

        Test.startTest();
        List<Enhanced_Note__c> notes = new List<Enhanced_Note__c>{
            insertNote(theLead.Id, 'Call', '<p>x</p>'),
            insertNote(theLead.Id, 'Text', '<p>x</p>'),
            insertNote(theLead.Id, 'Meeting', '<p>x</p>')
        };
        List<Messaging.SingleEmailMessage> emails = LeadNoteTeamNotifier.buildEmails(notes);
        Test.stopTest();

        System.assertEquals(0, emails.size(), 'Call/Text/Meeting are automation rows, not user notes');
    }

    @IsTest
    static void skipsNonConsumerRecordTypes() {
        List<User> users = buildUsers(1);
        Lead theLead = new Lead(
            LastName = 'Realtor', Company = 'Test', Status = 'New',
            RecordTypeId = realtorRecordTypeId(), OwnerId = users[0].Id
        );
        insert theLead;

        Test.startTest();
        Enhanced_Note__c note = insertNote(theLead.Id, 'Note', '<p>x</p>');
        List<Messaging.SingleEmailMessage> emails =
            LeadNoteTeamNotifier.buildEmails(new List<Enhanced_Note__c>{ note });
        Test.stopTest();

        System.assertEquals(0, emails.size(), 'Consumer leads only');
    }

    @IsTest
    static void handlesNoNotesAndNoRecipients() {
        Test.startTest();
        System.assertEquals(0, LeadNoteTeamNotifier.buildEmails(null).size(), 'Null input is safe');
        System.assertEquals(
            0,
            LeadNoteTeamNotifier.buildEmails(new List<Enhanced_Note__c>()).size(),
            'Empty input is safe'
        );
        LeadNoteTeamNotifier.notifyForNotes(new List<Enhanced_Note__c>());
        Test.stopTest();
    }
}
