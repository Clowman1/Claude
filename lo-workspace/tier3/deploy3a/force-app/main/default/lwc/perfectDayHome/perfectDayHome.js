import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPerfectDayHomeData from '@salesforce/apex/PerfectDayHomeController.getPerfectDayHomeData';
import deferUpNextItem from '@salesforce/apex/PerfectDayHomeController.deferUpNextItem';
import completeUpNextItem from '@salesforce/apex/PerfectDayHomeController.completeUpNextItem';
import markReplyHandled from '@salesforce/apex/PerfectDayHomeController.markReplyHandled';
import snoozePrompt from '@salesforce/apex/ExternalLoPortalController.snoozePrompt';
import { PORTAL_VIEWS, dispatchPortalNavigate, showPortalToast, loadPortalFont, reduceApexError, isExperienceCloudContext } from 'c/portalUtils';
import { registerTourHooks } from 'c/loWsTourHooks';

const GOAL_PERIOD_TABS = [
    { id: 'today', label: 'Today' },
    { id: 'thisWeek', label: 'This week' },
    { id: 'thisMonth', label: 'This month' }
];

const QUICK_LINKS = [
    { key: 'prospects', label: 'Realtor Prospects', view: PORTAL_VIEWS.REALTOR_PROSPECTS, filterKey: null, priorityKey: null },
    { key: 'realtors', label: 'My Realtors', view: PORTAL_VIEWS.REALTORS, filterKey: 'due', priorityKey: 'realtorFollowUps' },
    { key: 'pastClients', label: 'Past Clients', view: PORTAL_VIEWS.PAST_CLIENTS, filterKey: null, priorityKey: null },
    { key: 'leads', label: 'My Leads', view: PORTAL_VIEWS.LEADS, filterKey: 'new', priorityKey: 'newLeads' }
];

const PRIORITY_RECORD_SET = {
    newLeads: 'new-leads',
    realtorFollowUps: 'realtor-follow-ups',
    preApprovals: 'pre-approvals',
    milestoneLoans: 'milestone-loans',
    overdueTasks: 'overdue-tasks'
};

const METRIC_RECORD_SET = {
    dailyScore: 'completed-today',
    goalsCompleted: 'completed-today',
    overdueTasks: 'overdue-tasks',
    activitiesRemaining: 'activities-remaining'
};

const GOAL_PERIOD_KEY = {
    today: 'today',
    thisWeek: 'week',
    thisMonth: 'month'
};

const DEFER_OPTIONS = [
    { id: 'hour', label: 'In 1 hour', detail: 'Returns to Up Next in about an hour' },
    { id: 'afternoon', label: 'This afternoon', detail: 'Returns around 1:30 PM today' },
    { id: 'tomorrow', label: 'Tomorrow morning', detail: 'Returns at 9:00 AM tomorrow' }
];

// Task due dates are date-only, so intraday defer windows cannot be honored for tasks.
const TASK_DEFER_OPTIONS = [
    { id: 'tomorrow', label: 'Tomorrow', detail: 'The task due date moves to tomorrow' }
];


const URGENCY_META = {
    red: { label: 'Urgent', rowClass: 'priority-row priority-row-urgent', labelClass: 'priority-urgency-label priority-urgency-red' },
    orange: { label: 'Attention', rowClass: 'priority-row priority-row-attention', labelClass: 'priority-urgency-label priority-urgency-orange' },
    '': { label: 'Scheduled', rowClass: 'priority-row priority-row-normal', labelClass: 'priority-urgency-label' }
};

const PRIORITY_ICONS = {
    newLeads: 'user-plus',
    realtorFollowUps: 'handshake',
    preApprovals: 'file-check-2',
    milestoneLoans: 'trending-up',
    overdueTasks: 'clock'
};

export default class PerfectDayHome extends LightningElement {
    @api embeddedInShell = false;
    // LO Workspace only (never the Partner Workspace portal): BD's In Person Invite + Upcoming card.
    showInPersonEvents = !isExperienceCloudContext();
    _setupComplete;
    _refreshKey;
    _lastRefreshedKey;
    homeData;
    errorMessage;
    isLoading = true;
    isRefreshing = false;
    isActionLoading = false;
    // Action key ('defer' | 'complete'), not display copy — labels derive from it.
    runningAction;
    isLogOutcomeOpen = false;
    isActivityModalOpen = false;
    activityModalKey;
    activityModalRecordId;
    activityModalObjectApiName;
    activityModalContactName;
    activityModalPromptKey;
    isDeferOpen = false;
    activeGoalPeriod = 'today';
    upNextCompleted = false;
    completedUpNextId;
    activeRecordSetKey;
    wiredHomeResult;

