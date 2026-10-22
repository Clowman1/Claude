/**
 * Resolves the running user's activity plan. Users without goal rows receive
 * CMDT weekly defaults so already-onboarded LOs are not stranded.
 */
public with sharing class ExternalLoActivityPlanService {

    public class PlanRow {
        @AuraEnabled public String activityKey;
        @AuraEnabled public String categoryApiName;
        @AuraEnabled public String shortLabel;
        @AuraEnabled public String unitNoun;
        @AuraEnabled public String description;
        @AuraEnabled public String coachingNote;
        @AuraEnabled public String iconName;
        @AuraEnabled public String tone;
        @AuraEnabled public String cadence;
        @AuraEnabled public Integer weeklyTarget;
        @AuraEnabled public Integer dailyTarget;
        @AuraEnabled public Boolean isEnabled;
        @AuraEnabled public Boolean requiresContact;
        @AuraEnabled public List<Integer> targetOptions;
        @AuraEnabled public Integer sortOrder;
    }

    public class ActivityPlan {
        @AuraEnabled public Integer workdaysPerWeek;
        @AuraEnabled public String businessFocus;
        @AuraEnabled public List<PlanRow> rows;
    }

    public static ActivityPlan getPlan(Id userId) {
        return getPlan(userId, UserRepository.getInstance().selectPortalProfile(userId));
    }

    public static ActivityPlan getPlan(Id userId, User userRecord) {
        ActivityPlan plan = new ActivityPlan();
        plan.workdaysPerWeek = ExternalLoGoalMath.clampWorkdays(userRecord?.ExtLO_Workdays_Per_Week__c);
        plan.businessFocus = userRecord?.Business_Focus__c;
        plan.rows = new List<PlanRow>();
        Map<String, External_LO_Activity_Goal__c> saved = ExternalLoActivityGoalRepository.getInstance()
            .selectMapByUserId(userId);
        for (ExternalLoActivityCatalog.ActivityDefinition activity : ExternalLoActivityCatalog.activeActivities()) {
            PlanRow row = new PlanRow();
            row.activityKey = activity.activityKey;
            row.categoryApiName = activity.categoryApiName;
            row.shortLabel = activity.shortLabel;
            row.unitNoun = activity.unitNoun;
            row.description = activity.description;
            row.coachingNote = activity.coachingNote;
            row.iconName = activity.iconName;
            row.tone = activity.tone;
            row.cadence = activity.cadence;
            row.requiresContact = activity.requiresContact;
            row.targetOptions = activity.targetOptions;
            row.sortOrder = activity.sortOrder;
            External_LO_Activity_Goal__c savedRow = saved.get(activity.activityKey);
            if (savedRow != null) {
                row.weeklyTarget = savedRow.Weekly_Target__c == null ? 0 : savedRow.Weekly_Target__c.intValue();
                row.isEnabled = savedRow.Is_Enabled__c == true;
            } else {
                row.weeklyTarget = activity.defaultWeeklyTarget;
                row.isEnabled = true;
            }
            row.dailyTarget = ExternalLoGoalMath.dailyTarget(row.weeklyTarget, plan.workdaysPerWeek);
            plan.rows.add(row);
        }
        return plan;
    }

    public static Map<String, Integer> weeklyTargetsByKey(ActivityPlan plan) {
        Map<String, Integer> byKey = new Map<String, Integer>();
        if (plan?.rows == null) {
            return byKey;
        }
        for (PlanRow row : plan.rows) {
            if (row.isEnabled == true) {
                byKey.put(row.activityKey, row.weeklyTarget);
            }
        }
        return byKey;
    }
}