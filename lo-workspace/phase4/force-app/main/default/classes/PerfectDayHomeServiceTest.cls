@isTest
private class PerfectDayHomeServiceTest {

    private static User getTestUser() {
        return ExternalLoPortalTestHelper.currentUser();
    }

    private static User getEmptyUser() {
        return [SELECT Id, Name FROM User WHERE Alias = 'pdempty' LIMIT 1];
    }

    private static void applyCompanyBaseline() {
        ExternalLOBaselineHelper.baselineOverride = new External_LO_Baseline__mdt(
            Calls_Daily_Goal__c = 2,
            Texts_Daily_Goal__c = 2,
            Emails_Daily_Goal__c = 2,
            Meetings_Daily_Goal__c = 1,
            Open_House_Daily_Goal__c = 1,
            Weekly_Multiplier__c = 5,
            Monthly_Multiplier__c = 20
        );
    }

    private static User buildUser(String alias, String lastName) {
        return new User(
            Alias = alias,
            FirstName = 'Perfect',
            Email = alias + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            UserName = alias + DateTime.now().getTime() + '@example.com'
        );
    }

    @testSetup
    static void setupData() {
        User emptyUser = buildUser('pdempty', 'EmptyDay');
        insert emptyUser;
        ExternalLoPortalTestHelper.grantPortalAccess(UserInfo.getUserId());
        ExternalLoPortalTestHelper.grantPortalAccess(emptyUser.Id);

        // The running admin's User row is shared across the org, so a real
        // wizard save leaves personal goals on it and applyUserGoals then
        // overlays them. Clear them here (setup context, rolled back after the
        // run) so the baseline assertions test the company default.
        update new User(
            Id = UserInfo.getUserId(),
            External_LO_Onboarding_Complete__c = false,
            Calls_Daily_Goal__c = null,
            Texts_Daily_Goal__c = null,
            Emails_Daily_Goal__c = null,
            Meetings_Daily_Goal__c = null,
            Open_House_Daily_Goal__c = null,
            ExtLO_Workdays_Per_Week__c = null
        );

        User testUser = ExternalLoPortalTestHelper.currentUser();
        System.runAs(testUser) {
            Id consumerLeadRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                  AND DeveloperName = 'Consumer_Lead_record_type'
                LIMIT 1
            ].Id;

            insert new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                FirstName = 'New',
                LastName = 'Lead',
                Company = 'New Lead Co',
                Status = 'New',
                Email = 'new.lead@example.com'
            );

