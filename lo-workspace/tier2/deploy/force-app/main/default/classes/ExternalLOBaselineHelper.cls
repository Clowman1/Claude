/**
 * Pure calculations for external LO Perfect Day pace, urgency, and activity rollups.
 * Goal targets come from the company-wide External_LO_Baseline__mdt record so every
 * external LO is measured against the same standard; SLA and urgency thresholds are
 * company constants below.
 */
public class ExternalLOBaselineHelper {

    public static final Integer NEW_LEAD_SLA_MINUTES = 15;
    public static final Integer REALTOR_FOLLOW_UP_ORANGE_DAYS = 7;
    public static final Integer REALTOR_FOLLOW_UP_RED_DAYS = 14;
    public static final Integer PRE_APPROVAL_STAGNANT_DAYS = 6;
    public static final Integer WORKDAY_START_HOUR = 9;
    public static final Integer WORKDAY_END_HOUR = 17;

    private static final Integer DEFAULT_WEEKLY_MULTIPLIER = 5;
    private static final Integer DEFAULT_MONTHLY_MULTIPLIER = 20;

    @TestVisible
    private static External_LO_Baseline__mdt baselineOverride;

    @TestVisible
    private static Datetime nowOverride;

    public static final Set<String> CONSUMER_LEAD_RECORD_TYPES = new Set<String>{
        'Consumer_Lead_record_type',
        'Consumer_Under_Contract_Lead_Record_Type'
    };

    public static final List<String> ACTIVE_LOAN_STATUSES = new List<String>{
        'TRID Application',
        'Open',
        'Disclosures Out',
        'Pre-Processing',
        'Processing',
        'Submitted',
        'Conditionally Approved',
        'Re-Submitted',
        'Approved',
        'Waiting On Loan Officer',
        'Closing',
        'Funding',
        'PC Review'
    };

    /**
     * Company-wide goal baseline. Falls back to zero targets when the metadata
     * record is missing so the page still renders instead of throwing.
     */
    public static External_LO_Baseline__mdt getBaseline() {
        if (baselineOverride != null) {
            return baselineOverride;
        }
        External_LO_Baseline__mdt baseline = External_LO_Baseline__mdt.getInstance('Default');
        if (baseline == null) {
            baseline = new External_LO_Baseline__mdt(
                Calls_Daily_Goal__c = 0,
                Texts_Daily_Goal__c = 0,
                Emails_Daily_Goal__c = 0,
                Meetings_Daily_Goal__c = 0,
                Open_House_Daily_Goal__c = 0,
                Weekly_Multiplier__c = DEFAULT_WEEKLY_MULTIPLIER,
                Monthly_Multiplier__c = DEFAULT_MONTHLY_MULTIPLIER,
                Business_Focus_Options__c = 'Realtor Relationships;Purchase Pipeline;Refinance;Past Clients'
            );
        }
        return baseline;
    }

    public static Integer weeklyMultiplier(External_LO_Baseline__mdt baseline) {
        return safeGoal(baseline?.Weekly_Multiplier__c, DEFAULT_WEEKLY_MULTIPLIER);
    }

    public static Integer monthlyMultiplier(External_LO_Baseline__mdt baseline) {
        return safeGoal(baseline?.Monthly_Multiplier__c, DEFAULT_MONTHLY_MULTIPLIER);
    }

    /**
     * Tenant base URL for Arive deep links. Null when not configured so the UI
     * can fall back to a clear "not linked" state instead of a broken link.
     */
    public static String ariveBaseUrl() {
        String base = getBaseline()?.Arive_Base_Url__c;
        if (String.isBlank(base)) {
            return null;
        }
        return base.trim().removeEnd('/');
    }

