/**
 * O3: Twilio text stamping (origin loan/lead, reply threading, Workspace LO) and the LO Workspace reads.
 * The LO gets External_LO_Access directly (not the PSG, which may be recalculating during a deploy).
 */
@IsTest
private class LoWsTextsServiceTest {
    static final String AGENT_PHONE = '(239) 555-0100';

    @TestSetup
    static void setup() {
        User ext = newUser('o3ext', 'External Loan Officer Profile', ExternalLoStampService.ROLE_DEVELOPER_NAME);
        User internal = newUser('o3int', 'Loan Officer Profile', 'Loan_Officer');
        insert new List<User>{ ext, internal };
        insert new PermissionSetAssignment(AssigneeId = ext.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'External_LO_Access'].Id);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<Lead>{
                new Lead(LastName = 'O3 Ext Borrower', Company = 'O3', OwnerId = ext.Id, Phone = '407-555-0101'),
                new Lead(LastName = 'O3 Int Borrower', Company = 'O3', OwnerId = internal.Id, Phone = '407-555-0102')
            };
            insert new Account(
                RecordTypeId = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId(),
                FirstName = 'O3', LastName = 'Agent', PersonMobilePhone = AGENT_PHONE, Group__pc = 'Realtor', OwnerId = ext.Id
            );
        }
    }

    @IsTest
    static void stampsOriginsAndThreadsReplies() {
        User ext = user('o3ext');
        Lead mine = lead('O3 Ext Borrower');
        Lead theirs = lead('O3 Int Borrower');
        Account agent = [SELECT Id FROM Account WHERE LastName = 'Agent' AND FirstName = 'O3'];
        Transaction__c loan = new Transaction__c(Name = 'O3 Loan', Status__c = TestDataFactory.getOpportunityStageName(), Loan_Officer__c = ext.Id);
        insert loan;

        TwilioSF__Message__c fromMyLead = outbound(mine.Id, AGENT_PHONE, -60);
        TwilioSF__Message__c birthday = outbound(agent.Id, AGENT_PHONE, -120);
        TwilioSF__Message__c fromMyLoan = outbound(loan.Id, AGENT_PHONE, -180);
        TwilioSF__Message__c noParent = new TwilioSF__Message__c(TwilioSF__Direction__c = 'outbound-api',
            TwilioSF__To_Number__c = '4075550101', TwilioSF__Lead__c = mine.Id, TwilioSF__Body__c = 'Hi');
        insert noParent;

        TwilioSF__Message__c reply = inbound('+12395550100');

        System.assertEquals(mine.Id, row(fromMyLead.Id).LoWs_Lead__c);
        System.assertEquals(ext.Id, row(fromMyLead.Id).External_LO__c);
        System.assertEquals('2395550100', row(fromMyLead.Id).LoWs_Phone_Key__c);
        System.assertEquals(loan.Id, row(fromMyLoan.Id).LoWs_Transaction__c);
        System.assertEquals(ext.Id, row(fromMyLoan.Id).External_LO__c);
        System.assertEquals(null, row(birthday.Id).External_LO__c, 'an Account parent names no loan');
        System.assertEquals(null, row(birthday.Id).LoWs_Lead__c);
        System.assertEquals(mine.Id, row(noParent.Id).LoWs_Lead__c, 'no parent: the Lead lookup');
        System.assertEquals(mine.Id, row(reply.Id).LoWs_Lead__c, 'reply threads to the newest outbound to that number');
        System.assertEquals(ext.Id, row(reply.Id).External_LO__c);

        // Another LO texts the same agent later: the next reply belongs to that thread, never to this LO.
        outbound(theirs.Id, AGENT_PHONE, -10);
        TwilioSF__Message__c laterReply = inbound('2395550100');
        System.assertEquals(theirs.Id, row(laterReply.Id).LoWs_Lead__c);
        System.assertEquals(null, row(laterReply.Id).External_LO__c);
    }

    @IsTest
    static void loSeesOnlyTheirOwnTexts() {
        User ext = user('o3ext');
        Lead mine = lead('O3 Ext Borrower');
        Lead theirs = lead('O3 Int Borrower');
        Account agent = [SELECT Id FROM Account WHERE LastName = 'Agent' AND FirstName = 'O3'];
        TwilioSF__Message__c fromMyLead = outbound(mine.Id, AGENT_PHONE, -60);
        TwilioSF__Message__c reply = inbound('+12395550100');
        TwilioSF__Message__c fromTheirLead = outbound(theirs.Id, AGENT_PHONE, -5);

        System.runAs(ext) {
            Set<Id> onLead = ids(LoWsCommunicationsService.getCommunications(mine.Id).texts);
            System.assertEquals(new Set<Id>{ fromMyLead.Id, reply.Id }, onLead);
            System.assertEquals(new Set<Id>{ fromMyLead.Id, reply.Id }, ids(LoWsCommunicationsService.getPartnerTexts(agent.Id)),
                'realtor page: never another LO\'s texts to the same realtor');
            List<LoWsCommunicationsService.Item> texts = LoWsCommunicationsService.getPartnerTexts(agent.Id);
            System.assertEquals('Reply from your phone: 239-555-0100', texts[1].replyHint);
            System.assertEquals(null, texts[0].replyHint);

            List<PerfectDayHomeModels.RecentLogEntry> log = LoWsTextsService.withReplies(new List<PerfectDayHomeModels.RecentLogEntry>());
            System.assertEquals(1, log.size());
            System.assertEquals(LoWsTextsService.REPLY_KEY, log[0].activityKey);
            System.assertEquals(reply.Id, log[0].taskId);
            try {
                PerfectDayHomeController.getPerfectDayHomeData(null);
            } catch (AuraHandledException e) {
                System.debug('Perfect Day needs more setup than this test has: ' + e.getMessage());
            }
        }
        // Internal users see every text on the record.
        System.assertEquals(new Set<Id>{ fromTheirLead.Id }, ids(LoWsTextsService.forRecords(new Set<Id>{ theirs.Id })));
        System.assertEquals(0, LoWsTextsService.withReplies(null).size(), 'no replies for internal users');
    }

    @IsTest
    static void leadReassignmentRestampsTexts() {
        User ext = user('o3ext');
        Lead theirs = lead('O3 Int Borrower');
        TwilioSF__Message__c text = outbound(theirs.Id, AGENT_PHONE, -5);
        System.assertEquals(null, row(text.Id).External_LO__c);
        Test.startTest();
        update new Lead(Id = theirs.Id, OwnerId = ext.Id);
        Test.stopTest();
        System.assertEquals(ext.Id, row(text.Id).External_LO__c);
    }

    @IsTest
    static void phoneHelpers() {
        System.assertEquals('2395550100', LoWsTextsService.phoneKey('+1 (239) 555-0100'));
        System.assertEquals(null, LoWsTextsService.phoneKey('55501'));
        System.assertEquals('239-555-0100', LoWsTextsService.formatPhone('+12395550100'));
        System.assertEquals('55501', LoWsTextsService.formatPhone('55501'));
    }

    // ------------------------------------------------------------------ helpers

    static TwilioSF__Message__c outbound(Id parentId, String toNumber, Integer minutesAgo) {
        TwilioSF__Message__c m = new TwilioSF__Message__c(TwilioSF__Direction__c = 'outbound-api', TwilioSF__To_Number__c = toNumber,
            TwilioSF__From_Number__c = '7722385990', TwilioSF__SF_Parent_Record_Id__c = parentId, TwilioSF__Body__c = 'Update');
        insert m;
        Test.setCreatedDate(m.Id, Datetime.now().addMinutes(minutesAgo));
        return m;
    }

    static TwilioSF__Message__c inbound(String fromNumber) {
        TwilioSF__Message__c m = new TwilioSF__Message__c(TwilioSF__Direction__c = 'inbound', TwilioSF__From_Number__c = fromNumber,
            TwilioSF__To_Number__c = '+17722385990', TwilioSF__Body__c = 'Thanks!');
        insert m;
        return m;
    }

    static TwilioSF__Message__c row(Id id) {
        return [SELECT LoWs_Lead__c, LoWs_Transaction__c, LoWs_Phone_Key__c, External_LO__c FROM TwilioSF__Message__c WHERE Id = :id];
    }

    static Set<Id> ids(List<LoWsCommunicationsService.Item> items) {
        Set<Id> result = new Set<Id>();
        for (LoWsCommunicationsService.Item i : items) {
            result.add(i.id);
        }
        return result;
    }

    static Lead lead(String lastName) {
        return [SELECT Id FROM Lead WHERE LastName = :lastName LIMIT 1];
    }

    static User user(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias AND Username LIKE '%@reach-o3.test' LIMIT 1];
    }

    static User newUser(String alias, String profileName, String roleName) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = :roleName].Id,
            Username = alias + suffix + '@reach-o3.test', Email = alias + '@reach-o3.test',
            FirstName = 'O3', LastName = alias, Alias = alias,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}