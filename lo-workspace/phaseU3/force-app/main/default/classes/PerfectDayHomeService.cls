/**
 * Assembles personalized Perfect Day workspace data for external loan officers
 * and executes the Up Next actions (defer, complete).
 * View-model construction lives in PerfectDayHomeBuilder; shapes in PerfectDayHomeModels.
 * ADR-0001: lead defer DML uses SYSTEM_MODE (CCP has no Lead Update).
 */
public with sharing class PerfectDayHomeService {

    private static final Date MIN_LEAD_CREATED_DATE = Date.newInstance(2024, 1, 1);

    public static PerfectDayHomeModels.PerfectDayHomeData getHomeData() {
        Id userId = UserInfo.getUserId();
        User userRecord = UserRepository.getInstance().selectPortalProfile(userId);
        if (userRecord == null) {
            throw new DomainException('Your user profile could not be loaded.');
        }

        TaskRepository taskRepository = new TaskRepository();
        LeadRepository leadRepository = LeadRepository.getInstance();
        PersonAccountRepository personAccountRepository = new PersonAccountRepository();
        LoanRepository loanRepository = LoanRepository.getInstance();

        Date today = Date.today();
        Date startOfWeek = ExternalLoGoalMath.weekStartMonday(today);
        Date endOfWeek = ExternalLoGoalMath.weekEndSunday(today);
        Date startOfMonth = today.toStartOfMonth();
        Date endOfMonth = startOfMonth.addMonths(1).addDays(-1);
        Date rangeStart = startOfWeek < startOfMonth ? startOfWeek : startOfMonth;
        Date rangeEnd = endOfWeek > endOfMonth ? endOfWeek : endOfMonth;
        if (today < rangeStart) {
            rangeStart = today;
        }
        if (today > rangeEnd) {
            rangeEnd = today;
        }

        List<Task> rangeTasks = taskRepository.selectCompletedActivitiesByOwnerForDateRange(
            userId,
            rangeStart,
            rangeEnd
        );
        List<Task> todayTasks = tasksOnOrBetween(rangeTasks, today, today);
        List<Task> weekTasks = tasksOnOrBetween(rangeTasks, startOfWeek, endOfWeek);
        List<Task> monthTasks = tasksOnOrBetween(rangeTasks, startOfMonth, endOfMonth);
        List<Task> overdueTasks = taskRepository.selectOpenOverdueByOwner(userId);

        // LO Workspace Phase 6: new landing-page leads go to the top of the queue.
        List<Id> landingPageLeadIds = LoWsLeadIntakeService.recentLandingPageLeadIds(userId);
        List<Lead> candidateNewLeads = LoWsLeadIntakeService.landingPageFirst(
            landingPageLeadIds,
            leadRepository.selectNewLeadsToContact(userId, MIN_LEAD_CREATED_DATE)
        );
        Set<Id> leadIdsWithFutureEvents = leadRepository.selectLeadIdsWithFutureEvents(
            new Map<Id, Lead>(candidateNewLeads).keySet()
        );
        List<Lead> newLeadsToContact = new List<Lead>();
        for (Lead leadRecord : candidateNewLeads) {
            if (!leadIdsWithFutureEvents.contains(leadRecord.Id)) {
                newLeadsToContact.add(leadRecord);
            }
        }

        // Pre-approvals needing review = those due a weekly touch (LoWsTouchService, decided 2026-10-08).
        Datetime sixDaysAgo = System.now().addDays(-ExternalLOBaselineHelper.PRE_APPROVAL_STAGNANT_DAYS);
        ExternalLoPromptService.PromptContext promptContext = new ExternalLoPromptService.PromptContext();
        List<Lead> preApprovalsToReview = ExternalLoPromptService.touchDueLeads(
            leadRepository.selectPreApprovalsToReview(userId),
            promptContext
        );
        promptContext.touchDueLeads = preApprovalsToReview;

        List<Account> realtorAccounts = personAccountRepository.selectRealtorPartnersByOwner(userId);
        Map<Id, Datetime> lastTouchByAccountId = taskRepository.selectLastActivityDatetimeByWhatIds(
            new Map<Id, Account>(realtorAccounts).keySet(),
            userId
        );
        List<Account> realtorFollowUpsDue = new List<Account>();
        for (Account accountRecord : realtorAccounts) {
            Datetime lastTouch = lastTouchByAccountId.get(accountRecord.Id);
            if (accountRecord.LastActivityDate != null) {
                Datetime lastActivityDateTime = Datetime.newInstance(
                    accountRecord.LastActivityDate,
                    Time.newInstance(0, 0, 0, 0)
                );
                if (lastTouch == null || lastActivityDateTime > lastTouch) {
                    lastTouch = lastActivityDateTime;
                }
            }
            String urgency = ExternalLOBaselineHelper.realtorFollowUpUrgency(lastTouch);
            if (String.isNotBlank(urgency)) {
                realtorFollowUpsDue.add(accountRecord);
            }
        }

        List<Transaction__c> milestoneLoans = loanRepository.selectLoansNeedingMilestoneUpdates(userId);

        PerfectDayHomeModels.PerfectDayHomeData homeData = new PerfectDayHomeModels.PerfectDayHomeData();
        homeData.userName = userRecord.Name;
        homeData.userFirstName = extractFirstName(userRecord.Name);
        homeData.todayFormatted = formatTodayLabel(today);
        homeData.businessFocus = userRecord.Business_Focus__c;
        homeData.onboardingComplete = userRecord.External_LO_Onboarding_Complete__c == true;
        homeData.priorities = PerfectDayHomeBuilder.buildPriorities(
            newLeadsToContact,
            realtorFollowUpsDue,
            lastTouchByAccountId,
            preApprovalsToReview,
            sixDaysAgo,
            milestoneLoans,
            overdueTasks
        );
        homeData.upNext = PerfectDayHomeBuilder.selectUpNextItem(
            newLeadsToContact,
            overdueTasks,
            realtorFollowUpsDue,
            preApprovalsToReview,
            milestoneLoans
        );
        if (homeData.upNext != null && landingPageLeadIds.contains((Id) homeData.upNext.recordId)) {
            homeData.upNext.detail = 'New lead from your landing page';
        }

        ExternalLoActivityPlanService.ActivityPlan plan = ExternalLoActivityPlanService.getPlan(userId, userRecord);
        ExternalLoActivityRollupBuilder.PeriodScore todayScore = ExternalLoActivityRollupBuilder.build(
            plan,
            todayTasks,
            weekTasks,
            1,
            true
        );
        Integer monthDays = startOfMonth.daysBetween(endOfMonth) + 1;
        ExternalLoActivityRollupBuilder.PeriodScore weekScore = ExternalLoActivityRollupBuilder.build(
            plan,
            weekTasks,
            7,
            false
        );
        ExternalLoActivityRollupBuilder.PeriodScore monthScore = ExternalLoActivityRollupBuilder.build(
            plan,
            monthTasks,
            monthDays,
            false
        );
        homeData.todayPlan = todayScore.rows;
        Integer categoryGoalsMet = 0;
        for (ExternalLoActivityRollupBuilder.CategoryScore row : todayScore.rows) {
            if (row.isWinning == true) {
                categoryGoalsMet++;
            }
        }
        homeData.dailyCompletionPercent = todayScore.percent;
        homeData.goalsCompleted = categoryGoalsMet;
        homeData.goalsTotal = todayScore.rows.size();
        homeData.paceStatus = ExternalLOBaselineHelper.paceStatus(
            todayScore.percent,
            todayScore.totalGoal,
            todayScore.totalCompleted
        );
        homeData.summaryMetrics = PerfectDayHomeBuilder.buildSummaryMetrics(
            todayScore.percent,
            categoryGoalsMet,
            todayScore.rows.size(),
            overdueTasks,
            Math.max(0, todayScore.totalGoal - todayScore.totalCompleted)
        );
        homeData.goalProgress = PerfectDayHomeBuilder.buildGoalProgress(todayScore, weekScore, monthScore);

        promptContext.underContractLeads = new ExternalLoPromptSelector().selectUnderContractLeadsByOwner(userId);
        promptContext.pastClientLeads = leadRepository.selectPastClientLeadsByOwner(userId);
        promptContext.milestoneLoans = milestoneLoans;
        promptContext.fundedLoans = new ExternalLoPromptSelector().selectFundedLoansByOfficer(userId);
        promptContext.realtorAccounts = realtorAccounts;
        promptContext.lastTouchByAccountId = lastTouchByAccountId;
        promptContext.snoozedKeys = ExternalLoPromptService.snoozedKeysFor(userId);
        // Follow-ups and other open tasks due today (or overdue) lead Up Next, with Mark complete.
        // The card shows 3 at a time; the list stays capped at MAX_PROMPTS.
        // High alerts (borrower uploads to review) first, then due follow-ups, then computed prompts.
        List<ExternalLoPromptService.PromptItem> prompts = ExternalLoPromptService.documentReviewPrompts(userId);
        for (ExternalLoPromptService.PromptItem item : ExternalLoPromptService.followUpPrompts(
            taskRepository.selectOpenDueTasksByOwner(userId, ExternalLoPromptService.MAX_PROMPTS)
        )) {
            if (prompts.size() < ExternalLoPromptService.MAX_PROMPTS) {
                prompts.add(item);
            }
        }
        for (ExternalLoPromptService.PromptItem item : ExternalLoPromptService.build(promptContext)) {
            if (prompts.size() < ExternalLoPromptService.MAX_PROMPTS) {
                prompts.add(item);
            }
        }
        homeData.prompts = prompts;
        homeData.recentLog = buildRecentLog(rangeTasks);

        return homeData;
    }

    private static List<Task> tasksOnOrBetween(List<Task> tasks, Date startDate, Date endDate) {
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

    private static List<PerfectDayHomeModels.RecentLogEntry> buildRecentLog(List<Task> tasks) {
        List<Task> newest = new List<Task>();
        if (tasks != null) {
            newest.addAll(tasks);
            newest.sort(new RecentTaskSort());
        }
        List<Task> clipped = new List<Task>();
        Integer limitSize = Math.min(8, newest.size());
        for (Integer i = 0; i < limitSize; i++) {
            clipped.add(newest[i]);
        }
        Map<Id, String> names = ExternalLoActivityNameResolver.resolveTaskRelatedNames(clipped);
        List<PerfectDayHomeModels.RecentLogEntry> rows = new List<PerfectDayHomeModels.RecentLogEntry>();
        for (Task taskRecord : clipped) {
            PerfectDayHomeModels.RecentLogEntry entry = new PerfectDayHomeModels.RecentLogEntry();
            entry.taskId = taskRecord.Id;
            entry.subject = taskRecord.Subject;
            entry.activityKey = ExternalLoActivityRollupBuilder.activityKeyFor(taskRecord);
            ExternalLoActivityCatalog.ActivityDefinition definition =
                ExternalLoActivityCatalog.activityByKey(entry.activityKey);
            entry.shortLabel = definition == null ? taskRecord.Activity_Type__c : definition.shortLabel;
            entry.activityCount = ExternalLoActivityRollupBuilder.countOf(taskRecord);
            entry.contactName = ExternalLoActivityNameResolver.formatTaskRelatedLabel(taskRecord, names);
            entry.activityDateLabel = taskRecord.ActivityDate == null ? '' : taskRecord.ActivityDate.format();
            entry.notes = taskRecord.Description;
            rows.add(entry);
        }
        return rows;
    }

    private class RecentTaskSort implements Comparator<Task> {
        public Integer compare(Task left, Task right) {
            Date leftDate = left.ActivityDate;
            Date rightDate = right.ActivityDate;
            if (leftDate == rightDate) {
                return 0;
            }
            if (leftDate == null) {
                return 1;
            }
            if (rightDate == null) {
                return -1;
            }
            if (leftDate > rightDate) {
                return -1;
            }
            return 1;
        }
    }

    public static void deferUpNextItem(Id recordId, String objectApiName) {
        deferUpNextItem(recordId, objectApiName, 'tomorrow');
    }

    public static void deferUpNextItem(Id recordId, String objectApiName, String deferOption) {
        if (recordId == null || String.isBlank(objectApiName)) {
            throw new DomainException('A record is required to defer this action.');
        }

        if (objectApiName == 'Task') {
            // Task.ActivityDate is date-only, so intraday windows cannot be honored:
            // a Task defer always returns tomorrow. The UI only offers this option
            // for tasks; the guard keeps direct API calls honest.
            deferTask(recordId, Date.today().addDays(1));
            return;
        }

        if (objectApiName == 'Lead') {
            deferLead(recordId, deferReturnTime(deferOption));
            return;
        }

        throw new DomainException('This record type cannot be deferred from Perfect Day.');
    }

    private static Datetime deferReturnTime(String deferOption) {
        Datetime nowValue = System.now();
        if (deferOption == 'hour') {
            return nowValue.addHours(1);
        }
        if (deferOption == 'afternoon') {
            Datetime afternoon = Datetime.newInstance(Date.today(), Time.newInstance(13, 30, 0, 0));
            // Past the early afternoon already: push an hour out instead of into the past.
            return afternoon > nowValue ? afternoon : nowValue.addHours(1);
        }
        return Datetime.newInstance(Date.today().addDays(1), Time.newInstance(9, 0, 0, 0));
    }

    public static void completeUpNextItem(Id recordId, String objectApiName) {
        if (recordId == null || String.isBlank(objectApiName)) {
            throw new DomainException('A record is required to complete this action.');
        }

        if (objectApiName != 'Task') {
            throw new DomainException('Only overdue tasks can be marked complete from Perfect Day.');
        }
        if (!Schema.sObjectType.Task.isUpdateable()) {
            throw new DomainException('You do not have permission to update tasks.');
        }

        TaskRepository taskRepository = new TaskRepository();
        Task taskRecord = taskRepository.selectById(recordId);
        if (taskRecord == null || taskRecord.OwnerId != UserInfo.getUserId()) {
            throw new DomainException('Task could not be found or is not visible.');
        }
        if (taskRecord.IsClosed) {
            return;
        }

        // Stamp today's date so the completion is reflected in today's activity window.
        Task updateShell = new Task(
            Id = taskRecord.Id,
            Status = 'Completed',
            ActivityDate = Date.today()
        );
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<Task>{ updateShell }
        );
        update decision.getRecords();
    }

    private static String extractFirstName(String fullName) {
        if (String.isBlank(fullName)) {
            return 'there';
        }
        List<String> parts = fullName.trim().split('\\s+');
        return parts.isEmpty() ? fullName.trim() : parts[0];
    }

    private static String formatTodayLabel(Date today) {
        Datetime todayValue = Datetime.newInstance(today, Time.newInstance(12, 0, 0, 0));
        return todayValue.format('EEEE, MMMM d, yyyy');
    }

    private static void deferTask(Id taskId, Date returnDate) {
        if (!Schema.sObjectType.Task.isUpdateable()) {
            throw new DomainException('You do not have permission to update tasks.');
        }
        TaskRepository taskRepository = new TaskRepository();
        Task taskRecord = taskRepository.selectById(taskId);
        if (taskRecord == null || taskRecord.OwnerId != UserInfo.getUserId()) {
            throw new DomainException('Task could not be found or is not visible.');
        }

        Task updateShell = new Task(
            Id = taskRecord.Id,
            ActivityDate = returnDate
        );
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<Task>{ updateShell }
        );
        update decision.getRecords();
    }

    private static void deferLead(Id leadId, Datetime returnAt) {
        Lead leadRecord = LeadRepository.getInstance().selectForPerfectDayDefer(
            leadId,
            UserInfo.getUserId()
        );
        if (leadRecord == null) {
            throw new DomainException('Lead could not be found or is not visible.');
        }

        Lead updateShell = new Lead(
            Id = leadRecord.Id,
            Appointment_Date_Time__c = returnAt
        );
        Database.update(new List<Lead>{ updateShell }, AccessLevel.SYSTEM_MODE);
    }
}