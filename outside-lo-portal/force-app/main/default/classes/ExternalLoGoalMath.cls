/**
 * Pure target math for Partner Workspace category scoring.
 * Daily uses ceil(weekly / workdays). Week uses the weekly target directly.
 * Month and quarter use round(weekly * days / 7).
 */
public with sharing class ExternalLoGoalMath {
    public static final Integer DEFAULT_WORKDAYS = 5;
    public static final Integer MIN_WORKDAYS = 1;
    public static final Integer MAX_WORKDAYS = 7;

    public static Integer clampWorkdays(Decimal workdays) {
        Integer value = workdays == null ? DEFAULT_WORKDAYS : workdays.intValue();
        if (value < MIN_WORKDAYS) {
            return MIN_WORKDAYS;
        }
        if (value > MAX_WORKDAYS) {
            return MAX_WORKDAYS;
        }
        return value;
    }

    public static Integer dailyTarget(Integer weeklyTarget, Integer workdays) {
        Integer weekly = weeklyTarget == null ? 0 : weeklyTarget;
        Integer days = clampWorkdays(workdays);
        if (weekly <= 0) {
            return 0;
        }
        return (Integer) Math.ceil(weekly / (Decimal) days);
    }

    /**
     * Partner Workspace weeks are Monday–Sunday, matching My Progress.
     * Salesforce toStartOfWeek() is Sunday in en_US, so add one day.
     */
    public static Date weekStartMonday(Date today) {
        Date value = today == null ? Date.today() : today;
        return value.toStartOfWeek().addDays(1);
    }

    public static Date weekEndSunday(Date today) {
        return weekStartMonday(today).addDays(6);
    }

    public static Integer rangeTarget(Integer weeklyTarget, Integer daysInRange) {
        Integer weekly = weeklyTarget == null ? 0 : weeklyTarget;
        Integer days = daysInRange == null ? 0 : daysInRange;
        if (weekly <= 0 || days <= 0) {
            return 0;
        }
        return (Integer) Math.round((weekly * days) / 7.0);
    }

    public static Integer clampCount(Integer activityCount) {
        Integer value = activityCount == null ? 1 : activityCount;
        if (value < 1) {
            return 1;
        }
        if (value > 50) {
            return 50;
        }
        return value;
    }
}