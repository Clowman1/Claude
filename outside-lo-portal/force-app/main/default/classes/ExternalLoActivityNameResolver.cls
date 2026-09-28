/**
 * Resolves Task WhoId/WhatId to a display name for portal activity lists.
 */
public with sharing class ExternalLoActivityNameResolver {
    /**
     * Names for the Who/What records on the given tasks. All related-object
     * reads use SYSTEM_MODE so community licenses without Contact/Account FLS
     * still resolve Lead/loan labels without throwing SECURITY_ENFORCED.
     */
    public static Map<Id, String> resolveTaskRelatedNames(List<Task> taskRecords) {
        Map<Id, String> namesById = new Map<Id, String>();
        if (taskRecords == null || taskRecords.isEmpty()) {
            return namesById;
        }

        Set<Id> whoIds = new Set<Id>();
        Set<Id> whatIds = new Set<Id>();
        for (Task taskRecord : taskRecords) {
            if (taskRecord.WhoId != null) {
                whoIds.add(taskRecord.WhoId);
            }
            if (taskRecord.WhatId != null) {
                whatIds.add(taskRecord.WhatId);
            }
        }

        if (!whoIds.isEmpty()) {
            for (Lead leadRecord : [
                SELECT Id, Name
                FROM Lead
                WHERE Id IN :whoIds
                WITH SYSTEM_MODE
            ]) {
                namesById.put(leadRecord.Id, leadRecord.Name);
            }
            for (Contact contactRecord : [
                SELECT Id, Name
                FROM Contact
                WHERE Id IN :whoIds
                WITH SYSTEM_MODE
            ]) {
                namesById.put(contactRecord.Id, contactRecord.Name);
            }
        }

        if (!whatIds.isEmpty()) {
            for (Account accountRecord : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :whatIds
                WITH SYSTEM_MODE
            ]) {
                namesById.put(accountRecord.Id, accountRecord.Name);
            }
            for (Opportunity opportunityRecord : [
                SELECT Id, Name
                FROM Opportunity
                WHERE Id IN :whatIds
                WITH SYSTEM_MODE
            ]) {
                namesById.put(opportunityRecord.Id, opportunityRecord.Name);
            }
            for (Transaction__c loanRecord : [
                SELECT Id, Name
                FROM Transaction__c
                WHERE Id IN :whatIds
                WITH SYSTEM_MODE
            ]) {
                namesById.put(loanRecord.Id, loanRecord.Name);
            }
        }

        return namesById;
    }

    /**
     * Display name for a single task, or a generic fallback.
     */
    public static String formatTaskRelatedLabel(Task taskRecord, Map<Id, String> relatedNames) {
        if (taskRecord == null) {
            return 'Activity';
        }
        if (taskRecord.WhoId != null && relatedNames != null && relatedNames.containsKey(taskRecord.WhoId)) {
            return relatedNames.get(taskRecord.WhoId);
        }
        if (taskRecord.WhatId != null && relatedNames != null && relatedNames.containsKey(taskRecord.WhatId)) {
            return relatedNames.get(taskRecord.WhatId);
        }
        return 'Activity';
    }
}