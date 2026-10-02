@isTest
private class ExternalLOBaselineHelperTest {

    private static External_LO_Baseline__mdt buildBaseline() {
        return new External_LO_Baseline__mdt(
            Calls_Daily_Goal__c = 2,
            Texts_Daily_Goal__c = 2,
            Emails_Daily_Goal__c = 1,
            Meetings_Daily_Goal__c = 1,
            Open_House_Daily_Goal__c = 0,
            Weekly_Multiplier__c = 5,
            Monthly_Multiplier__c = 20
        );
    }

    @isTest
    static void baselineGoalsScaleByCompanyMultipliers() {
        ExternalLOBaselineHelper.baselineOverride = buildBaseline();
        External_LO_Baseline__mdt baseline = ExternalLOBaselineHelper.getBaseline();

        ExternalLOBaselineHelper.ActivityMetrics daily = new ExternalLOBaselineHelper.ActivityMetrics();
        daily.setGoals(baseline, 1);
        System.assertEquals(6, daily.all, 'Daily goal should sum the company baseline.');
        System.assertEquals(2, daily.calls, 'Calls goal should come from the baseline.');

        ExternalLOBaselineHelper.ActivityMetrics weekly = new ExternalLOBaselineHelper.ActivityMetrics();
        weekly.setGoals(baseline, ExternalLOBaselineHelper.weeklyMultiplier(baseline));
        System.assertEquals(30, weekly.all, 'Weekly goal should scale by the weekly multiplier.');

        ExternalLOBaselineHelper.ActivityMetrics monthly = new ExternalLOBaselineHelper.ActivityMetrics();
        monthly.setGoals(baseline, ExternalLOBaselineHelper.monthlyMultiplier(baseline));
        System.assertEquals(120, monthly.all, 'Monthly goal should scale by the monthly multiplier.');
    }

    @isTest
    static void completionPercentHandlesZeroGoal() {
        System.assertEquals(75, ExternalLOBaselineHelper.completionPercent(3, 4));
        System.assertEquals(100, ExternalLOBaselineHelper.completionPercent(9, 4));
        System.assertEquals(0, ExternalLOBaselineHelper.completionPercent(3, 0),
            'A zero goal should never report progress.');
        System.assertEquals(0, ExternalLOBaselineHelper.completionPercent(null, null));
    }

    @isTest
    static void paceStatusCoversAllThreeStates() {
        // 13:00 is halfway through the 9–17 workday: expected percent is 50.
        ExternalLOBaselineHelper.nowOverride = Datetime.newInstance(Date.today(), Time.newInstance(13, 0, 0, 0));

        System.assertEquals('Perfect day complete', ExternalLOBaselineHelper.paceStatus(100, 4, 4));
        System.assertEquals('On pace', ExternalLOBaselineHelper.paceStatus(75, 4, 3));
        System.assertEquals('Behind pace', ExternalLOBaselineHelper.paceStatus(25, 4, 1));
        System.assertEquals(50, ExternalLOBaselineHelper.expectedCompletionPercentForCurrentTime());

        ExternalLOBaselineHelper.nowOverride = Datetime.newInstance(Date.today(), Time.newInstance(7, 0, 0, 0));
        System.assertEquals(0, ExternalLOBaselineHelper.expectedCompletionPercentForCurrentTime());
        ExternalLOBaselineHelper.nowOverride = Datetime.newInstance(Date.today(), Time.newInstance(18, 0, 0, 0));
        System.assertEquals(100, ExternalLOBaselineHelper.expectedCompletionPercentForCurrentTime());
    }

    @isTest
    static void goalsCompletedCountOnlyCountsMetGoals() {
        ExternalLOBaselineHelper.ActivityMetrics completed = new ExternalLOBaselineHelper.ActivityMetrics();
        ExternalLOBaselineHelper.ActivityMetrics goal = new ExternalLOBaselineHelper.ActivityMetrics();
        goal.calls = 2;
        goal.texts = 2;
        goal.all = 4;
        completed.calls = 2;
        completed.texts = 1;
        completed.all = 3;
        System.assertEquals(1, ExternalLOBaselineHelper.goalsCompletedCount(completed, goal));
    }

    @isTest
    static void realtorFollowUpUrgencyIsRedOnlyWhenOverdue() {
        System.assertEquals('orange', ExternalLOBaselineHelper.realtorFollowUpUrgency(null),
            'A never-touched partner needs attention but is not overdue.');
        System.assertEquals('', ExternalLOBaselineHelper.realtorFollowUpUrgency(System.now().addDays(-2)));
        System.assertEquals('orange', ExternalLOBaselineHelper.realtorFollowUpUrgency(System.now().addDays(-8)));
        System.assertEquals('red', ExternalLOBaselineHelper.realtorFollowUpUrgency(System.now().addDays(-15)));
    }

