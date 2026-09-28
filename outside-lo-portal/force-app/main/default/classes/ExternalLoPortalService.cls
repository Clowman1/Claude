public with sharing class ExternalLoPortalService {

    public static List<LeadRow> getLeads(String filterKey, String searchTerm) {
        Id userId = UserInfo.getUserId();
        LeadRepository leadRepository = LeadRepository.getInstance();
        List<Lead> leads = leadRepository.selectPortalLeadsByOwner(userId);
        String term = normalizeSearch(searchTerm);
        List<LeadRow> rows = new List<LeadRow>();
        for (Lead leadRecord : leads) {
            LeadRow row = mapLead(leadRecord);
            if (!matchesLeadFilter(row, filterKey)) {
                continue;
            }
            if (!matchesSearch(term, row.name, row.idLabel, row.source)) {
                continue;
            }
            rows.add(row);
        }
        return rows;
    }

    public static LeadDetail getLeadDetail(Id leadId) {
        LeadRepository leadRepository = LeadRepository.getInstance();
        TaskRepository taskRepository = new TaskRepository();
        Id userId = UserInfo.getUserId();
        Lead leadRecord = leadRepository.selectPortalLeadDetail(leadId, userId);
        if (leadRecord == null) {
            throw new DomainException('Lead could not be found or is not visible.');
        }

        LeadDetail detail = new LeadDetail();
        detail.summary = mapLead(leadRecord);
        detail.scenarioFields = buildLeadScenarioFields(leadRecord);
        detail.scenarioNotes = leadRecord.Description;
        detail.ariveUrl = buildAriveLoanUrl(leadRecord.AriveId__c);
        detail.activityEntries = mapActivities(
            taskRepository.selectCompletedActivitiesForRecord(leadId, userId, 50)
        );
        detail.openTasks = mapOpenTasks(taskRepository.selectOpenTasksForLead(leadId, userId));
        return detail;
    }

    public static List<LeadRow> findLeadDuplicates(String name, String phone, String email) {
        return mapLeadRows(
            LeadRepository.getInstance().selectDuplicateLeads(
                UserInfo.getUserId(),
                name,
                normalizePhone(phone),
                email
            )
        );
    }

    public static List<PartnerRow> getRealtors(String filterKey, String searchTerm) {
        Id userId = UserInfo.getUserId();
        PersonAccountRepository repository = new PersonAccountRepository();
        TaskRepository taskRepository = new TaskRepository();
        List<Account> partners = repository.selectPortalPartnersForUser(userId);
        Map<Id, Datetime> lastTouchByAccountId = taskRepository.selectLastActivityDatetimeByWhatIds(
            new Map<Id, Account>(partners).keySet(),
            userId
        );
        Map<Id, Integer> sharedBuyersByPartnerId = countSharedBuyers(
            new Map<Id, Account>(partners).keySet(),
            userId
        );
        String term = normalizeSearch(searchTerm);
        List<PartnerRow> rows = new List<PartnerRow>();
        for (Account accountRecord : partners) {
            PartnerRow row = mapPartner(accountRecord, userId, lastTouchByAccountId);
            row.sharedBuyers = sharedBuyersByPartnerId.get(accountRecord.Id) ?? 0;
            if (!matchesPartnerFilter(row, filterKey)) {
                continue;
            }
            if (!matchesSearch(term, row.name, row.company, row.market)) {
                continue;
            }
            rows.add(row);
        }
        return rows;
    }

    private static Map<Id, Integer> countSharedBuyers(Set<Id> partnerIds, Id userId) {
        Map<Id, Integer> countsByPartnerId = new Map<Id, Integer>();
        if (partnerIds.isEmpty()) {
            return countsByPartnerId;
        }
        for (AggregateResult result : [
            SELECT Realtor_Buying_Agent__c partnerId, COUNT(Id) buyerCount
            FROM Lead
            WHERE OwnerId = :userId
              AND IsConverted = false
              AND Realtor_Buying_Agent__c IN :partnerIds
            WITH USER_MODE
            GROUP BY Realtor_Buying_Agent__c
        ]) {
            countsByPartnerId.put((Id) result.get('partnerId'), (Integer) result.get('buyerCount'));
        }
        return countsByPartnerId;
    }

    public static PartnerDetail getPartnerDetail(Id accountId) {
        Id userId = UserInfo.getUserId();
        PersonAccountRepository repository = new PersonAccountRepository();
        TaskRepository taskRepository = new TaskRepository();
        Account accountRecord = repository.selectPortalPartnerDetail(accountId, userId);
        if (accountRecord == null) {
            throw new DomainException('Partner could not be found.');
        }
        Map<Id, Datetime> lastTouch = taskRepository.selectLastActivityDatetimeByWhatIds(
            new Set<Id>{ accountId },
            userId
        );
        PartnerDetail detail = new PartnerDetail();
        detail.summary = mapPartner(accountRecord, userId, lastTouch);
        detail.activityEntries = mapActivities(
            taskRepository.selectCompletedActivitiesForRecord(accountId, userId, 50)
        );
        detail.relatedLeads = getLeadsForPartner(accountId);
        detail.summary.sharedBuyers = detail.relatedLeads.size();
        return detail;
    }

    private static List<LeadRow> getLeadsForPartner(Id accountId) {
        return mapLeadRows(
            LeadRepository.getInstance().selectPortalLeadsByPartner(UserInfo.getUserId(), accountId)
        );
    }

    public static List<PreApprovalRow> getPreApprovals(String filterKey, String searchTerm) {
        Id userId = UserInfo.getUserId();
        String term = normalizeSearch(searchTerm);
        List<PreApprovalRow> rows = new List<PreApprovalRow>();
        for (Lead leadRecord : LeadRepository.getInstance().selectPortalPreApprovalsByOwner(userId)) {
            PreApprovalRow row = mapPreApproval(leadRecord);
            if (!matchesPreApprovalFilter(row, filterKey)) {
                continue;
            }
            if (!matchesSearch(term, row.borrower, row.idLabel, row.realtorLabel)) {
                continue;
            }
            rows.add(row);
        }
        return rows;
    }

    public static NavBadges getNavBadges() {
        NavBadges badges = new NavBadges();
        badges.newLeads = getLeads('new', null).size();
        badges.dueRealtors = getRealtors('due', null).size();
        badges.preApprovals = getPreApprovals('all', null).size();
        badges.loansInProcess = getLoans('all', null).size();
        return badges;
    }

    public static List<LeadRow> getPastClients(String searchTerm) {
        Id userId = UserInfo.getUserId();
        String term = normalizeSearch(searchTerm);
        List<LeadRow> rows = new List<LeadRow>();
        for (Lead leadRecord : LeadRepository.getInstance().selectPastClientLeadsByOwner(userId)) {
            LeadRow row = mapLead(leadRecord);
            if (!matchesSearch(term, row.name, row.idLabel, row.source)) {
                continue;
            }
            rows.add(row);
        }
        return rows;
    }

    public static List<LoanRow> getLoans(String filterKey, String searchTerm) {
        Id userId = UserInfo.getUserId();
        String term = normalizeSearch(searchTerm);
        List<LoanRow> rows = new List<LoanRow>();
        for (Transaction__c loanRecord : LoanRepository.getInstance().selectPortalLoansByUser(userId)) {
            LoanRow row = mapLoan(loanRecord);
            if (!matchesLoanFilter(row, filterKey, loanRecord)) {
                continue;
            }
            if (!matchesSearch(term, row.borrower, row.idLabel, row.realtorLabel)) {
                continue;
            }
            rows.add(row);
        }
        return rows;
    }

    public static LoanDetail getLoanDetail(Id loanId) {
        Transaction__c loanRecord = LoanRepository.getInstance().selectPortalLoanDetail(
            loanId,
            UserInfo.getUserId()
        );
        if (loanRecord == null) {
            throw new DomainException('Loan could not be found or is not visible.');
        }
        LoanDetail detail = new LoanDetail();
        detail.summary = mapLoan(loanRecord);
        detail.loanDetails = buildLoanDetails(loanRecord);
        return detail;
    }

    public static RecordSetPayload getRecordSet(String recordSetKey) {
        RecordSetPayload payload = new RecordSetPayload();
        payload.records = new List<RecordSetItem>();

        if (recordSetKey == 'new-leads') {
            payload.title = 'New leads need contact';
            payload.subtitle = 'Purchase and refinance inquiries assigned to you';
            for (LeadRow row : getLeads('new', null)) {
                payload.records.add(toRecordSetItem(row.id, row.name, row.primary, row.secondary, row.tag, row.urgency, 'Lead'));
            }
            return payload;
        }

        if (recordSetKey == 'overdue-tasks') {
            payload.title = 'Overdue tasks need resolution';
            payload.subtitle = 'Past-due activities assigned to you';
            List<Task> overdueTaskRecords = new TaskRepository().selectOpenOverdueByOwner(UserInfo.getUserId());
            Map<Id, String> relatedNames = resolveTaskRelatedNames(overdueTaskRecords);
            for (Task taskRecord : overdueTaskRecords) {
                payload.records.add(toTaskRecordSetItem(taskRecord, 'Overdue', 'urgent', relatedNames));
            }
            return payload;
        }

        if (recordSetKey == 'realtor-follow-ups') {
            payload.title = 'Realtor follow-ups are due';
            payload.subtitle = 'Partner touches scheduled or overdue';
            for (PartnerRow row : getRealtors('due', null)) {
                payload.records.add(toRecordSetItem(
                    row.id,
                    row.name,
                    row.company,
                    row.lastTouchLabel,
                    row.followUpDue ? 'Due' : 'Scheduled',
                    row.followUpDue ? 'urgent' : 'attention',
                    'Account'
                ));
            }
            return payload;
        }

        if (recordSetKey == 'pre-approvals') {
            payload.title = 'Pre-approvals need review';
            payload.subtitle = 'Borrower files waiting on your review';
            for (PreApprovalRow row : getPreApprovals('all', null)) {
                payload.records.add(toRecordSetItem(
                    row.id,
                    row.borrower,
                    row.amount,
                    row.expiresLabel,
                    row.statusKey,
                    row.statusKey == 'expiring' ? 'urgent' : 'attention',
                    'Lead'
                ));
            }
            return payload;
        }

        if (recordSetKey == 'milestone-loans') {
            payload.title = 'Loans require milestone updates';
            payload.subtitle = 'Borrowers and partners waiting on status changes';
            for (LoanRow row : getLoans('update', null)) {
                payload.records.add(toRecordSetItem(
                    row.id,
                    row.borrower,
                    row.amount,
                    row.milestone,
                    'Needs update',
                    row.needsUpdate ? 'attention' : 'normal',
                    'Transaction__c'
                ));
            }
            return payload;
        }

        if (recordSetKey == 'completed-today') {
            payload.title = 'Today\'s completed activities';
            payload.subtitle = 'Activities logged toward your Perfect Day score';
            addCompletedTasks(payload, Date.today(), Date.today(), null);
            return payload;
        }

        if (recordSetKey == 'activities-remaining') {
            payload.title = 'Activities remaining today';
            payload.subtitle = 'Open tasks scheduled before 5:00 PM';
            List<Task> openTaskRecords = new TaskRepository().selectOpenTasksDueByOwner(
                UserInfo.getUserId(),
                Date.today()
            );
            Map<Id, String> relatedNames = resolveTaskRelatedNames(openTaskRecords);
            for (Task taskRecord : openTaskRecords) {
                String tag = 'Open';
                String urgency = 'attention';
                if (taskRecord.ActivityDate != null && taskRecord.ActivityDate < Date.today()) {
                    tag = 'Overdue';
                    urgency = 'urgent';
                }
                payload.records.add(toTaskRecordSetItem(taskRecord, tag, urgency, relatedNames));
            }
            return payload;
        }

        if (recordSetKey != null && recordSetKey.startsWith('goal-')) {
            return buildGoalRecordSet(recordSetKey);
        }

        payload.title = 'Records';
        payload.subtitle = 'Open the full list to continue working.';
        return payload;
    }

    public static PartnerRow mapPartner(
        Account accountRecord,
        Id userId,
        Map<Id, Datetime> lastTouchByAccountId
    ) {
        Datetime lastTouch = lastTouchByAccountId?.get(accountRecord.Id);
        Integer daysSince = lastTouch == null ? null : lastTouch.date().daysBetween(Date.today());
        PartnerRow row = new PartnerRow();
        row.id = accountRecord.Id;
        row.name = accountRecord.Name;
        row.company = accountRecord.Company__c;
        row.market = accountRecord.BillingCity;
        row.partnerType = mapPartnerTypeLabel(accountRecord.Group__pc);
        row.phone = accountRecord.Phone;
        row.email = accountRecord.PersonEmail;
        row.daysSinceMyTouch = daysSince;
        row.lastTouchLabel = lastTouch == null ? null : 'Last touch ' + daysSince + ' days ago';
        row.houseLocked = isHouseLocked(accountRecord, userId);
        row.followUpDue = daysSince != null && daysSince >= ExternalLOBaselineHelper.REALTOR_FOLLOW_UP_ORANGE_DAYS;
        return row;
    }

    public static Boolean isHouseLocked(Account accountRecord, Id userId) {
        if (accountRecord == null || userId == null) {
            return false;
        }
        Boolean ownedByUser = accountRecord.OwnerId == userId
            || accountRecord.Follow_Up_LO__c == userId
            || accountRecord.Preferred_LO__c == userId;
        if (ownedByUser) {
            return false;
        }
        return accountRecord.Biz_Dev_Designation__c == 'Biz Dev - Reach'
            || accountRecord.Biz_Dev_Designation__c == 'Biz Dev - Bondarevsky';
    }

    private static String buildAriveLoanUrl(String ariveId) {
        String baseUrl = ExternalLOBaselineHelper.ariveBaseUrl();
        if (String.isBlank(ariveId) || baseUrl == null) {
            // No configured tenant → the lead detail shows its "not linked"
            // state instead of a link to a wrong host.
            return null;
        }
        return baseUrl + '/app/loans/' + EncodingUtil.urlEncode(ariveId, 'UTF-8') + '/loan-info';
    }

    private static LeadRow mapLead(Lead leadRecord) {
        LeadRow row = new LeadRow();
        row.id = leadRecord.Id;
        row.name = leadRecord.Name;
        row.status = deriveLeadStage(leadRecord);
        row.statusLabel = String.isBlank(leadRecord.Status) ? row.status : leadRecord.Status;
        row.phone = leadRecord.Phone ?? leadRecord.MobilePhone;
        row.email = leadRecord.Email;
        row.source = leadRecord.LeadSource;
        row.purpose = leadRecord.Loan_Purpose__c;
        row.amount = formatCurrency(leadRecord.Loan_Amount__c);
        row.program = leadRecord.Loan_Program__c;
        row.market = joinLocation(leadRecord.City, leadRecord.State);
        row.primary = joinNonBlank(new List<String>{ row.purpose, row.amount, row.program }, ' · ');
        row.secondary = joinNonBlank(new List<String>{ row.source, row.market }, ' · ');
        row.idLabel = leadRecord.Id;
        row.assignedLabel = 'Assigned ' + leadRecord.CreatedDate.format('MMM d, yyyy h:mm a');
        row.lastContactLabel = leadRecord.LastActivityDate == null
            ? null
            : 'Last activity ' + leadRecord.LastActivityDate.format();
        row.urgency = row.status == 'new' && leadRecord.LastActivityDate == null
            ? 'urgent'
            : 'normal';
        row.tag = row.lastContactLabel == null ? 'Never contacted' : 'Working';
        return row;
    }

    private static PreApprovalRow mapPreApproval(Lead leadRecord) {
        PreApprovalRow row = new PreApprovalRow();
        row.id = leadRecord.Id;
        row.borrower = leadRecord.Name;
        row.idLabel = leadRecord.Id;
        row.amount = formatCurrency(leadRecord.Loan_Amount__c);
        row.program = leadRecord.Loan_Program__c;
        row.credit = leadRecord.App_Summary_Credit__c;
        row.realtorLabel = leadRecord.Realtor_Buying_Agent__r?.Name;
        row.statusKey = derivePreApprovalStatus(leadRecord);
        row.expiresLabel = leadRecord.Credit_Expiration_Date__c == null
            ? 'Expiration unknown'
            : 'Expires ' + leadRecord.Credit_Expiration_Date__c.format();
        row.lastTouchLabel = leadRecord.LastActivityDate == null
            ? 'No recent touch'
            : 'Last touch ' + leadRecord.LastActivityDate.format();
        row.weeklyTouchDone = leadRecord.LastActivityDate != null
            && leadRecord.LastActivityDate.daysBetween(Date.today()) <= 7;
        return row;
    }

    private static LoanRow mapLoan(Transaction__c loanRecord) {
        LoanRow row = new LoanRow();
        row.id = loanRecord.Id;
        row.borrower = loanRecord.Borrower_Name__r?.Name ?? loanRecord.Borrower_Name__c;
        row.idLabel = loanRecord.Name;
        row.amount = formatCurrency(loanRecord.Loan_Amount__c);
        row.program = loanRecord.Loan_Program_1st__c;
        row.milestone = loanRecord.Status__c;
        row.closingLabel = loanRecord.Closing_Date__c == null
            ? 'Closing TBD'
            : 'Closing ' + loanRecord.Closing_Date__c.format();
        row.processor = loanRecord.Processor__r?.Name;
        row.needsUpdate = ExternalLOBaselineHelper.loanMilestoneUrgency(loanRecord) != '';
        return row;
    }

    private static List<LoanDetailField> buildLeadScenarioFields(Lead leadRecord) {
        List<LoanDetailField> fields = new List<LoanDetailField>();
        addLeadScenarioField(fields, 'Loan purpose', leadRecord.Loan_Purpose__c);
        addLeadScenarioField(fields, 'Loan program', leadRecord.Loan_Program__c);
        addLeadScenarioField(fields, 'Requested amount', formatCurrency(leadRecord.Loan_Amount__c));
        addLeadScenarioField(fields, 'Down payment', formatDownPaymentLabel(leadRecord));
        addLeadScenarioField(fields, 'Estimated payment', formatCurrency(leadRecord.Estimated_Monthly_Payment__c));
        addLeadScenarioField(fields, 'Property type', leadRecord.Property_Type__c);
        addLeadScenarioField(fields, 'Buying timeline', leadRecord.Rating);
        addLeadScenarioField(fields, 'Location', joinLocation(leadRecord.City, leadRecord.State));
        addLeadScenarioField(fields, 'Purchase price', formatCurrency(leadRecord.Purchase_Price__c));
        addLeadScenarioField(fields, 'Realtor partner', leadRecord.Realtor_Buying_Agent__r?.Name);
        return fields;
    }

    private static void addLeadScenarioField(List<LoanDetailField> fields, String label, String value) {
        if (String.isNotBlank(value)) {
            fields.add(new LoanDetailField(label, value));
        }
    }

    private static String formatDownPaymentLabel(Lead leadRecord) {
        return joinNonBlank(
            new List<String>{
                formatCurrency(leadRecord.Down_Payment_Amount__c),
                leadRecord.Down_Payment_Percentage__c == null
                    ? null
                    : String.valueOf(leadRecord.Down_Payment_Percentage__c) + '%'
            },
            ' · '
        );
    }

    private static List<LoanDetailField> buildLoanDetails(Transaction__c loanRecord) {
        List<LoanDetailField> fields = new List<LoanDetailField>();
        fields.add(new LoanDetailField('Current milestone', loanRecord.Status__c));
        fields.add(new LoanDetailField(
            'Status since',
            loanRecord.Current_Status_Since__c?.format() ?? '—'
        ));
        fields.add(new LoanDetailField(
            'Closing date',
            loanRecord.Closing_Date__c?.format() ?? 'TBD'
        ));
        fields.add(new LoanDetailField('Processor', loanRecord.Processor__r?.Name ?? '—'));
        fields.add(new LoanDetailField('Loan amount', formatCurrency(loanRecord.Loan_Amount__c)));
        fields.add(new LoanDetailField('Purchase price', formatCurrency(loanRecord.Purchase_Price__c)));
        fields.add(new LoanDetailField('Rate', loanRecord.Interest_Rate__c == null ? '—' : String.valueOf(loanRecord.Interest_Rate__c) + '%'));
        fields.add(new LoanDetailField('LTV / DTI', joinNonBlank(new List<String>{
            loanRecord.LTV__c == null ? null : String.valueOf(loanRecord.LTV__c) + '%',
            loanRecord.DTI_Back_End__c == null ? null : String.valueOf(loanRecord.DTI_Back_End__c) + '%'
        }, ' / ')));
        fields.add(new LoanDetailField('Property', loanRecord.Property_Address__c));
        fields.add(new LoanDetailField('Lock expires', loanRecord.Lock_Exp_Date_1st_TD__c?.format()));
        return fields;
    }

    private static List<LeadRow> mapLeadRows(List<Lead> leads) {
        List<LeadRow> rows = new List<LeadRow>();
        for (Lead leadRecord : leads) {
            rows.add(mapLead(leadRecord));
        }
        return rows;
    }

    private static List<ActivityEntry> mapActivities(List<Task> tasks) {
        List<ActivityEntry> entries = new List<ActivityEntry>();
        for (Task taskRecord : tasks) {
            ActivityEntry entry = new ActivityEntry();
            entry.id = taskRecord.Id;
            entry.channel = mapChannel(taskRecord.Activity_Type__c);
            entry.outcome = taskRecord.Subject;
            entry.note = taskRecord.Description;
            entry.timestamp = taskRecord.ActivityDate?.format();
            entry.author = taskRecord.Owner?.Name;
            entries.add(entry);
        }
        return entries;
    }

    private static List<OpenTaskRow> mapOpenTasks(List<Task> tasks) {
        List<OpenTaskRow> rows = new List<OpenTaskRow>();
        for (Task taskRecord : tasks) {
            OpenTaskRow row = new OpenTaskRow();
            row.id = taskRecord.Id;
            row.label = taskRecord.Subject;
            row.due = taskRecord.ActivityDate == null ? 'No due date' : 'Due ' + taskRecord.ActivityDate.format();
            row.urgent = taskRecord.ActivityDate != null && taskRecord.ActivityDate < Date.today();
            rows.add(row);
        }
        return rows;
    }

    private static RecordSetPayload buildGoalRecordSet(String recordSetKey) {
        RecordSetPayload payload = new RecordSetPayload();
        payload.records = new List<RecordSetItem>();

        List<String> parts = recordSetKey.split('-');
        if (parts.size() < 3) {
            payload.title = 'Goal activities';
            payload.subtitle = 'Completed activities for this goal';
            return payload;
        }

        String periodKey = parts[1];
        String goalKey = parts[2];
        Date today = Date.today();
        Date startDate = today;
        Date endDate = today;
        String periodLabel = 'today';

        if (periodKey == 'week') {
            startDate = ExternalLoGoalMath.weekStartMonday(today);
            endDate = ExternalLoGoalMath.weekEndSunday(today);
            periodLabel = 'this week';
        } else if (periodKey == 'month') {
            startDate = today.toStartOfMonth();
            endDate = startDate.addMonths(1).addDays(-1);
            periodLabel = 'this month';
        }

        payload.title = goalLabel(goalKey) + ' — ' + periodLabel;
        payload.subtitle = 'Completed activities contributing to this goal';
        addCompletedTasks(payload, startDate, endDate, goalKey);
        return payload;
    }

    private static String goalLabel(String goalKey) {
        ExternalLoActivityCatalog.ActivityDefinition activity = ExternalLoActivityCatalog.activityByKey(goalKey);
        if (activity != null && !String.isBlank(activity.shortLabel)) {
            return activity.shortLabel;
        }
        switch on goalKey {
            when 'calls' { return 'Calls'; }
            when 'texts' { return 'Texts'; }
            when 'emails' { return 'Emails'; }
            when 'meetings' { return 'Meetings'; }
            when 'openHouses' { return 'Open houses'; }
            when else { return 'Goal'; }
        }
    }

    private static void addCompletedTasks(
        RecordSetPayload payload,
        Date startDate,
        Date endDate,
        String goalKey
    ) {
        List<Task> taskRecords = new TaskRepository().selectCompletedActivitiesByOwnerForDateRange(
            UserInfo.getUserId(),
            startDate,
            endDate
        );
        for (Task taskRecord : taskRecords) {
            if (goalKey != null && !matchesGoal(goalKey, taskRecord)) {
                continue;
            }
            payload.records.add(toRecordSetItem(
                taskRecord.Id,
                taskRecord.Subject,
                taskRecord.Activity_Type__c,
                taskRecord.ActivityDate == null
                    ? 'Completed today'
                    : 'Completed ' + taskRecord.ActivityDate.format(),
                'Logged',
                'normal',
                'Task'
            ));
        }
    }

    private static RecordSetItem toTaskRecordSetItem(
        Task taskRecord,
        String tag,
        String urgency,
        Map<Id, String> relatedNames
    ) {
        return toRecordSetItem(
            taskRecord.Id,
            taskRecord.Subject,
            formatTaskDueLabel(taskRecord),
            formatTaskRelatedLabel(taskRecord, relatedNames),
            tag,
            urgency,
            'Task'
        );
    }

    private static Map<Id, String> resolveTaskRelatedNames(List<Task> taskRecords) {
        return ExternalLoActivityNameResolver.resolveTaskRelatedNames(taskRecords);
    }

    private static String formatTaskDueLabel(Task taskRecord) {
        if (taskRecord.ActivityDate == null) {
            return 'No due date';
        }
        return 'Due ' + taskRecord.ActivityDate.format();
    }

    private static String formatTaskRelatedLabel(Task taskRecord, Map<Id, String> relatedNames) {
        if (taskRecord.WhoId != null && relatedNames?.containsKey(taskRecord.WhoId)) {
            return 'Related to ' + relatedNames.get(taskRecord.WhoId);
        }
        if (taskRecord.WhatId != null && relatedNames?.containsKey(taskRecord.WhatId)) {
            return 'Related to ' + relatedNames.get(taskRecord.WhatId);
        }
        if (String.isNotBlank(taskRecord.Activity_Type__c)) {
            return taskRecord.Activity_Type__c;
        }
        if (String.isNotBlank(taskRecord.Priority)) {
            return 'Priority: ' + taskRecord.Priority;
        }
        return null;
    }

    private static Boolean matchesGoal(String goalKey, Task taskRecord) {
        ExternalLoActivityCatalog.ActivityDefinition activity = ExternalLoActivityCatalog.activityByKey(goalKey);
        if (activity != null) {
            if (taskRecord.Activity_Category__c == activity.categoryApiName) {
                return true;
            }
            return activity.creditActivityTypes != null
                && activity.creditActivityTypes.contains(taskRecord.Activity_Type__c);
        }
        return matchesGoalActivityType(goalKey, taskRecord.Activity_Type__c);
    }

    private static Boolean matchesGoalActivityType(String goalKey, String activityType) {
        if (String.isBlank(goalKey) || String.isBlank(activityType)) {
            return false;
        }
        switch on goalKey {
            when 'calls' {
                return activityType == 'Call - Prospecting' || activityType == 'Call - Active Agent';
            }
            when 'texts' {
                return activityType == 'Text';
            }
            when 'emails' {
                return activityType == 'Email';
            }
            when 'meetings' {
                return activityType == 'Meeting (New Agent)' || activityType == 'Meeting (Active Agent)';
            }
            when 'openHouses' {
                return activityType == 'Open House';
            }
            when else {
                return false;
            }
        }
    }

    private static RecordSetItem toRecordSetItem(
        Id recordId,
        String name,
        String primary,
        String secondary,
        String tag,
        String urgency,
        String objectApiName
    ) {
        RecordSetItem item = new RecordSetItem();
        item.id = recordId;
        item.name = name;
        item.primary = primary;
        item.secondary = secondary;
        item.tag = tag;
        item.urgency = urgency;
        item.objectApiName = objectApiName;
        return item;
    }

    private static String mapChannel(String activityType) {
        if (activityType == 'Text') {
            return 'text';
        }
        if (activityType == 'Email') {
            return 'email';
        }
        if (activityType != null && activityType.contains('Meeting')) {
            return 'in-person';
        }
        return 'call';
    }

    private static String mapPartnerTypeLabel(String groupValue) {
        if (groupValue == 'Title Agent') {
            return 'Title';
        }
        if (groupValue == 'Insurance Agent') {
            return 'Insurance';
        }
        if (groupValue == 'Realtor Prospect') {
            return 'Realtor Prospect';
        }
        return 'Realtor';
    }

    private static String derivePreApprovalStatus(Lead leadRecord) {
        Datetime sixDaysAgo = System.now().addDays(-ExternalLOBaselineHelper.PRE_APPROVAL_STAGNANT_DAYS);
        String urgency = ExternalLOBaselineHelper.preApprovalReviewUrgency(leadRecord, sixDaysAgo);
        if (urgency == 'red') {
            return 'expiring';
        }
        if (urgency == 'orange') {
            return 'docs-outstanding';
        }
        return 'ready-to-review';
    }

    private static String deriveLeadStage(Lead leadRecord) {
        String status = leadRecord?.Status;
        if (status == 'New') {
            return 'new';
        }
        if (status == 'Pre-Approval') {
            return 'pre-approval';
        }
        if (status == 'Working' || status == 'Contacted' || status == 'Qualified') {
            return 'working';
        }
        if (status == 'Unqualified' || status == 'Closed' || status == 'Closed - Not Converted') {
            return 'closed';
        }
        if (leadRecord != null && leadRecord.LeadSource == 'Past Client') {
            return 'past-client';
        }
        if (String.isBlank(status)) {
            return 'nurture';
        }
        return status.trim().toLowerCase().replaceAll('[^a-z0-9]+', '-');
    }

    private static Boolean matchesLeadFilter(LeadRow row, String filterKey) {
        if (String.isBlank(filterKey) || filterKey == 'all') {
            return true;
        }
        if (filterKey == 'uncontacted') {
            return row.lastContactLabel == null;
        }
        if (filterKey == 'working') {
            return row.status == 'working' || row.status == 'pre-approval';
        }
        if (filterKey == 'nurture') {
            return row.status == 'nurture' || row.status == 'past-client';
        }
        return row.status == filterKey;
    }

    private static Boolean matchesPartnerFilter(PartnerRow row, String filterKey) {
        if (filterKey == 'prospects') {
            return row.partnerType == 'Realtor Prospect';
        }
        if (row.partnerType == 'Realtor Prospect') {
            return false;
        }
        if (String.isBlank(filterKey) || filterKey == 'all') {
            return true;
        }
        if (filterKey == 'due') {
            return row.followUpDue;
        }
        if (row.daysSinceMyTouch == null) {
            return false;
        }
        return row.daysSinceMyTouch <= Integer.valueOf(filterKey);
    }

    private static Boolean matchesPreApprovalFilter(PreApprovalRow row, String filterKey) {
        if (String.isBlank(filterKey) || filterKey == 'all') {
            return true;
        }
        if (filterKey == 'weekly-touch') {
            return !row.weeklyTouchDone;
        }
        return row.statusKey == filterKey;
    }

    private static Boolean matchesLoanFilter(LoanRow row, String filterKey, Transaction__c loanRecord) {
        if (String.isBlank(filterKey) || filterKey == 'all') {
            return true;
        }
        if (filterKey == 'update') {
            return row.needsUpdate;
        }
        if (filterKey == 'ctc') {
            return row.milestone == 'Clear to Close';
        }
        return row.milestone == 'Processing' || row.milestone == 'Underwriting' || row.milestone == 'Submitted';
    }

    private static Boolean matchesSearch(String term, String v1, String v2, String v3) {
        if (String.isBlank(term)) {
            return true;
        }
        String haystack = ((v1 ?? '') + ' ' + (v2 ?? '') + ' ' + (v3 ?? '')).toLowerCase();
        return haystack.contains(term);
    }

    private static String normalizeSearch(String searchTerm) {
        return String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
    }

    private static String normalizePhone(String phone) {
        return String.isBlank(phone) ? null : phone.replaceAll('[^0-9]', '');
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) {
            return '—';
        }
        return '$' + amount.setScale(0).format();
    }

    private static String joinLocation(String city, String state) {
        return joinNonBlank(new List<String>{ city, state }, ', ');
    }

    private static String joinNonBlank(List<String> values, String delimiter) {
        List<String> cleaned = new List<String>();
        for (String value : values) {
            if (String.isNotBlank(value)) {
                cleaned.add(value);
            }
        }
        return cleaned.isEmpty() ? '—' : String.join(cleaned, delimiter);
    }

    public class LeadRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String source;
        @AuraEnabled public String purpose;
        @AuraEnabled public String amount;
        @AuraEnabled public String program;
        @AuraEnabled public String market;
        @AuraEnabled public String primary;
        @AuraEnabled public String secondary;
        @AuraEnabled public String idLabel;
        @AuraEnabled public String assignedLabel;
        @AuraEnabled public String lastContactLabel;
        @AuraEnabled public String tag;
        @AuraEnabled public String urgency;
    }

    public class LeadDetail {
        @AuraEnabled public LeadRow summary;
        @AuraEnabled public List<LoanDetailField> scenarioFields;
        @AuraEnabled public String scenarioNotes;
        @AuraEnabled public String ariveUrl;
        @AuraEnabled public List<ActivityEntry> activityEntries;
        @AuraEnabled public List<OpenTaskRow> openTasks;
    }

    public class PartnerRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String market;
        @AuraEnabled public String partnerType;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public Integer daysSinceMyTouch;
        @AuraEnabled public String lastTouchLabel;
        @AuraEnabled public Boolean houseLocked;
        @AuraEnabled public Boolean followUpDue;
        @AuraEnabled public Integer sharedBuyers;
    }

    public class PartnerDetail {
        @AuraEnabled public PartnerRow summary;
        @AuraEnabled public List<ActivityEntry> activityEntries;
        @AuraEnabled public List<LeadRow> relatedLeads;
    }

    public class PreApprovalRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String borrower;
        @AuraEnabled public String idLabel;
        @AuraEnabled public String amount;
        @AuraEnabled public String program;
        @AuraEnabled public String credit;
        @AuraEnabled public String realtorLabel;
        @AuraEnabled public String statusKey;
        @AuraEnabled public String expiresLabel;
        @AuraEnabled public String lastTouchLabel;
        @AuraEnabled public Boolean weeklyTouchDone;
    }

    public class LoanRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String borrower;
        @AuraEnabled public String idLabel;
        @AuraEnabled public String amount;
        @AuraEnabled public String program;
        @AuraEnabled public String milestone;
        @AuraEnabled public String closingLabel;
        @AuraEnabled public String processor;
        @AuraEnabled public Boolean needsUpdate;
        @AuraEnabled public String realtorLabel;
    }

    public class LoanDetail {
        @AuraEnabled public LoanRow summary;
        @AuraEnabled public List<LoanDetailField> loanDetails;
    }

    public class LoanDetailField {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public LoanDetailField(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class ActivityEntry {
        @AuraEnabled public Id id;
        @AuraEnabled public String channel;
        @AuraEnabled public String outcome;
        @AuraEnabled public String note;
        @AuraEnabled public String timestamp;
        @AuraEnabled public String author;
    }

    public class OpenTaskRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String due;
        @AuraEnabled public Boolean urgent;
    }

    public class RecordSetPayload {
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public List<RecordSetItem> records;
    }

    public class RecordSetItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String primary;
        @AuraEnabled public String secondary;
        @AuraEnabled public String tag;
        @AuraEnabled public String urgency;
        @AuraEnabled public String objectApiName;
        public RecordSetItem() {}
        public RecordSetItem(Id id, String name, String primary, String secondary, String tag, String urgency) {
            this.id = id;
            this.name = name;
            this.primary = primary;
            this.secondary = secondary;
            this.tag = tag;
            this.urgency = urgency;
        }
    }

    public class NavBadges {
        @AuraEnabled public Integer newLeads;
        @AuraEnabled public Integer dueRealtors;
        @AuraEnabled public Integer preApprovals;
        @AuraEnabled public Integer loansInProcess;
    }
}