    @api
    get setupComplete() {
        return this._setupComplete;
    }
    set setupComplete(value) {
        this._setupComplete = value;
    }

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(value) {
        this._refreshKey = value;
        this.refreshIfKeyed();
    }

    // O4b: the shell passes true in LO Workspace (never the portal); shows the "?" that opens the tour menu.
    @api tourEnabled = false;
    // Mobile "Log Activity" tab: open the log form once the plan has loaded.
    @api autoOpenLog = false;
    _autoLogged = false;

    connectedCallback() {
        loadPortalFont(this);
        registerTourHooks(this);
    }

    handleTourHelp() {
        this.dispatchEvent(new CustomEvent('tourmenu'));
    }

    @wire(getPerfectDayHomeData, { cacheBust: '$refreshKey' })
    wiredHomeData(result) {
        this.wiredHomeResult = result;
        const { data, error } = result;

        if (data) {
            this.homeData = data;
            this.errorMessage = undefined;
            if (this.autoOpenLog && !this._autoLogged) {
                this._autoLogged = true;
                this.handleBannerLog();
            }
            // Keep the success card only while the backend still recommends the
            // item that was just completed; a new recommendation replaces it.
            if (data.upNext?.recordId !== this.completedUpNextId) {
                this.upNextCompleted = false;
                this.completedUpNextId = undefined;
            }
        } else if (error) {
            this.homeData = undefined;
            this.errorMessage = this.reduceError(error);
        }
        this.isLoading = false;
        this.isRefreshing = false;
        this.refreshIfKeyed();
    }

    get refreshIconClass() {
        return this.isRefreshing ? 'refresh-icon spinning' : 'refresh-icon';
    }

    get refreshButtonLabel() {
        return this.isRefreshing ? 'Refreshing…' : 'Refresh';
    }

    get completeButtonLabel() {
        return this.isCompleting ? 'Completing…' : 'Complete';
    }

    get deferButtonLabel() {
        return this.isDeferring ? 'Deferring…' : 'Defer';
    }

    get isCompleting() {
        return this.isActionLoading && this.runningAction === 'complete';
    }

    get isDeferring() {
        return this.isActionLoading && this.runningAction === 'defer';
    }

    get actionStatus() {
        return this.isDeferring ? 'Deferring…' : 'Completing…';
    }

    get hasHomeData() {
        return !!this.homeData;
    }

    get showFirstRun() {
        if (this._setupComplete === true) {
            return false;
        }
        if (this._setupComplete === false) {
            return !!this.homeData;
        }
        return !!this.homeData && this.homeData.onboardingComplete === false;
    }

    get showDashboard() {
        if (this._setupComplete === true) {
            return !!this.homeData;
        }
        if (this._setupComplete === false) {
            return false;
        }
        return !!this.homeData && this.homeData.onboardingComplete !== false;
    }

    get planUpdatedLabel() {
        return 'goals from your perfect week';
    }

    get welcomeGreeting() {
        const name = this.homeData?.userFirstName || 'there';
        return `Good morning, ${name}`;
    }

    get firstRunTitle() {
        const name = this.homeData?.userFirstName || 'there';
        return `Welcome, ${name}. Let’s build your perfect week.`;
    }

    get focusLabel() {
        return this.homeData?.businessFocus ? `Focus: ${this.homeData.businessFocus}` : null;
    }

    get hasFocus() {
        return !!this.focusLabel;
    }

    get goalFootnote() {
        if (this.homeData?.onboardingComplete) {
            return 'Goals come from the targets you set during setup. Only an admin can change them.';
        }
        return 'Goals are set from the Reach Home Loans company baseline. Only an admin or branch manager can raise or add goals.';
    }

    get paceBadgeClass() {
        const status = this.homeData?.paceStatus;
        if ((status || '').toLowerCase() === 'perfect day complete') {
            return 'pace-badge pace-badge-complete';
        }
        if ((status || '').toLowerCase() === 'behind pace') {
            return 'pace-badge pace-badge-behind';
        }
        return 'pace-badge pace-badge-on-track';
    }