    /**
     * Three-tier focus labels: CMDT (production) → baseline string → hardcoded
     * defaults. Tests that set baselineOverride skip CMDT so they stay isolated.
     */
    public static List<String> businessFocusOptions() {
        List<String> defaults = new List<String>{
            'Realtor Relationships',
            'Purchase Pipeline',
            'Refinance',
            'Past Clients'
        };
        if (baselineOverride == null && !External_LO_Focus__mdt.getAll().isEmpty()) {
            List<String> fromCmdt = new List<String>();
            for (ExternalLoActivityCatalog.FocusDefinition focus : ExternalLoActivityCatalog.activeFocuses()) {
                fromCmdt.add(focus.label);
            }
            if (!fromCmdt.isEmpty()) {
                return fromCmdt;
            }
        }
        String raw = getBaseline()?.Business_Focus_Options__c;
        if (String.isBlank(raw)) {
            return defaults;
        }
        List<String> options = new List<String>();
        for (String part : raw.split(';')) {
            String trimmed = part?.trim();
            if (!String.isBlank(trimmed)) {
                options.add(trimmed);
            }
        }
        return options.isEmpty() ? defaults : options;
    }

    public static External_LO_Baseline__mdt applyUserGoals(External_LO_Baseline__mdt baseline, User userRecord) {
        External_LO_Baseline__mdt working = baseline == null ? getBaseline() : baseline;
        if (userRecord == null || userRecord.External_LO_Onboarding_Complete__c != true) {
            return working;
        }
        External_LO_Baseline__mdt overlay = working.clone(false, true, false, false);
        if (userRecord.Calls_Daily_Goal__c != null) {
            overlay.Calls_Daily_Goal__c = userRecord.Calls_Daily_Goal__c;
        }
        if (userRecord.Texts_Daily_Goal__c != null) {
            overlay.Texts_Daily_Goal__c = userRecord.Texts_Daily_Goal__c;
        }
        if (userRecord.Emails_Daily_Goal__c != null) {
            overlay.Emails_Daily_Goal__c = userRecord.Emails_Daily_Goal__c;
        }
        if (userRecord.Meetings_Daily_Goal__c != null) {
            overlay.Meetings_Daily_Goal__c = userRecord.Meetings_Daily_Goal__c;
        }
        if (userRecord.Open_House_Daily_Goal__c != null) {
            overlay.Open_House_Daily_Goal__c = userRecord.Open_House_Daily_Goal__c;
        }
        return overlay;
    }

    private static Integer safeGoal(Decimal goalValue, Integer fallback) {
        return goalValue == null ? fallback : goalValue.intValue();
    }

    private static Datetime currentTime() {
        return nowOverride == null ? Datetime.now() : nowOverride;
    }

    public class ActivityMetrics {
        public Integer all = 0;
        public Integer calls = 0;
        public Integer texts = 0;
        public Integer emails = 0;
        public Integer meetings = 0;
        public Integer openHouses = 0;

        public void add(Task taskRecord) {
            Integer increment = taskRecord.Activity_Count__c == null ? 1 : taskRecord.Activity_Count__c.intValue();
            if (increment < 1) {
                increment = 1;
            }
            all += increment;
            switch on taskRecord.Activity_Type__c {
                when 'Call - Prospecting', 'Call - Active Agent' {
                    calls += increment;
                }
                when 'Text' {
                    texts += increment;
                }
                when 'Email' {
                    emails += increment;
                }
                when 'Meeting (New Agent)', 'Meeting (Active Agent)' {
                    meetings += increment;
                }
                when 'Open House' {
                    openHouses += increment;
                }
            }
        }

        public void setGoals(External_LO_Baseline__mdt baseline, Integer multiplier) {
            Integer goalMultiplier = multiplier == null ? 1 : multiplier;
            calls = safeBaselineGoal(baseline?.Calls_Daily_Goal__c) * goalMultiplier;
            texts = safeBaselineGoal(baseline?.Texts_Daily_Goal__c) * goalMultiplier;
            emails = safeBaselineGoal(baseline?.Emails_Daily_Goal__c) * goalMultiplier;
            meetings = safeBaselineGoal(baseline?.Meetings_Daily_Goal__c) * goalMultiplier;
            openHouses = safeBaselineGoal(baseline?.Open_House_Daily_Goal__c) * goalMultiplier;
            all = calls + texts + emails + meetings + openHouses;
        }

