/**
 * Upserts per-user weekly targets on Unique_Key__c in SYSTEM_MODE.
 * OwnerId is set to the plan user so Private sharing stays aligned.
 */
public with sharing class ExternalLoActivityGoalWriter {
    public static void upsertGoals(Id userId, List<External_LO_Activity_Goal__c> goals) {
        if (userId == null || goals == null || goals.isEmpty()) {
            return;
        }
        List<External_LO_Activity_Goal__c> toUpsert = new List<External_LO_Activity_Goal__c>();
        for (External_LO_Activity_Goal__c goal : goals) {
            if (goal == null || String.isBlank(goal.Activity_Key__c)) {
                continue;
            }
            External_LO_Activity_Goal__c row = new External_LO_Activity_Goal__c();
            row.User__c = userId;
            row.OwnerId = userId;
            row.Activity_Key__c = goal.Activity_Key__c;
            row.Weekly_Target__c = goal.Weekly_Target__c;
            row.Is_Enabled__c = goal.Is_Enabled__c == null ? true : goal.Is_Enabled__c;
            row.Unique_Key__c = uniqueKey(userId, goal.Activity_Key__c);
            toUpsert.add(row);
        }
        if (toUpsert.isEmpty()) {
            return;
        }
        Database.upsert(toUpsert, External_LO_Activity_Goal__c.Unique_Key__c, AccessLevel.SYSTEM_MODE);
    }

    public static String uniqueKey(Id userId, String activityKey) {
        return String.valueOf(userId) + ':' + activityKey;
    }
}