/**
 * Canonical SOQL access for Task records used by Perfect Day and activity rollups.
 */
public with sharing class TaskRepository {

    public List<Task> selectCompletedActivitiesByOwnerForDateRange(Id ownerId, Date startDate, Date endDate) {
        if (ownerId == null || startDate == null || endDate == null) {
            return new List<Task>();
        }

        return [
            SELECT Activity_Type__c, Activity_Category__c, Activity_Count__c, Prompt_Key__c,
                   ActivityDate, Id, Subject, Status, WhatId, WhoId, Description, CompletedDateTime
            FROM Task
            WHERE OwnerId = :ownerId
              AND Status = 'Completed'
              AND ActivityDate >= :startDate
              AND ActivityDate <= :endDate
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Newest completed log rows for the recent-activity feed.
     */
    public List<Task> selectRecentLoggedActivitiesByOwner(Id ownerId, Integer rowLimit) {
        if (ownerId == null) {
            return new List<Task>();
        }
        Integer safeLimit = rowLimit == null || rowLimit <= 0 ? 8 : Math.min(rowLimit, 20);
        return [
            SELECT Activity_Type__c, Activity_Category__c, Activity_Count__c, Prompt_Key__c,
                   ActivityDate, Id, Subject, Status, WhatId, WhoId, Description, CompletedDateTime
            FROM Task
            WHERE OwnerId = :ownerId
              AND Status = 'Completed'
              AND (Activity_Category__c != null OR Activity_Type__c != null)
            WITH SYSTEM_MODE
            ORDER BY ActivityDate DESC, CompletedDateTime DESC NULLS LAST
            LIMIT :safeLimit
        ];
    }

    /**
     * Open Tasks that hide a computed prompt until their due date.
     */
    public List<Task> selectOpenPromptTasksByOwner(Id ownerId) {
        if (ownerId == null) {
            return new List<Task>();
        }
        return [
            SELECT Id, Prompt_Key__c, ActivityDate, Status, Subject, WhoId, WhatId
            FROM Task
            WHERE OwnerId = :ownerId
              AND IsClosed = false
              AND Prompt_Key__c != null
            WITH SYSTEM_MODE
            LIMIT 200
        ];
    }

    /**
     * Open snooze Tasks plus completed "log it done" Tasks that still hide a prompt.
     */
    public List<Task> selectPromptTasksByOwner(Id ownerId) {
        if (ownerId == null) {
            return new List<Task>();
        }
        return [
            SELECT Id, Prompt_Key__c, ActivityDate, Status, IsClosed, Subject, WhoId, WhatId
            FROM Task
            WHERE OwnerId = :ownerId
              AND Prompt_Key__c != null
              AND ActivityDate >= LAST_N_DAYS:400
            WITH SYSTEM_MODE
            LIMIT 500
        ];
    }

    /**
     * One open prompt Task for snooze de-dupe and "log it done" close-out.
     */
    public Task selectOpenPromptTask(Id ownerId, String promptKey) {
        if (ownerId == null || String.isBlank(promptKey)) {
            return null;
        }
        List<Task> rows = [
            SELECT Id, Prompt_Key__c, ActivityDate, Status, Subject, WhoId, WhatId, OwnerId, IsClosed
            FROM Task
            WHERE OwnerId = :ownerId
              AND IsClosed = false
              AND Prompt_Key__c = :promptKey
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Open to-dos due today or earlier (follow-ups and any other dated task) for Up Next, newest due first.
     * Prompt snooze Tasks (Prompt_Key__c set) are excluded: they only hide a computed prompt.
     */
    public List<Task> selectOpenDueTasksByOwner(Id ownerId, Integer rowLimit) {
        if (ownerId == null) {
            return new List<Task>();
        }
        Date today = Date.today();
        return [
            SELECT Id, Subject, Description, ActivityDate, WhoId, Who.Name, Who.Type, WhatId, What.Name, What.Type
            FROM Task
            WHERE OwnerId = :ownerId
              AND IsClosed = false
              AND ActivityDate <= :today
              AND Prompt_Key__c = null
            WITH SYSTEM_MODE
            ORDER BY ActivityDate DESC, CreatedDate DESC
            LIMIT :rowLimit
        ];
    }

    public List<Task> selectOpenOverdueByOwner(Id ownerId) {
        if (ownerId == null) {
            return new List<Task>();
        }

        Date today = Date.today();
        return [
            SELECT Id, Subject, Status, ActivityDate, Priority, WhatId, WhoId, Activity_Type__c
            FROM Task
            WHERE OwnerId = :ownerId
              AND IsClosed = false
              AND ActivityDate < :today
            WITH SECURITY_ENFORCED
            ORDER BY ActivityDate ASC, Priority DESC
            LIMIT 500
        ];
    }

    public Integer countOpenOverdueByOwner(Id ownerId) {
        if (ownerId == null) {
            return 0;
        }

        Date today = Date.today();
        return [
            SELECT COUNT()
            FROM Task
            WHERE OwnerId = :ownerId
              AND IsClosed = false
              AND ActivityDate < :today
            WITH SECURITY_ENFORCED
        ];
    }

    public Map<Id, Datetime> selectLastActivityDatetimeByWhatIds(Set<Id> whatIds, Id ownerId) {
        Map<Id, Datetime> lastActivityByWhatId = new Map<Id, Datetime>();
        if (whatIds == null || whatIds.isEmpty() || ownerId == null) {
            return lastActivityByWhatId;
        }

        for (Task taskRecord : [
            SELECT WhatId, ActivityDate, CompletedDateTime, CreatedDate
            FROM Task
            WHERE WhatId IN :whatIds
              AND OwnerId = :ownerId
              AND Status = 'Completed'
            WITH SECURITY_ENFORCED
            ORDER BY ActivityDate DESC, CompletedDateTime DESC
            LIMIT 5000
        ]) {
            if (taskRecord.WhatId == null || lastActivityByWhatId.containsKey(taskRecord.WhatId)) {
                continue;
            }
            Datetime touchValue = taskRecord.CompletedDateTime;
            if (touchValue == null && taskRecord.ActivityDate != null) {
                touchValue = Datetime.newInstance(taskRecord.ActivityDate, Time.newInstance(0, 0, 0, 0));
            }
            if (touchValue == null) {
                touchValue = taskRecord.CreatedDate;
            }
            lastActivityByWhatId.put(taskRecord.WhatId, touchValue);
        }

        return lastActivityByWhatId;
    }

    public Task selectById(Id taskId) {
        if (taskId == null) {
            return null;
        }

        List<Task> tasks = [
            SELECT Id, Subject, Status, ActivityDate, OwnerId, WhatId, WhoId, IsClosed
            FROM Task
            WHERE Id = :taskId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return tasks.isEmpty() ? null : tasks[0];
    }

    public List<Task> selectCompletedActivitiesForRecord(Id recordId, Id ownerId, Integer rowLimit) {
        if (recordId == null || ownerId == null) {
            return new List<Task>();
        }
        Integer safeLimit = rowLimit == null || rowLimit <= 0 ? 50 : Math.min(rowLimit, 200);
        return [
            SELECT Id, Subject, Description, Status, ActivityDate, Activity_Type__c,
                   CompletedDateTime, CreatedDate, Owner.Name
            FROM Task
            WHERE OwnerId = :ownerId
              AND Status = 'Completed'
              AND (WhoId = :recordId OR WhatId = :recordId)
            WITH USER_MODE
            ORDER BY ActivityDate DESC, CompletedDateTime DESC NULLS LAST, CreatedDate DESC
            LIMIT :safeLimit
        ];
    }

    public List<Task> selectOpenTasksForLead(Id leadId, Id ownerId) {
        if (leadId == null || ownerId == null) {
            return new List<Task>();
        }
        return [
            SELECT Id, Subject, ActivityDate, Priority, Status
            FROM Task
            WHERE OwnerId = :ownerId
              AND IsClosed = false
              AND WhoId = :leadId
            WITH USER_MODE
            ORDER BY ActivityDate ASC NULLS LAST, Priority DESC
            LIMIT 50
        ];
    }

    public List<Task> selectOpenTasksDueByOwner(Id ownerId, Date maxDueDate) {
        if (ownerId == null) {
            return new List<Task>();
        }

        Date dueCutoff = maxDueDate == null ? Date.today() : maxDueDate;
        return [
            SELECT Id, Subject, ActivityDate, Priority, Status, WhatId, WhoId, Activity_Type__c
            FROM Task
            WHERE OwnerId = :ownerId
              AND IsClosed = false
              AND (ActivityDate = null OR ActivityDate <= :dueCutoff)
            WITH SECURITY_ENFORCED
            ORDER BY ActivityDate ASC NULLS LAST, Priority DESC
            LIMIT 100
        ];
    }
}