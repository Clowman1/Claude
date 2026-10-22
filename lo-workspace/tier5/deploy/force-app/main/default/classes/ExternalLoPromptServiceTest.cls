@isTest
private class ExternalLoPromptServiceTest {

    @isTest
    static void build_emitsOnePromptPerTriggerAndHonoursSnooze() {
        Id fakeLoanId = 'a0A000000000001AAA';
        Id fakeAccountId = '001000000000001AAA';

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
        context.milestoneLoans = new List<Transaction__c>{ milestone };
        context.realtorAccounts = new List<Account>{ partner };
        context.lastTouchByAccountId = new Map<Id, Datetime>();
        context.pastClientLeads = new List<Lead>{ pastClient };
        context.fundedLoans = new List<Transaction__c>{ funded };
        context.snoozedKeys = new Set<String>();

        Test.startTest();
        List<ExternalLoPromptService.PromptItem> openList = ExternalLoPromptService.build(context);
        context.snoozedKeys = new Set<String>{ 'past-client:' + pastClient.Id };
        List<ExternalLoPromptService.PromptItem> snoozedList = ExternalLoPromptService.build(context);
        Test.stopTest();

        Set<String> types = new Set<String>();
        for (ExternalLoPromptService.PromptItem item : openList) {
            types.add(item.triggerType);
        }
        // LO Workspace has no Under Contract status, so there is no under-contract prompt (2026-10-14).
        System.assert(!types.contains('under-contract'), types);
        System.assert(types.contains('milestone'), types);
        System.assert(types.contains('recurring-partner'), types);
        System.assert(types.contains('past-client'), types);
        System.assert(types.contains('escrow-analysis'), types);

        Boolean stillHasPastClient = false;
        for (ExternalLoPromptService.PromptItem item : snoozedList) {
            if (item.triggerType == 'past-client') {
                stillHasPastClient = true;
            }
        }
        System.assertEquals(false, stillHasPastClient, 'An open prompt Task key must hide that prompt.');
    }

    @isTest
    static void getAllUpNext_groupsOverdueTasksAndUpcomingItems() {
        Id me = UserInfo.getUserId();
        insert new List<Task>{
            new Task(OwnerId = me, Subject = 'Late', Status = 'Open', ActivityDate = Date.today().addDays(-2)),
            new Task(OwnerId = me, Subject = 'Soon', Status = 'Open', ActivityDate = Date.today().addDays(1))
        };
        Datetime start = System.now().addDays(1);
        insert new Event(OwnerId = me, Subject = 'Coffee', StartDateTime = start, EndDateTime = start.addHours(1));

        Test.startTest();
        List<ExternalLoPromptService.PromptItem> rows = ExternalLoPromptService.getAllUpNext(me);
        Test.stopTest();

        Set<String> groups = new Set<String>();
        for (ExternalLoPromptService.PromptItem row : rows) {
            groups.add(row.upNextGroup + ':' + row.kind);
            System.assertEquals(false, row.canLog, 'Open all rows are read-only');
            System.assertNotEquals('under-contract', row.triggerType);
        }
        System.assert(groups.contains('overdue:task'), groups);
        System.assert(groups.contains('upcoming:task'), groups);
        System.assert(groups.contains('upcoming:appt'), groups);
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
        tasks.add(closedPrompt('anniversary:acct1:' + today.year(), today.addDays(-200)));
        Set<String> keys = ExternalLoPromptService.suppressedKeysFrom(tasks, today);
        System.assert(keys.contains('anniversary:acct1:' + today.year()), keys);
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

    @isTest
    static void anniversaryPrompts_fireFromSevenDaysBeforeUntilTheDayNeverAfter() {
        Date today = Date.newInstance(2026, 10, 21);
        Id a = '001000000000001AAA';
        Id b = '001000000000002AAA';
        Id c = '001000000000003AAA';
        Id d = '001000000000004AAA';
        Id e = '001000000000005AAA';
        List<Transaction__c> loans = new List<Transaction__c>{
            new Transaction__c(Name = 'In 7 days', Borrower_Name__c = a, Funding_Date__c = Date.newInstance(2025, 10, 28)),
            new Transaction__c(Name = 'In 8 days', Borrower_Name__c = b, Funding_Date__c = Date.newInstance(2025, 10, 29)),
            new Transaction__c(Name = 'Yesterday', Borrower_Name__c = c, Funding_Date__c = Date.newInstance(2025, 10, 20)),
            // No funding date: falls back to the closing date; two years today.
            new Transaction__c(Name = 'Today', Borrower_Name__c = d, Closing_Date__c = Date.newInstance(2024, 10, 21)),
            // Funding this week: no anniversary yet.
            new Transaction__c(Name = 'Just funded', Borrower_Name__c = e, Funding_Date__c = Date.newInstance(2026, 10, 25))
        };

        List<ExternalLoPromptService.PromptItem> items = ExternalLoPromptService.anniversaryPrompts(loans, new Set<String>(), today);
        Set<String> keys = new Set<String>();
        for (ExternalLoPromptService.PromptItem item : items) {
            keys.add(item.promptKey);
            System.assertEquals('anniversary', item.triggerType);
            System.assertEquals(true, item.canSnooze);
        }
        System.assertEquals(new Set<String>{ 'anniversary:' + a + ':2026', 'anniversary:' + d + ':2026' }, keys);

        // Snoozed (or logged) for this year: hidden.
        items = ExternalLoPromptService.anniversaryPrompts(loans, new Set<String>{ 'anniversary:' + a + ':2026' }, today);
        System.assertEquals(1, items.size());

        // Year end: a January anniversary shows in late December, keyed to next year.
        items = ExternalLoPromptService.anniversaryPrompts(
            new List<Transaction__c>{ new Transaction__c(Name = 'New year', Borrower_Name__c = a, Funding_Date__c = Date.newInstance(2025, 1, 2)) },
            new Set<String>(), Date.newInstance(2026, 12, 28));
        System.assertEquals(1, items.size());
        System.assertEquals('anniversary:' + a + ':2027', items[0].promptKey);
    }

    private static Task closedPrompt(String promptKey, Date activityDate) {
        return new Task(
            Prompt_Key__c = promptKey,
            Status = 'Completed',
            ActivityDate = activityDate
        );
    }
}