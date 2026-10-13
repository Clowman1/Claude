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
        // LO Workspace badge (empty for portal users): my earliest future Event on each lead.
        Set<Id> rowIds = new Set<Id>();
        for (LeadRow row : rows) {
            rowIds.add(row.id);
        }
        Map<Id, String> next = LoWsContactService.nextAppointments(rowIds);
        // My Leads board cards show the realtor buying agent. My own leads, so the name is read in
        // system mode (the LO may not be able to read the realtor Account). LO Workspace only.
        Map<Id, String> realtors = new Map<Id, String>();
        if (!rowIds.isEmpty() && UserInfo.getUserType() == 'Standard') {
            for (Lead l : [SELECT Id, Realtor_Buying_Agent__r.Name FROM Lead
                           WHERE Id IN :rowIds AND Realtor_Buying_Agent__c != null WITH SYSTEM_MODE]) {
                realtors.put(l.Id, l.Realtor_Buying_Agent__r.Name);
            }
        }
        for (LeadRow row : rows) {
            row.nextAppointment = next.get(row.id);
            row.realtorName = realtors.get(row.id);
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
        detail.loggedCalls = loggedCalls(leadId);
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
        return getPartners(filterKey, searchTerm, 'realtor');
    }

    /**
     * kind (LO Workspace tag mode only, 2026-10-08): 'realtor' = My Realtors (BD_Industry__c Realtor or blank),
     * 'other' = Other Contacts (every other industry), 'all' = both. Partner Workspace ignores kind.
     */
    public static List<PartnerRow> getPartners(String filterKey, String searchTerm, String kind) {
        Id userId = UserInfo.getUserId();
        PersonAccountRepository repository = new PersonAccountRepository();
        TaskRepository taskRepository = new TaskRepository();
        // LO Workspace (outside LOs, Phase 5): the list is exactly my tags. Partner Workspace keeps
        // its ownership / touched / assignment record set.
        Boolean tagMode = LoWsPartnerTagService.isTagMode();
        Map<Id, External_User_Assignment__c> tags = tagMode ? LoWsPartnerTagService.myTags(null) : null;
        List<Account> partners = tagMode
            ? selectTaggedPartners(tags.keySet())
            : repository.selectPortalPartnersForUser(userId);
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
            if (tagMode) {
                applyTag(row, accountRecord, tags.get(accountRecord.Id));
                if (!matchesPartnerKind(accountRecord.BD_Industry__c, kind)) {
                    continue;
                }
            }
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

    @TestVisible
    private static Boolean matchesPartnerKind(String industry, String kind) {
        Boolean realtor = industry == null || industry == 'Realtor';
        if (kind == 'other') {
            return !realtor;
        }
        if (kind == 'all') {
            return true;
        }
        return realtor;
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
            WITH SYSTEM_MODE
            GROUP BY Realtor_Buying_Agent__c
        ]) {
            countsByPartnerId.put((Id) result.get('partnerId'), (Integer) result.get('buyerCount'));
        }
        // Converted leads leave the count above, so their Transactions are counted here (every status).
        for (AggregateResult result : [
            SELECT Realtor_Buying_Agent__c partnerId, COUNT(Id) loanCount
            FROM Transaction__c
            WHERE (Loan_Officer__c = :userId OR OwnerId = :userId)
              AND Realtor_Buying_Agent__c IN :partnerIds
            WITH SYSTEM_MODE
            GROUP BY Realtor_Buying_Agent__c
        ]) {
            Id partnerId = (Id) result.get('partnerId');
            countsByPartnerId.put(partnerId, (countsByPartnerId.get(partnerId) ?? 0) + (Integer) result.get('loanCount'));
        }
        return countsByPartnerId;
    }

    public static PartnerDetail getPartnerDetail(Id accountId) {
        Id userId = UserInfo.getUserId();
        PersonAccountRepository repository = new PersonAccountRepository();
        TaskRepository taskRepository = new TaskRepository();
        Boolean tagMode = LoWsPartnerTagService.isTagMode();
        Account accountRecord;
        if (tagMode) {
            List<Account> visible = selectTaggedPartners(new Set<Id>{ accountId });
            accountRecord = visible.isEmpty() ? null : visible[0];
        } else {
            accountRecord = repository.selectPortalPartnerDetail(accountId, userId);
        }
        if (accountRecord == null) {
            throw new DomainException('Partner could not be found.');
        }
        Map<Id, Datetime> lastTouch = taskRepository.selectLastActivityDatetimeByWhatIds(
            new Set<Id>{ accountId },
            userId
        );
        PartnerDetail detail = new PartnerDetail();
        detail.summary = mapPartner(accountRecord, userId, lastTouch);
        if (tagMode) {
            applyTag(detail.summary, accountRecord, LoWsPartnerTagService.myTags(new Set<Id>{ accountId }).get(accountId));
        }
        detail.activityEntries = mapActivities(
            taskRepository.selectCompletedActivitiesForRecord(accountId, userId, 50)
        );
        detail.relatedLeads = getLeadsForPartner(accountId);
        detail.relatedLeads.addAll(getLoansForPartner(accountId));
        detail.summary.sharedBuyers = detail.relatedLeads.size();
        return detail;
    }

    private static List<LeadRow> getLeadsForPartner(Id accountId) {
        return mapLeadRows(
            LeadRepository.getInstance().selectPortalLeadsByPartner(UserInfo.getUserId(), accountId)
        );
    }

    /** My Transactions with this partner as buyer's agent; rows open the loan. System mode: my own loans. */
    private static List<LeadRow> getLoansForPartner(Id accountId) {
        Id userId = UserInfo.getUserId();
        List<LeadRow> rows = new List<LeadRow>();
        for (Transaction__c loan : [
            SELECT Id, Name, Status__c, Loan_Amount_1st__c, Loan_Program_1st__c, Borrower_Name__r.Name
            FROM Transaction__c
            WHERE (Loan_Officer__c = :userId OR OwnerId = :userId) AND Realtor_Buying_Agent__c = :accountId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            LeadRow row = new LeadRow();
            row.id = loan.Id;
            row.openView = 'loans';
            row.name = loan.Borrower_Name__r?.Name ?? loan.Name;
            row.status = 'working';
            row.statusLabel = loanStatusLabel(loan.Status__c);
            row.primary = joinNonBlank(new List<String>{ formatCurrency(loan.Loan_Amount_1st__c), loan.Loan_Program_1st__c }, ' · ');
            rows.add(row);
        }
        return rows;
    }

    public static List<PreApprovalRow> getPreApprovals(String filterKey, String searchTerm) {
        Id userId = UserInfo.getUserId();
        String term = normalizeSearch(searchTerm);
        List<Lead> leads = LeadRepository.getInstance().selectPortalPreApprovalsByOwner(userId);
        Map<Id, LoWsTouchService.Touch> touches = LoWsTouchService.touchesFor(leads);
        List<PreApprovalSort> sorted = new List<PreApprovalSort>();
        for (Lead leadRecord : leads) {
            PreApprovalRow row = mapPreApproval(leadRecord, touches.get(leadRecord.Id));
            if (!matchesPreApprovalFilter(row, filterKey)) {
                continue;
            }
            if (!matchesSearch(term, row.borrower, row.idLabel, row.realtorLabel)) {
                continue;
            }
            sorted.add(new PreApprovalSort(row, leadRecord.CreatedDate));
        }
        sorted.sort();
        List<PreApprovalRow> rows = new List<PreApprovalRow>();
        for (PreApprovalSort s : sorted) {
            rows.add(s.row);
        }
        return rows;
    }

    /** Touch due first (longest without a touch at the top), then newest created (decided 2026-10-08). */
    public class PreApprovalSort implements Comparable {
        public PreApprovalRow row;
        Datetime created;
        public PreApprovalSort(PreApprovalRow row, Datetime created) {
            this.row = row;
            this.created = created;
        }
        public Integer compareTo(Object other) {
            PreApprovalSort that = (PreApprovalSort) other;
            Boolean thisDue = row.weeklyTouchDone != true;
            Boolean thatDue = that.row.weeklyTouchDone != true;
            if (thisDue != thatDue) {
                return thisDue ? -1 : 1;
            }
            if (thisDue) {
                Integer a = row.daysSinceTouch ?? 0;
                Integer b = that.row.daysSinceTouch ?? 0;
                if (a != b) {
                    return a > b ? -1 : 1;
                }
            }
            Long x = created == null ? 0 : created.getTime();
            Long y = that.created == null ? 0 : that.created.getTime();
            return x == y ? 0 : (x > y ? -1 : 1);
        }
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
        if (LoWsPartnerTagService.isTagMode()) {
            // LO Workspace: borrowers on my closed loans (one row each, newest loan), then the
            // past clients I imported. The portal keeps its Lead-based list below.
            Set<Id> seen = new Set<Id>();
            for (Transaction__c loan : LoWsPartnerTagService.myClosedLoans()) {
                if (!seen.add(loan.Borrower_Name__c)) {
                    continue;
                }
                LeadRow row = new LeadRow();
                row.id = loan.Id;
                row.openView = 'loans';
                row.name = loan.Borrower_Name__r?.Name;
                row.status = 'closed';
                row.statusLabel = loan.Closing_Date__c == null ? loanStatusLabel(loan.Status__c) : 'Closed ' + loan.Closing_Date__c.format();
                row.phone = loan.Borrower_Name__r?.PersonMobilePhone ?? loan.Borrower_Name__r?.Phone;
                row.email = loan.Borrower_Name__r?.PersonEmail;
                row.amount = formatCurrency(loan.Loan_Amount_1st__c);
                row.program = loan.Loan_Program_1st__c;
                row.primary = joinNonBlank(new List<String>{ row.amount, row.program }, ' · ');
                row.source = 'Your loan ' + loan.Name;
                row.idLabel = loan.Name;
                if (matchesSearch(term, row.name, row.idLabel, row.email)) {
                    rows.add(row);
                }
            }
            // Past clients I imported: client Person Accounts I own, unless already listed by loan.
            for (Account client : LoWsPartnerTagService.myClientAccounts()) {
                if (!seen.add(client.Id)) {
                    continue;
                }
                LeadRow row = new LeadRow();
                row.id = client.Id;
                row.openView = 'pastClients'; // in-workspace past client detail

                row.name = client.Name;
                row.status = 'closed';
                row.statusLabel = 'Past client';
                row.phone = client.PersonMobilePhone ?? client.Phone;
                row.email = client.PersonEmail;
                row.market = client.BillingCity;
                row.primary = joinNonBlank(new List<String>{ row.phone, row.email }, ' · ');
                row.source = 'Imported past client';
                row.idLabel = client.Id;
                if (matchesSearch(term, row.name, row.email, row.phone)) {
                    rows.add(row);
                }
            }
            return rows;
        }
        for (Lead leadRecord : LeadRepository.getInstance().selectPastClientLeadsByOwner(userId)) {
            LeadRow row = mapLead(leadRecord);
            if (!matchesSearch(term, row.name, row.idLabel, row.source)) {
                continue;
            }
            rows.add(row);
        }
        return rows;
    }

    // ---- LO Workspace past client detail (Person Account) ----

    /** My imported past client: a Person Account I own with Group__pc including Client. */
    private static Boolean isMyClient(Account a) {
        return a.IsPersonAccount && a.OwnerId == UserInfo.getUserId()
            && a.Group__pc != null && a.Group__pc.split(';').contains('Client');
    }

    /**
     * Where an Account opens inside LO Workspace: 'pastClients' (my imported past client),
     * 'realtors' (a partner account), or null (no in-workspace page; callers keep their fallback).
     * Returns only a routing word, never record data. LO Workspace (Standard users) only.
     */
    public static String accountWorkspaceView(Id accountId) {
        if (accountId == null || UserInfo.getUserType() != 'Standard'
            || accountId.getSobjectType() != Account.SObjectType) {
            return null;
        }
        List<Account> rows = [
            SELECT Id, OwnerId, IsPersonAccount, Group__pc, BD_Industry__c, Is_Realtor__c, Type, Type__c
            FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }
        if (isMyClient(rows[0])) {
            return 'pastClients';
        }
        return LoWsPartnerTagService.isPartner(rows[0]) ? 'realtors' : null;
    }

    /**
     * Past client page: the Person Account, the loans it borrowed on that I can read, and calls
     * logged by hand. Owner or RecordAccessGuard read first; system-mode reads after the check.
     */
    public static PastClientDetail getPastClientDetail(Id accountId) {
        if (UserInfo.getUserType() != 'Standard') {
            throw new DomainException('Past client pages are available in LO Workspace only.');
        }
        List<Account> rows = accountId == null || accountId.getSobjectType() != Account.SObjectType
            ? new List<Account>()
            : [
                SELECT Id, Name, FirstName, LastName, OwnerId, IsPersonAccount, PersonContactId, Group__pc, PersonEmail,
                       PersonMobilePhone, Phone, BillingCity, Most_Recent_Closing_Date__c,
                       Most_Recent_Loan_Amount__c, Most_Recent_Loan_Purpose__c, Purchase_Price__pc
                FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1
            ];
        if (rows.isEmpty() || !rows[0].IsPersonAccount) {
            throw new DomainException('Past client could not be found.');
        }
        Account a = rows[0];
        Id me = UserInfo.getUserId();
        if (a.OwnerId != me && !RecordAccessGuard.readable(new Set<Id>{ a.Id }).contains(a.Id)) {
            throw new DomainException(RecordAccessGuard.NO_ACCESS);
        }

        PastClientDetail detail = new PastClientDetail();
        detail.id = a.Id;
        detail.name = a.Name;
        detail.firstName = a.FirstName;
        detail.lastName = a.LastName;
        detail.phone = a.PersonMobilePhone ?? a.Phone;
        detail.email = a.PersonEmail;
        detail.market = a.BillingCity;
        detail.isOwner = a.OwnerId == me;
        detail.isPastClient = isMyClient(a);
        detail.recentClosingDate = a.Most_Recent_Closing_Date__c?.format();
        detail.recentLoanAmount = formatCurrency(a.Most_Recent_Loan_Amount__c);
        detail.recentLoanPurpose = a.Most_Recent_Loan_Purpose__c;
        detail.purchasePrice = formatCurrency(a.Purchase_Price__pc);

        List<Transaction__c> loans = [
            SELECT Id, Name, Status__c, Closing_Date__c, Loan_Amount_1st__c, Loan_Purpose__c,
                   Loan_Officer__c, OwnerId, Property_Address__c, Property_Unit__c, Property_City__c,
                   Property_State__c, Property_Postal_Code__c
            FROM Transaction__c
            WHERE Borrower_Name__c = :a.Id
            WITH SYSTEM_MODE
            ORDER BY Closing_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 50
        ];
        // Only loans I could open anyway; My Loans detail opens the ones I am the LO or owner of.
        Set<Id> readable = RecordAccessGuard.readable(new Map<Id, Transaction__c>(loans).keySet());
        detail.loans = new List<ClientLoanRow>();
        for (Transaction__c loan : loans) {
            if (!readable.contains(loan.Id)) {
                continue;
            }
            ClientLoanRow row = new ClientLoanRow();
            row.id = loan.Id;
            row.name = loan.Name;
            row.statusLabel = loanStatusLabel(loan.Status__c);
            row.closingDate = loan.Closing_Date__c?.format();
            row.amount = formatCurrency(loan.Loan_Amount_1st__c);
            row.purpose = loan.Loan_Purpose__c;
            row.propertyAddress = propertyAddress(loan);
            row.canOpen = loan.Loan_Officer__c == me || loan.OwnerId == me;
            detail.loans.add(row);
        }
        Set<Id> whoWhat = new Set<Id>{ a.Id };
        if (a.PersonContactId != null) {
            whoWhat.add(a.PersonContactId);
        }
        detail.loggedCalls = loggedCalls(whoWhat);
        return detail;
    }

    public static List<LoanRow> getLoans(String filterKey, String searchTerm) {
        Id userId = UserInfo.getUserId();
        String term = normalizeSearch(searchTerm);
        List<LoanRow> rows = new List<LoanRow>();
        List<String> statuses = myLoansTabStatuses(filterKey);
        List<Transaction__c> loans = LoanRepository.getInstance().selectPortalLoansByUser(
            userId, statuses, statuses != MY_LOANS_ACTIVE
        );
        Map<Id, String> borrowerNames = borrowerNames(loans);
        for (Transaction__c loanRecord : loans) {
            LoanRow row = mapLoan(loanRecord);
            row.borrower = borrowerNames.get(loanRecord.Id);
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

    // My Loans tabs (decided 2026-10-08). Funding counts as closed, so Active is the active pipeline without it.
    private static final List<String> MY_LOANS_CLOSED = new List<String>{ 'Funding', 'PC Review', 'Post-Closed' };
    private static final List<String> MY_LOANS_CANCELLED = new List<String>{ 'Cancelled', 'Lost' };
    private static final List<String> MY_LOANS_ACTIVE = activeWithoutClosed();

    private static List<String> activeWithoutClosed() {
        List<String> active = new List<String>();
        for (String status : ExternalLOBaselineHelper.ACTIVE_LOAN_STATUSES) {
            if (!MY_LOANS_CLOSED.contains(status)) {
                active.add(status);
            }
        }
        return active;
    }

    private static List<String> myLoansTabStatuses(String filterKey) {
        if (filterKey == 'closed') {
            return MY_LOANS_CLOSED;
        }
        if (filterKey == 'cancelled') {
            return MY_LOANS_CANCELLED;
        }
        return MY_LOANS_ACTIVE;
    }

    public static Map<String, Integer> getLoanTabCounts() {
        Id userId = UserInfo.getUserId();
        LoanRepository repo = LoanRepository.getInstance();
        return new Map<String, Integer>{
            'active' => repo.countPortalLoansByUser(userId, MY_LOANS_ACTIVE),
            'closed' => repo.countPortalLoansByUser(userId, MY_LOANS_CLOSED),
            'cancelled' => repo.countPortalLoansByUser(userId, MY_LOANS_CANCELLED)
        };
    }

    /** Board column for an active loan: Closing status wins, then a Clear to Close date, then the status group. */
    @TestVisible
    private static String boardStage(Transaction__c loanRecord) {
        String status = loanRecord.Status__c;
        if (status == 'Closing') {
            return 'closing';
        }
        if (loanRecord.Clear_to_Close_Date__c != null) {
            return 'ctc';
        }
        if (status == 'Conditionally Approved' || status == 'Approved') {
            return 'approved';
        }
        if (status == 'TRID Application' || status == 'Open' || status == 'Disclosures Out') {
            return 'application';
        }
        return 'processing';
    }

    public static LoanDetail getLoanDetail(Id loanId) {
        Id userId = UserInfo.getUserId();
        Transaction__c loanRecord = LoanRepository.getInstance().selectPortalLoanDetail(
            loanId,
            userId
        );
        if (loanRecord == null) {
            throw new DomainException('Loan could not be found or is not visible.');
        }
        TaskRepository taskRepository = new TaskRepository();
        LoanDetail detail = new LoanDetail();
        detail.summary = mapLoan(loanRecord);
        detail.summary.borrower = borrowerNames(new List<Transaction__c>{ loanRecord }).get(loanRecord.Id);
        detail.loanDetails = buildLoanDetails(loanRecord);
        detail.transactionPartners = buildTransactionPartners(loanRecord.Id);
        detail.cocHistory = buildCocHistory(loanRecord.Id);
        detail.activityEntries = mapActivities(
            taskRepository.selectCompletedActivitiesForRecord(loanId, userId, 50)
        );
        detail.conditionRows = mapPortalConditions(
            LoanRepository.getInstance().selectPortalConditionSnapshotByLoanId(loanId)
        );
        detail.loggedCalls = loggedCalls(loanId);
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
            for (PartnerRow row : getPartners('due', null, 'all')) {
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
                    row.lastTouchLabel,
                    row.statusKey,
                    'attention',
                    'Lead'
                ));
            }
            return payload;
        }

        if (recordSetKey == 'milestone-loans') {
            payload.title = 'Loans waiting on you';
            payload.subtitle = 'Status is Waiting On Loan Officer';
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

    /**
     * LO Workspace: my tagged partners, read WITH sharing so a row shows only while I can actually
     * read the account (the tag's share, ownership, or any other access).
     */
    private static List<Account> selectTaggedPartners(Set<Id> accountIds) {
        return [
            SELECT Id, Name, PersonEmail, Phone, PersonMobilePhone, PersonContactId, OwnerId, Follow_Up_LO__c,
                   Preferred_LO__c, Group__pc, BD_Industry__c, Company__c, PersonTitle, BillingCity,
                   LastActivityDate, Biz_Dev_Designation__c
            FROM Account
            WHERE Id IN :accountIds AND IsPersonAccount = true
            ORDER BY Name ASC
            LIMIT 2000
        ];
    }

    /** LO Workspace: stage from my tag; a tag grants logging, so no house lock; never-touched is due. */
    private static void applyTag(PartnerRow row, Account accountRecord, External_User_Assignment__c tag) {
        row.stage = tag == null ? null : (tag.Stage__c ?? LoWsPartnerTagService.DEFAULT_STAGE);
        row.tagged = tag != null;
        row.houseLocked = false;
        row.followUpDue = row.daysSinceMyTouch == null
            || row.daysSinceMyTouch >= ExternalLOBaselineHelper.REALTOR_FOLLOW_UP_ORANGE_DAYS;
        row.phone = accountRecord.Phone ?? accountRecord.PersonMobilePhone;
        row.company = accountRecord.Company__c ?? accountRecord.PersonTitle;
        if (accountRecord.BD_Industry__c != null) {
            row.partnerType = accountRecord.BD_Industry__c;
        }
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

    private static PreApprovalRow mapPreApproval(Lead leadRecord, LoWsTouchService.Touch touch) {
        PreApprovalRow row = new PreApprovalRow();
        row.id = leadRecord.Id;
        row.borrower = leadRecord.Name;
        row.idLabel = leadRecord.Id;
        row.amount = formatCurrency(leadRecord.Loan_Amount__c);
        row.program = leadRecord.Loan_Program__c;
        row.credit = leadRecord.App_Summary_Credit__c;
        row.realtorLabel = leadRecord.Realtor_Buying_Agent__r?.Name;
        row.lastTouchLabel = touch?.lastTouch == null
            ? 'No touch yet'
            : 'Last touch ' + touch.lastTouch.date().format();
        row.daysSinceTouch = touch?.daysSince;
        row.weeklyTouchDone = touch == null || touch.due != true;
        row.statusKey = row.weeklyTouchDone ? 'ready-to-review' : 'touch-due';
        return row;
    }

    /**
     * Loan Id -> borrower name. The loan queries run WITH USER_MODE, so an LO who can't read the borrower
     * Account got a null Borrower_Name__r and the row showed the raw Account Id. The loan itself is
     * visible to the LO, so its borrower's name is read without sharing; 'Borrower' if there is none.
     */
    private static Map<Id, String> borrowerNames(List<Transaction__c> loans) {
        Set<Id> missing = new Set<Id>();
        for (Transaction__c loan : loans) {
            if (loan.Borrower_Name__r?.Name == null && loan.Borrower_Name__c != null) missing.add(loan.Borrower_Name__c);
        }
        Map<Id, String> accountNames = new Map<Id, String>();
        if (!missing.isEmpty()) {
            for (Account a : LoWsContactService.readAccountsWithoutSharing(missing)) accountNames.put(a.Id, a.Name);
        }
        Map<Id, String> out = new Map<Id, String>();
        for (Transaction__c loan : loans) {
            out.put(loan.Id, loan.Borrower_Name__r?.Name ?? accountNames.get(loan.Borrower_Name__c) ?? 'Borrower');
        }
        return out;
    }

    private static LoanRow mapLoan(Transaction__c loanRecord) {
        LoanRow row = new LoanRow();
        row.id = loanRecord.Id;
        row.borrower = loanRecord.Borrower_Name__r?.Name ?? 'Borrower'; // never the raw Id; see borrowerNames
        row.idLabel = loanRecord.Name;
        // Live twins: Loan_Amount__c / Interest_Rate__c / Lock_Exp_Date_1st_TD__c are 0% populated on active files.
        row.amount = formatCurrency(loanRecord.Loan_Amount_1st__c);
        row.program = loanRecord.Loan_Program_1st__c;
        row.milestone = loanStatusLabel(loanRecord.Status__c);
        row.closingLabel = loanRecord.Closing_Date__c == null
            ? 'Closing TBD'
            : 'Closing ' + loanRecord.Closing_Date__c.format();
        row.processor = loanRecord.Processor__r?.Name;
        row.clearToClose = loanRecord.Clear_to_Close_Date__c != null;
        row.needsUpdate = ExternalLOBaselineHelper.loanMilestoneUrgency(loanRecord) != '';
        row.boardStage = boardStage(loanRecord);
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

    /**
     * Loan detail "Transaction Partners". System mode: the caller already passed the USER_MODE loan
     * visibility check, and the LO usually cannot read the agent / title Accounts themselves.
     */
    private static List<LoanDetailField> buildTransactionPartners(Id loanId) {
        Transaction__c t = [
            SELECT Loan_Officer__r.Name, Loan_Officer__r.Email, Loan_Officer__r.MobilePhone,
                   Processor__r.Name, Processor__r.Email, Processor__r.Phone,
                   Title_Agent__r.Name, Title_Agent__r.Company__c, Title_Agent__r.Phone, Title_Agent__r.PersonMobilePhone, Title_Agent__r.PersonEmail,
                   Realtor_Buying_Agent__r.Name, Realtor_Buying_Agent__r.Company__c, Realtor_Buying_Agent__r.Phone, Realtor_Buying_Agent__r.PersonMobilePhone, Realtor_Buying_Agent__r.PersonEmail,
                   Realtor_Buying_Agent_Lead__r.Name, Realtor_Buying_Agent_Lead__r.Company, Realtor_Buying_Agent_Lead__r.Phone, Realtor_Buying_Agent_Lead__r.Email,
                   Realtor_Listing_Agent__r.Name, Realtor_Listing_Agent__r.Company__c, Realtor_Listing_Agent__r.Phone, Realtor_Listing_Agent__r.PersonMobilePhone, Realtor_Listing_Agent__r.PersonEmail,
                   Realtor_Listing_Agent_Lead__r.Name, Realtor_Listing_Agent_Lead__r.Company, Realtor_Listing_Agent_Lead__r.Phone, Realtor_Listing_Agent_Lead__r.Email,
                   Buying_Agent_Assistant__r.Name, Buying_Agent_Assistant__r.Company__c, Buying_Agent_Assistant__r.Phone, Buying_Agent_Assistant__r.PersonMobilePhone, Buying_Agent_Assistant__r.PersonEmail,
                   Listing_Agent_TC__r.Name, Listing_Agent_TC__r.MobilePhone, Listing_Agent_TC__r.Phone, Listing_Agent_TC__r.Email
            FROM Transaction__c
            WHERE Id = :loanId
            WITH SYSTEM_MODE
        ];
        List<LoanDetailField> fields = new List<LoanDetailField>();
        fields.add(new LoanDetailField('Loan Officer', partnerLine(t.Loan_Officer__r?.Name, null, t.Loan_Officer__r?.MobilePhone, t.Loan_Officer__r?.Email)));
        fields.add(new LoanDetailField('Processor', partnerLine(t.Processor__r?.Name, null, t.Processor__r?.Phone, t.Processor__r?.Email)));
        fields.add(new LoanDetailField('Title Agent', accountLine(t.Title_Agent__r)));
        // Agents: the Account lookup, else the older Lead lookup.
        fields.add(new LoanDetailField('Buyer\'s Agent', t.Realtor_Buying_Agent__r != null
            ? accountLine(t.Realtor_Buying_Agent__r)
            : leadLine(t.Realtor_Buying_Agent_Lead__r)));
        fields.add(new LoanDetailField('Buyer\'s Agent TC', accountLine(t.Buying_Agent_Assistant__r)));
        fields.add(new LoanDetailField('Listing Agent', t.Realtor_Listing_Agent__r != null
            ? accountLine(t.Realtor_Listing_Agent__r)
            : leadLine(t.Realtor_Listing_Agent_Lead__r)));
        fields.add(new LoanDetailField('Listing Agent TC', partnerLine(t.Listing_Agent_TC__r?.Name, null,
            t.Listing_Agent_TC__r?.MobilePhone ?? t.Listing_Agent_TC__r?.Phone, t.Listing_Agent_TC__r?.Email)));
        return fields;
    }

    public class CocHistoryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String reasons;
        @AuraEnabled public String submittedLabel;
        @AuraEnabled public String specialist;
        @AuraEnabled public String completedLabel;
        @AuraEnabled public String notes;
    }

    /** Loan detail "COC's for this Loan", newest first. System mode: outside LOs have no FLS on COC fields. */
    private static List<CocHistoryRow> buildCocHistory(Id loanId) {
        List<CocHistoryRow> rows = new List<CocHistoryRow>();
        for (Change_of_Circumstance__c c : [
            SELECT Id, Name, Status__c, Reason_for_Change__c, CreatedDate, CreatedBy.Name,
                   COC_Specialist__r.Name, COC_Completion_Date__c, Notes__c
            FROM Change_of_Circumstance__c
            WHERE Transaction__c = :loanId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            CocHistoryRow row = new CocHistoryRow();
            row.id = c.Id;
            row.name = c.Name;
            row.status = c.Status__c ?? 'Submitted';
            row.reasons = String.isBlank(c.Reason_for_Change__c) ? 'No reason given' : c.Reason_for_Change__c.replace(';', ' · ');
            row.submittedLabel = 'Submitted ' + c.CreatedDate.format('M/d/yyyy') + ' by ' + c.CreatedBy.Name;
            row.specialist = c.COC_Specialist__r?.Name;
            row.completedLabel = c.COC_Completion_Date__c == null ? null : 'Completed ' + c.COC_Completion_Date__c.format();
            row.notes = c.Notes__c?.trim();
            rows.add(row);
        }
        return rows;
    }

    private static String accountLine(Account a) {
        return a == null ? '—' : partnerLine(a.Name, a.Company__c, a.PersonMobilePhone ?? a.Phone, a.PersonEmail);
    }

    private static String leadLine(Lead l) {
        return l == null ? '—' : partnerLine(l.Name, l.Company, l.Phone, l.Email);
    }

    private static String partnerLine(String name, String company, String phone, String email) {
        if (String.isBlank(name)) return '—';
        return joinNonBlank(new List<String>{ name, company, phone, email }, ' · ');
    }

    private static List<LoanDetailField> buildLoanDetails(Transaction__c loanRecord) {
        List<LoanDetailField> fields = new List<LoanDetailField>();
        fields.add(new LoanDetailField('Current milestone', loanStatusLabel(loanRecord.Status__c)));
        fields.add(new LoanDetailField(
            'Status since',
            loanRecord.Current_Status_Since__c?.format() ?? '—'
        ));
        fields.add(new LoanDetailField(
            'Closing date',
            loanRecord.Closing_Date__c?.format() ?? 'TBD'
        ));
        fields.add(new LoanDetailField('Processor', loanRecord.Processor__r?.Name ?? '—'));
        fields.add(new LoanDetailField('Loan amount', formatCurrency(loanRecord.Loan_Amount_1st__c)));
        fields.add(new LoanDetailField('Purchase price', formatCurrency(loanRecord.Purchase_Price__c)));
        fields.add(new LoanDetailField('Rate', loanRecord.Rate_1st_TD__c == null ? '—' : String.valueOf(loanRecord.Rate_1st_TD__c) + '%'));
        fields.add(new LoanDetailField('LTV / DTI', joinNonBlank(new List<String>{
            loanRecord.LTV__c == null ? null : String.valueOf(loanRecord.LTV__c) + '%',
            loanRecord.DTI_Back_End__c == null ? null : String.valueOf(loanRecord.DTI_Back_End__c) + '%'
        }, ' / ')));
        fields.add(new LoanDetailField('Property address', propertyAddress(loanRecord)));
        fields.add(new LoanDetailField('Lock expires', loanRecord.Rate_Lock_Exp_Date__c?.format()));
        return fields;
    }

    private static List<LeadRow> mapLeadRows(List<Lead> leads) {
        List<LeadRow> rows = new List<LeadRow>();
        for (Lead leadRecord : leads) {
            rows.add(mapLead(leadRecord));
        }
        return rows;
    }

    private static final Set<String> CALL_OR_MEETING_TYPES = new Set<String>{
        'Call - Prospecting', 'Call - Active Agent', 'Meeting (New Agent)', 'Meeting (Active Agent)'
    };

    /**
     * Calls and meetings logged by hand on this record (Log activity / Log communication), for the
     * Calls/Zooms tab next to RingSense and Zoom. Channel comes from Task.Type (or, on older rows,
     * Activity_Type__c), never Subject. RingCentral rows (CallType set) are left to RingSense.
     * LO Workspace only. SYSTEM_MODE because Activity_Category__c has FLS only in the External LO
     * permission sets; callers have already loaded the record through its own visibility check.
     */
    @TestVisible
    private static List<ActivityEntry> loggedCalls(Id recordId) {
        return loggedCalls(new Set<Id>{ recordId });
    }

    /** Several Ids: a Person Account's tasks sit on the Account (WhatId) or its PersonContact (WhoId). */
    private static List<ActivityEntry> loggedCalls(Set<Id> recordIds) {
        List<ActivityEntry> entries = new List<ActivityEntry>();
        recordIds.remove(null);
        if (recordIds.isEmpty() || UserInfo.getUserType() != 'Standard') {
            return entries;
        }
        for (Task taskRecord : [
            SELECT Id, Type, Activity_Type__c, Activity_Category__c, CallDisposition, Description, CreatedDate, Owner.Name
            FROM Task
            WHERE (WhoId IN :recordIds OR WhatId IN :recordIds)
              AND Status = 'Completed'
              AND CallType = null
              AND (Type IN ('Call', 'Meeting') OR Activity_Type__c IN :CALL_OR_MEETING_TYPES)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            Boolean meeting = taskRecord.Type == 'Meeting'
                || (taskRecord.Type != 'Call' && taskRecord.Activity_Type__c != null && taskRecord.Activity_Type__c.startsWith('Meeting'));
            ExternalLoActivityCatalog.ActivityDefinition category =
                ExternalLoActivityCatalog.activityByCategory(taskRecord.Activity_Category__c);
            ActivityEntry entry = new ActivityEntry();
            entry.id = taskRecord.Id;
            entry.channel = meeting ? 'Meeting' : 'Call';
            entry.outcome = joinNonBlank(new List<String>{
                category == null ? taskRecord.Activity_Type__c : category.shortLabel,
                taskRecord.CallDisposition
            }, ' · ');
            entry.note = taskRecord.Description;
            entry.timestamp = taskRecord.CreatedDate.format('MMM d, yyyy h:mm a');
            entry.author = taskRecord.Owner?.Name;
            entries.add(entry);
        }
        return entries;
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

        // Limit 3 so hyphenated goal keys (goal-today-realtor-outreach) stay whole.
        List<String> parts = recordSetKey.split('-', 3);
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

    // The five My Leads tabs agreed for LO Workspace (2026-09-30, Q27), using the org's real Lead statuses.
    private static final Set<String> STATUS_NEW = new Set<String>{ 'New' };
    private static final Set<String> STATUS_PRE_APPROVAL = new Set<String>{
        'Pre-Approval', 'Documents Requested', 'Documents Received for Review', 'Application'
    };
    private static final Set<String> STATUS_NURTURE = new Set<String>{
        'Nurturing', 'Nurture - Preapproval', 'Nurture-Pre-Approval', 'Nurturing - Meeting Complete', '30 Day + Follow Up'
    };
    private static final Set<String> STATUS_CONVERTED = new Set<String>{
        'Submitted For Disclosures', 'Active', 'Under Contract'
    };

    /** new | working | pre-approval | nurture | converted. Contact Attempt 1-8, Working, meetings etc. are 'working'. Public for LoWsOversightController (Phase 8). */
    public static String deriveLeadStage(Lead leadRecord) {
        String status = leadRecord?.Status;
        // Only some lead queries select IsConverted; detail views reuse this without it.
        if (leadRecord != null && leadRecord.isSet('IsConverted') && leadRecord.IsConverted == true) {
            return 'converted';
        }
        if (String.isBlank(status) || STATUS_NEW.contains(status)) {
            return 'new';
        }
        if (STATUS_PRE_APPROVAL.contains(status)) {
            return 'pre-approval';
        }
        if (STATUS_NURTURE.contains(status) || status.startsWithIgnoreCase('Nurtur')) {
            return 'nurture';
        }
        if (STATUS_CONVERTED.contains(status)) {
            return 'converted';
        }
        return 'working';
    }

    private static Boolean matchesLeadFilter(LeadRow row, String filterKey) {
        if (String.isBlank(filterKey) || filterKey == 'all') {
            return row.status != 'converted';
        }
        if (filterKey == 'uncontacted') {
            return row.lastContactLabel == null && row.status != 'converted';
        }
        return row.status == filterKey;
    }

    private static Boolean matchesPartnerFilter(PartnerRow row, String filterKey) {
        if (row.stage != null) {
            // LO Workspace tag rows: Prospects = not yet Active Partner; every other chip sees all tags.
            if (filterKey == 'prospects') {
                return LoWsPartnerTagService.PROSPECT_STAGES.contains(row.stage);
            }
            if (String.isBlank(filterKey) || filterKey == 'all') {
                return true;
            }
            if (filterKey == 'due') {
                return row.followUpDue;
            }
            return row.daysSinceMyTouch != null && row.daysSinceMyTouch <= Integer.valueOf(filterKey);
        }
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

    /** "4578 Pheasant Run Drive, Unit 2, Orlando, FL 32801", or a dash when the loan has no address yet. */
    private static String propertyAddress(Transaction__c loan) {
        String street = joinNonBlank(new List<String>{
            loan.Property_Address__c,
            String.isBlank(loan.Property_Unit__c) ? null : 'Unit ' + loan.Property_Unit__c
        }, ', ');
        String stateZip = joinNonBlank(new List<String>{ loan.Property_State__c, loan.Property_Postal_Code__c }, ' ');
        String full = joinNonBlank(new List<String>{ street, loan.Property_City__c, stateZip }, ', ');
        return String.isBlank(full) ? '—' : full;
    }

    private static Map<String, String> loanStatusLabels;

    /** The label the back end shows (e.g. API value Open displays as "Submission Form Complete"). */
    public static String loanStatusLabel(String value) {
        if (value == null) {
            return null;
        }
        if (loanStatusLabels == null) {
            loanStatusLabels = new Map<String, String>();
            for (Schema.PicklistEntry entry : Transaction__c.Status__c.getDescribe().getPicklistValues()) {
                loanStatusLabels.put(entry.getValue(), entry.getLabel());
            }
        }
        return loanStatusLabels.containsKey(value) ? loanStatusLabels.get(value) : value;
    }

    // Real Status__c pipeline (no 'Underwriting' or 'Clear to Close' status exists).
    private static final Set<String> IN_PROCESS_STATUSES = new Set<String>{
        'Pre-Processing', 'Processing', 'Submitted', 'Suspended', 'Waiting On Loan Officer', 'Conditionally Approved', 'Re-Submitted'
    };
    private static final Set<String> FUNDED_OR_LATER = new Set<String>{ 'Funding', 'PC Review', 'Post-Closed' };

    private static Boolean matchesLoanFilter(LoanRow row, String filterKey, Transaction__c loanRecord) {
        if (String.isBlank(filterKey) || filterKey == 'all' || filterKey == 'active'
            || filterKey == 'closed' || filterKey == 'cancelled') {
            return true;
        }
        if (filterKey == 'update') {
            return row.needsUpdate;
        }
        if (filterKey == 'ctc') {
            return row.clearToClose == true && !FUNDED_OR_LATER.contains(row.milestone);
        }
        return IN_PROCESS_STATUSES.contains(row.milestone);
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
        // Portal view that opens this row; null = the lead detail. Past Clients loan rows use loans.
        @AuraEnabled public String openView;
        // LO Workspace My Leads badge: "Next appointment: <when> — <subject>" (null in the portal).
        @AuraEnabled public String nextAppointment;
        // LO Workspace My Leads board: the realtor buying agent's name (null in the portal).
        @AuraEnabled public String realtorName;
    }

    public class LeadDetail {
        @AuraEnabled public LeadRow summary;
        @AuraEnabled public List<LoanDetailField> scenarioFields;
        @AuraEnabled public String scenarioNotes;
        @AuraEnabled public String ariveUrl;
        @AuraEnabled public List<ActivityEntry> activityEntries;
        @AuraEnabled public List<OpenTaskRow> openTasks;
        @AuraEnabled public List<ActivityEntry> loggedCalls;
    }

    public class PastClientDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String market;
        @AuraEnabled public Boolean isOwner;
        @AuraEnabled public Boolean isPastClient;
        @AuraEnabled public String recentClosingDate;
        @AuraEnabled public String recentLoanAmount;
        @AuraEnabled public String recentLoanPurpose;
        @AuraEnabled public String purchasePrice;
        @AuraEnabled public List<ClientLoanRow> loans;
        @AuraEnabled public List<ActivityEntry> loggedCalls;
    }

    public class ClientLoanRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String closingDate;
        @AuraEnabled public String amount;
        @AuraEnabled public String purpose;
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public Boolean canOpen;
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
        // LO Workspace tags only (null on the Partner Workspace portal).
        @AuraEnabled public String stage;
        @AuraEnabled public Boolean tagged;
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
        @AuraEnabled public String lastTouchLabel;
        @AuraEnabled public Boolean weeklyTouchDone;
        @AuraEnabled public Integer daysSinceTouch;
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
        @AuraEnabled public Boolean clearToClose;
        @AuraEnabled public String realtorLabel;
        @AuraEnabled public String boardStage;
    }

    public class LoanDetail {
        @AuraEnabled public LoanRow summary;
        @AuraEnabled public List<LoanDetailField> loanDetails;
        @AuraEnabled public List<LoanDetailField> transactionPartners;
        @AuraEnabled public List<CocHistoryRow> cocHistory;
        @AuraEnabled public List<ActivityEntry> activityEntries;
        @AuraEnabled public List<PortalConditionRow> conditionRows;
        @AuraEnabled public List<ActivityEntry> loggedCalls;
    }

    public class PortalConditionRow {
        @AuraEnabled public String conditionKey;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String type;
        @AuraEnabled public String description;
    }

    private static List<PortalConditionRow> mapPortalConditions(List<Condition__c> conditions) {
        List<PortalConditionRow> rows = new List<PortalConditionRow>();
        for (Condition__c conditionRecord : conditions) {
            PortalConditionRow row = new PortalConditionRow();
            row.conditionKey = String.valueOf(conditionRecord.Id);
            row.name = conditionRecord.Name;
            row.status = conditionRecord.Status__c;
            row.type = conditionRecord.Type__c;
            row.description = conditionRecord.Description__c;
            rows.add(row);
        }
        return rows;
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