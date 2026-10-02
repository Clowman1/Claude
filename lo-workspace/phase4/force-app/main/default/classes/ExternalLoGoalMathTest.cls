@isTest
private class ExternalLoGoalMathTest {

    @isTest
    static void dailyTargetUsesCeilAndDoesNotDeriveWeekly() {
        System.assertEquals(2, ExternalLoGoalMath.dailyTarget(10, 5), '10 / 5 is exact.');
        System.assertEquals(3, ExternalLoGoalMath.dailyTarget(10, 4), 'ceil(10/4) is 3 so daily * workdays can exceed weekly.');
        System.assertEquals(0, ExternalLoGoalMath.dailyTarget(0, 5));
        System.assertEquals(0, ExternalLoGoalMath.dailyTarget(null, null));
        Integer daily = ExternalLoGoalMath.dailyTarget(10, 4);
        System.assert(daily * 4 >= 10, 'Never derive weekly from daily; ceil means daily * workdays >= weekly.');
    }

    @isTest
    static void rangeMathCoversFebruaryMonthAndQuarter() {
        System.assertEquals(40, ExternalLoGoalMath.rangeTarget(10, 28), '28-day February is weekly * 4.');
        System.assertEquals(44, ExternalLoGoalMath.rangeTarget(10, 31), '31-day month rounds 10*31/7.');
        System.assertEquals(131, ExternalLoGoalMath.rangeTarget(10, 92), '92-day quarter rounds 10*92/7.');
        System.assertEquals(0, ExternalLoGoalMath.rangeTarget(10, 0));
    }

    @isTest
    static void workdaysAndCountClamp() {
        System.assertEquals(5, ExternalLoGoalMath.clampWorkdays(null));
        System.assertEquals(1, ExternalLoGoalMath.clampWorkdays(0));
        System.assertEquals(7, ExternalLoGoalMath.clampWorkdays(99));
        System.assertEquals(3, ExternalLoGoalMath.clampWorkdays(3));
        System.assertEquals(1, ExternalLoGoalMath.clampCount(null));
        System.assertEquals(1, ExternalLoGoalMath.clampCount(0));
        System.assertEquals(50, ExternalLoGoalMath.clampCount(200));
        System.assertEquals(7, ExternalLoGoalMath.clampCount(7));
    }

    @isTest
    static void weekBoundsAreMondayThroughSunday() {
        Date today = Date.today();
        Date monday = ExternalLoGoalMath.weekStartMonday(today);
        Date sunday = ExternalLoGoalMath.weekEndSunday(today);
        System.assertEquals(6, monday.daysBetween(sunday));
        System.assert(monday <= today && today <= sunday);
    }

    @IsTest
    static void sundayBelongsToTheWeekThatStartedSixDaysEarlier() {
        // 2026-10-04 is a Sunday; toStartOfWeek()+1 used to return 2026-10-05.
        System.assertEquals(Date.newInstance(2026, 9, 28), ExternalLoGoalMath.weekStartMonday(Date.newInstance(2026, 10, 4)));
        System.assertEquals(Date.newInstance(2026, 10, 4), ExternalLoGoalMath.weekEndSunday(Date.newInstance(2026, 10, 4)));
        System.assertEquals(Date.newInstance(2026, 9, 28), ExternalLoGoalMath.weekStartMonday(Date.newInstance(2026, 9, 28)), 'A Monday is its own week start');
    }
}