            insert new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                FirstName = 'Pre',
                LastName = 'Approval',
                Company = 'Pre Approval Co',
                Status = 'Pre-Approval',
                Email = 'pre.approval@example.com',
                Loan_Amount__c = 250000,
                Pre_Approval_Date__c = Date.today().addDays(-10)
            );

            insert new Transaction__c(
                Name = 'Milestone Loan',
                Loan_Officer__c = testUser.Id,
                Status__c = 'Waiting On Loan Officer',
                Current_Status_Since__c = Date.today().addDays(-5)
            );

            insert new Task(
                Subject = 'Overdue follow-up',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(-2),
                Priority = 'High'
            );

            insert new Task(
                Subject = 'Completed call',
                Status = 'Completed',
                ActivityDate = Date.today(),
                Activity_Type__c = 'Call - Active Agent'
            );
        }
    }

    @isTest
    static void getHomeData_returnsPersonalizedWorkspace() {
        User testUser = getTestUser();
        applyCompanyBaseline();
        // Early morning: one completed activity against an 8-goal baseline is still on track.
        ExternalLOBaselineHelper.nowOverride = Datetime.newInstance(Date.today(), Time.newInstance(8, 0, 0, 0));

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            Test.stopTest();

            System.assertNotEquals(null, homeData, 'Home data should be returned.');
            System.assertEquals(
                testUser.Name.trim().split('\\s+')[0],
                homeData.userFirstName,
                'First name should be extracted.'
            );
            System.assertEquals(
                homeData.todayPlan.size(),
                homeData.goalProgress.today.rows.size(),
                'Goal Progress rows must come from the activity plan, not channel goals.'
            );
            System.assert(homeData.goalProgress.today.totalGoal > 0, 'Plan daily totals should be configured.');
            System.assert(homeData.goalProgress.thisWeek.totalGoal > 0, 'Weekly totals come from the plan.');
            System.assertEquals(1, homeData.goalProgress.today.totalCompleted,
                'Today\'s completed call should count toward the daily score.');
            System.assertEquals('On pace', homeData.paceStatus, 'Pace should be on track at 8:00 AM.');
            System.assertNotEquals(null, homeData.summaryMetrics, 'Summary metrics should be present.');
            System.assertEquals(1, homeData.summaryMetrics.overdueTasks.value, 'One overdue task should be counted.');
            System.assertEquals(5, homeData.priorities.size(), 'All priority categories should be returned.');
            System.assertEquals('newLeads', homeData.priorities[0].key, 'New leads should rank first.');
            System.assertEquals('overdueTasks', homeData.priorities[4].key, 'Overdue tasks should rank last.');
            System.assertEquals('red', homeData.priorities[4].urgency, 'Overdue tasks are always red.');
            System.assertNotEquals(null, homeData.upNext, 'Up Next should identify competing work.');
            System.assertEquals('Lead', homeData.upNext.objectApiName, 'New leads should rank first for Up Next.');
            System.assertEquals(true, homeData.upNext.canLogOutcome, 'A lead Up Next supports logging.');
        }
    }

    @isTest
    static void getHomeData_behindPaceWhenNothingLoggedLateInDay() {
        User emptyUser = getEmptyUser();
        applyCompanyBaseline();
        ExternalLOBaselineHelper.nowOverride = Datetime.newInstance(Date.today(), Time.newInstance(16, 0, 0, 0));

        System.runAs(emptyUser) {
            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            Test.stopTest();

            System.assertEquals('Behind pace', homeData.paceStatus,
                'Nothing logged at 4 PM should read as behind pace.');
            System.assertEquals(0, homeData.dailyCompletionPercent, 'Completion should be zero.');
        }
    }

    @isTest
    static void getHomeData_emptyWorkloadStillRendersUsableState() {
        User emptyUser = getEmptyUser();
        applyCompanyBaseline();

        System.runAs(emptyUser) {
            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            Test.stopTest();

            System.assertEquals(5, homeData.priorities.size(), 'Empty workload still returns every category.');
            for (PerfectDayHomeModels.PriorityCategory category : homeData.priorities) {
                System.assertEquals(0, category.count, 'Counts should be zero with no work.');
                System.assert(String.isNotBlank(category.emptyStateMessage),
                    'Each empty category needs a usable empty-state message.');
            }
            System.assertEquals(null, homeData.upNext, 'No work means no Up Next recommendation.');
            System.assert(homeData.goalProgress.today.totalGoal > 0,
                'Plan goals apply even before any records exist.');
        }
    }

    @isTest
    static void getHomeData_bulkWorkloadStaysWithinGovernorLimits() {
        User testUser = getTestUser();
        applyCompanyBaseline();

        System.runAs(testUser) {
            Id consumerLeadRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                  AND DeveloperName = 'Consumer_Lead_record_type'
                LIMIT 1
            ].Id;

            List<Lead> bulkLeads = new List<Lead>();
            for (Integer i = 0; i < 200; i++) {
                bulkLeads.add(new Lead(
                    RecordTypeId = consumerLeadRecordTypeId,
                    FirstName = 'Bulk',
                    LastName = 'Lead ' + i,
                    Company = 'Bulk Co',
                    Status = 'New',
                    Email = 'bulk.lead' + i + '@example.com'
                ));
            }
            insert bulkLeads;

            List<Task> bulkTasks = new List<Task>();
            for (Integer i = 0; i < 200; i++) {
                bulkTasks.add(new Task(
                    Subject = 'Bulk overdue ' + i,
                    Status = 'Not Started',
                    ActivityDate = Date.today().addDays(-1 - Math.mod(i, 5))
                ));
            }
            insert bulkTasks;

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            Integer queriesUsed = Limits.getQueries() - queriesBefore;
            Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();

            System.assert(queriesUsed <= 16,
                'getHomeData must stay flat regardless of record volume; used ' + queriesUsed + ' queries.');
            System.assertEquals(0, dmlUsed, 'The homepage read must not perform DML.');
            System.assertEquals(201, homeData.priorities[0].count,
                'All 201 new leads should be counted.');
            System.assertEquals(201, homeData.summaryMetrics.overdueTasks.value,
                'All 201 overdue tasks should be counted.');
        }
    }

    @isTest
    static void deferAndCompleteUpNextItem_updateRecords() {
        User testUser = getTestUser();
        Task overdueTask = [
            SELECT Id
            FROM Task
            WHERE OwnerId = :testUser.Id
              AND IsClosed = false
              AND ActivityDate < TODAY
            LIMIT 1
        ];
        Lead newLead = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeService.deferUpNextItem(newLead.Id, 'Lead');
            PerfectDayHomeService.completeUpNextItem(overdueTask.Id, 'Task');
            Test.stopTest();

            Lead refreshedLead = [SELECT Appointment_Date_Time__c FROM Lead WHERE Id = :newLead.Id];
            Task refreshedTask = [SELECT Status, ActivityDate FROM Task WHERE Id = :overdueTask.Id];

            System.assertEquals(
                Datetime.newInstance(Date.today().addDays(1), Time.newInstance(9, 0, 0, 0)),
                refreshedLead.Appointment_Date_Time__c,
                'Deferred lead should get a 9 AM follow-up tomorrow.'
            );
            System.assertEquals('Completed', refreshedTask.Status, 'Overdue task should be marked complete.');
            System.assertEquals(Date.today(), refreshedTask.ActivityDate,
                'Completion should count toward today\'s activity window.');

            // A deferred lead leaves the new-lead queue until its follow-up time passes.
            applyCompanyBaseline();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            System.assertEquals(0, homeData.priorities[0].count,
                'A deferred lead should not be counted as needing contact.');
        }
    }

    @isTest
    static void deferUpNextItem_supportsShorterWindows() {
        User testUser = getTestUser();
        Lead newLead = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeService.deferUpNextItem(newLead.Id, 'Lead', 'hour');
            Test.stopTest();

            Lead refreshedLead = [SELECT Appointment_Date_Time__c FROM Lead WHERE Id = :newLead.Id];
            System.assert(refreshedLead.Appointment_Date_Time__c > System.now(),
                'A one-hour defer should schedule the return in the future.');
            System.assert(refreshedLead.Appointment_Date_Time__c <= System.now().addHours(2),
                'A one-hour defer should stay within the short window.');
        }
    }

    @isTest
    static void deferUnsupportedObject_throwsDomainException() {
        User testUser = getTestUser();
        Transaction__c loanRecord = [SELECT Id FROM Transaction__c LIMIT 1];

        System.runAs(testUser) {
            try {
                PerfectDayHomeService.deferUpNextItem(loanRecord.Id, 'Transaction__c');
                System.assert(false, 'Deferring a loan should throw.');
            } catch (DomainException expectedError) {
                System.assert(expectedError.getMessage().contains('cannot be deferred'),
                    'Error should explain the record type is not deferrable.');
            }
        }
    }

    @isTest
    static void completeSomeoneElsesTask_throwsDomainException() {
        User testUser = getTestUser();
        User emptyUser = getEmptyUser();
        Task foreignTask;
        System.runAs(emptyUser) {
            foreignTask = new Task(
                Subject = 'Foreign task',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(-1)
            );
            insert foreignTask;
        }

        System.runAs(testUser) {
            try {
                PerfectDayHomeService.completeUpNextItem(foreignTask.Id, 'Task');
                System.assert(false, 'Completing another user\'s task should throw.');
            } catch (DomainException expectedError) {
                System.assert(expectedError.getMessage().contains('not visible'),
                    'Error should not reveal more than visibility.');
            }
        }
    }

    @isTest
    static void controller_wrapsServiceResultsAndErrors() {
        User testUser = getTestUser();
        applyCompanyBaseline();

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeController.getPerfectDayHomeData(null);
            try {
                PerfectDayHomeController.deferUpNextItem(null, null, null);
                System.assert(false, 'Missing arguments should throw.');
            } catch (AuraHandledException expectedError) {
                System.assertNotEquals(null, expectedError.getMessage(),
                    'Domain errors should surface as Aura messages.');
            }
            try {
                PerfectDayHomeController.completeUpNextItem(null, 'Task');
                System.assert(false, 'Missing complete arguments should throw.');
            } catch (AuraHandledException expectedError) {
                System.assertNotEquals(null, expectedError.getMessage());
            }
            AuraHandledException domainWrapped = PerfectDayHomeController.toAura(
                new DomainException('Your user profile could not be loaded.'),
                'Unable to load Perfect Day. Please try again.'
            );
            System.assert(domainWrapped.getMessage().contains('profile'));
            AuraHandledException genericWrapped = PerfectDayHomeController.toAura(
                new CalloutException('hidden'),
                'Unable to load Perfect Day. Please try again.'
            );
            System.assert(genericWrapped.getMessage().contains('Perfect Day'));
            Test.stopTest();

            System.assertEquals(5, homeData.priorities.size(), 'Controller should return priority categories.');
        }
    }

    @isTest
    static void controller_deferAndComplete_updateRecords() {
        User testUser = getTestUser();
        Task overdueTask = [
            SELECT Id
            FROM Task
            WHERE OwnerId = :testUser.Id
              AND IsClosed = false
              AND ActivityDate < TODAY
            LIMIT 1
        ];
        Lead newLead = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeController.deferUpNextItem(newLead.Id, 'Lead', 'afternoon');
            PerfectDayHomeController.completeUpNextItem(overdueTask.Id, 'Task');
            Test.stopTest();

            Lead refreshedLead = [SELECT Appointment_Date_Time__c FROM Lead WHERE Id = :newLead.Id];
            Task refreshedTask = [SELECT Status FROM Task WHERE Id = :overdueTask.Id];
            System.assertNotEquals(null, refreshedLead.Appointment_Date_Time__c);
            System.assertEquals('Completed', refreshedTask.Status);
        }
    }

    @isTest
    static void completeUpNextItem_rejectsNonTasksAndClosedTasks() {
        User testUser = getTestUser();
        Lead newLead = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];
        Task completedTask = [
            SELECT Id
            FROM Task
            WHERE OwnerId = :testUser.Id
              AND Status = 'Completed'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Boolean nonTaskBlocked = false;
            try {
                PerfectDayHomeService.completeUpNextItem(newLead.Id, 'Lead');
            } catch (DomainException expectedError) {
                nonTaskBlocked = expectedError.getMessage().contains('overdue tasks');
            }
            PerfectDayHomeService.completeUpNextItem(completedTask.Id, 'Task');
            System.assert(nonTaskBlocked, 'Only tasks can be completed from Perfect Day.');
        }
    }

    @isTest
    static void deferUpNextItem_supportsTaskAndAfternoonWindows() {
        User testUser = getTestUser();
        Task overdueTask = [
            SELECT Id
            FROM Task
            WHERE OwnerId = :testUser.Id
              AND IsClosed = false
              AND ActivityDate < TODAY
            LIMIT 1
        ];
        Lead newLead = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeService.deferUpNextItem(overdueTask.Id, 'Task');
            PerfectDayHomeService.deferUpNextItem(newLead.Id, 'Lead', 'afternoon');
            Test.stopTest();

            Task refreshedTask = [SELECT ActivityDate FROM Task WHERE Id = :overdueTask.Id];
            Lead refreshedLead = [SELECT Appointment_Date_Time__c FROM Lead WHERE Id = :newLead.Id];
            System.assertEquals(Date.today().addDays(1), refreshedTask.ActivityDate);
            System.assertNotEquals(null, refreshedLead.Appointment_Date_Time__c);
        }
    }

    @isTest
    static void controller_completeUnexpectedError_wrapsMessage() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Boolean wrapped = false;
            try {
                PerfectDayHomeController.completeUpNextItem(null, 'Task');
            } catch (AuraHandledException expectedError) {
                wrapped = true;
            }
            System.assert(wrapped, 'Controller should wrap complete errors.');
        }
    }

    @isTest
    static void getHomeData_returnsTodayPlanForEveryActiveCategory() {
        User testUser = getTestUser();
        applyCompanyBaseline();

        System.runAs(testUser) {
            insert new Task(
                Subject = 'Prospect blitz',
                Status = 'Completed',
                ActivityDate = Date.today(),
                Activity_Type__c = 'Call - Prospecting',
                Activity_Category__c = 'Realtor_Outreach',
                Activity_Count__c = 3
            );

            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            Test.stopTest();

            System.assertNotEquals(null, homeData.todayPlan, 'Today plan drives the prototype homepage.');
            System.assertEquals(
                ExternalLoActivityCatalog.activities().size(),
                homeData.todayPlan.size(),
                'One row per active activity category.'
            );
            System.assertEquals(
                homeData.todayPlan.size(),
                homeData.goalsTotal,
                'goalsTotal must come from the category plan, not the legacy channel goals.'
            );

            ExternalLoActivityRollupBuilder.CategoryScore outreach;
            for (ExternalLoActivityRollupBuilder.CategoryScore row : homeData.todayPlan) {
                if (row.activityKey == 'realtor-outreach') {
                    outreach = row;
                }
                System.assertNotEquals(null, row.shortLabel, 'Each row carries catalog presentation data.');
                System.assertNotEquals(null, row.goal, 'Each row carries a daily goal.');
            }

            System.assertNotEquals(null, outreach, 'Realtor outreach must be present in the plan.');
            System.assert(
                outreach.completed >= 3,
                'Activity_Count__c must credit 3 touches from a single Task; got ' + outreach.completed
            );
        }
    }

    @isTest
    static void getHomeData_returnsRecentLogWithCatalogLabelAndCount() {
        User testUser = getTestUser();
        applyCompanyBaseline();

        System.runAs(testUser) {
            insert new Task(
                Subject = 'Coffee with a new agent',
                Status = 'Completed',
                ActivityDate = Date.today(),
                Activity_Type__c = 'Meeting (New Agent)',
                Activity_Category__c = 'Partner_Meeting',
                Activity_Count__c = 2,
                Description = 'Agreed to co-host an open house.'
            );

            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            Test.stopTest();

            System.assertNotEquals(null, homeData.recentLog, 'Recent log must be part of the payload.');
            System.assertNotEquals(0, homeData.recentLog.size(), 'A completed activity should appear in the log.');
            System.assert(homeData.recentLog.size() <= 8, 'Recent log is clipped to 8 entries.');

            PerfectDayHomeModels.RecentLogEntry meeting;
            for (PerfectDayHomeModels.RecentLogEntry entry : homeData.recentLog) {
                if (entry.activityKey == 'partner-meeting') {
                    meeting = entry;
                }
            }

            System.assertNotEquals(null, meeting, 'The categorized Task should resolve to its activity key.');
            System.assertEquals(2, meeting.activityCount, 'Recent log reports the logged count, not the row count.');
            System.assertEquals(
                ExternalLoActivityCatalog.activityByKey('partner-meeting').shortLabel,
                meeting.shortLabel,
                'Short label comes from the activity catalog.'
            );
            System.assertEquals('Agreed to co-host an open house.', meeting.notes, 'Notes carry through.');
            System.assertNotEquals(null, meeting.activityDateLabel, 'Recent log rows render a date.');
        }
    }

    @isTest
    static void getHomeData_returnsPromptsAndHonoursSnooze() {
        User testUser = getTestUser();
        applyCompanyBaseline();

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData before = PerfectDayHomeService.getHomeData();

            System.assertNotEquals(null, before.prompts, 'Prompts replace the single Up Next item.');
            System.assertNotEquals(0, before.prompts.size(), 'The stale milestone loan should raise a prompt.');
            System.assert(before.prompts.size() <= 8, 'Prompts are capped.');

            ExternalLoPromptService.PromptItem milestone;
            for (ExternalLoPromptService.PromptItem item : before.prompts) {
                System.assertNotEquals(null, item.promptKey, 'Every prompt needs a stable key to snooze against.');
                System.assertNotEquals(null, item.title, 'Every prompt renders a title.');
                if (item.triggerType == 'milestone') {
                    milestone = item;
                }
            }
            System.assertNotEquals(null, milestone, 'A loan waiting on the officer should surface a milestone prompt.');

            ExternalLoActivityLogService.snoozePrompt(
                milestone.promptKey,
                milestone.recordId,
                milestone.objectApiName
            );

            PerfectDayHomeModels.PerfectDayHomeData afterSnooze = PerfectDayHomeService.getHomeData();
            Test.stopTest();

            for (ExternalLoPromptService.PromptItem item : afterSnooze.prompts) {
                System.assertNotEquals(
                    milestone.promptKey,
                    item.promptKey,
                    'A snoozed prompt must stay hidden until its open Task comes due.'
                );
            }
        }
    }

    @isTest
    static void getHomeData_keepsUpNextAndPrioritiesForRollback() {
        User testUser = getTestUser();
        applyCompanyBaseline();

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            Test.stopTest();

            System.assertNotEquals(
                null,
                homeData.upNext,
                'upNext stays populated so the LWC can roll back independently of Apex.'
            );
            System.assertNotEquals(null, homeData.priorities, 'Pipeline priorities remain as a secondary strip.');
        }
    }
}