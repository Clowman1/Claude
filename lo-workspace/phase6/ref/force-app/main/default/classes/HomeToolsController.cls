public with sharing class HomeToolsController {
    private static final Set<String> FUNDED_REVIEW_STATUSES = new Set<String>{ 'Funding', 'PC Review', 'Post-Closed' };
    private static final Date TRACKER_PRE_APPROVAL_START = Date.newInstance(2025, 10, 1);
    private static final String DPA_SECOND_LOAN_TYPE = 'DPA 2nd';
    private static final String REPORT_ACTIVE_PRE_APPROVALS = 'LO_Active_Pre_Approvals_2026_Review';
    private static final String REPORT_HOUSE_DEALS_YTD = 'LO_House_Deals_YTD_Review';
    private static final String REPORT_HOUSE_DEALS_MTD = 'LO_House_Deals_MTD_Review';
    private static final String REPORT_PERSONAL_DEALS_YTD = 'LO_Personal_Deals_YTD_Review';
    private static final String REPORT_PERSONAL_DEALS_MTD = 'LO_Personal_Deals_MTD_Review';
    private static final String REPORT_JOSEPH_DEALS_YTD = 'LO_Joseph_Deals_YTD_Review';
    private static final String REPORT_JOSEPH_DEALS_MTD = 'LO_Joseph_Deals_MTD_Review';
    private static final Set<String> LOAN_PARTNER_CHECKLIST_EMAILS = new Set<String>{
        'joey@reachhomeloans.com',
        'mstraight@reachhomeloans.com'
    };
    private static final Set<String> LOAN_PARTNER_CHECKLIST_NAMES = new Set<String>{
        'Joey D\'Alessandro',
        'Megan Straight'
    };
    private static final String DAILY_CHECKLIST_SUBJECT_PREFIX = 'Daily Checklist: ';
    private static final Integer LEAD_NAME_LIMIT = 120;
    // A running to-do list, distinct from the Loan Partner daily checklist: items carry no due
    // date and stay open until they are checked off, so none of the past-due logic applies.
    private static final Set<String> RUNNING_TODO_EMAILS = new Set<String>{
        'clowman@reachhomeloans.com',
        'zfritz@reachhomeloans.com'
    };
    private static final String RUNNING_TODO_SUBJECT_PREFIX = 'To-Do: ';
    private static final Integer RUNNING_TODO_COMPLETED_LIMIT = 25;

    @AuraEnabled(cacheable=true)
    public static HomeToolsData getHomeToolsData() {
        HomeToolsData data = new HomeToolsData();
        data.isLoanPartnerChecklistUser = isLoanPartnerChecklistUser();
        if (data.isLoanPartnerChecklistUser) {
            data.events = new List<HomeItem>();
            data.recentRecords = new List<HomeItem>();
            data.trackers = new List<HomeTracker>();
            data.dailyChecklistItems = getDailyChecklistItems();
            return data;
        }
        // The drawer is the to-do list for these users. Events and recent records are omitted
        // deliberately, and their queries skipped rather than run and discarded.
        data.isRunningTodoUser = isRunningTodoUser();
        if (data.isRunningTodoUser) {
            data.runningTodoItems = getRunningTodoItems();
            data.events = new List<HomeItem>();
            data.recentRecords = new List<HomeItem>();
            data.trackers = getLoanOfficerTrackers();
            data.weeklyLeadTracker = getWeeklyLeadTracker();
            return data;
        }
        data.events = getEvents();
        data.recentRecords = getRecentRecords();
        data.trackers = getLoanOfficerTrackers();
        data.weeklyLeadTracker = getWeeklyLeadTracker();
        return data;
    }

    /**
     * The Lead is captured as free text rather than a lookup: Loan Partners track work for people
     * who do not always exist as a Salesforce Lead, and requiring a match blocked the item outright.
     * The name lives in the Subject, which is also what standard Task views show.
     */
    @AuraEnabled
    public static DailyChecklistItem addDailyChecklistItem(String leadName, String description, String priority) {
        verifyLoanPartnerChecklistUser();
        String trimmedLeadName = String.isBlank(leadName) ? '' : leadName.trim();
        if (String.isBlank(trimmedLeadName)) {
            throw new AuraHandledException('Enter the Lead name this checklist item belongs to.');
        }
        String trimmedDescription = String.isBlank(description) ? '' : description.trim();
        if (String.isBlank(trimmedDescription)) {
            throw new AuraHandledException('Enter a brief description of what needs to be done.');
        }

        Task checklistTask = new Task(
            Subject = checklistSubject(trimmedDescription),
            Description = trimmedDescription,
            Checklist_Lead_Name__c = truncate(trimmedLeadName, LEAD_NAME_LIMIT),
            Priority = taskPriorityValue(priority),
            Status = 'Not Started',
            ActivityDate = Date.today()
        );
        insert checklistTask;
        return toDailyChecklistItem([
            SELECT Id, Subject, Description, Priority, ActivityDate, WhoId, Who.Name,
                   Checklist_Lead_Name__c, Checklist_Sort_Order__c
            FROM Task
            WHERE Id = :checklistTask.Id
        ]);
    }

    private static String checklistSubject(String description) {
        return DAILY_CHECKLIST_SUBJECT_PREFIX + truncate(description, 255 - DAILY_CHECKLIST_SUBJECT_PREFIX.length());
    }

    private static String truncate(String value, Integer limitLength) {
        return value.length() > limitLength ? value.substring(0, limitLength) : value;
    }

    @AuraEnabled
    public static void completeDailyChecklistItem(Id taskId) {
        verifyLoanPartnerChecklistUser();
        if (taskId == null) {
            throw new AuraHandledException('The checklist item was not found.');
        }
        Task checklistTask = [
            SELECT Id, Subject, OwnerId, Status
            FROM Task
            WHERE Id = :taskId
            AND OwnerId = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!checklistTask.Subject.startsWith(DAILY_CHECKLIST_SUBJECT_PREFIX)) {
            throw new AuraHandledException('This is not a Daily Checklist item.');
        }
        checklistTask.Status = 'Completed';
        update checklistTask;
    }

    @AuraEnabled(cacheable=true)
    public static List<ClearedDailyChecklistItem> getClearedDailyChecklistItems() {
        verifyLoanPartnerChecklistUser();
        Datetime startOfYesterday = Datetime.newInstance(Date.today().addDays(-1), Time.newInstance(0, 0, 0, 0));
        String checklistSubjectPattern = DAILY_CHECKLIST_SUBJECT_PREFIX + '%';
        List<ClearedDailyChecklistItem> items = new List<ClearedDailyChecklistItem>();
        for (Task checklistTask : [
            SELECT Id, Subject, Description, Priority, WhoId, Who.Name, Checklist_Lead_Name__c, LastModifiedDate
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
            AND IsClosed = true
            AND Status = 'Completed'
            AND Subject LIKE :checklistSubjectPattern
            AND LastModifiedDate >= :startOfYesterday
            ORDER BY LastModifiedDate DESC
        ]) {
            items.add(toClearedDailyChecklistItem(checklistTask));
        }
        return items;
    }

    private static Boolean isRunningTodoUser() {
        User currentUser = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return RUNNING_TODO_EMAILS.contains(currentUser.Email == null ? '' : currentUser.Email.toLowerCase());
    }

    private static void verifyRunningTodoUser() {
        if (!isRunningTodoUser()) {
            throw new AuraHandledException('The running to-do list is available only to the configured users.');
        }
    }

    // Open items only, highest priority first, then in the order the user dragged them into.
    // Items never dragged fall to the back of their band, oldest first, so nothing quietly ages
    // out of view at the bottom of a long list.
    private static List<RunningTodoItem> getRunningTodoItems() {
        List<RunningTodoItem> high = new List<RunningTodoItem>();
        List<RunningTodoItem> medium = new List<RunningTodoItem>();
        List<RunningTodoItem> low = new List<RunningTodoItem>();
        String todoSubjectPattern = RUNNING_TODO_SUBJECT_PREFIX + '%';
        for (Task todoTask : [
            SELECT Id, Subject, Description, Priority, CreatedDate, Checklist_Sort_Order__c
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
            AND IsClosed = false
            AND Subject LIKE :todoSubjectPattern
            ORDER BY Checklist_Sort_Order__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            RunningTodoItem item = toRunningTodoItem(todoTask);
            if (todoTask.Priority == 'High') {
                high.add(item);
            } else if (todoTask.Priority == 'Low') {
                low.add(item);
            } else {
                medium.add(item);
            }
        }
        high.addAll(medium);
        high.addAll(low);
        return high;
    }

    @AuraEnabled
    public static RunningTodoItem addRunningTodoItem(String description, String priority) {
        verifyRunningTodoUser();
        String trimmedDescription = String.isBlank(description) ? '' : description.trim();
        if (String.isBlank(trimmedDescription)) {
            throw new AuraHandledException('Enter a brief description of what needs to be done.');
        }
        Integer subjectDescriptionLimit = 255 - RUNNING_TODO_SUBJECT_PREFIX.length();
        String subjectDescription = trimmedDescription.length() > subjectDescriptionLimit
            ? trimmedDescription.substring(0, subjectDescriptionLimit)
            : trimmedDescription;
        // ActivityDate is deliberately left null. These are running items with no due date,
        // which is what keeps them out of any past-due or daily rollover treatment.
        Task todoTask = new Task(
            Subject = RUNNING_TODO_SUBJECT_PREFIX + subjectDescription,
            Description = trimmedDescription,
            Priority = taskPriorityValue(priority),
            Status = 'Not Started'
        );
        insert todoTask;
        return toRunningTodoItem([
            SELECT Id, Subject, Description, Priority, CreatedDate FROM Task WHERE Id = :todoTask.Id
        ]);
    }

    @AuraEnabled
    public static void completeRunningTodoItem(Id taskId) {
        verifyRunningTodoUser();
        if (taskId == null) {
            throw new AuraHandledException('The to-do item was not found.');
        }
        Task todoTask = [
            SELECT Id, Subject, OwnerId, Status
            FROM Task
            WHERE Id = :taskId AND OwnerId = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!todoTask.Subject.startsWith(RUNNING_TODO_SUBJECT_PREFIX)) {
            throw new AuraHandledException('This is not a running to-do item.');
        }
        todoTask.Status = 'Completed';
        update todoTask;
    }

    /**
     * Editing rewrites both Subject and Description because the subject carries the prefix the
     * list queries on, and is what shows in standard Salesforce Task views. For a to-do the
     * subject is the description; for a Daily Checklist item it is the Lead name.
     */
    @AuraEnabled
    public static RunningTodoItem updateRunningTodoItem(Id taskId, String description, String priority) {
        verifyRunningTodoUser();
        Task todoTask = loadOwnedChecklistTask(taskId, RUNNING_TODO_SUBJECT_PREFIX, 'running to-do item');
        String trimmedDescription = applyChecklistEdit(todoTask, description, priority);
        todoTask.Subject = RUNNING_TODO_SUBJECT_PREFIX +
            truncate(trimmedDescription, 255 - RUNNING_TODO_SUBJECT_PREFIX.length());
        update todoTask;
        return toRunningTodoItem([
            SELECT Id, Subject, Description, Priority, CreatedDate FROM Task WHERE Id = :todoTask.Id
        ]);
    }

    @AuraEnabled
    public static DailyChecklistItem updateDailyChecklistItem(Id taskId, String leadName, String description, String priority) {
        verifyLoanPartnerChecklistUser();
        Task checklistTask = loadOwnedChecklistTask(taskId, DAILY_CHECKLIST_SUBJECT_PREFIX, 'Daily Checklist item');
        String trimmedLeadName = String.isBlank(leadName) ? '' : leadName.trim();
        if (String.isBlank(trimmedLeadName)) {
            throw new AuraHandledException('Enter the Lead name this checklist item belongs to.');
        }
        String trimmedDescription = applyChecklistEdit(checklistTask, description, priority);
        checklistTask.Subject = checklistSubject(trimmedDescription);
        checklistTask.Checklist_Lead_Name__c = truncate(trimmedLeadName, LEAD_NAME_LIMIT);
        update checklistTask;
        return toDailyChecklistItem([
            SELECT Id, Subject, Description, Priority, ActivityDate, WhoId, Who.Name,
                   Checklist_Lead_Name__c, Checklist_Sort_Order__c
            FROM Task WHERE Id = :checklistTask.Id
        ]);
    }

    /**
     * Persists the exact arrangement produced by dragging a row, together with the priority the
     * drop position implies. Sort order is rewritten for the whole list rather than the moved row
     * alone, which keeps the stored positions dense and free of ties.
     */
    @AuraEnabled
    public static void reorderChecklistItems(List<ChecklistOrderItem> orderedItems) {
        if (orderedItems == null || orderedItems.isEmpty()) {
            return;
        }
        Map<Id, ChecklistOrderItem> requestedById = new Map<Id, ChecklistOrderItem>();
        for (ChecklistOrderItem orderedItem : orderedItems) {
            if (orderedItem != null && orderedItem.id != null) {
                requestedById.put(orderedItem.id, orderedItem);
            }
        }
        List<Task> tasks = [
            SELECT Id, Subject, Priority, Checklist_Sort_Order__c
            FROM Task
            WHERE Id IN :requestedById.keySet()
            AND OwnerId = :UserInfo.getUserId()
        ];
        if (tasks.size() != requestedById.size()) {
            throw new AuraHandledException('One of those items is no longer on your list.');
        }
        Map<Id, Task> tasksById = new Map<Id, Task>(tasks);
        List<Task> updates = new List<Task>();
        Integer position = 0;
        for (ChecklistOrderItem orderedItem : orderedItems) {
            Task listTask = tasksById.get(orderedItem.id);
            if (listTask == null) {
                continue;
            }
            if (!listTask.Subject.startsWith(DAILY_CHECKLIST_SUBJECT_PREFIX) &&
                !listTask.Subject.startsWith(RUNNING_TODO_SUBJECT_PREFIX)) {
                throw new AuraHandledException('One of those items is not a checklist item.');
            }
            listTask.Checklist_Sort_Order__c = position;
            listTask.Priority = taskPriorityValue(orderedItem.priority);
            updates.add(listTask);
            position++;
        }
        update updates;
    }

    // Shared by both lists: an item is only editable by the person who owns it, and only if it
    // still carries the prefix that marks it as belonging to that list.
    private static Task loadOwnedChecklistTask(Id taskId, String subjectPrefix, String itemLabel) {
        if (taskId == null) {
            throw new AuraHandledException('The ' + itemLabel + ' was not found.');
        }
        List<Task> tasks = [
            SELECT Id, Subject, Description, Priority, OwnerId, Status, IsClosed
            FROM Task
            WHERE Id = :taskId AND OwnerId = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (tasks.isEmpty() || !tasks[0].Subject.startsWith(subjectPrefix)) {
            throw new AuraHandledException('This is not one of your ' + itemLabel + 's.');
        }
        return tasks[0];
    }

    // Returns the trimmed description so the caller can build the Subject its list expects.
    private static String applyChecklistEdit(Task checklistTask, String description, String priority) {
        String trimmedDescription = String.isBlank(description) ? '' : description.trim();
        if (String.isBlank(trimmedDescription)) {
            throw new AuraHandledException('Enter a brief description of what needs to be done.');
        }
        checklistTask.Description = trimmedDescription;
        checklistTask.Priority = taskPriorityValue(priority);
        return trimmedDescription;
    }

    @AuraEnabled
    public static void reopenRunningTodoItem(Id taskId) {
        verifyRunningTodoUser();
        if (taskId == null) {
            throw new AuraHandledException('The to-do item was not found.');
        }
        Task todoTask = [
            SELECT Id, Subject, OwnerId, Status
            FROM Task
            WHERE Id = :taskId AND OwnerId = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!todoTask.Subject.startsWith(RUNNING_TODO_SUBJECT_PREFIX)) {
            throw new AuraHandledException('This is not a running to-do item.');
        }
        todoTask.Status = 'Not Started';
        update todoTask;
    }

    // No date cutoff -- a running list is not bounded by a day, so this returns the most
    // recently completed items regardless of when they were finished.
    @AuraEnabled(cacheable=true)
    public static List<CompletedRunningTodoItem> getCompletedRunningTodoItems() {
        verifyRunningTodoUser();
        String todoSubjectPattern = RUNNING_TODO_SUBJECT_PREFIX + '%';
        List<CompletedRunningTodoItem> items = new List<CompletedRunningTodoItem>();
        for (Task todoTask : [
            SELECT Id, Subject, Description, Priority, LastModifiedDate
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
            AND IsClosed = true
            AND Status = 'Completed'
            AND Subject LIKE :todoSubjectPattern
            ORDER BY LastModifiedDate DESC
            LIMIT :RUNNING_TODO_COMPLETED_LIMIT
        ]) {
            items.add(new CompletedRunningTodoItem(
                todoTask.Id,
                runningTodoDescription(todoTask),
                todoTask.Priority == 'Normal' ? 'Medium' : todoTask.Priority,
                todoTask.LastModifiedDate.format('MMM d, h:mm a')
            ));
        }
        return items;
    }

    private static String runningTodoDescription(Task todoTask) {
        return String.isBlank(todoTask.Description)
            ? todoTask.Subject.substring(RUNNING_TODO_SUBJECT_PREFIX.length())
            : todoTask.Description;
    }

    private static RunningTodoItem toRunningTodoItem(Task todoTask) {
        return new RunningTodoItem(
            todoTask.Id,
            runningTodoDescription(todoTask),
            todoTask.Priority == 'Normal' ? 'Medium' : todoTask.Priority,
            todoTask.CreatedDate.format('MMM d')
        );
    }

    private static Boolean isLoanPartnerChecklistUser() {
        User currentUser = [
            SELECT Name, Email
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return LOAN_PARTNER_CHECKLIST_EMAILS.contains(currentUser.Email == null ? '' : currentUser.Email.toLowerCase()) ||
            LOAN_PARTNER_CHECKLIST_NAMES.contains(currentUser.Name);
    }

    private static void verifyLoanPartnerChecklistUser() {
        if (!isLoanPartnerChecklistUser()) {
            throw new AuraHandledException('Daily Checklist access is available only to the configured Loan Partners.');
        }
    }

    private static List<DailyChecklistItem> getDailyChecklistItems() {
        List<DailyChecklistItem> high = new List<DailyChecklistItem>();
        List<DailyChecklistItem> medium = new List<DailyChecklistItem>();
        List<DailyChecklistItem> low = new List<DailyChecklistItem>();
        String checklistSubjectPattern = DAILY_CHECKLIST_SUBJECT_PREFIX + '%';
        for (Task checklistTask : [
            SELECT Id, Subject, Description, Priority, ActivityDate, WhoId, Who.Name,
                   Checklist_Lead_Name__c, Checklist_Sort_Order__c
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
            AND IsClosed = false
            AND Subject LIKE :checklistSubjectPattern
            ORDER BY Checklist_Sort_Order__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            DailyChecklistItem item = toDailyChecklistItem(checklistTask);
            // Bucketed on the item, not the Task, because a past-due item reports as High.
            if (item.priority == 'High') {
                high.add(item);
            } else if (item.priority == 'Low') {
                low.add(item);
            } else {
                medium.add(item);
            }
        }
        high.addAll(medium);
        high.addAll(low);
        return high;
    }

    private static DailyChecklistItem toDailyChecklistItem(Task checklistTask) {
        Boolean isPastDue = checklistTask.ActivityDate != null && checklistTask.ActivityDate < Date.today();
        // Anything carried over from a previous day is simply High priority now.
        String priority = isPastDue
            ? 'High'
            : (checklistTask.Priority == 'Normal' ? 'Medium' : checklistTask.Priority);
        return new DailyChecklistItem(
            checklistTask.Id,
            checklistTask.WhoId,
            checklistLeadName(checklistTask),
            checklistDescription(checklistTask),
            priority,
            checklistTask.ActivityDate,
            isPastDue
        );
    }

    private static ClearedDailyChecklistItem toClearedDailyChecklistItem(Task checklistTask) {
        return new ClearedDailyChecklistItem(
            checklistTask.Id,
            checklistTask.WhoId,
            checklistLeadName(checklistTask),
            checklistDescription(checklistTask),
            checklistTask.Priority == 'Normal' ? 'Medium' : checklistTask.Priority,
            checklistTask.LastModifiedDate.format('MMM d, h:mm a')
        );
    }

    /**
     * Items created before the Lead lookup was dropped carry the borrower on WhoId; items created
     * since carry the typed name in Checklist_Lead_Name__c. Reading the typed name first means an
     * edited legacy item shows what was typed, with no data migration needed.
     */
    private static String checklistLeadName(Task checklistTask) {
        if (!String.isBlank(checklistTask.Checklist_Lead_Name__c)) {
            return checklistTask.Checklist_Lead_Name__c;
        }
        return checklistTask.Who == null ? '' : checklistTask.Who.Name;
    }

    private static String checklistDescription(Task checklistTask) {
        return String.isBlank(checklistTask.Description)
            ? checklistTask.Subject.substring(DAILY_CHECKLIST_SUBJECT_PREFIX.length())
            : checklistTask.Description;
    }

    private static String taskPriorityValue(String priority) {
        if (priority == 'High') {
            return 'High';
        }
        if (priority == 'Low') {
            return 'Low';
        }
        return 'Normal';
    }

    private static WeeklyLeadTracker getWeeklyLeadTracker() {
        User currentUser = [
            SELECT Id, Title, Profile.Name, UserRole.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!isLoanOfficerUser(currentUser)) {
            return null;
        }

        Date today = Date.today();
        // The org uses Monday as the first day of the business week.
        Date thisWeekStart = today.toStartOfWeek().addDays(1);
        Date nextWeekStart = thisWeekStart.addDays(7);
        Date lastWeekStart = thisWeekStart.addDays(-7);
        Date rollingTwelveMonthStart = today.addMonths(-12);

        Integer thisWeek = [
            SELECT COUNT()
            FROM Lead
            WHERE OwnerId = :currentUser.Id
            AND CreatedDate >= :DateTime.newInstance(thisWeekStart, Time.newInstance(0, 0, 0, 0))
            AND CreatedDate < :DateTime.newInstance(nextWeekStart, Time.newInstance(0, 0, 0, 0))
        ];
        Integer lastWeek = [
            SELECT COUNT()
            FROM Lead
            WHERE OwnerId = :currentUser.Id
            AND CreatedDate >= :DateTime.newInstance(lastWeekStart, Time.newInstance(0, 0, 0, 0))
            AND CreatedDate < :DateTime.newInstance(thisWeekStart, Time.newInstance(0, 0, 0, 0))
        ];
        Integer rollingTwelveMonthTotal = [
            SELECT COUNT()
            FROM Lead
            WHERE OwnerId = :currentUser.Id
            AND CreatedDate >= :DateTime.newInstance(rollingTwelveMonthStart, Time.newInstance(0, 0, 0, 0))
            AND CreatedDate < :DateTime.newInstance(today.addDays(1), Time.newInstance(0, 0, 0, 0))
        ];

        return new WeeklyLeadTracker(
            lastWeek,
            thisWeek,
            Decimal.valueOf(rollingTwelveMonthTotal).divide(Decimal.valueOf(52), 1)
        );
    }

    private static List<HomeTracker> getLoanOfficerTrackers() {
        User currentUser = [
            SELECT Id, Name, FirstName, LastName, Title, Profile.Name, UserRole.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!isLoanOfficerUser(currentUser)) {
            return new List<HomeTracker>();
        }

        Map<String, Id> reportIdsByDeveloperName = reportIds(new Set<String>{
            REPORT_ACTIVE_PRE_APPROVALS,
            REPORT_HOUSE_DEALS_YTD,
            REPORT_HOUSE_DEALS_MTD,
            REPORT_PERSONAL_DEALS_YTD,
            REPORT_PERSONAL_DEALS_MTD,
            REPORT_JOSEPH_DEALS_YTD,
            REPORT_JOSEPH_DEALS_MTD
        });

        Date today = Date.today();
        Date yearStart = Date.newInstance(today.year(), 1, 1);
        Date nextYearStart = yearStart.addYears(1);
        Date monthStart = Date.newInstance(today.year(), today.month(), 1);
        Date nextMonthStart = monthStart.addMonths(1);
        String personalBizDev = 'Biz Dev - ' + currentUser.LastName;

        if (currentUser.Name == 'Joseph Carey') {
            return new List<HomeTracker>{
                buildProductionTracker(
                    'Personal Deals Closed This Month',
                    'Your funded month-to-date production.',
                    currentUser.Id,
                    monthStart,
                    nextMonthStart,
                    null,
                    false,
                    reportUrl(reportIdsByDeveloperName.get(REPORT_JOSEPH_DEALS_MTD), new List<String>{ currentUser.Name })
                ),
                buildProductionTracker(
                    'Personal Deals Closed This Year',
                    'Your funded year-to-date production.',
                    currentUser.Id,
                    yearStart,
                    nextYearStart,
                    null,
                    false,
                    reportUrl(reportIdsByDeveloperName.get(REPORT_JOSEPH_DEALS_YTD), new List<String>{ currentUser.Name })
                )
            };
        }

        return new List<HomeTracker>{
            buildPreApprovalTracker(
                currentUser.Id,
                reportUrl(reportIdsByDeveloperName.get(REPORT_ACTIVE_PRE_APPROVALS), new List<String>{ currentUser.Name })
            ),
            buildProductionTracker(
                'Closed House Deals this Year',
                'Company-sourced closings credited to you.',
                currentUser.Id,
                yearStart,
                nextYearStart,
                personalBizDev,
                true,
                reportUrl(reportIdsByDeveloperName.get(REPORT_HOUSE_DEALS_YTD), new List<String>{ currentUser.Name, personalBizDev })
            ),
            buildProductionTracker(
                'Closed House Deals this Month',
                'Company-sourced closings month to date.',
                currentUser.Id,
                monthStart,
                nextMonthStart,
                personalBizDev,
                true,
                reportUrl(reportIdsByDeveloperName.get(REPORT_HOUSE_DEALS_MTD), new List<String>{ currentUser.Name, personalBizDev })
            ),
            buildProductionTracker(
                'Personal Deals Closed This Year',
                'Your personal-sourced funded volume.',
                currentUser.Id,
                yearStart,
                nextYearStart,
                personalBizDev,
                false,
                reportUrl(reportIdsByDeveloperName.get(REPORT_PERSONAL_DEALS_YTD), new List<String>{ currentUser.Name, personalBizDev })
            ),
            buildProductionTracker(
                'Personal Deals Closed This Month',
                'Your personal-sourced funded MTD volume.',
                currentUser.Id,
                monthStart,
                nextMonthStart,
                personalBizDev,
                false,
                reportUrl(reportIdsByDeveloperName.get(REPORT_PERSONAL_DEALS_MTD), new List<String>{ currentUser.Name, personalBizDev })
            )
        };
    }

    private static HomeTracker buildPreApprovalTracker(Id userId, String reportUrl) {
        AggregateResult result = [
            SELECT COUNT(Id) unitCount, SUM(Loan_Amount__c) totalVolume
            FROM Lead
            WHERE OwnerId = :userId
            AND Status = 'Pre-Approval'
            AND Pre_Approval_Date__c >= :TRACKER_PRE_APPROVAL_START
        ];
        return new HomeTracker(
            'Active Pre-Approvals',
            'Work Done, money on the table',
            decimalValue(result.get('totalVolume')),
            integerValue(result.get('unitCount')),
            reportUrl,
            'preapproval'
        );
    }

    private static HomeTracker buildProductionTracker(
        String label,
        String helperText,
        Id userId,
        Date startDate,
        Date endDate,
        String personalBizDev,
        Boolean excludePersonalBizDev,
        String reportUrl
    ) {
        String queryText =
            'SELECT COUNT(Id) unitCount, SUM(Loan_Amount_1st__c) totalVolume ' +
            'FROM Transaction__c ' +
            'WHERE Loan_Officer__c = :userId ' +
            'AND Status__c IN :FUNDED_REVIEW_STATUSES ' +
            'AND Closing_Date__c >= :startDate ' +
            'AND Closing_Date__c < :endDate ' +
            'AND (Loan_Type_1st_TD__c = null OR Loan_Type_1st_TD__c != :DPA_SECOND_LOAN_TYPE) ';
        if (!String.isBlank(personalBizDev)) {
            queryText += excludePersonalBizDev
                ? 'AND (Biz_Dev__c = null OR Biz_Dev__c != :personalBizDev) '
                : 'AND Biz_Dev__c = :personalBizDev ';
        }
        AggregateResult result = Database.query(queryText);
        return new HomeTracker(
            label,
            helperText,
            decimalValue(result.get('totalVolume')),
            integerValue(result.get('unitCount')),
            reportUrl,
            excludePersonalBizDev ? 'house' : 'personal'
        );
    }

    private static Boolean isLoanOfficerUser(User userRecord) {
        String descriptor = (
            stringValue(userRecord.Title) + ' ' +
            (userRecord.Profile == null ? '' : stringValue(userRecord.Profile.Name)) + ' ' +
            (userRecord.UserRole == null ? '' : stringValue(userRecord.UserRole.Name))
        ).toLowerCase();
        return descriptor.contains('loan officer') || descriptor.contains('outside lo') || descriptor.contains('inside lo');
    }

    private static Map<String, Id> reportIds(Set<String> developerNames) {
        Map<String, Id> idsByDeveloperName = new Map<String, Id>();
        if (developerNames == null || developerNames.isEmpty()) {
            return idsByDeveloperName;
        }
        for (Report reportRecord : [
            SELECT Id, DeveloperName
            FROM Report
            WHERE DeveloperName IN :developerNames
        ]) {
            idsByDeveloperName.put(reportRecord.DeveloperName, reportRecord.Id);
        }
        return idsByDeveloperName;
    }

    private static String reportUrl(Id reportId, List<String> filterValues) {
        if (reportId == null) {
            return null;
        }
        String url = '/lightning/r/Report/' + reportId + '/view';
        List<String> parameters = new List<String>();
        for (Integer i = 0; filterValues != null && i < filterValues.size(); i++) {
            parameters.add('fv' + String.valueOf(i) + '=' + EncodingUtil.urlEncode(stringValue(filterValues[i]), 'UTF-8'));
        }
        return parameters.isEmpty() ? url : url + '?' + String.join(parameters, '&');
    }

    private static Integer integerValue(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Long) {
            return Integer.valueOf((Long) value);
        }
        return Integer.valueOf(String.valueOf(value));
    }

    private static Decimal decimalValue(Object value) {
        return value == null ? 0 : (Decimal) value;
    }

    private static String stringValue(String value) {
        return String.isBlank(value) ? '' : value;
    }

    private static List<HomeItem> getTasks() {
        List<HomeItem> items = new List<HomeItem>();
        for (Task taskRecord : [
            SELECT Id, Subject, ActivityDate, Status
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
            AND IsClosed = false
            ORDER BY ActivityDate ASC NULLS LAST, LastModifiedDate DESC
            LIMIT 5
        ]) {
            String subtitle = taskRecord.ActivityDate == null ? taskRecord.Status : String.valueOf(taskRecord.ActivityDate);
            items.add(new HomeItem(taskRecord.Id, taskRecord.Subject, subtitle, 'Task'));
        }
        return items;
    }

    private static List<HomeItem> getEvents() {
        List<HomeItem> items = new List<HomeItem>();
        for (Event eventRecord : [
            SELECT Id, Subject, StartDateTime
            FROM Event
            WHERE OwnerId = :UserInfo.getUserId()
            AND StartDateTime >= TODAY
            ORDER BY StartDateTime ASC
            LIMIT 5
        ]) {
            items.add(new HomeItem(eventRecord.Id, eventRecord.Subject, String.valueOf(eventRecord.StartDateTime), 'Event'));
        }
        return items;
    }

    private static List<HomeItem> getRecentRecords() {
        List<HomeItem> items = new List<HomeItem>();
        for (RecentlyViewed viewedRecord : [
            SELECT Id, Name, Type, LastViewedDate
            FROM RecentlyViewed
            ORDER BY LastViewedDate DESC NULLS LAST
            LIMIT 8
        ]) {
            items.add(new HomeItem(viewedRecord.Id, viewedRecord.Name, viewedRecord.Type, viewedRecord.Type));
        }
        return items;
    }

    public class HomeToolsData {
        @AuraEnabled public List<HomeItem> events;
        @AuraEnabled public List<HomeItem> recentRecords;
        @AuraEnabled public List<HomeTracker> trackers;
        @AuraEnabled public WeeklyLeadTracker weeklyLeadTracker;
        @AuraEnabled public Boolean isLoanPartnerChecklistUser;
        @AuraEnabled public List<DailyChecklistItem> dailyChecklistItems;
        @AuraEnabled public Boolean isRunningTodoUser;
        @AuraEnabled public List<RunningTodoItem> runningTodoItems;
    }

    public class RunningTodoItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String description;
        @AuraEnabled public String priority;
        @AuraEnabled public String addedText;

        public RunningTodoItem(Id id, String description, String priority, String addedText) {
            this.id = id;
            this.description = description;
            this.priority = priority;
            this.addedText = addedText;
        }
    }

    public class CompletedRunningTodoItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String description;
        @AuraEnabled public String priority;
        @AuraEnabled public String completedAtText;

        public CompletedRunningTodoItem(Id id, String description, String priority, String completedAtText) {
            this.id = id;
            this.description = description;
            this.priority = priority;
            this.completedAtText = completedAtText;
        }
    }

    public class DailyChecklistItem {
        @AuraEnabled public Id id;
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String description;
        @AuraEnabled public String priority;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Boolean isPastDue;

        public DailyChecklistItem(
            Id id,
            Id leadId,
            String leadName,
            String description,
            String priority,
            Date dueDate,
            Boolean isPastDue
        ) {
            this.id = id;
            this.leadId = leadId;
            this.leadName = leadName;
            this.description = description;
            this.priority = priority;
            this.dueDate = dueDate;
            this.isPastDue = isPastDue;
        }
    }

    public class ChecklistOrderItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String priority { get; set; }
    }

    public class WeeklyLeadTracker {
        @AuraEnabled public Integer lastWeek;
        @AuraEnabled public Integer thisWeek;
        @AuraEnabled public Decimal rollingTwelveMonthWeeklyAverage;

        public WeeklyLeadTracker(Integer lastWeek, Integer thisWeek, Decimal rollingTwelveMonthWeeklyAverage) {
            this.lastWeek = lastWeek == null ? 0 : lastWeek;
            this.thisWeek = thisWeek == null ? 0 : thisWeek;
            this.rollingTwelveMonthWeeklyAverage = rollingTwelveMonthWeeklyAverage == null ? 0 : rollingTwelveMonthWeeklyAverage;
        }
    }

    public class ClearedDailyChecklistItem {
        @AuraEnabled public Id id;
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String description;
        @AuraEnabled public String priority;
        @AuraEnabled public String clearedAtText;

        public ClearedDailyChecklistItem(Id id, Id leadId, String leadName, String description, String priority, String clearedAtText) {
            this.id = id;
            this.leadId = leadId;
            this.leadName = leadName;
            this.description = description;
            this.priority = priority;
            this.clearedAtText = clearedAtText;
        }
    }

    public class HomeItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String objectApiName;

        public HomeItem(Id id, String title, String subtitle, String objectApiName) {
            this.id = id;
            this.title = title;
            this.subtitle = subtitle;
            this.objectApiName = objectApiName;
        }
    }

    public class HomeTracker {
        @AuraEnabled public String label;
        @AuraEnabled public String helperText;
        @AuraEnabled public Decimal volume;
        @AuraEnabled public Integer units;
        @AuraEnabled public String reportUrl;
        @AuraEnabled public String variant;

        public HomeTracker(String label, String helperText, Decimal volume, Integer units, String reportUrl, String variant) {
            this.label = label;
            this.helperText = helperText;
            this.volume = volume == null ? 0 : volume;
            this.units = units == null ? 0 : units;
            this.reportUrl = reportUrl;
            this.variant = variant;
        }
    }
}