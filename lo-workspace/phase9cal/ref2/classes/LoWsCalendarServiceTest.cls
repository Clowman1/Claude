/**
 * LO Workspace calendar + follow-ups, run as a real outside loan officer (External Loan Officer Profile
 * + role + permission set group External_Loan_Officer, like the pilot).
 */
@IsTest
private class LoWsCalendarServiceTest {

    static final String NAME = 'Zedcaltest';

    @TestSetup
    static void setup() {
        User lo = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p9cal' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p9.test',
            Email = 'p9cal@reach-p9.test',
            LastName = 'p9cal',
            Alias = 'p9cal',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert lo;
            insert new PermissionSetAssignment(AssigneeId = lo.Id,
                PermissionSetGroupId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'External_Loan_Officer'].Id);
        }
        Id consumerRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId();
        insert new Lead(RecordTypeId = consumerRt, FirstName = 'Lee', LastName = NAME + 'Lead', Company = 'n/a',
            Status = 'New', OwnerId = lo.Id);
    }

    static User lo() {
        return [SELECT Id FROM User WHERE Alias = 'p9cal' LIMIT 1];
    }

    static Id leadId() {
        return [SELECT Id FROM Lead WHERE LastName = :NAME + 'Lead' LIMIT 1].Id;
    }

    static ExternalLoCommunicationService.LogRequest call(Id recordId, String followUp) {
        ExternalLoCommunicationService.LogRequest r = new ExternalLoCommunicationService.LogRequest();
        r.recordId = recordId;
        r.objectApiName = 'Lead';
        r.channel = 'call';
        r.outcome = 'connected';
        r.notes = 'Talked through next steps.';
        r.followUpOption = followUp;
        return r;
    }

    @IsTest
    static void generalFollowUpCreatesTaskWith8amReminder() {
        Id lead = leadId();
        System.runAs(lo()) {
            Test.startTest();
            Id fromCall = ExternalLoCommunicationService.logCommunication(call(lead, 'tomorrow')).followUpEventId;
            Date onDate = Date.today().addDays(5);
            ExternalLoActivityLogService.LogRequest r = new ExternalLoActivityLogService.LogRequest();
            r.activityKey = 'consumer-conversation';
            r.channel = 'text';
            r.activityCount = 1;
            r.recordId = lead;
            r.followUpOption = 'date:' + String.valueOf(onDate);
            Id fromActivity = ExternalLoActivityLogService.logActivity(r).followUpId;
            Test.stopTest();

            Map<Id, Task> tasks = new Map<Id, Task>([
                SELECT Status, ActivityDate, IsReminderSet, ReminderDateTime, WhoId, OwnerId, IsClosed
                FROM Task WHERE Id IN :new List<Id>{ fromCall, fromActivity }
            ]);
            Task t1 = tasks.get(fromCall);
            System.assertEquals('Not Started', t1.Status);
            System.assertEquals(false, t1.IsClosed);
            System.assertEquals(Date.today().addDays(1), t1.ActivityDate);
            System.assertEquals(true, t1.IsReminderSet);
            System.assertEquals(Datetime.newInstance(Date.today().addDays(1), Time.newInstance(8, 0, 0, 0)), t1.ReminderDateTime);
            System.assertEquals(lead, t1.WhoId);
            System.assertEquals(UserInfo.getUserId(), t1.OwnerId);
            Task t2 = tasks.get(fromActivity);
            System.assertEquals(onDate, t2.ActivityDate);
            System.assertEquals(Datetime.newInstance(onDate, Time.newInstance(8, 0, 0, 0)), t2.ReminderDateTime);
            // General never creates an Event (the old fixed 9 AM Event is gone).
            System.assertEquals(0, [SELECT COUNT() FROM Event WHERE WhoId = :lead]);
        }
    }

    @IsTest
    static void exactTimeRequiresDatetimeAndCreatesEventWithReminder() {
        Id lead = leadId();
        System.runAs(lo()) {
            for (String bad : new List<String>{ 'exact:', 'exact:' + JSON.serialize(System.now().addHours(-2)).remove('"'), 'date:', 'exact:not-a-date', 'sometime' }) {
                try {
                    ExternalLoCommunicationService.logCommunication(call(lead, bad));
                    System.assert(false, 'Expected a follow-up error for ' + bad);
                } catch (DomainException expected) {
                    System.assert(expected.getMessage().containsIgnoreCase('follow'), expected.getMessage());
                }
            }
            Datetime startAt = Datetime.newInstance(Date.today().addDays(2), Time.newInstance(14, 30, 0, 0));
            Test.startTest();
            Id eventId = ExternalLoCommunicationService.logCommunication(
                call(lead, 'exact:' + JSON.serialize(startAt).remove('"'))
            ).followUpEventId;
            Test.stopTest();

            Event e = [SELECT StartDateTime, DurationInMinutes, IsReminderSet, ReminderDateTime, WhoId, OwnerId FROM Event WHERE Id = :eventId];
            System.assertEquals(startAt, e.StartDateTime);
            System.assertEquals(30, e.DurationInMinutes);
            System.assertEquals(true, e.IsReminderSet);
            System.assertEquals(startAt.addMinutes(-15), e.ReminderDateTime);
            System.assertEquals(lead, e.WhoId);
            System.assertEquals(UserInfo.getUserId(), e.OwnerId);
            System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :lead AND IsClosed = false], 'Exact time creates no to-do.');

            List<LoWsCalendarService.EventRow> rows = LoWsCalendarService.getMyEvents(null, null);
            System.assertEquals(1, rows.size(), 'The exact follow-up is on the calendar.');
            System.assertEquals(lead, rows[0].relatedId);
            System.assertEquals('Lead', rows[0].relatedType);
        }
    }

    @IsTest
    static void taskDueTodayAndOverdueShowOnPerfectDayUntilCompleted() {
        Id lead = leadId();
        System.runAs(lo()) {
            Id today = LoWsCalendarService.createFollowUp(lead, 'date:' + String.valueOf(Date.today()));
            Task overdue = new Task(OwnerId = UserInfo.getUserId(), Subject = 'Old follow up', Status = 'Not Started',
                ActivityDate = Date.today().addDays(-3), WhoId = lead);
            insert overdue;
            Id future = LoWsCalendarService.createFollowUp(lead, 'next-week');

            Test.startTest();
            Map<Id, ExternalLoPromptService.PromptItem> byTask = followUps(PerfectDayHomeService.getHomeData());
            System.assert(byTask.containsKey(today), 'A follow-up due today is in Up Next.');
            System.assert(byTask.containsKey(overdue.Id), 'An overdue follow-up keeps showing.');
            System.assert(!byTask.containsKey(future), 'A future follow-up waits for its day.');
            ExternalLoPromptService.PromptItem row = byTask.get(today);
            System.assertEquals(true, row.canComplete);
            System.assertEquals('Follow-up due today', row.reason);
            System.assertEquals(lead, row.recordId);
            System.assert(row.title.contains(NAME + 'Lead'), row.title);

            PerfectDayHomeController.completeUpNextItem(today, 'Task');
            Test.stopTest();
            System.assert(!followUps(PerfectDayHomeService.getHomeData()).containsKey(today), 'Completed follow-ups leave Up Next.');
        }
    }

    static Map<Id, ExternalLoPromptService.PromptItem> followUps(PerfectDayHomeModels.PerfectDayHomeData data) {
        Map<Id, ExternalLoPromptService.PromptItem> byTask = new Map<Id, ExternalLoPromptService.PromptItem>();
        for (ExternalLoPromptService.PromptItem item : data.prompts) {
            if (item.taskId != null) {
                byTask.put(item.taskId, item);
            }
        }
        return byTask;
    }

    @IsTest
    static void calendarReturnsOnlyMyEvents() {
        User officer = lo();
        Id lead = leadId();
        Datetime soon = System.now().addDays(1);
        insert new List<Event>{
            new Event(OwnerId = officer.Id, Subject = 'Mine', StartDateTime = soon, DurationInMinutes = 30, WhoId = lead),
            new Event(OwnerId = UserInfo.getUserId(), Subject = 'Someone else', StartDateTime = soon, DurationInMinutes = 30),
            new Event(OwnerId = officer.Id, Subject = 'Next month', StartDateTime = soon.addDays(40), DurationInMinutes = 30)
        };
        System.runAs(officer) {
            List<LoWsCalendarService.EventRow> upcoming = LoWsCalendarService.getMyEvents(null, null);
            System.assertEquals(1, upcoming.size(), 'Next 7 days, own events only.');
            System.assertEquals('Mine', upcoming[0].subject);
            System.assertEquals(NAME + 'Lead', upcoming[0].relatedName.substringAfter(' '));

            List<LoWsCalendarService.EventRow> wide = LoWsCalendarService.getMyEvents(System.now(), System.now().addDays(365));
            System.assertEquals(2, wide.size(), 'Range is capped at 62 days and never shows another owner.');
            for (LoWsCalendarService.EventRow row : wide) {
                System.assertNotEquals('Someone else', row.subject);
            }
        }
    }

    @IsTest
    static void loggedNotesDoNotEmailTheLeadTeamButManualNotesStillDo() {
        Id lead = leadId();
        System.runAs(lo()) {
            Test.startTest();
            ExternalLoCommunicationService.logCommunication(call(lead, 'none'));
            ExternalLoActivityLogService.LogRequest r = new ExternalLoActivityLogService.LogRequest();
            r.activityKey = 'consumer-conversation';
            r.channel = 'call';
            r.activityCount = 1;
            r.recordId = lead;
            r.notes = 'Asked about the rate lock.';
            ExternalLoActivityLogService.logActivity(r);
            System.assertEquals(2, [SELECT COUNT() FROM Enhanced_Note__c WHERE Lead__c = :lead AND Type__c = 'Note'], 'Both logs keep their Type Note row.');
            System.assertEquals(0, Limits.getEmailInvocations(), 'Logged-activity notes send no Lead Team email.');
            System.assertEquals(false, LeadNoteTeamNotifier.suppressForLoggedActivity, 'The switch is reset after the insert.');

            // Control: a hand-added note (AddNewNote path) still emails the Lead Owner.
            insert new Enhanced_Note__c(Lead__c = lead, Type__c = 'Note', Subject__c = 'Manual', Body__c = 'Manual note');
            System.assert(Limits.getEmailInvocations() > 0, 'Manual notes still email the Lead Team.');
            Test.stopTest();
        }
    }

    @IsTest
    static void outsideLoCanSeeZoomMeetingsSoEventSavesWork() {
        // EventTrigger -> ZoomEventSync queries Zoom_Meeting__c; without object access an Event save fails.
        System.runAs(lo()) {
            System.assert(Schema.SObjectType.Zoom_Meeting__c.isAccessible(), 'External_Loan_Officer PSG must grant Zoom_Meeting__c (Zoom_Meeting_Sync_Access).');
        }
        System.assertEquals(null, LoWsCalendarService.createFollowUp(leadId(), 'none'));
        System.assertEquals(null, LoWsCalendarService.createFollowUp(null, null));
    }
}