    get progressBarTone() {
        const status = this.homeData?.paceStatus;
        if ((status || '').toLowerCase() === 'perfect day complete') {
            return 'success';
        }
        if ((status || '').toLowerCase() === 'behind pace') {
            return 'warn';
        }
        return 'teal';
    }

    get completionProgressStyle() {
        const percent = this.homeData?.dailyCompletionPercent || 0;
        return `width: ${Math.min(100, Math.max(0, percent))}%`;
    }

    get goalsSummaryLabel() {
        const completed = this.homeData?.goalsCompleted ?? 0;
        const total = this.homeData?.goalsTotal ?? 0;
        return `${completed} of ${total} daily goals complete · target 85% by 5:00 PM`;
    }

    get summaryMetrics() {
        if (!this.homeData?.summaryMetrics) {
            return [];
        }
        const metrics = this.homeData.summaryMetrics;
        return [metrics.dailyScore, metrics.goalsCompleted, metrics.overdueTasks, metrics.activitiesRemaining]
            .filter(Boolean)
            .map((metric) => ({
                ...metric,
                cardClass: `metric-card metric-card-${metric.tone || 'navy'}`,
                recordSetKey: METRIC_RECORD_SET[metric.drillFilterKey],
                notDrillable: !METRIC_RECORD_SET[metric.drillFilterKey],
                hasProgress: metric.progressTarget != null && metric.progressTarget > 0,
                progressStyle: this.buildProgressStyle(metric.progressCurrent, metric.progressTarget),
                valueClass: metric.tone === 'danger' ? 'metric-value metric-value-danger' : 'metric-value'
            }));
    }

    get quickLinks() {
        const priorities = this.homeData?.priorities || [];
        const countByKey = priorities.reduce((map, item) => {
            map[item.key] = item.count;
            return map;
        }, {});

        return QUICK_LINKS.map((link) => {
            const count = countByKey[link.priorityKey] ?? 0;
            let detail = 'Open list';
            if (link.key === 'leads') {
                detail = count > 0 ? `${count} new to contact` : 'All contacted';
            } else if (link.key === 'realtors') {
                detail = count > 0 ? `${count} follow-ups due` : 'On cadence';
            } else if (link.key === 'prospects') {
                detail = 'Open prospect list';
            } else if (link.key === 'pastClients') {
                detail = 'Open past clients';
            }
            return { ...link, detail };
        });
    }

    get priorities() {
        return (this.homeData?.priorities || []).map((priority) => {
            const urgency = priority.urgency || '';
            const meta = URGENCY_META[urgency] || URGENCY_META[''];
            return {
                ...priority,
                rowClass: meta.rowClass,
                urgencyLabel: meta.label,
                urgencyLabelClass: meta.labelClass,
                badgeClass: `priority-badge priority-badge-${urgency || 'normal'}`,
                iconWrapClass: `priority-icon-wrap priority-icon-wrap-${urgency || 'normal'}`,
                iconName: PRIORITY_ICONS[priority.key] || 'file-text',
                hasCount: priority.count > 0
            };
        });
    }

    get urgentPriorityCount() {
        return (this.homeData?.priorities || []).filter((p) => p.urgency === 'red').length;
    }

    get hasUpNext() {
        return !!this.homeData?.upNext && !this.upNextCompleted;
    }

    get upNext() {
        return this.homeData?.upNext;
    }

    get upNextActionLabel() {
        return this.upNext?.actionLabel || this.upNext?.title;
    }

    get hasUpNextContact() {
        return !!(this.upNext?.phone || this.upNext?.email);
    }

    get showUpNextLog() {
        return this.upNext?.canLogOutcome === true;
    }

    get completionProgressFillClass() {
        return `progress-fill progress-fill-${this.progressBarTone}`;
    }

    get goalPeriodTabs() {
        return GOAL_PERIOD_TABS.map((tab) => ({
            ...tab,
            tabClass: tab.id === this.activeGoalPeriod ? 'goal-tab goal-tab-active' : 'goal-tab',
            isActive: tab.id === this.activeGoalPeriod
        }));
    }

