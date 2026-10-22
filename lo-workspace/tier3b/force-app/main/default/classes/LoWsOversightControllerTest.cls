/**
 * Phase 8: LoWsOversightController. A manager holding LO_Workspace_Oversight sees each outside LO's
 * goals vs Perfect Week/Month activity, lead stages, active loans by status, closed units/volume,
 * landing-page leads (new + taken over), realtor tags by stage and setup-change history.
 * Anyone without the custom permission is refused.
 */
@IsTest
private class LoWsOversightControllerTest {

    @TestSetup
    static void setup() {
        User lo = newUser('p8.lo', 'External Loan Officer Profile', 'External_Loan_Officer');
        lo.ExtLO_Monthly_Unit_Goal__c = 3;
        lo.ExtLO_Monthly_Volume_Goal__c = 900000;
        lo.ExtLO_Target_Realtor_Count__c = 5;
        User manager = newUser('p8.mgr', 'System Administrator', null);
        User outsider = newUser('p8.nope', 'System Administrator', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ lo, manager, outsider };
            insert new PermissionSetAssignment(
                AssigneeId = manager.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'LO_Workspace_Oversight'].Id
            );
        }
        Id consumerRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId();
        insert new List<Lead>{
            new Lead(RecordTypeId = consumerRt, FirstName = 'Lana', LastName = 'Landing', Company = 'Landing Household',
                Status = 'New', LeadSource = 'LO Landing Page', OwnerId = lo.Id),
            new Lead(RecordTypeId = consumerRt, FirstName = 'Nell', LastName = 'Nurture', Company = 'Nurture Household',
                Status = 'Nurturing', LeadSource = 'Website', OwnerId = lo.Id)
        };
        insert new List<Transaction__c>{
            new Transaction__c(Name = 'P8 Active', Loan_Officer__c = lo.Id, Status__c = 'Waiting On Loan Officer', Loan_Amount_1st__c = 300000),
            new Transaction__c(Name = 'P8 Closed', Loan_Officer__c = lo.Id, Status__c = 'Funding',
                Loan_Amount_1st__c = 250000, Closing_Date__c = Date.today(), Funding_Date__c = Date.today())
        };
        insert new List<External_User_Assignment__c>{
            new External_User_Assignment__c(User__c = lo.Id, Unique_Key__c = 'p8-a', Stage__c = 'Active Partner'),
            new External_User_Assignment__c(User__c = lo.Id, Unique_Key__c = 'p8-b')
        };
        insert new External_LO_Plan_Change__c(User__c = lo.Id, Summary__c = 'Loans closed per month: 3');
        insert new Task(OwnerId = lo.Id, Subject = 'P8 log', Status = 'Completed', ActivityDate = Date.today(),
            Activity_Category__c = ExternalLoActivityCatalog.activeActivities()[0].categoryApiName);
    }

    @IsTest
    static void managerSeesGoalsActivityPipelineTagsAndHistory() {
        LoWsOversightController.Overview result;
        System.runAs(byAlias('p8.mgr')) {
            Test.startTest();
            result = LoWsOversightController.getOverview(false);
            Test.stopTest();
        }
        LoWsOversightController.LoRow row;
        for (LoWsOversightController.LoRow r : result.los) {
            System.assert(r.isOutside, 'outside LOs only without the toggle: ' + r.name);
            if (r.userId == byAlias('p8.lo').Id) {
                row = r;
            }
        }
        System.assertNotEquals(null, row, 'the outside LO is listed');
        System.assertEquals(3, row.monthlyUnitGoal);
        System.assertEquals(5, row.targetRealtorCount);
        System.assertEquals(1, row.unitsClosedThisMonth, 'Funding loan funded this month (dated by Funding_Date__c)');
        System.assertEquals(250000, row.volumeClosedThisMonth);
        System.assertEquals(1, row.activeLoans, 'Waiting On Loan Officer is active; Funding is Closed (My Loans tabs)');
        System.assertEquals(1, row.activePartners);
        System.assert(row.week.totalCompleted >= 1, 'the logged task counts toward the week');
        System.assert(row.month.totalCompleted >= 1, 'and the month');

        Map<String, Integer> leads = toMap(row.leadStages);
        System.assertEquals(1, leads.get('New'));
        System.assertEquals(1, leads.get('Nurture'));
        System.assertEquals(5, row.leadStages.size(), 'every lead stage is a column');
        Map<String, Integer> tags = toMap(row.tagStages);
        System.assertEquals(1, tags.get('Active Partner'));
        System.assertEquals(1, tags.get('Prospect'), 'a blank stage counts as Prospect');
        System.assertEquals(1, toMap(row.loanStatuses).get('Waiting On Loan Officer'));

        Boolean sawLanding = false;
        for (LoWsOversightController.LandingLead l : result.landingLeads) {
            sawLanding |= l.name.contains('Landing') && l.takenOver == false && l.stage == 'New';
            System.assert(!l.name.contains('Nurture'), 'non-landing leads are not listed');
        }
        System.assert(sawLanding, 'the landing-page lead is listed');
        System.assertEquals(1, result.planChanges.size());
        System.assertEquals(byAlias('p8.lo').Id, result.planChanges[0].userId);
    }

    @IsTest
    static void internalToggleAddsInternalLoansOfficersOnly() {
        System.runAs(byAlias('p8.mgr')) {
            Integer outside = LoWsOversightController.getOverview(false).los.size();
            Integer internalLos = [SELECT COUNT() FROM User WHERE IsActive = true AND Profile.Name = 'Loan Officer Profile'
                AND (UserRole.DeveloperName = null OR UserRole.DeveloperName != 'External_Loan_Officer')];
            System.assertEquals(Math.min(25, outside + internalLos), LoWsOversightController.getOverview(true).los.size());
        }
    }

    @IsTest
    static void everyoneElseIsRefused() {
        System.runAs(byAlias('p8.nope')) {
            try {
                LoWsOversightController.getOverview(false);
                System.assert(false, 'expected a refusal');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    static Map<String, Integer> toMap(List<LoWsOversightController.StageCount> rows) {
        Map<String, Integer> m = new Map<String, Integer>();
        for (LoWsOversightController.StageCount c : rows) {
            m.put(c.label, c.value);
        }
        return m;
    }

    static User byAlias(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias.right(8)];
    }

    static User newUser(String alias, String profileName, String roleName) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName].Id,
            UserRoleId = roleName == null ? null : [SELECT Id FROM UserRole WHERE DeveloperName = :roleName].Id,
            Username = alias + suffix + '@reach-p8.test',
            Email = alias + '@reach-p8.test',
            LastName = alias,
            Alias = alias.right(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}