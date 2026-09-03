@IsTest
private class HomeToolsControllerTest {
    @IsTest
    static void getHomeToolsDataReturnsLists() {
        Test.startTest();
        HomeToolsController.HomeToolsData data = HomeToolsController.getHomeToolsData();
        Test.stopTest();

        System.assertNotEquals(null, data, 'Expected home tools data.');
        System.assertNotEquals(null, data.events, 'Expected event list.');
        System.assertNotEquals(null, data.recentRecords, 'Expected recent record list.');
    }

    @IsTest
    static void getHomeToolsDataReturnsStandardLoanOfficerTrackers() {
        User loanOfficer = testUser('Tracker', 'Waters', 'Loan Officer');

        System.runAs(loanOfficer) {
            Test.startTest();
            HomeToolsController.HomeToolsData data = HomeToolsController.getHomeToolsData();
            Test.stopTest();

            System.assertEquals(5, data.trackers.size(), 'Standard loan officers should receive five tracker cards.');
            System.assertEquals('Active Pre-Approvals', data.trackers[0].label);
            System.assertEquals('Work Done, money on the table', data.trackers[0].helperText);
            System.assertNotEquals(null, data.weeklyLeadTracker, 'Loan Officers should receive the weekly lead tracker.');
            System.assertEquals(0, data.weeklyLeadTracker.lastWeek);
            System.assertEquals(0, data.weeklyLeadTracker.thisWeek);
            System.assertEquals(Decimal.valueOf(0), data.weeklyLeadTracker.rollingTwelveMonthWeeklyAverage);
        }
    }

    @IsTest
    static void productionTrackersExcludeDpaSecondLoanTypes() {
        User loanOfficer = testUser('Martin', 'Rebagliati', 'Loan Officer');
        Date todayDate = Date.today();
        Date closeDate = Date.newInstance(todayDate.year(), todayDate.month(), Math.min(15, Date.daysInMonth(todayDate.year(), todayDate.month())));
        insert new List<Transaction__c>{
            new Transaction__c(
                Name = 'Included Production File',
                Loan_Officer__c = loanOfficer.Id,
                Status__c = 'Post-Closed',
                Closing_Date__c = closeDate,
                Loan_Amount_1st__c = 100000,
                Loan_Type_1st_TD__c = 'Conventional'
            ),
            new Transaction__c(
                Name = 'Excluded DPA Second File',
                Loan_Officer__c = loanOfficer.Id,
                Status__c = 'Post-Closed',
                Closing_Date__c = closeDate,
                Loan_Amount_1st__c = 50000,
                Loan_Type_1st_TD__c = 'DPA 2nd'
            )
        };

        System.runAs(loanOfficer) {
            Test.startTest();
            HomeToolsController.HomeToolsData data = HomeToolsController.getHomeToolsData();
            Test.stopTest();

            System.assertEquals(1, data.trackers[2].units, 'House MTD production should exclude DPA 2nd transactions.');
            System.assertEquals(100000, data.trackers[2].volume, 'House MTD production volume should exclude DPA 2nd transactions.');
        }
    }

    @IsTest
    static void getHomeToolsDataReturnsJosephCareyExceptionTrackers() {
        User josephCarey = testUser('Joseph', 'Carey', 'Loan Officer');

        System.runAs(josephCarey) {
            Test.startTest();
            HomeToolsController.HomeToolsData data = HomeToolsController.getHomeToolsData();
            Test.stopTest();

            System.assertEquals(2, data.trackers.size(), 'Joseph Carey should only receive the two personal production tracker cards.');
            System.assertEquals('Personal Deals Closed This Month', data.trackers[0].label);
            System.assertEquals('Personal Deals Closed This Year', data.trackers[1].label);
        }
    }