    get activeGoalRows() {
        const progress = this.homeData?.goalProgress;
        if (!progress) {
            return [];
        }
        const periodData =
            this.activeGoalPeriod === 'thisWeek' ? progress.thisWeek
            : this.activeGoalPeriod === 'thisMonth' ? progress.thisMonth
            : progress.today;

        if (!periodData) {
            return [];
        }

        const rows = (periodData.rows || [])
            .map((item) => {
                if (!item || item.goal <= 0) {
                    return null;
                }
                const percent = item.completionPercent ?? 0;
                // Pace comes from Apex (ExternalLOBaselineHelper.paceFor): one rule on every screen.
                const complete = item.pace === 'ahead' || item.completed >= item.goal;
                const onPace = !complete && item.pace !== 'behind';
                let status = 'behind';
                let statusLabel = 'Behind pace';
                let tone = 'warn';
                if (complete) {
                    status = 'complete';
                    statusLabel = 'Goal met';
                    tone = 'success';
                } else if (onPace) {
                    status = 'on-pace';
                    statusLabel = 'On pace';
                    tone = 'teal';
                }
                return {
                    key: item.activityKey,
                    label: item.label,
                    progressLabel: `${item.completed} of ${item.goal}`,
                    percent,
                    progressStyle: `width: ${Math.min(100, percent)}%`,
                    barFillClass: `progress-fill progress-fill-${tone}`,
                    status,
                    statusLabel,
                    badgeClass: `goal-status-badge goal-status-${status}`
                };
            })
            .filter(Boolean);

        // Inverted goal: keep overdue tasks at zero. Only meaningful for today.
        if (this.activeGoalPeriod === 'today') {
            const overdueCount = this.homeData?.summaryMetrics?.overdueTasks?.value ?? 0;
            const clear = overdueCount === 0;
            rows.push({
                key: 'overdueTasks',
                label: 'Overdue tasks',
                progressLabel: clear ? 'All clear — target is 0' : `${overdueCount} open — target is 0`,
                percent: 100,
                progressStyle: 'width: 100%',
                barFillClass: clear ? 'progress-fill progress-fill-success' : 'progress-fill progress-fill-danger',
                status: clear ? 'complete' : 'at-risk',
                statusLabel: clear ? 'Complete' : 'At risk',
                badgeClass: clear ? 'goal-status-badge goal-status-complete' : 'goal-status-badge goal-status-at-risk'
            });
        }
        return rows;
    }

    get hasGoalRows() {
        return this.activeGoalRows.length > 0;
    }

    get goalPeriodSummary() {
        if (!this.homeData?.goalProgress) {
            return '';
        }
        const rows = this.activeGoalRows;
        if (rows.length === 0) {
            return 'No goals configured for this period';
        }
        const periodLabel = GOAL_PERIOD_TABS.find((t) => t.id === this.activeGoalPeriod)?.label || 'Today';
        const activityRows = rows.filter((row) => row.key !== 'overdueTasks');
        const completeCount = activityRows.filter((row) => row.status === 'complete').length;
        return `${completeCount} of ${activityRows.length} goals met ${periodLabel.toLowerCase()}`;
    }

    get showLogModal() {
        return this.isLogOutcomeOpen && !!this.homeData?.upNext?.recordId;
    }

    get logRecordId() {
        return this.homeData?.upNext?.recordId;
    }

    get logObjectApiName() {
        const apiName = this.homeData?.upNext?.objectApiName;
        if (apiName) {
            return apiName;
        }
        const categoryKey = this.homeData?.upNext?.categoryKey;
        if (categoryKey === 'realtorFollowUps') {
            return 'Account';
        }
        if (categoryKey === 'milestoneLoans') {
            return 'Transaction__c';
        }
        return 'Lead';
    }

    get logSubjectName() {
        return this.homeData?.upNext?.title;
    }

    get logSubjectContext() {
        return this.homeData?.upNext?.reason;
    }

    get logPhone() {
        return this.homeData?.upNext?.phone;
    }

    get logEmail() {
        return this.homeData?.upNext?.email;
    }

    get logGoalCredit() {
        return this.homeData?.upNext?.goalCreditLabel || 'your daily goals';
    }

    async handleRefresh() {
        if (this.isRefreshing) {
            return;
        }
        this.isLoading = true;
        await this.refreshHomeData(true);
    }

    get showSkeleton() {
        return this.isLoading && !this.hasHomeData;
    }

