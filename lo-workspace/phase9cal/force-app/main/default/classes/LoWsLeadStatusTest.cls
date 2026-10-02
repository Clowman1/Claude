/**
 * Phase 9 lead status rules for outside LOs. Users get the External_LO_Access permission set only (not the
 * External_Loan_Officer group), so these tests don't depend on the group's recalculation status.
 * - Logged calls move New / Contact Attempt forward (ExternalLoActivityLogService.progressLeadAfterCall).
 * - An initial document request email moves an outside LO's early lead to Documents Requested.
 * - Calls_Required_for_Status_Change no longer applies to External_LO users.
 * No @TestSetup: the validation-rule test needs SeeAllData (only existing leads carry the inactive
 * "Consumer Refinance Lead Record Type" the rule targets), and SeeAllData can't share a class with @TestSetup.
 */
@IsTest
private class LoWsLeadStatusTest {

    static User outsideLo() {
        User u = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p9st' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p9.test',
            Email = 'p9st@reach-p9.test', LastName = 'p9st', Alias = 'p9st',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'External_LO_Access'].Id);
        }
        return u;
    }

    static User internalLo() {
        User u = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Loan Officer Profile' LIMIT 1].Id,
            Username = 'p9in' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p9.test',
            Email = 'p9in@reach-p9.test', LastName = 'p9in', Alias = 'p9in',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    static Lead lead(Id ownerId, String status) {
        Lead l = new Lead(
            RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId(),
            FirstName = 'Stat', LastName = 'Zedstatus' + status.replace(' ', ''), Company = 'n/a', Status = status,
            OwnerId = ownerId, Loan_Amount__c = 350000
        );
        insert l;
        return l;
    }

    static ExternalLoActivityLogService.LogResult logCall(Id leadId, String outcome) {
        ExternalLoActivityLogService.LogRequest r = new ExternalLoActivityLogService.LogRequest();
        r.activityKey = 'consumer-conversation';
        r.channel = 'call';
        r.activityCount = 1;
        r.recordId = leadId;
        r.callOutcome = outcome;
        return ExternalLoActivityLogService.logActivity(r);
    }

    static String statusOf(Id leadId) {
        return [SELECT Status FROM Lead WHERE Id = :leadId].Status;
    }

    @IsTest
    static void nextStatusRules() {
        System.assertEquals('Contact Attempt 1', ExternalLoActivityLogService.nextLeadStatus('New', 'left-voicemail', 6));
        System.assertEquals('Contact Attempt 2', ExternalLoActivityLogService.nextLeadStatus('Contact Attempt 1', 'no-answer', 6));
        System.assertEquals(null, ExternalLoActivityLogService.nextLeadStatus('Contact Attempt 6', 'no-answer', 6), 'Capped at the highest value.');
        System.assertEquals('Working', ExternalLoActivityLogService.nextLeadStatus('New', 'connected', 6));
        System.assertEquals('Working', ExternalLoActivityLogService.nextLeadStatus('Contact Attempt 3', 'reached', 6));
        System.assertEquals(null, ExternalLoActivityLogService.nextLeadStatus('Working', 'no-answer', 6), 'Never backwards.');
        System.assertEquals(null, ExternalLoActivityLogService.nextLeadStatus('Pre-Approval', 'connected', 6));
        System.assertEquals(null, ExternalLoActivityLogService.nextLeadStatus('Nurturing', 'left-voicemail', 6));
        System.assertEquals(null, ExternalLoActivityLogService.nextLeadStatus('New', null, 6), 'No outcome, no move.');
    }

    @IsTest
    static void loggedCallsMoveAnOutsideLosLeadForwardOnly() {
        User lo = outsideLo();
        Lead fresh = lead(lo.Id, 'New');
        Lead attempt = lead(lo.Id, 'Contact Attempt 1');
        Lead reached = lead(lo.Id, 'New');
        Lead preApproved = lead(lo.Id, 'Pre-Approval');
        System.runAs(lo) {
            ExternalLoActivityLogService.LogResult r1 = logCall(fresh.Id, 'left-voicemail');
            System.assertEquals('Contact Attempt 1', statusOf(fresh.Id), 'New + voicemail -> Contact Attempt 1');
            System.assert(r1.userMessage.contains('lead moved to Contact Attempt 1'), r1.userMessage);

            logCall(attempt.Id, 'no-answer');
            System.assertEquals('Contact Attempt 2', statusOf(attempt.Id), 'CA1 + no answer -> CA2');

            logCall(reached.Id, 'connected');
            System.assertEquals('Working', statusOf(reached.Id), 'New + reached -> Working');

            ExternalLoActivityLogService.LogResult r4 = logCall(preApproved.Id, 'connected');
            System.assertEquals('Pre-Approval', statusOf(preApproved.Id), 'A Pre-Approval lead never moves.');
            System.assert(!r4.userMessage.contains('moved'), r4.userMessage);
        }
    }

    @IsTest
    static void documentRequestMovesAnOutsideLosLeadToDocumentsRequestedForwardOnly() {
        User lo = outsideLo();
        Lead working = lead(lo.Id, 'Working');
        Lead resend = lead(lo.Id, 'Contact Attempt 2');
        Lead preApproved = lead(lo.Id, 'Pre-Approval');
        update new Lead(Id = resend.Id, Initial_Docs_Requested_Date__c = System.now().addDays(-3));
        System.runAs(lo) {
            LeadDocumentRequestService.stampInitialDocsRequested(working, 'Lead_Initial_Documents_Needed');
            LeadDocumentRequestService.stampInitialDocsRequested(resend, 'Lead_Refinance_Items_Needed');
            LeadDocumentRequestService.stampInitialDocsRequested(preApproved, 'Lead_Initial_Documents_Needed');
        }
        System.assertEquals('Documents Requested', statusOf(working.Id));
        System.assertNotEquals(null, [SELECT Initial_Docs_Requested_Date__c FROM Lead WHERE Id = :working.Id].Initial_Docs_Requested_Date__c);
        System.assertEquals('Documents Requested', statusOf(resend.Id), 'Outside LOs: a later initial send still moves an early lead.');
        System.assertEquals('Pre-Approval', statusOf(preApproved.Id), 'Never back from Pre-Approval.');
        System.assertNotEquals(null, [SELECT Initial_Docs_Requested_Date__c FROM Lead WHERE Id = :preApproved.Id].Initial_Docs_Requested_Date__c,
            'The first-send date is still stamped.');
    }

    @IsTest
    static void internalSendBehaviourIsUnchanged() {
        User admin = new User(Id = UserInfo.getUserId());
        Lead resend = lead(admin.Id, 'Working');
        update new Lead(Id = resend.Id, Initial_Docs_Requested_Date__c = System.now().addDays(-3));
        Lead first = lead(admin.Id, 'Working');
        LeadDocumentRequestService.stampInitialDocsRequested(resend, 'Lead_Initial_Documents_Needed');
        LeadDocumentRequestService.stampInitialDocsRequested(first, 'Lead_Initial_Documents_Needed');
        System.assertEquals('Working', statusOf(resend.Id), 'Internal: only the first send moves status.');
        System.assertEquals('Documents Requested', statusOf(first.Id));
    }

    @IsTest(SeeAllData=true)
    static void callsRequiredRuleExemptsOutsideLosButStillBlocksInternalLos() {
        List<Lead> refis = [
            SELECT Id FROM Lead
            WHERE RecordType.DeveloperName = 'Consumer_Under_Contract_Lead_Record_Type'
              AND IsConverted = false AND Realtor_Buying_Agent__c = null
              AND LeadSource NOT IN ('Realtor Referral', 'Facebook - Landing Refi')
            LIMIT 2
        ];
        System.assertEquals(2, refis.size(), 'Needs two existing Consumer Refinance leads.');
        User outside = outsideLo();
        User inside = internalLo();
        // Admin (exempt by profile) gives each user their own lead, at New. Rolled back with the test.
        update new List<Lead>{
            new Lead(Id = refis[0].Id, OwnerId = outside.Id, Status = 'New', Loan_Amount__c = 350000),
            new Lead(Id = refis[1].Id, OwnerId = inside.Id, Status = 'New', Loan_Amount__c = 350000)
        };

        System.runAs(outside) {
            // No call logged (Number_of_Calls__c unchanged): only the External_LO exemption lets this through.
            update new Lead(Id = refis[0].Id, Status = 'Pre-Approval');
        }
        System.assertEquals('Pre-Approval', statusOf(refis[0].Id), 'Outside LO: New -> Pre-Approval with no calls.');

        System.runAs(inside) {
            try {
                update new Lead(Id = refis[1].Id, Status = 'Working');
                System.assert(false, 'An internal LO must still be blocked.');
            } catch (DmlException expected) {
                System.assert(expected.getMessage().contains('Log an Activity'), expected.getMessage());
            }
        }
    }
}