    @isTest
    static void newLeadSlaBreachUsesCompanyThreshold() {
        ExternalLOBaselineHelper.nowOverride = Datetime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0));
        System.assertEquals(true, ExternalLOBaselineHelper.isNewLeadSlaBreached(
            ExternalLOBaselineHelper.nowOverride.addMinutes(-30)));
        System.assertEquals(false, ExternalLOBaselineHelper.isNewLeadSlaBreached(
            ExternalLOBaselineHelper.nowOverride.addMinutes(-5)));
        System.assertEquals(false, ExternalLOBaselineHelper.isNewLeadSlaBreached(null));
    }

    @isTest
    static void preApprovalUrgencyIsRedOnlyForExpiredCredit() {
        Datetime sixDaysAgo = System.now().addDays(-6);

        Lead expiredCredit = new Lead(Credit_Expiration_Date__c = Date.today().addDays(-1));
        System.assertEquals('red', ExternalLOBaselineHelper.preApprovalReviewUrgency(expiredCredit, sixDaysAgo),
            'Expired credit is an SLA breach.');

        Lead stagnant = new Lead(
            Credit_Expiration_Date__c = Date.today().addDays(30),
            Last_Call_Attempt_RingCentral__c = System.now().addDays(-10),
            Last_SMS_Attempt_RingCentral__c = System.now().addDays(-10)
        );
        System.assertEquals('orange', ExternalLOBaselineHelper.preApprovalReviewUrgency(stagnant, sixDaysAgo));

        Lead fresh = new Lead(
            Credit_Expiration_Date__c = Date.today().addDays(30),
            Last_Call_Attempt_RingCentral__c = System.now().addDays(-1),
            Last_SMS_Attempt_RingCentral__c = System.now().addDays(-1)
        );
        System.assertEquals('', ExternalLOBaselineHelper.preApprovalReviewUrgency(fresh, sixDaysAgo));
    }

    @isTest
    static void loanMilestoneUrgencyIsRedOnlyWhenStale() {
        Transaction__c freshWaiting = new Transaction__c(
            Status__c = 'Waiting On Loan Officer',
            Current_Status_Since__c = Date.today()
        );
        System.assertEquals('orange', ExternalLOBaselineHelper.loanMilestoneUrgency(freshWaiting),
            'A fresh Waiting On Loan Officer needs attention but is not yet overdue.');

        Transaction__c staleWaiting = new Transaction__c(
            Status__c = 'Waiting On Loan Officer',
            Current_Status_Since__c = Date.today().addDays(-5)
        );
        System.assertEquals('red', ExternalLOBaselineHelper.loanMilestoneUrgency(staleWaiting));

        Transaction__c staleOther = new Transaction__c(
            Status__c = 'Processing',
            Current_Status_Since__c = Date.today().addDays(-5)
        );
        System.assertEquals('orange', ExternalLOBaselineHelper.loanMilestoneUrgency(staleOther));

        Transaction__c freshOther = new Transaction__c(
            Status__c = 'Processing',
            Current_Status_Since__c = Date.today()
        );
        System.assertEquals('', ExternalLOBaselineHelper.loanMilestoneUrgency(freshOther));
    }

    @isTest
    static void businessFocusOptionsAndUserGoalOverlay() {
        ExternalLOBaselineHelper.baselineOverride = new External_LO_Baseline__mdt(
            Calls_Daily_Goal__c = 10,
            Texts_Daily_Goal__c = 5,
            Emails_Daily_Goal__c = 5,
            Meetings_Daily_Goal__c = 1,
            Open_House_Daily_Goal__c = 0,
            Business_Focus_Options__c = 'Purchase Pipeline;Refinance'
        );
        List<String> options = ExternalLOBaselineHelper.businessFocusOptions();
        System.assertEquals(2, options.size(), 'Focus options should come from metadata.');
        System.assertEquals('Purchase Pipeline', options[0]);

        User onboarded = new User(
            External_LO_Onboarding_Complete__c = true,
            Calls_Daily_Goal__c = 3
        );
        External_LO_Baseline__mdt overlay = ExternalLOBaselineHelper.applyUserGoals(
            ExternalLOBaselineHelper.getBaseline(),
            onboarded
        );
        System.assertEquals(3, overlay.Calls_Daily_Goal__c.intValue(), 'Onboarded user goals should overlay the baseline.');
        System.assertEquals(5, overlay.Texts_Daily_Goal__c.intValue(), 'Unset user goals should keep the baseline.');

        User notOnboarded = new User(External_LO_Onboarding_Complete__c = false, Calls_Daily_Goal__c = 99);
        External_LO_Baseline__mdt company = ExternalLOBaselineHelper.applyUserGoals(
            ExternalLOBaselineHelper.getBaseline(),
            notOnboarded
        );
        System.assertEquals(10, company.Calls_Daily_Goal__c.intValue(), 'Users who have not finished setup keep the company baseline.');
    }

    @isTest
    static void activityCountIncrementsPortalMetrics() {
        ExternalLOBaselineHelper.ActivityMetrics metrics = new ExternalLOBaselineHelper.ActivityMetrics();
        metrics.add(new Task(Activity_Type__c = 'Text', Activity_Count__c = 3));
        metrics.add(new Task(Activity_Type__c = 'Text'));
        System.assertEquals(4, metrics.texts, 'Portal metrics honour Activity_Count__c and treat null as 1.');
        System.assertEquals(4, metrics.all);
    }

    @IsTest
    static void loggedActivityCountsAsContactWithoutRingCentral() {
        Datetime sixDaysAgo = System.now().addDays(-6);
        Lead loggedByHand = new Lead(LastName = 'Manual Logger');
        // LastActivityDate is read-only, so build the row the way SOQL would return it.
        loggedByHand = (Lead) JSON.deserialize(
            JSON.serialize(loggedByHand).removeEnd('}') + ',"LastActivityDate":"' + String.valueOf(Date.today()) + '"}',
            Lead.class
        );
        System.assertEquals('', ExternalLOBaselineHelper.preApprovalReviewUrgency(loggedByHand, sixDaysAgo),
            'A call logged today (no RingCentral) is contact');
        Lead neverTouched = new Lead(LastName = 'Untouched');
        System.assertEquals('orange', ExternalLOBaselineHelper.preApprovalReviewUrgency(neverTouched, sixDaysAgo));
    }
}
