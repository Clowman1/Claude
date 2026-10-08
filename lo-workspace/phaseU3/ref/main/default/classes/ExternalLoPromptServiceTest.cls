@isTest
private class ExternalLoPromptServiceTest {

    @isTest
    static void build_emitsOnePromptPerTriggerAndHonoursSnooze() {
        Id fakeLeadId = '00Q000000000001AAA';
        Id fakeLoanId = 'a0A000000000001AAA';
        Id fakeAccountId = '001000000000001AAA';

        Lead underContract = new Lead(Id = fakeLeadId, FirstName = 'Under', LastName = 'Contract', Company = 'UC');
        Transaction__c milestone = new Transaction__c(
            Name = 'Stale File',
            Status__c = 'Waiting On Loan Officer',
            Current_Status_Since__c = Date.today().addDays(-5)
        );
        Account partner = new Account(Name = 'Quiet Realtor');
        Lead pastClient = new Lead(Id = '00Q000000000002AAA', FirstName = 'Past', LastName = 'Client', Company = 'PC');
        Transaction__c funded = new Transaction__c(
            Name = 'Funded File',
            Funded_Date__c = Date.today().addMonths(-12)
        );

        ExternalLoPromptService.PromptContext context = new ExternalLoPromptService.PromptContext();
        context.underContractLeads = new List<Lead>{ underContract };
        context.milestoneLoans = new List<Transaction__c>{ milestone };
        context.realtorAccounts = new List<Account>{ partner };
        context.lastTouchByAccountId = new Map<Id, Datetime>();
        context.pastClientLeads = new List<Lead>{ pastClient };
        context.fundedLoans = new List<Transaction__c>{ funded };
        context.snoozedKeys = new Set<String>();

        Test.startTest();
        List<ExternalLoPromptService.PromptItem> openList = ExternalLoPromptService.build(context);
        context.snoozedKeys = new Set<String>{ 'under-contract:' + fakeLeadId };
        List<ExternalLoPromptService.PromptItem> snoozedList = ExternalLoPromptService.build(context);
        Test.stopTest();

        Set<String> types = new Set<String>();
        for (ExternalLoPromptService.PromptItem item : openList) {
            types.add(item.triggerType);
        }
        System.assert(types.contains('under-contract'), types);
        System.assert(types.contains('milestone'), types);
        System.assert(types.contains('recurring-partner'), types);
        System.assert(types.contains('past-client'), types);
        System.assert(types.contains('escrow-analysis'), types);

        Boolean stillHasUnderContract = false;
        for (ExternalLoPromptService.PromptItem item : snoozedList) {
            if (item.triggerType == 'under-contract') {
                stillHasUnderContract = true;
            }
        }
        System.assertEquals(false, stillHasUnderContract, 'An open prompt Task key must hide that prompt.');
    }

    @isTest
    static void getPrompts_returnsListForCurrentUser() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        System.runAs(importer) {
            Test.startTest();
            List<ExternalLoPromptService.PromptItem> items = ExternalLoPromptService.getPrompts(UserInfo.getUserId());
            Test.stopTest();
            System.assertNotEquals(null, items);
        }
    }

    @isTest
    static void suppressedKeys_foreverTriggersStayHiddenAfterComplete() {
        Date today = Date.today();
        List<Task> tasks = new List<Task>{
            closedPrompt('escrow-analysis:loan1', today.addYears(-1)),
            closedPrompt('past-client:lead1', today.addDays(-40)),
            closedPrompt('under-contract:lead2', today.addDays(-3))
        };
        Set<String> keys = ExternalLoPromptService.suppressedKeysFrom(tasks, today);
        System.assert(keys.contains('escrow-analysis:loan1'), keys);
        System.assert(keys.contains('past-client:lead1'), keys);
        System.assert(keys.contains('under-contract:lead2'), keys);
    }

    @isTest
    static void suppressedKeys_periodTriggersHideThisWeekOnly() {
        Date today = Date.today();
        Date thisWeek = ExternalLoGoalMath.weekStartMonday(today);
        Date lastWeek = thisWeek.addDays(-2);
        List<Task> tasks = new List<Task>{
            closedPrompt('milestone:loan1', thisWeek),
            closedPrompt('recurring-partner:acct1', today),
            closedPrompt('milestone:loan2', lastWeek),
            closedPrompt('recurring-partner:acct2', lastWeek)
        };
        Set<String> keys = ExternalLoPromptService.suppressedKeysFrom(tasks, today);
        System.assert(keys.contains('milestone:loan1'), keys);
        System.assert(keys.contains('recurring-partner:acct1'), keys);
        System.assertEquals(false, keys.contains('milestone:loan2'), keys);
        System.assertEquals(false, keys.contains('recurring-partner:acct2'), keys);
    }

    @isTest
    static void suppressedKeys_openSnoozeHidesEveryTrigger() {
        Date today = Date.today();
        Task snooze = new Task(
            Prompt_Key__c = 'milestone:open1',
            Status = 'Not Started',
            ActivityDate = today.addDays(1)
        );
        Set<String> keys = ExternalLoPromptService.suppressedKeysFrom(new List<Task>{ snooze }, today);
        System.assert(keys.contains('milestone:open1'), 'Open snooze Tasks still hide the prompt.');
    }

    private static Task closedPrompt(String promptKey, Date activityDate) {
        return new Task(
            Prompt_Key__c = promptKey,
            Status = 'Completed',
            ActivityDate = activityDate
        );
    }
}