    handleMetricClick(event) {
        const recordSetKey = event.currentTarget.dataset.recordSetKey;
        // "Activities left today" counts goal gaps, not tasks: Today's Plan lists them per category.
        if (recordSetKey === 'activities-remaining') {
            this.template.querySelector('[data-tour="today-plan"]')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
            return;
        }
        this.openRecordSet(recordSetKey);
    }

    handlePriorityClick(event) {
        const priorityKey = event.currentTarget.dataset.priorityKey;
        const recordSetKey = PRIORITY_RECORD_SET[priorityKey];
        this.openRecordSet(recordSetKey);
    }

    handleQuickLinkClick(event) {
        const view = event.currentTarget.dataset.view;
        const filterKey = event.currentTarget.dataset.filterKey;
        this.navigateToPortalView(view, filterKey);
    }

    handleStartSetup() {
        this.navigateToPortalView(PORTAL_VIEWS.PERFECT_WEEK);
    }

    handleViewScoreboard() {
        this.navigateToPortalView(PORTAL_VIEWS.PROGRESS);
    }

    handleInPersonInvite() {
        const events = this.template.querySelector('c-lo-ws-in-person-events');
        if (events) events.openInvite();
    }

    handleOpenCalendar() {
        const calendar = this.template.querySelector('c-lo-ws-appointments');
        if (calendar) calendar.openCalendar();
    }

    // Follow-up rows in Up Next (open Tasks due today or overdue): Mark complete.
    // A follow-up was completed or moved from the Open all list or a drawer.
    handleTasksChanged() {
        this.refreshHomeData();
    }

    async handlePromptComplete(event) {
        const prompt = event.detail.prompt || {};
        try {
            await completeUpNextItem({ recordId: prompt.taskId, objectApiName: 'Task' });
            this.showToast('Completed', 'Follow-up marked complete.', 'success');
            await this.refreshHomeData();
        } catch (error) {
            this.showToast('Unable to complete', reduceApexError(error), 'error');
        }
    }

    handleBannerLog() {
        const plan = this.homeData?.todayPlan || [];
        const firstRow = plan.find((row) => row.isEnabled !== false) || plan[0];
        this.activityModalKey = firstRow?.activityKey;
        this.activityModalPromptKey = undefined;
        this.activityModalRecordId = undefined;
        this.activityModalObjectApiName = undefined;
        this.activityModalContactName = undefined;
        this.isActivityModalOpen = true;
    }

    handleGoalPeriodClick(event) {
        this.activeGoalPeriod = event.currentTarget.dataset.period;
    }

    handleGoalRowClick(event) {
        const goalKey = event.currentTarget.dataset.goalKey;
        if (goalKey === 'overdueTasks') {
            this.openRecordSet('overdue-tasks');
            return;
        }
        const periodKey = GOAL_PERIOD_KEY[this.activeGoalPeriod] || 'today';
        this.openRecordSet(`goal-${periodKey}-${goalKey}`);
    }

    openRecordSet(recordSetKey) {
        if (!recordSetKey) {
            return;
        }
        this.activeRecordSetKey = recordSetKey;
    }

    handleDrawerClose() {
        this.activeRecordSetKey = null;
    }

    async handleDrawerRecordsChanged() {
        await this.refreshHomeData();
    }

    deferChoice = 'hour';

    get availableDeferOptions() {
        return this.homeData?.upNext?.objectApiName === 'Task' ? TASK_DEFER_OPTIONS : DEFER_OPTIONS;
    }

    get deferOptions() {
        return this.availableDeferOptions.map((option) => ({
            ...option,
            isSelected: option.id === this.deferChoice,
            optionClass: option.id === this.deferChoice ? 'defer-option defer-option-active' : 'defer-option'
        }));
    }

    handleDefer() {
        this.deferChoice = this.availableDeferOptions[0].id;
        this.isDeferOpen = true;
    }

    closeDeferModal() {
        this.isDeferOpen = false;
    }

    handleDeferChoice(event) {
        this.deferChoice = event.currentTarget.dataset.option;
    }

    async confirmDefer() {
        if (!this.homeData?.upNext) {
            return;
        }
        await this.runUpNextAction('defer');
    }

    async handleComplete() {
        if (!this.homeData?.upNext) {
            return;
        }
        await this.runUpNextAction('complete');
    }

