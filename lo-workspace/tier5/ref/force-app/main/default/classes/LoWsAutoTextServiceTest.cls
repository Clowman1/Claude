/**
 * comms-settings: External LO automated texts (LoWsAutoTextService), the settings modal + contact switch
 * (LoWsCommSettingsController), and replies to the no-reply number in Up Next (LoWsTextsService).
 * Trigger handlers are called with in-memory old/new rows so org automation on Lead/Transaction stays out of it.
 */
@IsTest
private class LoWsAutoTextServiceTest {
    static final String AGENT_PHONE = '239-555-0177'; // PhoneFormat triggers store xxx-xxx-xxxx
    static final String BORROWER_PHONE = '407-555-0188';

    @TestSetup
    static void setup() {
        User ext = newUser('csext', 'External Loan Officer Profile', ExternalLoStampService.ROLE_DEVELOPER_NAME);
        insert ext;
        insert new PermissionSetAssignment(AssigneeId = ext.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'External_LO_Access'].Id);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id personRt = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
            Account agent = new Account(RecordTypeId = personRt, FirstName = 'Cs', LastName = 'Agent',
                PersonMobilePhone = AGENT_PHONE, Group__pc = 'Realtor', OwnerId = ext.Id);
            Account borrower = new Account(RecordTypeId = personRt, FirstName = 'Bea', LastName = 'Borrower',
                PersonMobilePhone = BORROWER_PHONE, OwnerId = ext.Id);
            insert new List<Account>{ agent, borrower };
            insert new Lead(FirstName = 'Lia', LastName = 'Lead', Company = 'CS', OwnerId = ext.Id,
                MobilePhone = BORROWER_PHONE, Realtor_Buying_Agent__c = agent.Id);
        }
    }

    @IsTest
    static void loanMilestonesTextAgentAndBorrowerFromNoReplyNumber() {
        Transaction__c loan = loan();
        Transaction__c before = loan.clone(true);
        Transaction__c after = loan.clone(true);
        after.Status__c = 'Approved';
        after.Disclosures_Out_Date__c = Datetime.now();

        LoWsAutoTextService.onTransactions(new List<Transaction__c>{ after }, new Map<Id, Transaction__c>{ loan.Id => before });

        Map<String, String> byBody = sentByBody();
        System.assertEquals(4, LoWsAutoTextService.sentForTest.size(), 'A5 + N7 + A9 + N8: ' + byBody.keySet());
        System.assert(byBody.containsKey('Bea Borrower is Clear To Close! - Reach Home Loans\nNo-reply'), byBody.keySet());
        for (Map<String, Object> m : LoWsAutoTextService.sentForTest) {
            System.assertEquals('5615894420', m.get('fromNumber'));
            System.assertEquals(loan.Id, m.get('recordId'));
        }
        System.assertEquals(AGENT_PHONE, byBody.get('Bea Borrower is Clear To Close! - Reach Home Loans\nNo-reply'));
    }

    @IsTest
    static void loSettingsAndContactSwitchSuppressTexts() {
        User ext = user();
        Transaction__c loan = loan();
        System.runAs(ext) {
            List<LoWsAutoTextService.Def> defs = LoWsCommSettingsController.getSettings();
            System.assertEquals(LoWsAutoTextService.CATALOG.size(), defs.size());
            System.assert(defs[0].enabled);
            LoWsCommSettingsController.saveSetting('A9', false, null);
            defs = LoWsCommSettingsController.saveSetting('N8', true, 'Hi {First Name}, CTC! -{LO Name}');
            for (LoWsAutoTextService.Def d : defs) {
                if (d.key == 'A9') System.assertEquals(false, d.enabled);
                if (d.key == 'N8') System.assert(d.customized);
            }
        }
        Transaction__c after = loan.clone(true);
        after.Status__c = 'Approved';
        LoWsAutoTextService.onTransactions(new List<Transaction__c>{ after }, new Map<Id, Transaction__c>{ loan.Id => loan.clone(true) });
        System.assertEquals(1, LoWsAutoTextService.sentForTest.size(), 'A9 is off');
        System.assertEquals('Hi Bea, CTC! -O3 csext\nNo-reply', LoWsAutoTextService.sentForTest[0].get('message'));

        // Reset to default, then switch the borrower off.
        System.runAs(ext) {
            LoWsCommSettingsController.saveSetting('N8', true, '');
            List<LoWsCommSettingsController.TextSwitch> switches = LoWsCommSettingsController.getTextSwitches(loan.Id);
            System.assertEquals(2, switches.size(), 'loan page: borrower + buyer\'s agent');
            switches = LoWsCommSettingsController.setTextsOff(loan.Id, loan.Borrower_Name__c, true);
            System.assert(switches[0].off);
            System.assert(!switches[1].off);
            try {
                LoWsCommSettingsController.setTextsOff(loan.Id, ext.Id, true);
                System.assert(false, 'only the loan\'s own contacts');
            } catch (AuraHandledException e) {
                System.assertEquals('This contact is not on this record.', e.getMessage());
            }
        }
        LoWsAutoTextService.sentForTest.clear();
        Transaction__c funded = loan.clone(true);
        funded.Funded_Date__c = Date.today();
        funded.Disclosures_Out_Date__c = Datetime.now();
        LoWsAutoTextService.onTransactions(new List<Transaction__c>{ funded }, new Map<Id, Transaction__c>{ loan.Id => loan.clone(true) });
        Set<String> to = new Set<String>();
        for (Map<String, Object> m : LoWsAutoTextService.sentForTest) {
            to.add((String) m.get('toNumber'));
        }
        System.assertEquals(new Set<String>{ AGENT_PHONE }, to, 'borrower switched off: agent texts only (A5, N2)');
        String saved = [SELECT LoWs_Comm_Settings__c FROM User WHERE Id = :ext.Id].LoWs_Comm_Settings__c;
        System.assert(saved.contains('A9') && !saved.contains('N8'), 'N8 reset drops its override; A9 stays off: ' + saved);
    }

    @IsTest
    static void leadPreApprovalAndDocRequests() {
        Lead l = [SELECT Id, OwnerId, FirstName, LastName, Status, IsConverted, MobilePhone, Phone, Realtor_Buying_Agent__c,
            LoWs_Texts_Off__c, Purchase_Price__c, Loan_Amount__c, Letter_Completed__c, Initial_Docs_Requested_Date__c,
            Recycled_From_Transaction__c, Recycle_Reactivated_At__c FROM Lead LIMIT 1];
        Lead after = l.clone(true);
        after.Status = 'Pre-Approval';
        after.Purchase_Price__c = 450000;
        after.Loan_Amount__c = 430000;
        after.Initial_Docs_Requested_Date__c = Datetime.now();
        LoWsAutoTextService.onLeads(new List<Lead>{ after }, new Map<Id, Lead>{ l.Id => l });
        Map<String, String> byBody = sentByBody();
        System.assertEquals(3, byBody.size(), 'A2 + A3 + N6: ' + byBody.keySet());
        System.assert(byBody.containsKey('Great news! Lia Lead is Pre-Approved. The Pre-Approval letter for Purchase Price $450,000 and Loan Amount $430,000 is on the way! - Reach Home Loans\nNo-reply'),
            byBody.keySet());

        LoWsAutoTextService.sentForTest.clear();
        Lead_Document_Request__c r = new Lead_Document_Request__c(Lead__c = l.Id, Status__c = 'Requested');
        LoWsAutoTextService.onDocRequests(new List<Lead_Document_Request__c>{ r }, null);
        System.assertEquals(1, LoWsAutoTextService.sentForTest.size(), 'N4');
        System.assert(((String) LoWsAutoTextService.sentForTest[0].get('message')).startsWith('Hi Lia, I\'ve requested'));
    }

    @IsTest
    static void dailyRemindersEveryThreeDaysThroughDayFifteen() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        insert new Lead_Document_Request__c(Lead__c = l.Id, Status__c = 'Requested', Requested_Date__c = Date.today().addDays(-6),
            Subject__c = 'Paystubs', Category__c = 'Income');
        LoWsAutoTextService.sentForTest.clear();
        LoWsAutoTextService.runDaily(Date.today());
        System.assertEquals(1, LoWsAutoTextService.sentForTest.size(), 'day 6 reminder');
        System.assert(((String) LoWsAutoTextService.sentForTest[0].get('message')).contains('1 items are still needed'));
        LoWsAutoTextService.sentForTest.clear();
        LoWsAutoTextService.runDaily(Date.today().addDays(11)); // day 17: past the 15-day stop
        System.assertEquals(0, LoWsAutoTextService.sentForTest.size());
        Test.startTest();
        System.schedule('LoWs auto text test', '0 0 10 * * ?', new LoWsAutoTextDaily());
        Test.stopTest();
    }

    @IsTest
    static void replyToNoReplyNumberIsAnUpNextAlertUntilHandled() {
        User ext = user();
        Transaction__c loan = loan();
        insert new TwilioSF__Message__c(TwilioSF__Direction__c = 'outbound-api', TwilioSF__To_Number__c = AGENT_PHONE,
            TwilioSF__From_Number__c = '5615894420', TwilioSF__SF_Parent_Record_Id__c = loan.Id, TwilioSF__Body__c = 'CTC');
        TwilioSF__Message__c reply = new TwilioSF__Message__c(TwilioSF__Direction__c = 'inbound', TwilioSF__From_Number__c = '+12395550177',
            TwilioSF__To_Number__c = '+15615894420', TwilioSF__Body__c = 'Great, thanks!');
        insert reply;
        System.runAs(ext) {
            List<ExternalLoPromptService.PromptItem> items = LoWsTextsService.replyPrompts(ext.Id);
            System.assertEquals(1, items.size());
            System.assertEquals('realtors', items[0].openView, 'agent reply opens the realtor page');
            System.assertEquals(loan.Realtor_Buying_Agent__c, items[0].recordId);
            System.assert(items[0].isHighAlert);
            PerfectDayHomeController.markReplyHandled(reply.Id);
            System.assertEquals(0, LoWsTextsService.replyPrompts(ext.Id).size());
        }
    }

    @IsTest
    static void helpers() {
        System.assertEquals('$1,250,000', LoWsAutoTextService.money(1250000));
        System.assertEquals('', LoWsAutoTextService.money(null));
        System.assertEquals('Hi Ann, call me', LoWsAutoTextService.render('Hi {First Name}, call me {Unknown}', new Map<String, String>{ '{First Name}' => 'Ann' }));
        System.assert(LoWsTextsService.isNoReplyNumber('+1 (561) 589-4420'));
        System.assert(!LoWsTextsService.isNoReplyNumber('7722385990'));
        try {
            LoWsCommSettingsController.saveSetting('ZZ', true, null);
            System.assert(false, 'unknown key');
        } catch (AuraHandledException e) {
            System.assertEquals('Unknown message.', e.getMessage());
        }
    }

    @IsTest
    static void failedSendsAreLoggedDurably() {
        Id fakeLead = Lead.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        Custom_Log__c mapped = LoWsAutoTextService.failedSendLog(fakeLead, 'Twilio said no');
        System.assertEquals(fakeLead, mapped.Lead__c);
        System.assertEquals(null, mapped.Transaction__c);

        LoWsAutoTextService.saveFailureLogs(new List<Custom_Log__c>{ LoWsAutoTextService.failedSendLog(null, null) });
        Custom_Log__c saved = [SELECT Errors__c FROM Custom_Log__c WHERE Source__c = :LoWsAutoTextService.FAILURE_LOG_SOURCE];
        System.assertEquals('Unknown error', saved.Errors__c);
        LoWsAutoTextService.saveFailureLogs(new List<Custom_Log__c>{ new Custom_Log__c(Lead__c = fakeLead) }); // bad row: no throw
    }

    @IsTest
    static void optOutFlagsAndStopKeywordsBlockTexts() {
        System.assertEquals('STOP', LoWsAutoTextService.keyword(' Stop. '));
        System.assertEquals('2395550177', LoWsAutoTextService.digits('+1 (239) 555-0177'));
        System.assertEquals(null, LoWsAutoTextService.digits('555-0177'));

        Transaction__c loan = loan();
        Transaction__c after = loan.clone(true);
        after.Status__c = 'Approved'; // A9 to the agent, N8 to the borrower
        Map<Id, Transaction__c> old = new Map<Id, Transaction__c>{ loan.Id => loan.clone(true) };

        // Borrower opted out by flag; agent texted STOP to a Reach number.
        update new Account(Id = loan.Borrower_Name__c, SMS_Opt_Out__c = true);
        TwilioSF__Message__c stop = new TwilioSF__Message__c(TwilioSF__Direction__c = 'inbound',
            TwilioSF__From_Number_Unformatted__c = '2395550177', TwilioSF__Body__c = 'Stop.');
        insert stop;
        Test.setCreatedDate(stop.Id, Datetime.now().addDays(-2));
        LoWsAutoTextService.onTransactions(new List<Transaction__c>{ after }, old);
        System.assertEquals(0, LoWsAutoTextService.sentForTest.size(), 'flag + STOP: ' + sentByBody().keySet());

        // A newer START opts the agent back in; the borrower stays out.
        TwilioSF__Message__c start = new TwilioSF__Message__c(TwilioSF__Direction__c = 'inbound',
            TwilioSF__From_Number_Unformatted__c = '2395550177', TwilioSF__Body__c = 'START');
        insert start;
        Test.setCreatedDate(start.Id, Datetime.now().addDays(-1));
        LoWsAutoTextService.onTransactions(new List<Transaction__c>{ after }, old);
        System.assertEquals(1, LoWsAutoTextService.sentForTest.size(), 'agent only: ' + sentByBody().keySet());
        System.assertEquals(AGENT_PHONE, LoWsAutoTextService.sentForTest[0].get('toNumber'));

        // Lead flag: the org's SMS automation opt-out stops the N4 text.
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        update new Lead(Id = l.Id, Opt_Out_from_SMS_Automation__c = true);
        LoWsAutoTextService.sentForTest.clear();
        LoWsAutoTextService.onDocRequests(new List<Lead_Document_Request__c>{
            new Lead_Document_Request__c(Lead__c = l.Id, Status__c = 'Requested') }, null);
        System.assertEquals(0, LoWsAutoTextService.sentForTest.size(), 'lead opted out');
    }

    // ------------------------------------------------------------------ helpers

    static Transaction__c loan() {
        Account agent = [SELECT Id FROM Account WHERE LastName = 'Agent' AND FirstName = 'Cs'];
        Account borrower = [SELECT Id FROM Account WHERE LastName = 'Borrower' AND FirstName = 'Bea'];
        Transaction__c t = new Transaction__c(Name = 'CS Loan', Status__c = TestDataFactory.getOpportunityStageName(),
            Loan_Officer__c = user().Id, Borrower_Name__c = borrower.Id, Realtor_Buying_Agent__c = agent.Id);
        insert t;
        LoWsAutoTextService.sentForTest.clear();
        return [SELECT Id, Status__c, Loan_Officer__c, Borrower_Name__c, Realtor_Buying_Agent__c, Disclosures_Out_Date__c,
            Appraisal_1_Ordered_Date__c, Appraisal_1_Received_Date__c, Funded_Date__c FROM Transaction__c WHERE Id = :t.Id];
    }

    static Map<String, String> sentByBody() {
        Map<String, String> result = new Map<String, String>();
        for (Map<String, Object> m : LoWsAutoTextService.sentForTest) {
            result.put((String) m.get('message'), (String) m.get('toNumber'));
        }
        return result;
    }

    static User user() {
        return [SELECT Id FROM User WHERE Alias = 'csext' AND Username LIKE '%@reach-cs.test' LIMIT 1];
    }

    static User newUser(String alias, String profileName, String roleName) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = :roleName].Id,
            Username = alias + suffix + '@reach-cs.test', Email = alias + '@reach-cs.test',
            FirstName = 'O3', LastName = alias, Alias = alias,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }
}