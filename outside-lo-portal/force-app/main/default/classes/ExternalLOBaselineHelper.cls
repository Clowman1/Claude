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
    public static final Integer LOAN_MILESTONE_STALE_DAYS = 3;
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
        if (daysSinceTouch > REALTOR_FOLLOW_UP_ORANGE_DAYS) {
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
     * Red only when the credit report is already expired (SLA breach);
     * orange when the file has gone stagnant and needs attention.
     */
    public static String preApprovalReviewUrgency(Lead leadRecord, Datetime sixDaysAgo) {
        if (leadRecord.Credit_Expiration_Date__c != null
            && leadRecord.Credit_Expiration_Date__c <= Date.today()) {
            return 'red';
        }
        Boolean stagnantCall = leadRecord.Last_Call_Attempt_RingCentral__c == null
            || leadRecord.Last_Call_Attempt_RingCentral__c <= sixDaysAgo;
        Boolean stagnantSms = leadRecord.Last_SMS_Attempt_RingCentral__c == null
            || leadRecord.Last_SMS_Attempt_RingCentral__c <= sixDaysAgo;
        if (stagnantCall && stagnantSms) {
            return 'orange';
        }
        return '';
    }

    /**
     * Red only for loans whose status has been stale beyond the company threshold.
     * A fresh "Waiting On Loan Officer" is attention-needed, not overdue.
     */
    public static String loanMilestoneUrgency(Transaction__c loanRecord) {
        Boolean stale = loanRecord.Current_Status_Since__c != null
            && loanRecord.Current_Status_Since__c <= Date.today().addDays(-LOAN_MILESTONE_STALE_DAYS);
        if (loanRecord.Status__c == 'Waiting On Loan Officer') {
            return stale ? 'red' : 'orange';
        }
        return stale ? 'orange' : '';
    }
}