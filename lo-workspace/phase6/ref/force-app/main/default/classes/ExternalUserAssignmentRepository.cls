public with sharing class ExternalUserAssignmentRepository {
    private static ExternalUserAssignmentRepository self;

    public static ExternalUserAssignmentRepository getInstance() {
        if (self == null) {
            self = new ExternalUserAssignmentRepository();
        }
        return self;
    }

    public Set<Id> selectContactIdsByUserId(Id userId) {
        Set<Id> contactIds = new Set<Id>();
        if (userId == null) {
            return contactIds;
        }
        for (External_User_Assignment__c assignment : [
            SELECT Contact__c
            FROM External_User_Assignment__c
            WHERE User__c = :userId
              AND Contact__c != null
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            contactIds.add(assignment.Contact__c);
        }
        return contactIds;
    }

    public Set<String> selectUniqueKeys(Id userId, Set<Id> contactIds) {
        Set<String> keys = new Set<String>();
        if (userId == null || contactIds == null || contactIds.isEmpty()) {
            return keys;
        }
        for (External_User_Assignment__c assignment : [
            SELECT Unique_Key__c
            FROM External_User_Assignment__c
            WHERE User__c = :userId
              AND Contact__c IN :contactIds
            WITH SYSTEM_MODE
        ]) {
            if (!String.isBlank(assignment.Unique_Key__c)) {
                keys.add(assignment.Unique_Key__c.toLowerCase());
            }
        }
        return keys;
    }
}