    handleOpenRecord() {
        const upNext = this.homeData?.upNext;
        if (!upNext?.recordId) {
            return;
        }
        const viewByObject = {
            Lead: PORTAL_VIEWS.LEADS,
            Account: PORTAL_VIEWS.REALTORS,
            Transaction__c: PORTAL_VIEWS.LOANS
        };
        const view = viewByObject[upNext.objectApiName];
        if (view) {
            this.navigateToPortalView(view, null, upNext.recordId);
            return;
        }
        if (upNext.objectApiName === 'Task') {
            this.openRecordSet('overdue-tasks');
            return;
        }
        this.showToast('Record', 'This record is not available in Partner Workspace.', 'info');
    }

    handleLogCommunication() {
        const upNext = this.homeData?.upNext;
        if (!upNext?.recordId) {
            return;
        }
        // The communication modal logs against Lead, Account, and Transaction__c —
        // the same objects ExternalLoCommunicationService accepts.
        if (['Lead', 'Account', 'Transaction__c'].includes(upNext.objectApiName)) {
            this.isLogOutcomeOpen = true;
            return;
        }
        this.handleOpenRecord();
    }

    get activityCategories() {
        return this.homeData?.todayPlan || [];
    }

    handlePlanLog(event) {
        this.activityModalKey = event.detail.activityKey;
        this.activityModalPromptKey = undefined;
        this.activityModalRecordId = undefined;
        this.activityModalObjectApiName = undefined;
        this.activityModalContactName = undefined;
        this.isActivityModalOpen = true;
    }

    // High alert: open the lead on its Document requests tab to decision the uploads.
    handlePromptReview(event) {
        const prompt = event.detail?.prompt;
        if (!prompt?.recordId) {
            return;
        }
        dispatchPortalNavigate(this, { view: PORTAL_VIEWS.LEADS, filter: 'all', recordId: prompt.recordId, tab: 'requests' });
    }

    // comms-settings: a reply to an automated text opens that page's text thread (realtor page shows its Texts card).
    handleReplyOpen(event) {
        const prompt = event.detail?.prompt;
        if (!prompt?.recordId || !prompt.openView) {
            this.showToast('Text reply', 'This reply is not linked to a record you can open.', 'info');
            return;
        }
        const filter = prompt.openView === 'leads' ? 'all' : undefined; // as the document-review alert
        dispatchPortalNavigate(this, { view: prompt.openView, filter, recordId: prompt.recordId, tab: 'texts' });
    }

    async handleReplyHandled(event) {
        const prompt = event.detail?.prompt || {};
        try {
            await markReplyHandled({ messageId: prompt.messageId });
            this.showToast('Handled', 'Reply marked handled.', 'success');
            await this.refreshHomeData();
        } catch (error) {
            this.showToast('Unable to update', reduceApexError(error), 'error');
        }
    }

    // Up Next "Open all" row: Leads / Realtors / Loans open in the workspace, anything else shows a note.
    handlePromptOpenRecord(event) {
        const { recordId, objectApiName } = event.detail || {};
        const viewByObject = {
            Lead: PORTAL_VIEWS.LEADS,
            Account: PORTAL_VIEWS.REALTORS,
            Transaction__c: PORTAL_VIEWS.LOANS
        };
        const view = viewByObject[objectApiName];
        if (view && recordId) {
            this.navigateToPortalView(view, null, recordId);
            return;
        }
        this.showToast('Record', 'This item has no record to open here.', 'info');
    }

    handlePromptLog(event) {
        const prompt = event.detail.prompt || {};
        this.activityModalKey = prompt.activityKey;
        // Follow-up rows send 'task:<id>': the server completes that follow-up in the same save as the log.
        this.activityModalPromptKey = prompt.promptKey;
        this.activityModalRecordId = prompt.recordId;
        this.activityModalObjectApiName = prompt.objectApiName;
        this.activityModalContactName = prompt.contactName;
        this.isActivityModalOpen = true;
    }

