/**
 * AuraEnabled data shapes for the external LO Perfect Day homepage.
 * Pure DTOs — no logic. Built by PerfectDayHomeBuilder, served by PerfectDayHomeService.
 */
public class PerfectDayHomeModels {

    public class PerfectDayHomeData {
        @AuraEnabled public String userName;
        @AuraEnabled public String userFirstName;
        @AuraEnabled public String todayFormatted;
        @AuraEnabled public String businessFocus;
        @AuraEnabled public Boolean onboardingComplete;
        @AuraEnabled public Integer dailyCompletionPercent;
        @AuraEnabled public Integer goalsCompleted;
        @AuraEnabled public Integer goalsTotal;
        @AuraEnabled public String paceStatus;
        @AuraEnabled public SummaryMetrics summaryMetrics;
        @AuraEnabled public List<PriorityCategory> priorities;
        @AuraEnabled public UpNextItem upNext;
        @AuraEnabled public GoalProgress goalProgress;
        @AuraEnabled public List<ExternalLoActivityRollupBuilder.CategoryScore> todayPlan;
        @AuraEnabled public List<ExternalLoPromptService.PromptItem> prompts;
        @AuraEnabled public List<RecentLogEntry> recentLog;
    }

    public class RecentLogEntry {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String subject;
        @AuraEnabled public String activityKey;
        @AuraEnabled public String shortLabel;
        @AuraEnabled public Integer activityCount;
        @AuraEnabled public String contactName;
        @AuraEnabled public String activityDateLabel;
        @AuraEnabled public String notes;
    }

    public class SummaryMetrics {
        @AuraEnabled public MetricCard dailyScore;
        @AuraEnabled public MetricCard goalsCompleted;
        @AuraEnabled public MetricCard overdueTasks;
        @AuraEnabled public MetricCard activitiesRemaining;
    }

    public class MetricCard {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        @AuraEnabled public String displayValue;
        @AuraEnabled public String supportText;
        @AuraEnabled public String tone;
        @AuraEnabled public Integer progressCurrent;
        @AuraEnabled public Integer progressTarget;
        @AuraEnabled public String drillObjectApiName;
        @AuraEnabled public String drillListViewApiName;
        @AuraEnabled public String drillFilterKey;
    }

    public class PriorityCategory {
        @AuraEnabled public String key;
        @AuraEnabled public String categoryType;
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
        @AuraEnabled public String urgency;
        @AuraEnabled public String description;
        @AuraEnabled public String drillObjectApiName;
        @AuraEnabled public String drillListViewApiName;
        @AuraEnabled public String emptyStateMessage;
    }

    public class UpNextItem {
        @AuraEnabled public String recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String title;
        @AuraEnabled public String actionLabel;
        @AuraEnabled public String reason;
        @AuraEnabled public String detail;
        @AuraEnabled public String source;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String slaLabel;
        @AuraEnabled public String impactLabel;
        @AuraEnabled public String categoryKey;
        @AuraEnabled public Boolean canLogOutcome;
        @AuraEnabled public Boolean canDefer;
        @AuraEnabled public Boolean canComplete;
        @AuraEnabled public Boolean canOpenRecord;
    }

    public class GoalProgress {
        @AuraEnabled public PeriodProgress today;
        @AuraEnabled public PeriodProgress thisWeek;
        @AuraEnabled public PeriodProgress thisMonth;
    }

    public class PeriodProgress {
        @AuraEnabled public List<GoalRowProgress> rows;
        @AuraEnabled public ActivityTypeProgress calls;
        @AuraEnabled public ActivityTypeProgress texts;
        @AuraEnabled public ActivityTypeProgress emails;
        @AuraEnabled public ActivityTypeProgress meetings;
        @AuraEnabled public ActivityTypeProgress openHouses;
        @AuraEnabled public Integer totalCompleted;
        @AuraEnabled public Integer totalGoal;
        @AuraEnabled public Integer completionPercent;
        @AuraEnabled public String drillObjectApiName;
        @AuraEnabled public String drillListViewApiName;
    }

    public class GoalRowProgress {
        @AuraEnabled public String activityKey;
        @AuraEnabled public String label;
        @AuraEnabled public Integer completed;
        @AuraEnabled public Integer goal;
        @AuraEnabled public Integer completionPercent;
    }

    public class ActivityTypeProgress {
        @AuraEnabled public Integer completed;
        @AuraEnabled public Integer goal;
        @AuraEnabled public Integer completionPercent;
    }
}