    @IsTest
    static void loanPartnerGetsDailyChecklistAndCanManageItems() {
        User loanPartner = testUser('Joey', 'D\'Alessandro', 'Loan Partner');
        Lead checklistLead = new Lead(
            LastName = 'Checklist Lead',
            Company = 'Reach Home Loans',
            OwnerId = loanPartner.Id
        );
        insert checklistLead;
        // A Lead-linked item created before the lookup was dropped, so both shapes are covered.
        Task pastDueItem = new Task(
            Subject = 'Daily Checklist: Follow up on prior-day item.',
            Description = 'Follow up on prior-day item.',
            OwnerId = loanPartner.Id,
            WhoId = checklistLead.Id,
            Priority = 'Low',
            Status = 'Not Started',
            ActivityDate = Date.today().addDays(-1)
        );
        insert pastDueItem;

        System.runAs(loanPartner) {
            Test.startTest();
            HomeToolsController.HomeToolsData initialData = HomeToolsController.getHomeToolsData();
            HomeToolsController.DailyChecklistItem highItem = HomeToolsController.addDailyChecklistItem(
                'Walk-in Borrower',
                'Call borrower about missing income documents.',
                'High'
            );
            HomeToolsController.DailyChecklistItem lowItem = HomeToolsController.addDailyChecklistItem(
                'Walk-in Borrower',
                'Review notes after the call.',
                'Low'
            );
            HomeToolsController.HomeToolsData data = HomeToolsController.getHomeToolsData();
            HomeToolsController.completeDailyChecklistItem(highItem.id);
            HomeToolsController.HomeToolsData afterComplete = HomeToolsController.getHomeToolsData();
            List<HomeToolsController.ClearedDailyChecklistItem> clearedItems = HomeToolsController.getClearedDailyChecklistItems();
            Test.stopTest();

            System.assertEquals(true, initialData.isLoanPartnerChecklistUser);
            System.assertEquals(0, initialData.trackers.size(), 'Loan Partners should not receive production trackers.');
            System.assertEquals(null, initialData.weeklyLeadTracker, 'Loan Partners should not receive weekly lead tracking.');
            System.assertEquals(3, data.dailyChecklistItems.size());
            System.assertEquals(pastDueItem.Id, data.dailyChecklistItems[0].id, 'Past-day items should come before High priority items.');
            System.assertEquals(true, data.dailyChecklistItems[0].isPastDue);
            System.assertEquals('High', data.dailyChecklistItems[0].priority, 'A carried-over item should report as High, not its stored Low.');
            System.assertEquals('Checklist Lead', data.dailyChecklistItems[0].leadName, 'A legacy Lead-linked item should still show the Lead name.');
            System.assertEquals('High', data.dailyChecklistItems[1].priority, 'High priority items should follow catch-up items.');
            System.assertEquals(null, data.dailyChecklistItems[1].leadId, 'Free-text items should not be linked to a Lead.');
            System.assertEquals('Walk-in Borrower', data.dailyChecklistItems[1].leadName);
            System.assertEquals('Call borrower about missing income documents.', data.dailyChecklistItems[1].description);
            System.assertEquals('Low', data.dailyChecklistItems[2].priority);
            System.assertEquals(pastDueItem.Id, afterComplete.dailyChecklistItems[0].id, 'Completing an item should retain the prior-day catch-up item.');
            System.assertEquals(lowItem.id, afterComplete.dailyChecklistItems[1].id, 'Completing an item should remove it from the open checklist.');
            System.assertEquals(1, clearedItems.size(), 'The completed item should be available in the two-day look-back view.');
            System.assertEquals(highItem.id, clearedItems[0].id);
            System.assertEquals('Walk-in Borrower', clearedItems[0].leadName);
        }
    }

