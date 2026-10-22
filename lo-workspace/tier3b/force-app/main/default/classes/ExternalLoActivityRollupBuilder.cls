/**
 * Pure category rollups for Partner Workspace scoreboards.
 * Daily uses ceil(weekly/workdays). Week uses weekly. Month/quarter use
 * round(weekly × days / 7). Historical Tasks without a category are
 * back-credited from Credit_Activity_Types__c.
 */
public with sharing class ExternalLoActivityRollupBuilder {
    public class CategoryScore {
        @AuraEnabled public String activityKey;
        @AuraEnabled public String categoryApiName;
        @AuraEnabled public String shortLabel;
        @AuraEnabled public String unitNoun;
        @AuraEnabled public String iconName;
        @AuraEnabled public String tone;
        @AuraEnabled public String cadence;
        @AuraEnabled public String coachingNote;
        @AuraEnabled public Integer completed;
        @AuraEnabled public Integer goal;
        @AuraEnabled public Integer remaining;
        @AuraEnabled public Integer percent;
        @AuraEnabled public Boolean isEnabled;
        @AuraEnabled public Boolean requiresContact;
        @AuraEnabled public Boolean isWinning;
        @AuraEnabled public Boolean isCoaching;
        @AuraEnabled public String pace; // ahead / on-track / behind (ExternalLOBaselineHelper.paceFor)
    }

    public class PeriodScore {
        @AuraEnabled public Integer totalCompleted;
        @AuraEnabled public Integer totalGoal;
        @AuraEnabled public Integer percent;
        @AuraEnabled public Integer expectedPercent;
        @AuraEnabled public List<CategoryScore> rows;
    }

    /**
     * Scores tasks against the user's plan for a period of periodDays.
     * Pass periodDays = 1 for today (daily target) or 7 for the week.
     */
    public static PeriodScore build(
        ExternalLoActivityPlanService.ActivityPlan plan,
        List<Task> tasks,
        Integer periodDays,
        Boolean useDailyTarget
    ) {
        return build(plan, tasks, null, periodDays, useDailyTarget);
    }

    /**
     * Today's plan mixes cadences: daily categories score today's tasks against
     * ceil(weekly/workdays), while a weekly category (partner meetings) scores
     * the whole week against the weekly target. weekTasks supplies that second
     * bucket and is ignored unless useDailyTarget is true.
     */
    public static PeriodScore build(
        ExternalLoActivityPlanService.ActivityPlan plan,
        List<Task> tasks,
        List<Task> weekTasks,
        Integer periodDays,
        Boolean useDailyTarget
    ) {
        PeriodScore score = new PeriodScore();
        score.rows = new List<CategoryScore>();
        score.totalCompleted = 0;
        score.totalGoal = 0;
        Map<String, Integer> completedByKey = completedByActivityKey(tasks);
        Map<String, Integer> weeklyCompletedByKey = weekTasks == null
            ? completedByKey
            : completedByActivityKey(weekTasks);
        Integer workdays = plan == null ? ExternalLoGoalMath.DEFAULT_WORKDAYS : plan.workdaysPerWeek;
        List<ExternalLoActivityPlanService.PlanRow> rows =
            plan == null ? new List<ExternalLoActivityPlanService.PlanRow>() : plan.rows;
        score.expectedPercent = ExternalLOBaselineHelper.expectedPercentForPeriod(periodDays);
        Integer weekExpected = ExternalLOBaselineHelper.expectedPercentForPeriod(7);
        for (ExternalLoActivityPlanService.PlanRow planRow : rows) {
            if (planRow.isEnabled != true) {
                continue;
            }
            CategoryScore row = new CategoryScore();
            row.activityKey = planRow.activityKey;
            row.categoryApiName = planRow.categoryApiName;
            row.shortLabel = planRow.shortLabel;
            row.unitNoun = planRow.unitNoun;
            row.iconName = planRow.iconName;
            row.tone = planRow.tone;
            row.cadence = planRow.cadence;
            row.coachingNote = planRow.coachingNote;
            row.requiresContact = planRow.requiresContact;
            row.isEnabled = true;
            Boolean scoreWholeWeek = useDailyTarget == true && isWeeklyCadence(planRow);
            Map<String, Integer> source = scoreWholeWeek ? weeklyCompletedByKey : completedByKey;
            row.completed = source.containsKey(planRow.activityKey)
                ? source.get(planRow.activityKey)
                : 0;
            if (scoreWholeWeek) {
                row.goal = planRow.weeklyTarget == null ? 0 : planRow.weeklyTarget;
            } else if (useDailyTarget == true) {
                row.goal = ExternalLoGoalMath.dailyTarget(planRow.weeklyTarget, workdays);
            } else if (periodDays != null && periodDays == 7) {
                row.goal = planRow.weeklyTarget == null ? 0 : planRow.weeklyTarget;
            } else {
                row.goal = ExternalLoGoalMath.rangeTarget(planRow.weeklyTarget, periodDays);
            }
            row.remaining = Math.max(0, row.goal - row.completed);
            row.percent = ExternalLOBaselineHelper.completionPercent(row.completed, row.goal);
            row.isWinning = row.goal > 0 && row.completed >= row.goal;
            row.pace = ExternalLOBaselineHelper.paceFor(row.percent, scoreWholeWeek ? weekExpected : score.expectedPercent);
            row.isCoaching = row.goal > 0 && row.pace == 'behind';
            score.rows.add(row);
            // Capped: extra calls must not hide an untouched category.
            score.totalCompleted += row.goal > 0 ? Math.min(row.completed, row.goal) : 0;
            score.totalGoal += row.goal;
        }
        score.percent = ExternalLOBaselineHelper.completionPercent(score.totalCompleted, score.totalGoal);
        return score;
    }

    /**
     * A category tracked weekly is never split across working days.
     */
    @TestVisible
    private static Boolean isWeeklyCadence(ExternalLoActivityPlanService.PlanRow planRow) {
        return planRow != null
            && planRow.cadence != null
            && planRow.cadence.trim().toLowerCase() == 'weekly';
    }

    /**
     * Maps a Task to an activity key via category, then Credit_Activity_Types.
     */
    public static String activityKeyFor(Task taskRecord) {
        if (taskRecord == null) {
            return null;
        }
        if (!String.isBlank(taskRecord.Activity_Category__c)) {
            ExternalLoActivityCatalog.ActivityDefinition byCategory =
                ExternalLoActivityCatalog.activityByCategory(taskRecord.Activity_Category__c);
            if (byCategory != null) {
                return byCategory.activityKey;
            }
        }
        ExternalLoActivityCatalog.ActivityDefinition byType = null;
        if (!String.isBlank(taskRecord.Activity_Type__c)) {
            for (ExternalLoActivityCatalog.ActivityDefinition item : ExternalLoActivityCatalog.activeActivities()) {
                if (item.creditActivityTypes != null && item.creditActivityTypes.contains(taskRecord.Activity_Type__c)) {
                    byType = item;
                    break;
                }
            }
        }
        return byType == null ? null : byType.activityKey;
    }

    public static Integer countOf(Task taskRecord) {
        if (taskRecord == null || taskRecord.Activity_Count__c == null) {
            return 1;
        }
        Integer value = taskRecord.Activity_Count__c.intValue();
        return value < 1 ? 1 : value;
    }

    private static Map<String, Integer> completedByActivityKey(List<Task> tasks) {
        Map<String, Integer> byKey = new Map<String, Integer>();
        if (tasks == null) {
            return byKey;
        }
        for (Task taskRecord : tasks) {
            String activityKey = activityKeyFor(taskRecord);
            if (String.isBlank(activityKey)) {
                continue;
            }
            Integer current = byKey.containsKey(activityKey) ? byKey.get(activityKey) : 0;
            byKey.put(activityKey, current + countOf(taskRecord));
        }
        return byKey;
    }
}