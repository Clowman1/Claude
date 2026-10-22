/**
 * LO Workspace Phase 8: read-only manager oversight of outside loan officers.
 * Gate: custom permission LO_Workspace_Oversight, checked in every @AuraEnabled method.
 * Managers have full visibility, so reads run in system mode behind the gate.
 * Activity math is the Perfect Day / Perfect Week math (ExternalLoActivityPlanService +
 * ExternalLoActivityRollupBuilder); lead stages come from ExternalLoPortalService.deriveLeadStage.
 */
public without sharing class LoWsOversightController {

    public static final String PERMISSION = 'LO_Workspace_Oversight';
    static final String OUTSIDE_ROLE = 'External_Loan_Officer';
    static final String INTERNAL_PROFILE = 'Loan Officer Profile';
    static final String LANDING_SOURCE = 'LO Landing Page';
    static final List<String> LEAD_STAGES = new List<String>{ 'new', 'working', 'pre-approval', 'nurture', 'converted' };
    static final Map<String, String> LEAD_STAGE_LABELS = new Map<String, String>{
        'new' => 'New', 'working' => 'Working', 'pre-approval' => 'Pre-Approval', 'nurture' => 'Nurture', 'converted' => 'Converted'
    };
    // Status__c pipeline order (PC Review is after Closing). Post-Closed / Cancelled / Lost are not active.
    static final List<String> LOAN_STATUSES = new List<String>{
        'TRID Application', 'Open', 'Disclosures Out', 'Pre-Processing', 'Processing', 'Submitted', 'Suspended',
        'Waiting On Loan Officer', 'Conditionally Approved', 'Re-Submitted', 'Approved', 'Closing', 'Funding', 'PC Review'
    };
    static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Funding', 'PC Review', 'Post-Closed' };
    static final List<String> TAG_STAGES = new List<String>{ 'Prospect', 'Contacted', 'Meeting Set', 'Met', 'Active Partner', 'Dormant' };
    static final Integer LO_CAP = 25; // ponytail: 2 SOQL per LO for the activity math; page it if the roster passes ~40

    @AuraEnabled
    public static Overview getOverview(Boolean includeInternal) {
        requireOversight();
        Overview result = new Overview();
        Date today = Date.today();
        Date weekStart = ExternalLoGoalMath.weekStartMonday(today);
        Date weekEnd = ExternalLoGoalMath.weekEndSunday(today);
        Date monthStart = today.toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        result.weekLabel = weekStart.format() + ' - ' + weekEnd.format();
        result.monthLabel = Datetime.newInstance(monthStart, Time.newInstance(12, 0, 0, 0)).format('MMMM yyyy');
        result.leadStageLabels = new List<String>();
        for (String key : LEAD_STAGES) {
            result.leadStageLabels.add(LEAD_STAGE_LABELS.get(key));
        }
        result.tagStageLabels = TAG_STAGES;

        String roleName = OUTSIDE_ROLE;
        String profileName = includeInternal == true ? INTERNAL_PROFILE : '__none__';
        List<User> users = [
            SELECT Id, Name, UserRole.DeveloperName, Business_Focus__c, External_LO_Onboarding_Complete__c,
                   ExtLO_Workdays_Per_Week__c, ExtLO_Monthly_Unit_Goal__c, ExtLO_Monthly_Volume_Goal__c,
                   ExtLO_Target_Realtor_Count__c
            FROM User
            WHERE IsActive = true AND (UserRole.DeveloperName = :roleName OR Profile.Name = :profileName)
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :LO_CAP
        ];
        Set<Id> ids = new Map<Id, User>(users).keySet();
        Map<Id, String> names = new Map<Id, String>();
        for (User u : users) {
            names.put(u.Id, u.Name);
        }

        Map<Id, Map<String, Integer>> leadCounts = leadStageCounts(ids);
        Map<Id, Map<String, Integer>> loanCounts = new Map<Id, Map<String, Integer>>();
        Map<Id, Decimal> loanVolume = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Loan_Officer__c lo, Status__c st, COUNT(Id) n, SUM(Loan_Amount_1st__c) amt
            FROM Transaction__c
            WHERE Loan_Officer__c IN :ids AND Status__c NOT IN ('Post-Closed', 'Cancelled', 'Lost')
            WITH SYSTEM_MODE
            GROUP BY Loan_Officer__c, Status__c
        ]) {
            Id lo = (Id) ar.get('lo');
            bump(loanCounts, lo, (String) ar.get('st'), (Integer) ar.get('n'));
            loanVolume.put(lo, nz(loanVolume.get(lo)) + nz((Decimal) ar.get('amt')));
        }
        Map<Id, Integer> unitsClosed = new Map<Id, Integer>();
        Map<Id, Decimal> volumeClosed = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Loan_Officer__c lo, COUNT(Id) n, SUM(Loan_Amount_1st__c) amt
            FROM Transaction__c
            WHERE Loan_Officer__c IN :ids AND Status__c IN :CLOSED_STATUSES
              AND Closing_Date__c >= :monthStart AND Closing_Date__c <= :monthEnd
            WITH SYSTEM_MODE
            GROUP BY Loan_Officer__c
        ]) {
            unitsClosed.put((Id) ar.get('lo'), (Integer) ar.get('n'));
            volumeClosed.put((Id) ar.get('lo'), nz((Decimal) ar.get('amt')));
        }
        Map<Id, Map<String, Integer>> tagCounts = new Map<Id, Map<String, Integer>>();
        for (AggregateResult ar : [
            SELECT User__c lo, Stage__c st, COUNT(Id) n
            FROM External_User_Assignment__c
            WHERE User__c IN :ids
            WITH SYSTEM_MODE
            GROUP BY User__c, Stage__c
        ]) {
            String stage = String.isBlank((String) ar.get('st')) ? 'Prospect' : (String) ar.get('st');
            bump(tagCounts, (Id) ar.get('lo'), stage, (Integer) ar.get('n'));
        }

        Date rangeStart = weekStart < monthStart ? weekStart : monthStart;
        Date rangeEnd = weekEnd > monthEnd ? weekEnd : monthEnd;
        Integer monthDays = monthStart.daysBetween(monthEnd) + 1;
        TaskRepository tasks = new TaskRepository();
        result.los = new List<LoRow>();
        for (User u : users) {
            LoRow row = new LoRow();
            row.userId = u.Id;
            row.name = u.Name;
            row.isOutside = u.UserRole?.DeveloperName == OUTSIDE_ROLE;
            row.onboardingComplete = u.External_LO_Onboarding_Complete__c == true;
            row.businessFocus = u.Business_Focus__c;
            row.monthlyUnitGoal = toInt(u.ExtLO_Monthly_Unit_Goal__c);
            row.monthlyVolumeGoal = u.ExtLO_Monthly_Volume_Goal__c;
            row.targetRealtorCount = toInt(u.ExtLO_Target_Realtor_Count__c);
            row.unitsClosedThisMonth = unitsClosed.containsKey(u.Id) ? unitsClosed.get(u.Id) : 0;
            row.volumeClosedThisMonth = nz(volumeClosed.get(u.Id));
            row.activeLoanVolume = nz(loanVolume.get(u.Id));

            List<Task> rangeTasks = tasks.selectCompletedActivitiesByOwnerForDateRange(u.Id, rangeStart, rangeEnd);
            ExternalLoActivityPlanService.ActivityPlan plan = ExternalLoActivityPlanService.getPlan(u.Id, u);
            row.workdaysPerWeek = plan.workdaysPerWeek;
            row.week = ExternalLoActivityRollupBuilder.build(plan, between(rangeTasks, weekStart, weekEnd), 7, false);
            row.month = ExternalLoActivityRollupBuilder.build(plan, between(rangeTasks, monthStart, monthEnd), monthDays, false);

            row.leadStages = counts(leadCounts.get(u.Id), LEAD_STAGES, LEAD_STAGE_LABELS, false);
            row.loanStatuses = counts(loanCounts.get(u.Id), LOAN_STATUSES, null, true);
            row.tagStages = counts(tagCounts.get(u.Id), TAG_STAGES, null, false);
            row.activePartners = tagCounts.containsKey(u.Id) && tagCounts.get(u.Id).containsKey('Active Partner')
                ? tagCounts.get(u.Id).get('Active Partner') : 0;
            row.activeLoans = 0;
            for (StageCount c : row.loanStatuses) {
                row.activeLoans += c.value;
            }
            result.los.add(row);
        }

        result.landingLeads = landingLeads(ids, names, today.addDays(-30));
        result.planChanges = new List<PlanChange>();
        for (External_LO_Plan_Change__c pc : [
            SELECT Id, Name, User__c, Summary__c, CreatedDate
            FROM External_LO_Plan_Change__c
            WHERE User__c IN :ids
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            PlanChange p = new PlanChange();
            p.id = pc.Id;
            p.name = pc.Name;
            p.userId = pc.User__c;
            p.loName = names.get(pc.User__c);
            p.summary = pc.Summary__c;
            p.createdDate = pc.CreatedDate;
            result.planChanges.add(p);
        }
        return result;
    }

    static void requireOversight() {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw new AuraHandledException('You do not have access to LO Workspace oversight.');
        }
    }

    static Map<Id, Map<String, Integer>> leadStageCounts(Set<Id> ids) {
        Map<Id, Map<String, Integer>> byLo = new Map<Id, Map<String, Integer>>();
        Date convertedSince = Date.today().addDays(-365); // same window as My Leads
        for (AggregateResult ar : [
            SELECT OwnerId lo, Status st, IsConverted conv, COUNT(Id) n
            FROM Lead
            WHERE OwnerId IN :ids AND (IsConverted = false OR ConvertedDate >= :convertedSince)
            WITH SYSTEM_MODE
            GROUP BY OwnerId, Status, IsConverted
        ]) {
            String stage = (Boolean) ar.get('conv') == true
                ? 'converted'
                : ExternalLoPortalService.deriveLeadStage(new Lead(Status = (String) ar.get('st')));
            bump(byLo, (Id) ar.get('lo'), stage, (Integer) ar.get('n'));
        }
        return byLo;
    }

    static List<LandingLead> landingLeads(Set<Id> ids, Map<Id, String> names, Date since) {
        List<LandingLead> rows = new List<LandingLead>();
        for (Lead l : [
            SELECT Id, Name, OwnerId, Status, IsConverted, LeadSource, CreatedDate, LO_Takeover_At__c
            FROM Lead
            WHERE OwnerId IN :ids
              AND ((LeadSource = :LANDING_SOURCE AND CreatedDate >= :since) OR LO_Takeover_At__c >= :since)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            LandingLead r = new LandingLead();
            r.id = l.Id;
            r.name = l.Name;
            r.userId = l.OwnerId;
            r.loName = names.get(l.OwnerId);
            r.status = l.Status;
            r.stage = LEAD_STAGE_LABELS.get(ExternalLoPortalService.deriveLeadStage(l));
            r.leadSource = l.LeadSource;
            r.takenOver = l.LO_Takeover_At__c != null && l.LO_Takeover_At__c >= since;
            r.arrivedAt = r.takenOver ? l.LO_Takeover_At__c : l.CreatedDate;
            rows.add(r);
        }
        rows.sort();
        return rows;
    }

    static List<Task> between(List<Task> tasks, Date startDate, Date endDate) {
        List<Task> rows = new List<Task>();
        for (Task t : tasks) {
            if (t.ActivityDate != null && t.ActivityDate >= startDate && t.ActivityDate <= endDate) {
                rows.add(t);
            }
        }
        return rows;
    }

    static List<StageCount> counts(Map<String, Integer> byKey, List<String> order, Map<String, String> labels, Boolean skipZero) {
        List<StageCount> rows = new List<StageCount>();
        for (String key : order) {
            Integer n = byKey != null && byKey.containsKey(key) ? byKey.get(key) : 0;
            if (skipZero && n == 0) {
                continue;
            }
            StageCount c = new StageCount();
            c.label = labels == null ? key : labels.get(key);
            c.value = n;
            rows.add(c);
        }
        return rows;
    }

    static void bump(Map<Id, Map<String, Integer>> byLo, Id lo, String key, Integer n) {
        if (!byLo.containsKey(lo)) {
            byLo.put(lo, new Map<String, Integer>());
        }
        Map<String, Integer> m = byLo.get(lo);
        m.put(key, (m.containsKey(key) ? m.get(key) : 0) + n);
    }

    static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }

    static Integer toInt(Decimal d) {
        return d == null ? null : d.intValue();
    }

    public class Overview {
        @AuraEnabled public String weekLabel;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public List<String> leadStageLabels;
        @AuraEnabled public List<String> tagStageLabels;
        @AuraEnabled public List<LoRow> los;
        @AuraEnabled public List<LandingLead> landingLeads;
        @AuraEnabled public List<PlanChange> planChanges;
    }

    public class LoRow {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isOutside;
        @AuraEnabled public Boolean onboardingComplete;
        @AuraEnabled public String businessFocus;
        @AuraEnabled public Integer workdaysPerWeek;
        @AuraEnabled public Integer monthlyUnitGoal;
        @AuraEnabled public Decimal monthlyVolumeGoal;
        @AuraEnabled public Integer targetRealtorCount;
        @AuraEnabled public Integer unitsClosedThisMonth;
        @AuraEnabled public Decimal volumeClosedThisMonth;
        @AuraEnabled public Integer activePartners;
        @AuraEnabled public Integer activeLoans;
        @AuraEnabled public Decimal activeLoanVolume;
        @AuraEnabled public ExternalLoActivityRollupBuilder.PeriodScore week;
        @AuraEnabled public ExternalLoActivityRollupBuilder.PeriodScore month;
        @AuraEnabled public List<StageCount> leadStages;
        @AuraEnabled public List<StageCount> loanStatuses;
        @AuraEnabled public List<StageCount> tagStages;
    }

    public class StageCount {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
    }

    public class LandingLead implements Comparable {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id userId;
        @AuraEnabled public String loName;
        @AuraEnabled public String status;
        @AuraEnabled public String stage;
        @AuraEnabled public String leadSource;
        @AuraEnabled public Boolean takenOver;
        @AuraEnabled public Datetime arrivedAt;
        public Integer compareTo(Object other) {
            Datetime o = ((LandingLead) other).arrivedAt;
            return arrivedAt == o ? 0 : (arrivedAt > o ? -1 : 1); // newest first
        }
    }

    public class PlanChange {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id userId;
        @AuraEnabled public String loName;
        @AuraEnabled public String summary;
        @AuraEnabled public Datetime createdDate;
    }
}