        private Integer safeBaselineGoal(Decimal goalValue) {
            return goalValue == null ? 0 : goalValue.intValue();
        }
    }

    public static Integer completionPercent(Integer completed, Integer goal) {
        if (goal == null || goal <= 0) {
            return 0;
        }
        Integer completedValue = completed == null ? 0 : completed;
        return Math.min(100, (Integer) Math.floor((completedValue * 100.0) / goal));
    }

    public static String paceStatus(Integer completionPercent, Integer dailyGoal, Integer dailyCompleted) {
        if (dailyGoal != null && dailyGoal > 0 && dailyCompleted != null && dailyCompleted >= dailyGoal) {
            return 'Perfect day complete';
        }
        if (completionPercent == null) {
            completionPercent = 0;
        }
        Integer expectedPercent = expectedCompletionPercentForCurrentTime();
        if (completionPercent < expectedPercent) {
            return 'Behind pace';
        }
        return 'On pace';
    }

    // ------------------------------------------------------------------ one pace rule (decided 2026-10-20)
    // Expected % = (full Mon–Fri workdays before today + today's share of the 9–5 day) / workdays in the period.
    // On pace = at least 90% of expected; 'ahead' = goal met. Every LO Workspace screen reads this.

    public static final Decimal PACE_TOLERANCE = 0.9;

    /** periodDays as the callers pass it: 1 = today, 7 = this week, 28–31 = this month, more = this quarter. */
    public static Integer expectedPercentForPeriod(Integer periodDays) {
        Date today = currentTime().date();
        Decimal todayShare = isWorkday(today) ? expectedCompletionPercentForCurrentTime() / 100.0 : 0;
        if (periodDays == null || periodDays <= 1) {
            return isWorkday(today) ? expectedCompletionPercentForCurrentTime() : 0;
        }
        Date startDate;
        Date endDate;
        if (periodDays == 7) {
            startDate = today.addDays(1 - isoDayOfWeek(today)); // Monday
            endDate = startDate.addDays(6);
        } else if (periodDays <= 31) {
            startDate = today.toStartOfMonth();
            endDate = startDate.addMonths(1).addDays(-1);
        } else {
            Integer firstMonth = ((today.month() - 1) / 3) * 3 + 1;
            startDate = Date.newInstance(today.year(), firstMonth, 1);
            endDate = startDate.addMonths(3).addDays(-1);
        }
        Integer total = workdaysBetween(startDate, endDate);
        if (total == 0) {
            return 0;
        }
        Decimal elapsed = workdaysBetween(startDate, today.addDays(-1)) + todayShare;
        return (Integer) Math.min(100, Math.round(elapsed / total * 100));
    }

    /** 'ahead' (goal met), 'on-track' or 'behind'. */
    public static String paceFor(Integer percent, Integer expectedPercent) {
        Integer value = percent == null ? 0 : percent;
        if (value >= 100) {
            return 'ahead';
        }
        return value >= (expectedPercent == null ? 0 : expectedPercent) * PACE_TOLERANCE ? 'on-track' : 'behind';
    }

    /** Banner: complete only when every category hit its goal; weekends never read as behind. */
    public static String dayPaceStatus(Integer percent, Boolean everyGoalMet) {
        if (everyGoalMet == true) {
            return 'Perfect day complete';
        }
        return paceFor(percent, expectedPercentForPeriod(1)) == 'behind' ? 'Behind pace' : 'On pace';
    }

    private static Boolean isWorkday(Date d) {
        return isoDayOfWeek(d) <= 5;
    }

    /** 1 = Monday ... 7 = Sunday. */
    private static Integer isoDayOfWeek(Date d) {
        return Integer.valueOf(Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('u'));
    }

