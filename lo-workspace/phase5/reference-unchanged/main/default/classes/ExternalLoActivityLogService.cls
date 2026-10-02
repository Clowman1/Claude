/**
 * Logs Partner Workspace activities as a single Task with category, channel,
 * and count. Social engagement may omit a related record. Does not replace
 * ExternalLoCommunicationService.logCommunication.
 */
public with sharing class ExternalLoActivityLogService {
    private static final Set<String> LOGGABLE_OBJECTS = new Set<String>{
        'Lead',
        'Account',
        'Transaction__c',
        'Contact'
    };

    /**
     * Inserts one completed Task. Count is clamped 1–50 and stored on
     * Activity_Count__c so TaskTrigger is not amplified.
     */
    public static LogResult logActivity(LogRequest request) {
        validate(request);
        ExternalLoActivityCatalog.ActivityDefinition activity = ExternalLoActivityCatalog.activityByKey(request.activityKey);
        if (activity == null || activity.isActive != true) {
            throw new DomainException('Choose an activity category to log.');
        }
        if (activity.requiresContact == true && request.recordId == null) {
            throw new DomainException('Choose a contact for ' + activity.shortLabel + '.');
        }
        Integer countValue = ExternalLoGoalMath.clampCount(request.activityCount);
        Id userId = UserInfo.getUserId();
        Task taskRecord = new Task();
        taskRecord.OwnerId = userId;
        taskRecord.Status = 'Completed';
        taskRecord.Priority = 'Normal';
        taskRecord.ActivityDate = Date.today();
        taskRecord.Activity_Category__c = activity.categoryApiName;
        taskRecord.Activity_Type__c = resolveActivityType(activity, request.channel);
        taskRecord.Activity_Count__c = countValue;
        taskRecord.Prompt_Key__c = String.isBlank(request.promptKey) ? null : request.promptKey.trim();
        taskRecord.Subject = buildSubject(activity, countValue);
        if (!String.isBlank(request.notes)) {
            taskRecord.Description = request.notes.trim();
        }
        assignRelated(taskRecord, request);
        Database.insert(new List<Task>{ taskRecord }, AccessLevel.SYSTEM_MODE);
        if (!String.isBlank(request.promptKey)) {
            completeMatchingPromptTask(userId, request.promptKey.trim());
        }

        LogResult result = new LogResult();
        result.taskId = taskRecord.Id;
        result.userMessage = countValue == 1
            ? activity.shortLabel + ' logged.'
            : countValue + ' ' + activity.unitNoun + ' logged.';
        result.activityKey = activity.activityKey;
        result.activityCount = countValue;
        return result;
    }

    /**
     * Inserts an open Task due tomorrow so the computed prompt stays hidden
     * until that date. No new snooze object.
     */
    public static LogResult snoozePrompt(String promptKey, Id recordId, String objectApiName) {
        if (String.isBlank(promptKey)) {
            throw new DomainException('A prompt is required to snooze.');
        }
        Id userId = UserInfo.getUserId();
        Task existing = new TaskRepository().selectOpenPromptTask(userId, promptKey.trim());
        if (existing != null) {
            LogResult already = new LogResult();
            already.taskId = existing.Id;
            already.userMessage = 'This prompt is already scheduled for later.';
            return already;
        }
        Task snooze = new Task();
        snooze.OwnerId = userId;
        snooze.Status = 'Not Started';
        snooze.Priority = 'Normal';
        snooze.ActivityDate = Date.today().addDays(1);
        snooze.Prompt_Key__c = promptKey.trim();
        snooze.Subject = 'Follow up — ' + promptKey.trim();
        LogRequest related = new LogRequest();
        related.recordId = recordId;
        related.objectApiName = objectApiName;
        assignRelated(snooze, related);
        Database.insert(new List<Task>{ snooze }, AccessLevel.SYSTEM_MODE);

        LogResult result = new LogResult();
        result.taskId = snooze.Id;
        result.userMessage = 'We will bring this back tomorrow.';
        return result;
    }

    /**
     * Leads and partners the user can attach to a log row.
     */
    public static List<SearchHit> searchLoggableRecords(String searchTerm) {
        String term = searchTerm == null ? '' : searchTerm.trim();
        List<SearchHit> hits = new List<SearchHit>();
        if (term.length() < 2) {
            return hits;
        }
        String likeTerm = '%' + term + '%';
        Id userId = UserInfo.getUserId();
        for (Lead leadRecord : [
            SELECT Id, Name, Status, Phone, Email
            FROM Lead
            WHERE OwnerId = :userId
              AND IsConverted = false
              AND Name LIKE :likeTerm
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 10
        ]) {
            SearchHit hit = new SearchHit();
            hit.id = leadRecord.Id;
            hit.name = leadRecord.Name;
            hit.objectApiName = 'Lead';
            hit.subtitle = leadRecord.Status;
            hit.phone = leadRecord.Phone;
            hit.email = leadRecord.Email;
            hits.add(hit);
        }
        for (ExternalLoPortalService.PartnerRow partner : ExternalLoPortalService.getRealtors('all', term)) {
            if (hits.size() >= 20) {
                break;
            }
            SearchHit hit = new SearchHit();
            hit.id = partner.id;
            hit.name = partner.name;
            hit.objectApiName = 'Account';
            hit.subtitle = partner.partnerType;
            hit.phone = partner.phone;
            hit.email = partner.email;
            hits.add(hit);
        }
        return hits;
    }

    private static void validate(LogRequest request) {
        if (request == null || String.isBlank(request.activityKey)) {
            throw new DomainException('Choose an activity category to log.');
        }
        if (request.recordId != null && !String.isBlank(request.objectApiName)
            && !LOGGABLE_OBJECTS.contains(request.objectApiName)) {
            throw new DomainException('Log against a lead, partner, or loan record.');
        }
    }

    private static String resolveActivityType(
        ExternalLoActivityCatalog.ActivityDefinition activity,
        String channel
    ) {
        String mapped = channelActivityType(channel);
        if (!String.isBlank(mapped) && activity.creditActivityTypes != null
            && activity.creditActivityTypes.contains(mapped)) {
            return mapped;
        }
        if (!String.isBlank(mapped)) {
            return mapped;
        }
        return ExternalLoActivityCatalog.activityTypeForCategory(activity.categoryApiName);
    }

    private static String channelActivityType(String channel) {
        if (String.isBlank(channel)) {
            return null;
        }
        switch on channel {
            when 'call' {
                return 'Call - Active Agent';
            }
            when 'text' {
                return 'Text';
            }
            when 'email' {
                return 'Email';
            }
            when 'meeting', 'in-person', 'video' {
                return 'Meeting (Active Agent)';
            }
            when 'open-house' {
                return 'Open House';
            }
            when else {
                return null;
            }
        }
    }

    private static String buildSubject(ExternalLoActivityCatalog.ActivityDefinition activity, Integer countValue) {
        if (countValue > 1) {
            return '+' + String.valueOf(countValue) + ' ' + activity.unitNoun;
        }
        return activity.shortLabel;
    }

    private static void assignRelated(Task taskRecord, LogRequest request) {
        if (request == null || request.recordId == null) {
            return;
        }
        if (request.objectApiName == 'Lead' || request.objectApiName == 'Contact') {
            taskRecord.WhoId = request.recordId;
        } else {
            taskRecord.WhatId = request.recordId;
        }
    }

    private static void completeMatchingPromptTask(Id userId, String promptKey) {
        Task openPrompt = new TaskRepository().selectOpenPromptTask(userId, promptKey);
        if (openPrompt == null) {
            return;
        }
        Task updateShell = new Task(
            Id = openPrompt.Id,
            Status = 'Completed',
            ActivityDate = Date.today()
        );
        Database.update(new List<Task>{ updateShell }, AccessLevel.SYSTEM_MODE);
    }

    public class LogRequest {
        @AuraEnabled public String activityKey;
        @AuraEnabled public String channel;
        @AuraEnabled public Integer activityCount;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String notes;
        @AuraEnabled public String promptKey;
    }

    public class LogResult {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String userMessage;
        @AuraEnabled public String activityKey;
        @AuraEnabled public Integer activityCount;
    }

    public class SearchHit {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
    }
}