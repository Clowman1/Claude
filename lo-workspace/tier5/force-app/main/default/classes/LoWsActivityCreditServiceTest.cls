/**
 * LoWsActivityCreditService: Perfect Day credit by who was contacted (owner rules, 2026-10-21).
 */
@IsTest
private class LoWsActivityCreditServiceTest {

    @TestSetup
    static void setup() {
        Id consumerRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId();
        insert new Lead(RecordTypeId = consumerRt, FirstName = 'Cora', LastName = 'Consumer', Company = 'Cora Household',
            Status = 'New', Phone = '561-555-0101', OwnerId = UserInfo.getUserId());
        Id personRt = new PersonAccountRepository().selectPersonAccountRecordTypeId();
        Account pastClient = new Account(RecordTypeId = personRt, FirstName = 'Paul', LastName = 'Pastclient',
            PersonEmail = 'paul.pastclient@example.com', Phone = '561-555-0202', OwnerId = UserInfo.getUserId());
        Account realtor = new Account(RecordTypeId = personRt, FirstName = 'Rita', LastName = 'Realtor',
            PersonEmail = 'rita.realtor@example.com', Phone = '561-555-0303', Group__pc = 'Realtor', OwnerId = UserInfo.getUserId());
        insert new List<Account>{ pastClient, realtor };
        insert new Transaction__c(Name = 'Closed loan', Borrower_Name__c = pastClient.Id, Status__c = 'Funding',
            Loan_Officer__c = UserInfo.getUserId());
    }

    @IsTest
    static void creditsByWhoWasContacted() {
        Id leadId = [SELECT Id FROM Lead WHERE LastName = 'Consumer'].Id;
        Account realtor = [SELECT Id, PersonContactId FROM Account WHERE LastName = 'Realtor'];
        Task borrowerProspectingCall = done(new Task(Subject = 'Prospecting call', TaskSubtype = 'Call',
            Activity_Type__c = 'Call - Prospecting', WhoId = leadId));
        Task pastClientRc = rc('Call', 'Outbound', '+15615550202', null);
        Task realtorText = rc('Sms', 'Outbound', '+15615550303', null);
        Task unknownNumber = rc('Call', 'Outbound', '+15615559999', null);
        Task inbound = rc('Call', 'Inbound', '+15615550101', null);
        inbound.WhoId = leadId;
        Task explicitCategory = done(new Task(Subject = 'Instagram', WhoId = leadId, Activity_Category__c = 'Social_Engagement'));
        Task meeting = done(new Task(Subject = 'Coffee', Activity_Type__c = 'Meeting (Active Agent)', WhoId = realtor.PersonContactId));
        Task email = done(new Task(Subject = 'Email: rates', TaskSubtype = 'Email', WhoId = leadId));
        insert new List<Task>{ borrowerProspectingCall, pastClientRc, realtorText, unknownNumber, inbound, explicitCategory, meeting, email };

        Test.startTest();
        Map<Id, String> keys = classified();
        Test.stopTest();

        Assert.areEqual('consumer-conversation', keys.get(borrowerProspectingCall.Id),
            'Call - Prospecting to an open consumer lead is a consumer conversation, not realtor outreach.');
        Assert.areEqual('past-client-call', keys.get(pastClientRc.Id), 'Number of a closed-loan borrower.');
        Assert.areEqual('realtor-outreach', keys.get(realtorText.Id), 'Number of a realtor Person Account.');
        Assert.isNull(keys.get(unknownNumber.Id), 'A number that matches nobody earns nothing.');
        Assert.isNull(keys.get(inbound.Id), 'Inbound RingCentral activity never counts.');
        Assert.areEqual('social-engagement', keys.get(explicitCategory.Id), 'An explicit category wins over the contact.');
        Assert.areEqual('partner-meeting', keys.get(meeting.Id), 'Meeting types keep the partner-meeting rule.');
        Assert.isNull(keys.get(email.Id), 'Emails are not conversations.');
    }

    @IsTest
    static void manualLogAndRingCentralWithinFifteenMinutesCountOnce() {
        Id leadId = [SELECT Id FROM Lead WHERE LastName = 'Consumer'].Id;
        Task manual = done(new Task(Subject = 'Call - Connected', TaskSubtype = 'Call', WhoId = leadId));
        Task sameCall = rc('Call', 'Outbound', '+15615550101', System.now().addMinutes(-5));
        Task earlierText = rc('Sms', 'Outbound', '+15615550101', System.now().addMinutes(-40));
        Task ctiCopy = rc(null, 'Outbound', '+15615550101', earlierText.rcsfl__call_start_time__c);
        ctiCopy.TaskSubtype = 'Call';
        insert new List<Task>{ manual, sameCall, earlierText, ctiCopy };

        Test.startTest();
        Map<Id, String> keys = classified();
        Test.stopTest();

        Assert.areEqual('consumer-conversation', keys.get(manual.Id), 'The manual log is kept.');
        Assert.isNull(keys.get(sameCall.Id), 'RingCentral row 5 minutes from the manual log is the same call.');
        Assert.areEqual(1, (keys.get(earlierText.Id) == null ? 0 : 1) + (keys.get(ctiCopy.Id) == null ? 0 : 1),
            '40 minutes earlier counts, but only once when RingCentral logged it twice.');
    }

    @IsTest
    static void rollupScoresThroughTheRepositoryInOnePass() {
        Task call = rc('Call', 'Outbound', '+15615550202', null);
        insert call;
        Test.startTest();
        List<Task> rows = new TaskRepository().selectCompletedActivitiesByOwnerForDateRange(
            UserInfo.getUserId(), Date.today(), Date.today());
        ExternalLoActivityPlanService.ActivityPlan plan = ExternalLoActivityPlanService.getPlan(UserInfo.getUserId());
        ExternalLoActivityRollupBuilder.PeriodScore score = ExternalLoActivityRollupBuilder.build(plan, rows, 7, false);
        Integer before = Limits.getQueries();
        ExternalLoActivityRollupBuilder.build(plan, rows, 1, true);
        Assert.areEqual(before, Limits.getQueries(), 'A second build reuses the classification (no SOQL).');
        Test.stopTest();
        Integer pastClient = 0;
        for (ExternalLoActivityRollupBuilder.CategoryScore row : score.rows) {
            pastClient += row.activityKey == 'past-client-call' ? row.completed : 0;
        }
        Assert.areEqual(1, pastClient, 'The RingCentral call to a past client credits Past clients.');
        Assert.areEqual('past-client-call', ExternalLoActivityRollupBuilder.activityKeyFor(new Task(Id = call.Id)),
            'The recent-activity feed reads the same classification.');
    }

    static Map<Id, String> classified() {
        List<Task> rows = new TaskRepository().selectCompletedActivitiesByOwnerForDateRange(
            UserInfo.getUserId(), Date.today(), Date.today());
        List<String> keys = LoWsActivityCreditService.keysFor(rows);
        Map<Id, String> byId = new Map<Id, String>();
        for (Integer i = 0; i < rows.size(); i++) {
            byId.put(rows[i].Id, keys[i]);
        }
        return byId;
    }

    static Task done(Task t) {
        t.Status = 'Completed';
        t.ActivityDate = Date.today();
        t.OwnerId = UserInfo.getUserId();
        return t;
    }

    static Task rc(String interactionType, String callType, String toNumber, Datetime startedAt) {
        return done(new Task(Subject = 'Call on ' + Date.today().format(), InteractionType__c = interactionType,
            CallType = callType, rcsfl__to_number__c = toNumber, rcsfl__call_start_time__c = startedAt));
    }
}
