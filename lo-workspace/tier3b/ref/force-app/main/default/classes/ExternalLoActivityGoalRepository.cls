/**
 * Canonical SOQL for External_LO_Activity_Goal__c. Reads in SYSTEM_MODE
 * filtered to the requested user so community FLS can stay read-only.
 */
public with sharing class ExternalLoActivityGoalRepository {
    private static ExternalLoActivityGoalRepository self;

    public static ExternalLoActivityGoalRepository getInstance() {
        if (self == null) {
            self = new ExternalLoActivityGoalRepository();
        }
        return self;
    }

    public List<External_LO_Activity_Goal__c> selectByUserId(Id userId) {
        if (userId == null) {
            return new List<External_LO_Activity_Goal__c>();
        }
        return [
            SELECT Id, User__c, Activity_Key__c, Weekly_Target__c, Is_Enabled__c, Unique_Key__c, OwnerId
            FROM External_LO_Activity_Goal__c
            WHERE User__c = :userId
            WITH SYSTEM_MODE
            LIMIT 200
        ];
    }

    public Map<String, External_LO_Activity_Goal__c> selectMapByUserId(Id userId) {
        Map<String, External_LO_Activity_Goal__c> byKey = new Map<String, External_LO_Activity_Goal__c>();
        for (External_LO_Activity_Goal__c row : selectByUserId(userId)) {
            if (!String.isBlank(row.Activity_Key__c)) {
                byKey.put(row.Activity_Key__c, row);
            }
        }
        return byKey;
    }
}