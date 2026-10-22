/**
 * Week / month / quarter category scoreboards for My Progress.
 */
public with sharing class ExternalLoProgressService {
    public class ProgressPayload {
        @AuraEnabled public String businessFocus;
        @AuraEnabled public Integer workdaysPerWeek;
        @AuraEnabled public ExternalLoActivityRollupBuilder.PeriodScore week;
        @AuraEnabled public ExternalLoActivityRollupBuilder.PeriodScore month;
        @AuraEnabled public ExternalLoActivityRollupBuilder.PeriodScore quarter;
    }

    /**
     * Scores completed Tasks in the current week, month, and quarter.
     */
    public static ProgressPayload getProgress(Id userId) {
        User userRecord = UserRepository.getInstance().selectPortalProfile(userId);
        ExternalLoActivityPlanService.ActivityPlan plan = ExternalLoActivityPlanService.getPlan(userId, userRecord);
        Date today = Date.today();
        Date startOfWeek = ExternalLoGoalMath.weekStartMonday(today);
        Date endOfWeek = ExternalLoGoalMath.weekEndSunday(today);
        Date startOfMonth = today.toStartOfMonth();
        Date endOfMonth = startOfMonth.addMonths(1).addDays(-1);
        Date startOfQuarter = startOfQuarter(today);
        Date endOfQuarter = startOfQuarter.addMonths(3).addDays(-1);
        Date rangeStart = earliest(new List<Date>{ startOfWeek, startOfMonth, startOfQuarter });
        Date rangeEnd = latest(new List<Date>{ endOfWeek, endOfMonth, endOfQuarter, today });

        List<Task> tasks = new TaskRepository().selectCompletedActivitiesByOwnerForDateRange(
            userId,
            rangeStart,
            rangeEnd
        );
        ProgressPayload payload = new ProgressPayload();
        payload.businessFocus = userRecord?.Business_Focus__c;
        payload.workdaysPerWeek = plan.workdaysPerWeek;
        payload.week = ExternalLoActivityRollupBuilder.build(
            plan,
            inRange(tasks, startOfWeek, endOfWeek),
            7,
            false
        );
        Integer monthDays = startOfMonth.daysBetween(endOfMonth) + 1;
        payload.month = ExternalLoActivityRollupBuilder.build(
            plan,
            inRange(tasks, startOfMonth, endOfMonth),
            monthDays,
            false
        );
        Integer quarterDays = startOfQuarter.daysBetween(endOfQuarter) + 1;
        payload.quarter = ExternalLoActivityRollupBuilder.build(
            plan,
            inRange(tasks, startOfQuarter, endOfQuarter),
            quarterDays,
            false
        );
        return payload;
    }

    public static Date startOfQuarter(Date today) {
        Date value = today == null ? Date.today() : today;
        Integer month = value.month();
        Integer quarterStartMonth = ((month - 1) / 3) * 3 + 1;
        return Date.newInstance(value.year(), quarterStartMonth, 1);
    }

    private static List<Task> inRange(List<Task> tasks, Date startDate, Date endDate) {
        List<Task> rows = new List<Task>();
        if (tasks == null) {
            return rows;
        }
        for (Task taskRecord : tasks) {
            if (taskRecord.ActivityDate == null) {
                continue;
            }
            if (taskRecord.ActivityDate >= startDate && taskRecord.ActivityDate <= endDate) {
                rows.add(taskRecord);
            }
        }
        return rows;
    }

    private static Date earliest(List<Date> values) {
        Date minValue = values[0];
        for (Date value : values) {
            if (value < minValue) {
                minValue = value;
            }
        }
        return minValue;
    }

    private static Date latest(List<Date> values) {
        Date maxValue = values[0];
        for (Date value : values) {
            if (value > maxValue) {
                maxValue = value;
            }
        }
        return maxValue;
    }
}