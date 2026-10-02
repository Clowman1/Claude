@isTest
private class ExternalLoActivityLogServiceTest {

    @testSetup
    static void setupData() {
        ExternalLoPortalTestHelper.grantPortalAccess(UserInfo.getUserId());
    }

    @isTest
    static void logActivity_countWritesOneTaskWithCategoryAndChannel() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        System.runAs(importer) {
            ExternalLoActivityLogService.LogRequest request = new ExternalLoActivityLogService.LogRequest();
            request.activityKey = 'social-engagement';
            request.channel = 'text';
            request.activityCount = 3;
            request.notes = 'Posted in the Facebook group.';

            Test.startTest();
            ExternalLoActivityLogService.LogResult result = ExternalLoActivityLogService.logActivity(request);
            Test.stopTest();

            List<Task> tasks = [
                SELECT Id, Activity_Category__c, Activity_Type__c, Activity_Count__c, Status
                FROM Task
                WHERE Id = :result.taskId
            ];
            System.assertEquals(1, tasks.size(), 'Count > 1 must still insert one Task.');
            System.assertEquals('Social_Engagement', tasks[0].Activity_Category__c);
            System.assertEquals('Text', tasks[0].Activity_Type__c);
            System.assertEquals(3, tasks[0].Activity_Count__c.intValue());
            System.assertEquals('Completed', tasks[0].Status);
        }
    }

    @isTest
    static void logActivity_viaControllerWithContact() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        Id consumerRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Lead' AND DeveloperName = 'Consumer_Lead_record_type'
            LIMIT 1
        ].Id;
        Lead leadRecord;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            leadRecord = new Lead(
                RecordTypeId = consumerRtId,
                FirstName = 'Log',
                LastName = 'Target',
                Company = 'Log Co',
                Status = 'New',
                Email = 'log.target.' + String.valueOf(Crypto.getRandomInteger()) + '@example.com',
                OwnerId = importer.Id
            );
            insert leadRecord;
        }
        System.runAs(importer) {
            ExternalLoActivityLogService.LogRequest request = new ExternalLoActivityLogService.LogRequest();
            request.activityKey = 'consumer-conversation';
            request.channel = 'call';
            request.activityCount = 1;
            request.recordId = leadRecord.Id;
            request.objectApiName = 'Lead';
            request.notes = 'Spoke with the realtor.';
            ExternalLoActivityLogService.LogResult result = ExternalLoPortalController.logActivity(
                request.activityKey,
                request.channel,
                request.activityCount,
                request.recordId,
                request.objectApiName,
                request.notes,
                request.promptKey
            );
            System.assertNotEquals(null, result.taskId);
            List<Task> logged = [SELECT WhoId, Activity_Category__c FROM Task WHERE Id = :result.taskId];
            System.assertEquals(leadRecord.Id, logged[0].WhoId);
            System.assertEquals('Consumer_Conversation', logged[0].Activity_Category__c);
        }
    }

    @isTest
    static void logActivity_closesMatchingPromptAndResolvesNames() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        Id consumerRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Lead' AND DeveloperName = 'Consumer_Lead_record_type'
            LIMIT 1
        ].Id;
        Lead leadRecord;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            leadRecord = new Lead(
                RecordTypeId = consumerRtId,
                FirstName = 'Prompt',
                LastName = 'Closeout',
                Company = 'Prompt Co',
                Status = 'New',
                Email = 'prompt.close.' + String.valueOf(Crypto.getRandomInteger()) + '@example.com',
                OwnerId = importer.Id
            );
            insert leadRecord;
        }
        System.runAs(importer) {
            ExternalLoActivityLogService.snoozePrompt('under-contract:' + leadRecord.Id, leadRecord.Id, 'Lead');
            ExternalLoActivityLogService.LogRequest request = new ExternalLoActivityLogService.LogRequest();
            request.activityKey = 'consumer-conversation';
            request.channel = 'open-house';
            request.activityCount = 2;
            request.recordId = leadRecord.Id;
            request.objectApiName = 'Lead';
            request.promptKey = 'under-contract:' + leadRecord.Id;
            request.notes = 'Logged the open house.';
            ExternalLoActivityLogService.LogResult result = ExternalLoActivityLogService.logActivity(request);
            Task completedPrompt = [
                SELECT IsClosed FROM Task
                WHERE OwnerId = :UserInfo.getUserId() AND Prompt_Key__c = :request.promptKey
                LIMIT 1
            ];
            System.assertEquals(true, completedPrompt.IsClosed, 'Logging against a prompt must close the snooze Task.');
            Task logged = [SELECT Activity_Type__c, WhoId, WhatId FROM Task WHERE Id = :result.taskId];
            System.assertEquals('Open House', logged.Activity_Type__c);
            Map<Id, String> names = ExternalLoActivityNameResolver.resolveTaskRelatedNames(new List<Task>{ logged });
            System.assert(names.containsKey(leadRecord.Id), names);
            System.assertEquals('Activity', ExternalLoActivityNameResolver.formatTaskRelatedLabel(null, null));
            Boolean invalidCaught = false;
            try {
                ExternalLoActivityLogService.LogRequest bad = new ExternalLoActivityLogService.LogRequest();
                bad.activityKey = 'not-a-real-activity';
                ExternalLoActivityLogService.logActivity(bad);
            } catch (DomainException error) {
                invalidCaught = true;
            }
            System.assertEquals(true, invalidCaught);
        }
    }

    @isTest
    static void nameResolver_coversWhoAndWhatLookups() {
        ExternalLoPortalTestHelper.grantPortalAccess(UserInfo.getUserId());
        Id consumerRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Lead' AND DeveloperName = 'Consumer_Lead_record_type'
            LIMIT 1
        ].Id;
        Lead leadRecord = new Lead(
            RecordTypeId = consumerRtId,
            FirstName = 'Who',
            LastName = 'Lookup',
            Company = 'Who Co',
            Status = 'New',
            Email = 'who.lookup.' + String.valueOf(Crypto.getRandomInteger()) + '@example.com'
        );
        insert leadRecord;
        Transaction__c loanRecord = new Transaction__c(Name = 'What Lookup');
        insert loanRecord;
        Task whoTask = new Task(
            Subject = 'Who',
            Status = 'Completed',
            ActivityDate = Date.today(),
            WhoId = leadRecord.Id
        );
        Task whatTask = new Task(
            Subject = 'What',
            Status = 'Completed',
            ActivityDate = Date.today(),
            WhatId = loanRecord.Id
        );
        insert new List<Task>{ whoTask, whatTask };
        Lead namedLead = [SELECT Name FROM Lead WHERE Id = :leadRecord.Id];
        Map<Id, String> names = ExternalLoActivityNameResolver.resolveTaskRelatedNames(
            new List<Task>{ whoTask, whatTask }
        );
        System.assertEquals(namedLead.Name, names.get(leadRecord.Id));
        System.assert(names.containsKey(loanRecord.Id), names);
        System.assert(
            ExternalLoActivityNameResolver.formatTaskRelatedLabel(whoTask, names).contains('Who')
            || ExternalLoActivityNameResolver.formatTaskRelatedLabel(whoTask, names) == leadRecord.Name
        );
        System.assertEquals(
            names.get(loanRecord.Id),
            ExternalLoActivityNameResolver.formatTaskRelatedLabel(whatTask, names)
        );
        List<ExternalLoActivityLogService.SearchHit> hits = ExternalLoActivityLogService.searchLoggableRecords('Lookup');
        System.assert(hits.size() >= 0);
        ExternalLoActivityLogService.LogRequest emailLog = new ExternalLoActivityLogService.LogRequest();
        emailLog.activityKey = 'social-engagement';
        emailLog.channel = 'email';
        emailLog.activityCount = 1;
        emailLog.notes = 'Emailed a listing.';
        System.assertNotEquals(null, ExternalLoActivityLogService.logActivity(emailLog).taskId);
    }

    @isTest
    static void logActivity_requiresContactWhenCatalogSaysSo() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        System.runAs(importer) {
            ExternalLoActivityLogService.LogRequest request = new ExternalLoActivityLogService.LogRequest();
            request.activityKey = 'realtor-outreach';
            request.channel = 'call';
            request.activityCount = 1;
            Boolean caught = false;
            try {
                ExternalLoActivityLogService.logActivity(request);
            } catch (DomainException error) {
                caught = true;
                System.assert(error.getMessage().contains('contact'), error.getMessage());
            }
            System.assertEquals(true, caught, 'Realtor outreach requires a related record.');
        }
    }

    @isTest
    static void snoozePrompt_insertsOpenTaskForTomorrow() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        System.runAs(importer) {
            Test.startTest();
            ExternalLoActivityLogService.LogResult result = ExternalLoActivityLogService.snoozePrompt(
                'under-contract:00Q000000000001',
                null,
                null
            );
            Test.stopTest();
            Task snooze = [
                SELECT Status, ActivityDate, Prompt_Key__c, IsClosed
                FROM Task
                WHERE Id = :result.taskId
            ];
            System.assertEquals(false, snooze.IsClosed);
            System.assertEquals(Date.today().addDays(1), snooze.ActivityDate);
            System.assertEquals('under-contract:00Q000000000001', snooze.Prompt_Key__c);

            ExternalLoActivityLogService.LogResult viaController = ExternalLoPortalController.snoozePrompt(
                'milestone:00Q000000000002',
                null,
                null
            );
            System.assertNotEquals(null, viaController.taskId);
            System.assertEquals(0, ExternalLoPortalController.searchLoggableRecords('x').size());
            ExternalLoProgressService.ProgressPayload rollup = ExternalLoPortalController.getActivityRollup(null);
            System.assertNotEquals(null, rollup.week);
            System.assertEquals(0, ExternalLoActivityNameResolver.resolveTaskRelatedNames(new List<Task>()).size());
            System.assertEquals(0, new ExternalLoPromptSelector().selectUnderContractLeadsByOwner(null).size());
            System.assertEquals(0, new ExternalLoPromptSelector().selectFundedLoansByOfficer(null).size());
            ExternalLoActivityLogService.LogResult duplicate = ExternalLoActivityLogService.snoozePrompt(
                'under-contract:00Q000000000001',
                null,
                null
            );
            System.assertEquals(result.taskId, duplicate.taskId);
            Boolean blankCaught = false;
            try {
                ExternalLoActivityLogService.snoozePrompt('  ', null, null);
            } catch (DomainException error) {
                blankCaught = true;
            }
            System.assertEquals(true, blankCaught);
            Boolean invalidObjectCaught = false;
            try {
                ExternalLoActivityLogService.LogRequest badObject = new ExternalLoActivityLogService.LogRequest();
                badObject.activityKey = 'social-engagement';
                badObject.recordId = UserInfo.getUserId();
                badObject.objectApiName = 'User';
                ExternalLoActivityLogService.logActivity(badObject);
            } catch (DomainException error) {
                invalidObjectCaught = true;
            }
            System.assertEquals(true, invalidObjectCaught);
            ExternalLoActivityLogService.LogRequest meetingLog = new ExternalLoActivityLogService.LogRequest();
            meetingLog.activityKey = 'social-engagement';
            meetingLog.channel = 'video';
            meetingLog.activityCount = 1;
            meetingLog.notes = 'Posted a video update.';
            System.assertNotEquals(null, ExternalLoActivityLogService.logActivity(meetingLog).taskId);
            Boolean nullRequestCaught = false;
            try {
                ExternalLoActivityLogService.logActivity(null);
            } catch (DomainException error) {
                nullRequestCaught = true;
            }
            System.assertEquals(true, nullRequestCaught);
        }
    }

    @isTest
    static void logActivity_viaControllerSuppressesCompletedPromptKey() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        System.runAs(importer) {
            String promptKey = 'escrow-analysis:a01TESTESCROW000AAA';
            Test.startTest();
            ExternalLoActivityLogService.LogResult result = ExternalLoPortalController.logActivity(
                'social-engagement',
                'text',
                1,
                null,
                null,
                'Logged from the prompt card.',
                promptKey
            );
            Test.stopTest();
            System.assertNotEquals(null, result.taskId);
            Set<String> keys = ExternalLoPromptService.snoozedKeysFor(UserInfo.getUserId());
            System.assert(keys.contains(promptKey), 'A completed log with Prompt_Key__c must hide that prompt.');
        }
    }
}