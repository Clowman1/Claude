@isTest
private class PerfectDayHomeBuilderTest {

    @isTest
    static void buildSummaryMetrics_coversEmptyAndOverdueStates() {
        List<Task> overdueTasks = new List<Task>{
            new Task(Subject = 'Old task', ActivityDate = Date.today().addDays(-4))
        };

        PerfectDayHomeModels.SummaryMetrics withWork = PerfectDayHomeBuilder.buildSummaryMetrics(
            40, 1, 4, overdueTasks, 3
        );
        PerfectDayHomeModels.SummaryMetrics allGoalsMet = PerfectDayHomeBuilder.buildSummaryMetrics(
            100, 4, 4, new List<Task>(), 0
        );

        System.assertEquals('Oldest overdue 4 days', withWork.overdueTasks.supportText);
        System.assertEquals('All daily goals met', allGoalsMet.goalsCompleted.supportText);
        System.assertEquals('No overdue tasks', allGoalsMet.overdueTasks.supportText);
    }

    @isTest
    static void buildPrioritiesAndUpNext_coverEveryQueue() {
        Lead newLead = new Lead(
            FirstName = 'New',
            LastName = 'Borrower',
            Phone = '2395550100',
            Email = 'new@example.com',
            LeadSource = 'Web'
        );
        Lead freshLead = new Lead(
            FirstName = 'Fresh',
            LastName = 'Borrower'
        );
        Lead expiredPreApproval = new Lead(
            FirstName = 'Expired',
            LastName = 'Credit',
            Credit_Expiration_Date__c = Date.today().addDays(-1)
        );
        Lead stagnantPreApproval = new Lead(
            FirstName = 'Stagnant',
            LastName = 'File',
            Credit_Expiration_Date__c = Date.today().addDays(20),
            Last_Call_Attempt_RingCentral__c = System.now().addDays(-10),
            Last_SMS_Attempt_RingCentral__c = System.now().addDays(-10)
        );
        Account dueRealtor = new Account(Name = 'Due Realtor');
        Account staleRealtor = new Account(Name = 'Stale Realtor');
        Map<Id, Datetime> lastTouch = new Map<Id, Datetime>();
        Transaction__c staleLoan = new Transaction__c(
            Name = 'Stale Loan',
            Status__c = 'Waiting On Loan Officer',
            Current_Status_Since__c = Date.today().addDays(-5)
        );
        Transaction__c freshLoan = new Transaction__c(
            Name = 'Fresh Loan',
            Status__c = 'Processing',
            Current_Status_Since__c = Date.today()
        );
        Task overdueTask = new Task(Subject = 'Overdue', ActivityDate = Date.today().addDays(-2));

        List<PerfectDayHomeModels.PriorityCategory> populated = PerfectDayHomeBuilder.buildPriorities(
            new List<Lead>{ newLead, freshLead },
            new List<Account>{ dueRealtor, staleRealtor },
            lastTouch,
            new List<Lead>{ expiredPreApproval, stagnantPreApproval },
            System.now().addDays(-6),
            new List<Transaction__c>{ staleLoan, freshLoan },
            new List<Task>{ overdueTask }
        );
        List<PerfectDayHomeModels.PriorityCategory> empty = PerfectDayHomeBuilder.buildPriorities(
            new List<Lead>(),
            new List<Account>(),
            lastTouch,
            new List<Lead>(),
            System.now().addDays(-6),
            new List<Transaction__c>(),
            new List<Task>()
        );

        System.assertEquals(5, populated.size());
        System.assertEquals('newLeads', populated[0].key);
        System.assertEquals('overdueTasks', populated[4].key);
        System.assertEquals('red', populated[4].urgency);
        System.assertEquals(5, empty.size());
        System.assertEquals(0, empty[0].count);

        PerfectDayHomeModels.UpNextItem leadItem = PerfectDayHomeBuilder.selectUpNextItem(
            new List<Lead>{ newLead },
            new List<Task>{ overdueTask },
            new List<Account>{ dueRealtor },
            new List<Lead>{ expiredPreApproval },
            new List<Transaction__c>{ staleLoan }
        );
        PerfectDayHomeModels.UpNextItem taskItem = PerfectDayHomeBuilder.selectUpNextItem(
            new List<Lead>(),
            new List<Task>{ overdueTask },
            new List<Account>{ dueRealtor },
            new List<Lead>{ expiredPreApproval },
            new List<Transaction__c>{ staleLoan }
        );
        PerfectDayHomeModels.UpNextItem realtorItem = PerfectDayHomeBuilder.selectUpNextItem(
            new List<Lead>(),
            new List<Task>(),
            new List<Account>{ dueRealtor },
            new List<Lead>{ expiredPreApproval },
            new List<Transaction__c>{ staleLoan }
        );
        PerfectDayHomeModels.UpNextItem preApprovalItem = PerfectDayHomeBuilder.selectUpNextItem(
            new List<Lead>(),
            new List<Task>(),
            new List<Account>(),
            new List<Lead>{ expiredPreApproval },
            new List<Transaction__c>{ staleLoan }
        );
        PerfectDayHomeModels.UpNextItem loanItem = PerfectDayHomeBuilder.selectUpNextItem(
            new List<Lead>(),
            new List<Task>(),
            new List<Account>(),
            new List<Lead>(),
            new List<Transaction__c>{ staleLoan }
        );
        PerfectDayHomeModels.UpNextItem noneItem = PerfectDayHomeBuilder.selectUpNextItem(
            new List<Lead>(),
            new List<Task>(),
            new List<Account>(),
            new List<Lead>(),
            new List<Transaction__c>()
        );

        System.assertEquals('Lead', leadItem.objectApiName);
        System.assertEquals('Task', taskItem.objectApiName);
        System.assertEquals('Account', realtorItem.objectApiName);
        System.assertEquals('Lead', preApprovalItem.objectApiName);
        System.assertEquals('preApprovals', preApprovalItem.categoryKey);
        System.assertEquals('Transaction__c', loanItem.objectApiName);
        System.assertEquals(null, noneItem);
    }

    @isTest
    static void buildGoalProgress_usesPlanRowsNotChannels() {
        ExternalLoActivityRollupBuilder.PeriodScore todayScore = new ExternalLoActivityRollupBuilder.PeriodScore();
        todayScore.totalCompleted = 5;
        todayScore.totalGoal = 13;
        todayScore.percent = 38;
        ExternalLoActivityRollupBuilder.CategoryScore row = new ExternalLoActivityRollupBuilder.CategoryScore();
        row.activityKey = 'realtor-outreach';
        row.shortLabel = 'Realtor outreach';
        row.completed = 5;
        row.goal = 4;
        row.percent = 100;
        todayScore.rows = new List<ExternalLoActivityRollupBuilder.CategoryScore>{ row };

        PerfectDayHomeModels.GoalProgress progress = PerfectDayHomeBuilder.buildGoalProgress(
            todayScore, todayScore, todayScore
        );

        System.assertEquals(5, progress.today.totalCompleted);
        System.assertEquals(13, progress.today.totalGoal);
        System.assertEquals(1, progress.today.rows.size());
        System.assertEquals('realtor-outreach', progress.today.rows[0].activityKey);
        System.assertEquals('Realtor outreach', progress.today.rows[0].label);
    }
}