    private static Integer workdaysBetween(Date startDate, Date endDate) {
        Integer count = 0;
        for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
            if (isWorkday(d)) {
                count++;
            }
        }
        return count;
    }

    public static Integer expectedCompletionPercentForCurrentTime() {
        Datetime nowValue = currentTime();
        Integer hour = nowValue.hour();
        if (hour < WORKDAY_START_HOUR) {
            return 0;
        }
        if (hour >= WORKDAY_END_HOUR) {
            return 100;
        }
        Decimal elapsedHours = hour - WORKDAY_START_HOUR;
        Decimal totalHours = WORKDAY_END_HOUR - WORKDAY_START_HOUR;
        return (Integer) Math.floor((elapsedHours / totalHours) * 100);
    }

    public static Integer goalsCompletedCount(ActivityMetrics completed, ActivityMetrics goal) {
        Integer completedGoals = 0;
        if (goal.calls > 0 && completed.calls >= goal.calls) {
            completedGoals++;
        }
        if (goal.texts > 0 && completed.texts >= goal.texts) {
            completedGoals++;
        }
        if (goal.emails > 0 && completed.emails >= goal.emails) {
            completedGoals++;
        }
        if (goal.meetings > 0 && completed.meetings >= goal.meetings) {
            completedGoals++;
        }
        if (goal.openHouses > 0 && completed.openHouses >= goal.openHouses) {
            completedGoals++;
        }
        return completedGoals;
    }

    /**
     * Red only when the follow-up cadence is genuinely breached. A partner with no
     * logged touch yet is attention-needed (orange), not overdue.
     */
    public static String realtorFollowUpUrgency(Datetime lastTouch) {
        if (lastTouch == null) {
            return 'orange';
        }
        Integer daysSinceTouch = lastTouch.date().daysBetween(Date.today());
        if (daysSinceTouch >= REALTOR_FOLLOW_UP_RED_DAYS) {
            return 'red';
        }
        if (daysSinceTouch >= REALTOR_FOLLOW_UP_ORANGE_DAYS) { // 7+ days, same as the My Realtors "due" chip
            return 'orange';
        }
        return '';
    }

    public static Boolean isNewLeadSlaBreached(Datetime createdDate) {
        if (createdDate == null) {
            return false;
        }
        Long minutesSinceCreated = (currentTime().getTime() - createdDate.getTime()) / (1000 * 60);
        return minutesSinceCreated > NEW_LEAD_SLA_MINUTES;
    }

    /**
     * Orange when the file has gone stagnant and needs attention. Credit expiration is deliberately
     * ignored: Credit_Expiration_Date__c is not reliably maintained (decided 2026-10-08).
     */
    public static String preApprovalReviewUrgency(Lead leadRecord, Datetime sixDaysAgo) {
        Boolean stagnantCall = leadRecord.Last_Call_Attempt_RingCentral__c == null
            || leadRecord.Last_Call_Attempt_RingCentral__c <= sixDaysAgo;
        Boolean stagnantSms = leadRecord.Last_SMS_Attempt_RingCentral__c == null
            || leadRecord.Last_SMS_Attempt_RingCentral__c <= sixDaysAgo;
        // RingCentral is optional for outside LOs, so a logged call/text/meeting also counts as contact.
        // Not every caller selects LastActivityDate, hence isSet.
        Boolean recentLoggedActivity = leadRecord.isSet('LastActivityDate')
            && leadRecord.LastActivityDate != null
            && leadRecord.LastActivityDate > sixDaysAgo.date();
        if (stagnantCall && stagnantSms && !recentLoggedActivity) {
            return 'orange';
        }
        return '';
    }

    /**
     * A loan needs the LO only when it is Waiting On Loan Officer. Time in status is not a signal
     * (decided 2026-10-08): the processor, not the LO, moves every other status.
     */
    public static String loanMilestoneUrgency(Transaction__c loanRecord) {
        return loanRecord.Status__c == 'Waiting On Loan Officer' ? 'orange' : '';
    }
}