    async handlePromptSnooze(event) {
        const prompt = event.detail.prompt || {};
        if (prompt.taskId) {
            // A follow-up Task: move its due date to tomorrow.
            try {
                await deferUpNextItem({ recordId: prompt.taskId, objectApiName: 'Task', deferOption: 'tomorrow' });
                this.showToast('Moved to tomorrow', 'The follow-up is now due tomorrow.', 'success');
                await this.refreshHomeData();
            } catch (error) {
                this.showToast('Unable to move', reduceApexError(error), 'error');
            }
            return;
        }
        try {
            const result = await snoozePrompt({
                promptKey: prompt.promptKey,
                recordId: prompt.recordId,
                objectApiName: prompt.objectApiName
            });
            this.showToast('Saved for tomorrow', result.userMessage, 'success');
            await this.refreshHomeData();
        } catch (error) {
            this.showToast('Unable to snooze', reduceApexError(error), 'error');
        }
    }

    closeActivityModal() {
        this.isActivityModalOpen = false;
        this.activityModalPromptKey = undefined;
    }

    async handleActivityLogged(event) {
        this.closeActivityModal();
        this.showToast('Activity logged', event.detail.message, 'success');
        await this.refreshHomeData();
        // A new exact-time follow-up belongs on the appointments card.
        this.template.querySelector('c-lo-ws-appointments')?.refresh();
    }

    closeLogOutcome() {
        this.isLogOutcomeOpen = false;
    }

    async handleLogOutcomeFinished() {
        const upNext = this.homeData?.upNext;
        this.closeLogOutcome();
        this.completedUpNextId = upNext?.recordId;
        this.upNextCompleted = true;
        this.showToast('Activity logged', 'Your Perfect Day progress has been updated.', 'success');
        await this.refreshHomeData();
        this.template.querySelector('c-lo-ws-appointments')?.refresh();
    }

    undoUpNextComplete() {
        this.upNextCompleted = false;
        this.completedUpNextId = undefined;
    }

    buildProgressStyle(current, target) {
        if (!target || target <= 0) {
            return 'width: 0%';
        }
        const percent = Math.min(100, Math.round(((current || 0) / target) * 100));
        return `width: ${percent}%`;
    }

    navigateToPortalView(view, filterKey, recordId) {
        dispatchPortalNavigate(this, {
            view,
            filter: filterKey,
            recordId
        });
    }

    async runUpNextAction(actionName) {
        const upNext = this.homeData.upNext;
        this.isActionLoading = true;
        this.runningAction = actionName;
        try {
            if (actionName === 'defer') {
                await deferUpNextItem({
                    recordId: upNext.recordId,
                    objectApiName: upNext.objectApiName,
                    deferOption: this.deferChoice
                });
                const option = this.availableDeferOptions.find((item) => item.id === this.deferChoice);
                this.showToast('Deferred', option ? option.detail : 'This recommendation will return later.', 'success');
                this.isDeferOpen = false;
            } else {
                await completeUpNextItem({
                    recordId: upNext.recordId,
                    objectApiName: upNext.objectApiName
                });
                this.completedUpNextId = upNext.recordId;
                this.upNextCompleted = true;
                this.showToast('Completed', 'The task was marked complete.', 'success');
            }
            await this.refreshHomeData();
        } catch (error) {
            this.upNextCompleted = false;
            this.completedUpNextId = undefined;
            this.showToast('Action failed', this.reduceError(error), 'error');
        } finally {
            this.isActionLoading = false;
            this.runningAction = undefined;
        }
    }

    // The wire handler normally clears the flags when fresh data (or an error)
    // arrives, but refreshApex can also reject without re-emitting — e.g. an
    // expired session, a network drop, or a click before the wire has
    // provisioned. The finally block guarantees the button never sticks in
    // its "Refreshing…" state.
    async refreshHomeData(showErrorToast) {
        if (!this.wiredHomeResult) {
            this.isLoading = false;
            return;
        }
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredHomeResult);
        } catch (error) {
            if (showErrorToast) {
                this.showToast('Refresh failed', this.reduceError(error), 'error');
            }
        } finally {
            this.isRefreshing = false;
            this.isLoading = false;
        }
    }

    refreshIfKeyed() {
        if (!this._refreshKey || !this.wiredHomeResult || this._lastRefreshedKey === this._refreshKey) {
            return;
        }
        this._lastRefreshedKey = this._refreshKey;
        this.refreshHomeData();
    }

    showToast(title, message, variant) {
        showPortalToast(this, title, message, variant);
    }

    reduceError(error) {
        return reduceApexError(error);
    }
}