    @IsTest
    static void addingAChecklistItemWithoutALeadNameIsRejected() {
        User loanPartner = testUser('Joey', 'D\'Alessandro', 'Loan Partner');

        System.runAs(loanPartner) {
            try {
                HomeToolsController.addDailyChecklistItem('   ', 'Something to do.', 'High');
                System.assert(false, 'A blank Lead name should be rejected.');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e, 'A blank Lead name should raise an AuraHandledException.');
            }
        }
    }

    @IsTest
    static void editingAChecklistItemRewritesTheLeadName() {
        User loanPartner = testUser('Joey', 'D\'Alessandro', 'Loan Partner');
        Lead checklistLead = new Lead(
            LastName = 'Checklist Lead',
            Company = 'Reach Home Loans',
            OwnerId = loanPartner.Id
        );
        insert checklistLead;
        Task legacyItem = new Task(
            Subject = 'Daily Checklist: Follow up.',
            Description = 'Follow up.',
            OwnerId = loanPartner.Id,
            WhoId = checklistLead.Id,
            Priority = 'Normal',
            Status = 'Not Started',
            ActivityDate = Date.today()
        );
        insert legacyItem;

        System.runAs(loanPartner) {
            Test.startTest();
            HomeToolsController.DailyChecklistItem edited = HomeToolsController.updateDailyChecklistItem(
                legacyItem.Id,
                'Renamed Borrower',
                'Follow up again.',
                'High'
            );
            Test.stopTest();

            System.assertEquals('Renamed Borrower', edited.leadName);
            System.assertEquals('Follow up again.', edited.description);
            System.assertEquals('High', edited.priority);
        }
    }

    @IsTest
    static void draggingAnItemStoresBothTheNewPositionAndPriority() {
        User todoUser = testUserWithEmail('Christopher', 'Lowman', 'clowman@reachhomeloans.com');

        System.runAs(todoUser) {
            HomeToolsController.RunningTodoItem first = HomeToolsController.addRunningTodoItem('First item.', 'High');
            HomeToolsController.RunningTodoItem second = HomeToolsController.addRunningTodoItem('Second item.', 'High');
            HomeToolsController.RunningTodoItem third = HomeToolsController.addRunningTodoItem('Third item.', 'Low');

            // The Low item dragged to the top of the High band, exactly as the drawer sends it.
            Test.startTest();
            HomeToolsController.reorderChecklistItems(new List<HomeToolsController.ChecklistOrderItem>{
                orderItem(third.id, 'High'),
                orderItem(first.id, 'High'),
                orderItem(second.id, 'High')
            });
            HomeToolsController.HomeToolsData data = HomeToolsController.getHomeToolsData();
            Test.stopTest();

            System.assertEquals(3, data.runningTodoItems.size());
            System.assertEquals(third.id, data.runningTodoItems[0].id, 'The dragged item should hold its new position.');
            System.assertEquals('High', data.runningTodoItems[0].priority, 'The drop position should have raised its priority.');
            System.assertEquals(first.id, data.runningTodoItems[1].id);
            System.assertEquals(second.id, data.runningTodoItems[2].id);
        }
    }

    private static HomeToolsController.ChecklistOrderItem orderItem(Id taskId, String priority) {
        HomeToolsController.ChecklistOrderItem item = new HomeToolsController.ChecklistOrderItem();
        item.id = taskId;
        item.priority = priority;
        return item;
    }

    @isTest
    static void runningTodoUserCanManageAListWithNoDueDates() {
        User todoUser = testUserWithEmail('Christopher', 'Lowman', 'clowman@reachhomeloans.com');

        System.runAs(todoUser) {
            Test.startTest();
            HomeToolsController.HomeToolsData initialData = HomeToolsController.getHomeToolsData();
            HomeToolsController.RunningTodoItem lowItem =
                HomeToolsController.addRunningTodoItem('Tidy up the reporting folder.', 'Low');
            HomeToolsController.RunningTodoItem highItem =
                HomeToolsController.addRunningTodoItem('Review the renewal contract.', 'High');
            HomeToolsController.HomeToolsData data = HomeToolsController.getHomeToolsData();
            HomeToolsController.completeRunningTodoItem(highItem.id);
            HomeToolsController.HomeToolsData afterComplete = HomeToolsController.getHomeToolsData();
            List<HomeToolsController.CompletedRunningTodoItem> completedItems =
                HomeToolsController.getCompletedRunningTodoItems();
            HomeToolsController.reopenRunningTodoItem(highItem.id);
            HomeToolsController.HomeToolsData afterReopen = HomeToolsController.getHomeToolsData();
            Test.stopTest();

            System.assertEquals(true, initialData.isRunningTodoUser);
            System.assertEquals(0, initialData.runningTodoItems.size(), 'A new list starts empty.');
            System.assertEquals(0, initialData.events.size(), 'To-do users get a drawer without events.');
            System.assertEquals(0, initialData.recentRecords.size(), 'To-do users get a drawer without recent records.');
            System.assertEquals(2, data.runningTodoItems.size());
            System.assertEquals(highItem.id, data.runningTodoItems[0].id, 'High priority items sort first.');
            System.assertEquals('High', data.runningTodoItems[0].priority);
            System.assertEquals('Low', data.runningTodoItems[1].priority);
            System.assertEquals(1, afterComplete.runningTodoItems.size(), 'Completing an item removes it from the open list.');
            System.assertEquals(lowItem.id, afterComplete.runningTodoItems[0].id);
            System.assertEquals(1, completedItems.size());
            System.assertEquals(highItem.id, completedItems[0].id);
            System.assertEquals(2, afterReopen.runningTodoItems.size(), 'Reopening an item returns it to the open list.');
        }

        // Running to-do items carry no due date, which is what keeps them clear of the
        // Loan Partner past-due treatment.
        Task savedItem = [SELECT ActivityDate, Subject FROM Task WHERE Subject LIKE 'To-Do:%' LIMIT 1];
        System.assertEquals(null, savedItem.ActivityDate, 'Running to-do items must not carry a due date.');
    }

    @isTest
    static void runningTodoActionsRejectOtherUsers() {
        User otherUser = testUser('Someone', 'Else', 'Loan Officer');
        System.runAs(otherUser) {
            HomeToolsController.HomeToolsData data = HomeToolsController.getHomeToolsData();
            System.assertEquals(false, data.isRunningTodoUser);
            try {
                HomeToolsController.addRunningTodoItem('Should not be allowed.', 'High');
                System.assert(false, 'Users outside the configured list must not add to-do items.');
            } catch (Exception expected) {
                System.assert(true);
            }
        }
    }

    @isTest
    static void runningTodoItemsCanBeEditedAfterAdding() {
        User todoUser = testUserWithEmail('Christopher', 'Lowman', 'clowman@reachhomeloans.com');

        System.runAs(todoUser) {
            Test.startTest();
            HomeToolsController.RunningTodoItem created =
                HomeToolsController.addRunningTodoItem('Original wording.', 'Low');
            HomeToolsController.RunningTodoItem edited = HomeToolsController.updateRunningTodoItem(
                created.id, 'Corrected wording after a change.', 'High'
            );
            Test.stopTest();

            System.assertEquals('Corrected wording after a change.', edited.description, 'The edit should replace the description.');
            System.assertEquals('High', edited.priority, 'The edit should replace the priority.');
            Task saved = [SELECT Subject, Description, Priority FROM Task WHERE Id = :created.id];
            System.assert(saved.Subject.startsWith('To-Do: '), 'The list prefix must survive an edit.');
            System.assert(saved.Subject.contains('Corrected wording'), 'Subject should track the new description.');
            System.assertEquals('High', saved.Priority);
        }
    }

    @isTest
    static void editingRejectsBlankDescriptionAndForeignItems() {
        User todoUser = testUserWithEmail('Christopher', 'Lowman', 'clowman@reachhomeloans.com');
        Id createdId;
        System.runAs(todoUser) {
            createdId = HomeToolsController.addRunningTodoItem('Keep this wording.', 'Medium').id;
        }

        Test.startTest();
        System.runAs(todoUser) {
            try {
                HomeToolsController.updateRunningTodoItem(createdId, '   ', 'High');
                System.assert(false, 'A blank description must be rejected.');
            } catch (Exception expected) {
                System.assert(true);
            }
        }
        // Someone else's item must not be editable even by a configured to-do user.
        User otherUser = testUser('Someone', 'Else', 'Loan Officer');
        Task foreign = new Task(Subject = 'To-Do: Not yours.', Status = 'Not Started', OwnerId = otherUser.Id);
        insert foreign;
        System.runAs(todoUser) {
            try {
                HomeToolsController.updateRunningTodoItem(foreign.Id, 'Trying to edit.', 'High');
                System.assert(false, 'Editing another user\u0027s item must be rejected.');
            } catch (Exception expected) {
                System.assert(true);
            }
        }
        Test.stopTest();

        Task unchanged = [SELECT Description FROM Task WHERE Id = :createdId];
        System.assertEquals('Keep this wording.', unchanged.Description, 'A rejected edit must leave the item untouched.');
    }

    private static User testUserWithEmail(String firstName, String lastName, String email) {
        User userRecord = testUser(firstName, lastName, 'Operations');
        // Username stays unique; the gate matches on Email, which does not have to be.
        userRecord.Email = email;
        update userRecord;
        return userRecord;
    }

    private static User testUser(String firstName, String lastName, String title) {
        Profile profileRecord = [
            SELECT Id
            FROM Profile
            WHERE UserType = 'Standard'
            LIMIT 1
        ];
        String uniqueToken = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User userRecord = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = (firstName.left(1) + lastName).left(8),
            Email = uniqueToken + '@example.com',
            Username = uniqueToken + '@example.com',
            CommunityNickname = ('u' + uniqueToken).left(40),
            Title = title,
            ProfileId = profileRecord.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert userRecord;
        return userRecord;
    }
}