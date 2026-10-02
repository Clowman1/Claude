/**
 * Builds the Perfect Day homepage view models — summary metrics, priority
 * categories, the single Up Next recommendation, and goal progress.
 * Pure in-memory transformation: no SOQL and no DML.
 */
public with sharing class PerfectDayHomeBuilder {

    public static PerfectDayHomeModels.SummaryMetrics buildSummaryMetrics(
        Integer dailyCompletionPercent,
        Integer goalsCompletedCount,
        Integer goalsTotalCount,
        List<Task> overdueTasks,
        Integer activitiesRemaining
    ) {
        Integer overdueTaskCount = overdueTasks.size();
        Integer oldestOverdueDays = oldestOverdueDays(overdueTasks);

        PerfectDayHomeModels.SummaryMetrics metrics = new PerfectDayHomeModels.SummaryMetrics();
        metrics.dailyScore = metricCard(
            'Daily Score',
            dailyCompletionPercent,
            dailyCompletionPercent + '%',
            'Perfect Day completion',
            'brand',
            null,
            null,
            'My_Completed_Activities',
            'dailyScore'
        );
        metrics.goalsCompleted = metricCard(
            'Goals Completed',
            goalsCompletedCount,
            goalsCompletedCount + ' of ' + goalsTotalCount,
            buildGoalsCompletedSupport(goalsCompletedCount, goalsTotalCount),
            'teal',
            goalsCompletedCount,
            goalsTotalCount,
            'My_Completed_Activities',
            'goalsCompleted'
        );
        metrics.overdueTasks = metricCard(
            'Overdue Tasks',
            overdueTaskCount,
            String.valueOf(overdueTaskCount),
            oldestOverdueDays == null
                ? 'No overdue tasks'
                : 'Oldest overdue ' + oldestOverdueDays + ' days',
            'danger',
            null,
            null,
            'My_Overdue_Tasks',
            'overdueTasks'
        );
        metrics.activitiesRemaining = metricCard(
            'Activities Remaining',
            activitiesRemaining,
            String.valueOf(activitiesRemaining),
            'Scheduled before 5:00 PM',
            'navy',
            null,
            null,
            'My_Open_Tasks',
            'activitiesRemaining'
        );
        return metrics;
    }

    public static List<PerfectDayHomeModels.PriorityCategory> buildPriorities(
        List<Lead> newLeadsToContact,
        List<Account> realtorFollowUpsDue,
        Map<Id, Datetime> lastTouchByAccountId,
        List<Lead> preApprovalsToReview,
        Datetime sixDaysAgo,
        List<Transaction__c> milestoneLoans,
        List<Task> overdueTasks
    ) {
        List<PerfectDayHomeModels.PriorityCategory> priorities = new List<PerfectDayHomeModels.PriorityCategory>();
        priorities.add(buildNewLeadPriority(newLeadsToContact));
        priorities.add(buildRealtorPriority(realtorFollowUpsDue, lastTouchByAccountId));
        priorities.add(buildPreApprovalPriority(preApprovalsToReview, sixDaysAgo));
        priorities.add(buildMilestoneLoanPriority(milestoneLoans));
        priorities.add(buildOverdueTaskPriority(overdueTasks));
        return priorities;
    }

    public static PerfectDayHomeModels.UpNextItem selectUpNextItem(
        List<Lead> newLeadsToContact,
        List<Task> overdueTasks,
        List<Account> realtorFollowUpsDue,
        List<Lead> preApprovalsToReview,
        List<Transaction__c> milestoneLoans
    ) {
        if (!newLeadsToContact.isEmpty()) {
            Lead leadRecord = newLeadsToContact[0];
            PerfectDayHomeModels.UpNextItem item = new PerfectDayHomeModels.UpNextItem();
            item.recordId = leadRecord.Id;
            item.objectApiName = 'Lead';
            item.title = leadRecord.Name;
            item.actionLabel = 'Call ' + leadRecord.Name;
            item.categoryKey = 'newLeads';
            item.canLogOutcome = true;
            item.canDefer = true;
            item.canComplete = false;
            item.canOpenRecord = true;
            item.phone = leadRecord.Phone;
            item.email = leadRecord.Email;
            item.source = leadRecord.LeadSource;
            item.detail = 'New lead assigned to you';
            item.impactLabel = 'Highest impact';
            item.slaLabel = 'Contact within ' + ExternalLOBaselineHelper.NEW_LEAD_SLA_MINUTES
                + ' minutes to stay inside SLA';
            if (ExternalLOBaselineHelper.isNewLeadSlaBreached(leadRecord.CreatedDate)) {
                item.reason = 'This lead is already outside the company response SLA — contact them now.';
            } else {
                item.reason = 'New lead response speed ranks first. Contact this lead before other work.';
            }
            return item;
        }

        if (!overdueTasks.isEmpty()) {
            Task taskRecord = overdueTasks[0];
            PerfectDayHomeModels.UpNextItem item = new PerfectDayHomeModels.UpNextItem();
            item.recordId = taskRecord.Id;
            item.objectApiName = 'Task';
            item.title = taskRecord.Subject;
            item.actionLabel = taskRecord.Subject;
            item.categoryKey = 'overdueTasks';
            item.reason = 'This overdue task is the most time-sensitive work after new lead response.';
            item.canLogOutcome = false;
            item.canDefer = true;
            item.canComplete = true;
            item.canOpenRecord = true;
            return item;
        }

        if (!realtorFollowUpsDue.isEmpty()) {
            Account accountRecord = realtorFollowUpsDue[0];
            PerfectDayHomeModels.UpNextItem item = new PerfectDayHomeModels.UpNextItem();
            item.recordId = accountRecord.Id;
            item.objectApiName = 'Account';
            item.title = accountRecord.Name;
            item.actionLabel = 'Follow up with ' + accountRecord.Name;
            item.categoryKey = 'realtorFollowUps';
            item.reason = 'This realtor relationship is past the follow-up cadence and needs a touch.';
            item.canLogOutcome = true;
            item.canDefer = false;
            item.canComplete = false;
            item.canOpenRecord = true;
            return item;
        }

        if (!preApprovalsToReview.isEmpty()) {
            Lead leadRecord = preApprovalsToReview[0];
            PerfectDayHomeModels.UpNextItem item = new PerfectDayHomeModels.UpNextItem();
            item.recordId = leadRecord.Id;
            item.objectApiName = 'Lead';
            item.title = leadRecord.Name;
            item.actionLabel = 'Review pre-approval — ' + leadRecord.Name;
            item.categoryKey = 'preApprovals';
            item.reason = 'This pre-approved borrower needs review to keep the file moving.';
            item.canLogOutcome = true;
            item.canDefer = false;
            item.canComplete = false;
            item.canOpenRecord = true;
            return item;
        }

        if (!milestoneLoans.isEmpty()) {
            Transaction__c loanRecord = milestoneLoans[0];
            PerfectDayHomeModels.UpNextItem item = new PerfectDayHomeModels.UpNextItem();
            item.recordId = loanRecord.Id;
            item.objectApiName = 'Transaction__c';
            item.title = loanRecord.Name;
            item.actionLabel = 'Update milestone — ' + loanRecord.Name;
            item.categoryKey = 'milestoneLoans';
            item.reason = 'This loan needs a milestone or status update to stay on track.';
            item.canLogOutcome = true;
            item.canDefer = false;
            item.canComplete = false;
            item.canOpenRecord = true;
            return item;
        }

        return null;
    }

    public static PerfectDayHomeModels.GoalProgress buildGoalProgress(
        ExternalLoActivityRollupBuilder.PeriodScore todayScore,
        ExternalLoActivityRollupBuilder.PeriodScore weekScore,
        ExternalLoActivityRollupBuilder.PeriodScore monthScore
    ) {
        PerfectDayHomeModels.GoalProgress progress = new PerfectDayHomeModels.GoalProgress();
        progress.today = fromPeriodScore(todayScore);
        progress.thisWeek = fromPeriodScore(weekScore);
        progress.thisMonth = fromPeriodScore(monthScore);
        return progress;
    }

    private static PerfectDayHomeModels.MetricCard metricCard(
        String label,
        Integer value,
        String displayValue,
        String supportText,
        String tone,
        Integer progressCurrent,
        Integer progressTarget,
        String listViewApiName,
        String filterKey
    ) {
        PerfectDayHomeModels.MetricCard card = new PerfectDayHomeModels.MetricCard();
        card.label = label;
        card.value = value == null ? 0 : value;
        card.displayValue = displayValue;
        card.supportText = supportText;
        card.tone = tone;
        card.progressCurrent = progressCurrent;
        card.progressTarget = progressTarget;
        card.drillObjectApiName = 'Task';
        card.drillListViewApiName = listViewApiName;
        card.drillFilterKey = filterKey;
        return card;
    }

    private static String buildGoalsCompletedSupport(Integer completed, Integer total) {
        Integer attention = total - completed;
        if (attention <= 0) {
            return 'All daily goals met';
        }
        return completed + ' complete or on pace · ' + attention + ' need attention';
    }

    private static Integer oldestOverdueDays(List<Task> overdueTasks) {
        if (overdueTasks.isEmpty()) {
            return null;
        }
        Date oldestDate = overdueTasks[0].ActivityDate;
        return oldestDate.daysBetween(Date.today());
    }

    private static PerfectDayHomeModels.PriorityCategory buildNewLeadPriority(List<Lead> newLeadsToContact) {
        PerfectDayHomeModels.PriorityCategory category = new PerfectDayHomeModels.PriorityCategory();
        category.key = 'newLeads';
        category.categoryType = 'lead';
        category.label = 'New leads need contact';
        category.count = newLeadsToContact.size();
        category.drillObjectApiName = 'Lead';
        category.drillListViewApiName = 'My_Leads_New_to_Contact';
        category.emptyStateMessage = 'No new leads need contact right now.';
        category.urgency = '';
        category.description = buildNewLeadDescription(newLeadsToContact);

        for (Lead leadRecord : newLeadsToContact) {
            if (ExternalLOBaselineHelper.isNewLeadSlaBreached(leadRecord.CreatedDate)) {
                category.urgency = 'red';
                break;
            }
            if (String.isBlank(category.urgency)) {
                category.urgency = 'orange';
            }
        }
        return category;
    }

    private static String buildNewLeadDescription(List<Lead> newLeadsToContact) {
        if (newLeadsToContact.isEmpty()) {
            return 'Every assigned lead has been contacted.';
        }
        Integer slaBreached = 0;
        for (Lead leadRecord : newLeadsToContact) {
            if (ExternalLOBaselineHelper.isNewLeadSlaBreached(leadRecord.CreatedDate)) {
                slaBreached++;
            }
        }
        if (slaBreached > 0) {
            return slaBreached + ' lead' + (slaBreached == 1 ? '' : 's')
                + ' outside the company response SLA';
        }
        return newLeadsToContact.size() + ' assigned lead'
            + (newLeadsToContact.size() == 1 ? '' : 's') + ' still need first contact';
    }

    private static PerfectDayHomeModels.PriorityCategory buildRealtorPriority(
        List<Account> realtorFollowUpsDue,
        Map<Id, Datetime> lastTouchByAccountId
    ) {
        PerfectDayHomeModels.PriorityCategory category = new PerfectDayHomeModels.PriorityCategory();
        category.key = 'realtorFollowUps';
        category.categoryType = 'realtor';
        category.label = 'Realtor follow-ups are due';
        category.count = realtorFollowUpsDue.size();
        category.drillObjectApiName = 'Account';
        category.drillListViewApiName = 'My_Realtors';
        category.emptyStateMessage = 'Your realtor relationships are on cadence.';
        category.urgency = highestRealtorUrgency(realtorFollowUpsDue, lastTouchByAccountId);
        category.description = buildRealtorDescription(realtorFollowUpsDue, lastTouchByAccountId);
        return category;
    }

    private static String buildRealtorDescription(
        List<Account> realtorFollowUpsDue,
        Map<Id, Datetime> lastTouchByAccountId
    ) {
        if (realtorFollowUpsDue.isEmpty()) {
            return 'Partner touches are on cadence.';
        }
        Integer stalePartners = 0;
        for (Account accountRecord : realtorFollowUpsDue) {
            Datetime lastTouch = lastTouchByAccountId.get(accountRecord.Id);
            if (ExternalLOBaselineHelper.realtorFollowUpUrgency(lastTouch) == 'red') {
                stalePartners++;
            }
        }
        if (stalePartners > 0) {
            return stalePartners + ' partner' + (stalePartners == 1 ? '' : 's')
                + ' have not been touched in over '
                + ExternalLOBaselineHelper.REALTOR_FOLLOW_UP_RED_DAYS + ' days';
        }
        return realtorFollowUpsDue.size() + ' partner touch'
            + (realtorFollowUpsDue.size() == 1 ? '' : 'es') + ' scheduled or overdue';
    }

    private static PerfectDayHomeModels.PriorityCategory buildPreApprovalPriority(
        List<Lead> preApprovalsToReview,
        Datetime sixDaysAgo
    ) {
        PerfectDayHomeModels.PriorityCategory category = new PerfectDayHomeModels.PriorityCategory();
        category.key = 'preApprovals';
        category.categoryType = 'preapproval';
        category.label = 'Pre-approvals need review';
        category.count = preApprovalsToReview.size();
        category.drillObjectApiName = 'Lead';
        category.drillListViewApiName = 'My_Pre_Approvals';
        category.emptyStateMessage = 'No pre-approvals need review today.';
        category.urgency = '';
        category.description = preApprovalsToReview.isEmpty()
            ? 'All active pre-approvals have a recent touch.'
            : preApprovalsToReview.size() + ' borrower file'
                + (preApprovalsToReview.size() == 1 ? '' : 's') + ' need your review';

        for (Lead leadRecord : preApprovalsToReview) {
            String urgency = ExternalLOBaselineHelper.preApprovalReviewUrgency(leadRecord, sixDaysAgo);
            if (urgency == 'red') {
                category.urgency = 'red';
                break;
            }
            if (urgency == 'orange') {
                category.urgency = 'orange';
            }
        }
        return category;
    }

    private static PerfectDayHomeModels.PriorityCategory buildMilestoneLoanPriority(
        List<Transaction__c> milestoneLoans
    ) {
        PerfectDayHomeModels.PriorityCategory category = new PerfectDayHomeModels.PriorityCategory();
        category.key = 'milestoneLoans';
        category.categoryType = 'milestone';
        category.label = 'Loans require milestone updates';
        category.count = milestoneLoans.size();
        category.drillObjectApiName = 'Transaction__c';
        category.drillListViewApiName = 'My_Loans_Milestone_Updates';
        category.emptyStateMessage = 'No loans need milestone updates right now.';
        category.urgency = highestLoanUrgency(milestoneLoans);
        category.description = milestoneLoans.isEmpty()
            ? 'Borrowers and partners have current loan statuses.'
            : 'Borrowers and Realtors are waiting on a status change';
        return category;
    }

    private static PerfectDayHomeModels.PriorityCategory buildOverdueTaskPriority(List<Task> overdueTasks) {
        PerfectDayHomeModels.PriorityCategory category = new PerfectDayHomeModels.PriorityCategory();
        category.key = 'overdueTasks';
        category.categoryType = 'task';
        category.label = 'Overdue tasks need resolution';
        category.count = overdueTasks.size();
        category.drillObjectApiName = 'Task';
        category.drillListViewApiName = 'My_Overdue_Tasks';
        category.emptyStateMessage = 'You have no overdue tasks.';
        category.urgency = overdueTasks.isEmpty() ? '' : 'red';
        Integer oldestDays = oldestOverdueDays(overdueTasks);
        category.description = overdueTasks.isEmpty()
            ? 'Task hygiene is clear.'
            : oldestDays == null
                ? 'Past-due activities assigned to you'
                : 'Oldest is ' + oldestDays + ' days past due';
        return category;
    }

    private static PerfectDayHomeModels.PeriodProgress fromPeriodScore(
        ExternalLoActivityRollupBuilder.PeriodScore score
    ) {
        PerfectDayHomeModels.PeriodProgress period = new PerfectDayHomeModels.PeriodProgress();
        period.rows = new List<PerfectDayHomeModels.GoalRowProgress>();
        period.totalCompleted = score == null || score.totalCompleted == null ? 0 : score.totalCompleted;
        period.totalGoal = score == null || score.totalGoal == null ? 0 : score.totalGoal;
        period.completionPercent = score == null || score.percent == null ? 0 : score.percent;
        period.drillObjectApiName = 'Task';
        period.drillListViewApiName = 'My_Completed_Activities';
        if (score == null || score.rows == null) {
            return period;
        }
        for (ExternalLoActivityRollupBuilder.CategoryScore row : score.rows) {
            PerfectDayHomeModels.GoalRowProgress item = new PerfectDayHomeModels.GoalRowProgress();
            item.activityKey = row.activityKey;
            item.label = row.shortLabel;
            item.completed = row.completed == null ? 0 : row.completed;
            item.goal = row.goal == null ? 0 : row.goal;
            item.completionPercent = row.percent == null ? 0 : row.percent;
            period.rows.add(item);
        }
        return period;
    }

    private static String highestRealtorUrgency(
        List<Account> realtorFollowUpsDue,
        Map<Id, Datetime> lastTouchByAccountId
    ) {
        String highest = '';
        for (Account accountRecord : realtorFollowUpsDue) {
            Datetime lastTouch = lastTouchByAccountId.get(accountRecord.Id);
            String urgency = ExternalLOBaselineHelper.realtorFollowUpUrgency(lastTouch);
            if (urgency == 'red') {
                return 'red';
            }
            if (urgency == 'orange') {
                highest = 'orange';
            }
        }
        return highest;
    }

    private static String highestLoanUrgency(List<Transaction__c> milestoneLoans) {
        String highest = '';
        for (Transaction__c loanRecord : milestoneLoans) {
            String urgency = ExternalLOBaselineHelper.loanMilestoneUrgency(loanRecord);
            if (urgency == 'red') {
                return 'red';
            }
            if (urgency == 'orange') {
                highest = 'orange';
            }
        }
        return highest;
    }
}