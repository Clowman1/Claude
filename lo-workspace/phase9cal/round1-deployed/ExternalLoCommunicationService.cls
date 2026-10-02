// ADR-0001: Task/Event WhoId on Lead uses SYSTEM_MODE so CCP users can log without Lead FLS.

public with sharing class ExternalLoCommunicationService {

    public static LogResult logCommunication(LogRequest request) {
        validateRequest(request);
        ExternalLoActivityLogService.requireLoggable(request.recordId);
        Id userId = UserInfo.getUserId();
        Task taskRecord = buildTask(request, userId);
        // Credit the goal that matches who was contacted. Without a category the rollup fell back to
        // Activity_Type__c, and every call (Call - Active Agent) credited Realtor outreach, even to a lead.
        String kind = ExternalLoActivityLogService.targetKind(request.recordId);
        ExternalLoActivityCatalog.ActivityDefinition activity = ExternalLoActivityCatalog.activityByKey(
            ExternalLoActivityLogService.defaultActivityKey(request.recordId, kind, request.channel)
        );
        if (activity != null && kind != null) {
            taskRecord.Activity_Category__c = activity.categoryApiName;
            taskRecord.Activity_Type__c = ExternalLoActivityLogService.resolveActivityType(activity, request.channel, kind);
        }
        taskRecord.Type = ExternalLoActivityLogService.taskTypeFor(request.channel);
        // The outcome in a dedicated field: Subject is rewritten by org automation.
        taskRecord.CallDisposition = String.isBlank(request.outcome) ? null : request.outcome.replace('-', ' ').capitalize();
        if (ExternalLoActivityLogService.writesNote(request.recordId, request.notes)) {
            taskRecord.Create_Enhanced_Note__c = false;
        }
        Database.insert(new List<Task>{ taskRecord }, AccessLevel.SYSTEM_MODE);
        ExternalLoActivityLogService.addNote(
            request.recordId,
            channelLabel(request.channel) + ' — ' + (activity == null ? 'Logged' : activity.shortLabel),
            request.notes
        );

        // General follow-up = open Task with an 8 AM reminder; exact = Event (LoWsCalendarService).
        Id followUpId = LoWsCalendarService.createFollowUp(request.recordId, request.followUpOption);

        LogResult result = new LogResult();
        result.taskId = taskRecord.Id;
        result.followUpEventId = followUpId;
        result.userMessage = buildSuccessMessage(request);
        return result;
    }

    private static final Set<String> LOGGABLE_OBJECTS = new Set<String>{ 'Lead', 'Account', 'Transaction__c' };

    private static void validateRequest(LogRequest request) {
        if (request == null || request.recordId == null) {
            throw new DomainException('A record is required to log communication.');
        }
        if (String.isBlank(request.objectApiName)) {
            throw new DomainException('Select the lead or partner record to log against.');
        }
        if (!LOGGABLE_OBJECTS.contains(request.objectApiName)) {
            throw new DomainException('Log communication from the related lead or partner record.');
        }
        if (String.isBlank(request.channel)) {
            throw new DomainException('Select how you reached out.');
        }
        if (String.isBlank(request.notes) || request.notes.trim().length() < 3) {
            throw new DomainException('Add a short note so the activity history stays useful.');
        }
    }

    private static Task buildTask(LogRequest request, Id userId) {
        Task taskRecord = new Task();
        taskRecord.OwnerId = userId;
        taskRecord.Status = 'Completed';
        taskRecord.Priority = 'Normal';
        taskRecord.ActivityDate = Date.today();
        taskRecord.Description = request.notes.trim();
        taskRecord.Subject = buildSubject(request);
        taskRecord.Activity_Type__c = mapActivityType(request.channel);

        if (request.objectApiName == 'Lead') {
            taskRecord.WhoId = request.recordId;
        } else {
            taskRecord.WhatId = request.recordId;
        }
        return taskRecord;
    }

    private static String buildSubject(LogRequest request) {
        String channelLabel = channelLabel(request.channel);
        String outcomeLabel = String.isBlank(request.outcome) ? 'Logged' : request.outcome.replace('-', ' ');
        return channelLabel + ' - ' + outcomeLabel;
    }

    private static String mapActivityType(String channel) {
        switch on channel {
            when 'call' { return 'Call - Active Agent'; }
            when 'text' { return 'Text'; }
            when 'email' { return 'Email'; }
            when 'in-person' { return 'Meeting (Active Agent)'; }
            when 'video' { return 'Meeting (Active Agent)'; }
            when else { return 'Call - Active Agent'; }
        }
    }

    private static String channelLabel(String channel) {
        switch on channel {
            when 'call' { return 'Call'; }
            when 'text' { return 'Text'; }
            when 'email' { return 'Email'; }
            when 'in-person' { return 'In person'; }
            when 'video' { return 'Video'; }
            when else { return 'Activity'; }
        }
    }

    private static String buildSuccessMessage(LogRequest request) {
        return channelLabel(request.channel) + ' logged successfully.';
    }

    public class LogRequest {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String channel;
        @AuraEnabled public String outcome;
        @AuraEnabled public String notes;
        /** none | tomorrow | 3-days | next-week | date:YYYY-MM-DD | exact:<ISO datetime>. See LoWsCalendarService. */
        @AuraEnabled public String followUpOption;
    }

    public class LogResult {
        @AuraEnabled public Id taskId;
        /** The follow-up record: a Task (general) or an Event (exact). Name kept for existing callers. */
        @AuraEnabled public Id followUpEventId;
        @AuraEnabled public String userMessage;
    }
}