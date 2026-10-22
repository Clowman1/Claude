/**
 * Logs Partner Workspace activities as a single Task with category, channel,
 * and count. Social engagement may omit a related record. Does not replace
 * ExternalLoCommunicationService.logCommunication.
 */
public with sharing class ExternalLoActivityLogService {
    private static final Set<String> LOGGABLE_OBJECTS = new Set<String>{
        'Lead',
        'Account',
        'Transaction__c',
        'Contact'
    };

    /**
     * Inserts one completed Task. Count is clamped 1–50 and stored on
     * Activity_Count__c so TaskTrigger is not amplified.
     */
    public static LogResult logActivity(LogRequest request) {
        validate(request);
        ExternalLoActivityCatalog.ActivityDefinition activity = ExternalLoActivityCatalog.activityByKey(request.activityKey);
        if (activity == null || activity.isActive != true) {
            throw new DomainException('Choose an activity category to log.');
        }
        if (activity.requiresContact == true && request.recordId == null) {
            throw new DomainException('Choose a contact for ' + activity.shortLabel + '.');
        }
        if (activity.activityKey == SOCIAL_KEY) {
            // A social post has no contact and no channel; the modal writes "Platform: X" into the notes.
            if (request.recordId != null) {
                throw new DomainException(activity.shortLabel + ' are not logged against a contact. Clear the contact and pick the platform.');
            }
            request.channel = null;
        }
        String kind;
        if (request.recordId != null) {
            // Trust the Id, not the client's object name.
            request.objectApiName = String.valueOf(request.recordId.getSObjectType());
            validate(request);
            requireLoggable(request.recordId);
            kind = targetKind(request.recordId);
            requireMatchingCategory(activity, kind);
        }
        // Log on a due follow-up row in Up Next sends promptKey 'task:<Task Id>': that Task is completed in
        // this same save (after the log insert), and the key is not stamped on the log Task.
        Id followUpTaskToComplete = followUpTaskIdFrom(request.promptKey);
        if (followUpTaskToComplete != null) {
            request.promptKey = null;
        }
        Integer countValue = ExternalLoGoalMath.clampCount(request.activityCount);
        Id userId = UserInfo.getUserId();
        Task taskRecord = new Task();
        taskRecord.OwnerId = userId;
        taskRecord.Status = 'Completed';
        taskRecord.Priority = 'Normal';
        taskRecord.ActivityDate = Date.today();
        taskRecord.Activity_Category__c = activity.categoryApiName;
        taskRecord.Activity_Type__c = resolveActivityType(activity, request.channel, kind);
        taskRecord.Type = taskTypeFor(request.channel);
        taskRecord.Activity_Count__c = countValue;
        taskRecord.Prompt_Key__c = String.isBlank(request.promptKey) ? null : request.promptKey.trim();
        taskRecord.Subject = buildSubject(activity, countValue);
        if (!String.isBlank(request.notes)) {
            taskRecord.Description = request.notes.trim();
        }
        assignRelated(taskRecord, request);
        if (writesNote(request.recordId, request.notes)) {
            taskRecord.Create_Enhanced_Note__c = false;
        }
        Database.insert(new List<Task>{ taskRecord }, AccessLevel.SYSTEM_MODE);
        addNote(request.recordId, channelLabel(request.channel) + ' — ' + activity.shortLabel, request.notes);
        if (!String.isBlank(request.promptKey)) {
            completeMatchingPromptTask(userId, request.promptKey.trim());
        }
        // Only contact-bound logs get a follow-up (Social posts have no record).
        Id followUpId = request.recordId == null
            ? null
            : LoWsCalendarService.createFollowUp(request.recordId, request.followUpOption);
        completeFollowUpTask(userId, followUpTaskToComplete);
        LeadProgress progress = progressLeadAfterCall(request.recordId, request.channel, request.callOutcome);

        LogResult result = new LogResult();
        result.taskId = taskRecord.Id;
        result.followUpId = followUpId;
        result.userMessage = (countValue == 1
            ? activity.shortLabel + ' logged'
            : countValue + ' ' + activity.unitNoun + ' logged') + progress.suffix();
        result.statusWarning = progress.warning;
        result.activityKey = activity.activityKey;
        result.activityCount = countValue;
        return result;
    }

    /**
     * Inserts an open Task due tomorrow so the computed prompt stays hidden
     * until that date. No new snooze object.
     */
    public static LogResult snoozePrompt(String promptKey, Id recordId, String objectApiName) {
        if (String.isBlank(promptKey)) {
            throw new DomainException('A prompt is required to snooze.');
        }
        Id userId = UserInfo.getUserId();
        Task existing = new TaskRepository().selectOpenPromptTask(userId, promptKey.trim());
        if (existing != null) {
            LogResult already = new LogResult();
            already.taskId = existing.Id;
            already.userMessage = 'This prompt is already scheduled for later.';
            return already;
        }
        Task snooze = new Task();
        snooze.OwnerId = userId;
        snooze.Status = 'Not Started';
        snooze.Priority = 'Normal';
        snooze.ActivityDate = Date.today().addDays(1);
        snooze.Prompt_Key__c = promptKey.trim();
        snooze.Subject = 'Follow up — ' + promptKey.trim();
        LogRequest related = new LogRequest();
        related.recordId = recordId;
        related.objectApiName = objectApiName;
        assignRelated(snooze, related);
        Database.insert(new List<Task>{ snooze }, AccessLevel.SYSTEM_MODE);

        LogResult result = new LogResult();
        result.taskId = snooze.Id;
        result.userMessage = 'We will bring this back tomorrow.';
        return result;
    }

    /**
     * Leads and partners the user can attach to a log row.
     */
    public static List<SearchHit> searchLoggableRecords(String searchTerm) {
        String term = searchTerm == null ? '' : searchTerm.trim();
        List<SearchHit> hits = new List<SearchHit>();
        if (term.length() < 2) {
            return hits;
        }
        String likeTerm = '%' + term + '%';
        Id userId = UserInfo.getUserId();
        // LO Workspace also searches past clients and borrowers, so each source gets a share of the 20.
        Boolean tagMode = LoWsPartnerTagService.isTagMode();
        Integer perSource = tagMode ? 5 : 20;
        for (Lead leadRecord : [
            SELECT Id, Name, Status, Phone, Email, LeadSource
            FROM Lead
            WHERE OwnerId = :userId
              AND IsConverted = false
              AND Name LIKE :likeTerm
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 10
        ]) {
            if (hits.size() >= Math.min(perSource, 10)) {
                break;
            }
            String kind = leadRecord.LeadSource == PAST_CLIENT_SOURCE ? KIND_CLIENT : KIND_CONSUMER;
            hits.add(hit(leadRecord.Id, leadRecord.Name, 'Lead', 'Lead · ' + leadRecord.Status,
                leadRecord.Phone, leadRecord.Email, kind, defaultKeyFor(kind)));
        }
        Integer cap = hits.size() + perSource;
        for (ExternalLoPortalService.PartnerRow partner : ExternalLoPortalService.getRealtors('all', term)) {
            if (hits.size() >= Math.min(cap, 20)) {
                break;
            }
            hits.add(hit(partner.id, partner.name, 'Account',
                String.isBlank(partner.partnerType) ? 'Partner' : 'Partner · ' + partner.partnerType,
                partner.phone, partner.email, KIND_PARTNER, 'realtor-outreach'));
        }
        if (!tagMode) {
            return hits;
        }
        // Borrowers on my loans. The loan is the target: outside LOs read the loan through
        // LoanOfficerRecordSharingService, but not always the borrower's Person Account.
        Set<Id> borrowerAccountIds = new Set<Id>();
        List<SearchHit> borrowers = new List<SearchHit>();
        for (Transaction__c loan : [
            SELECT Id, Status__c, Borrower_Name__c, Borrower_Name__r.Name, Borrower_Name__r.PersonEmail,
                   Borrower_Name__r.PersonMobilePhone, Borrower_Name__r.Phone
            FROM Transaction__c
            WHERE Loan_Officer__c = :userId AND Borrower_Name__r.Name LIKE :likeTerm
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 5
        ]) {
            borrowerAccountIds.add(loan.Borrower_Name__c);
            borrowers.add(hit(loan.Id, loan.Borrower_Name__r.Name, 'Transaction__c', 'Borrower · ' + loan.Status__c,
                loan.Borrower_Name__r.PersonMobilePhone ?? loan.Borrower_Name__r.Phone, loan.Borrower_Name__r.PersonEmail,
                KIND_CLIENT, isClosedLoan(loan.Status__c) ? 'past-client-call' : 'consumer-conversation'));
        }
        cap = hits.size() + perSource;
        String lowerTerm = term.toLowerCase();
        for (Account client : LoWsPartnerTagService.myClientAccounts()) {
            if (hits.size() >= Math.min(cap, 20 - borrowers.size())) {
                break;
            }
            if (client.Name == null || !client.Name.toLowerCase().contains(lowerTerm) || borrowerAccountIds.contains(client.Id)) {
                continue;
            }
            hits.add(hit(client.Id, client.Name, 'Account', 'Past client', client.PersonMobilePhone ?? client.Phone,
                client.PersonEmail, KIND_CLIENT, 'past-client-call'));
        }
        hits.addAll(borrowers);
        return hits;
    }

    private static SearchHit hit(Id id, String name, String objectApiName, String subtitle, String phone, String email,
        String kind, String activityKey) {
        SearchHit hit = new SearchHit();
        hit.id = id;
        hit.name = name;
        hit.objectApiName = objectApiName;
        hit.subtitle = subtitle;
        hit.phone = phone;
        hit.email = email;
        hit.activityKey = activityKey;
        hit.allowedKeys = new List<String>();
        for (String key : KINDS_FOR_ACTIVITY.keySet()) {
            if (KINDS_FOR_ACTIVITY.get(key).contains(kind)) {
                hit.allowedKeys.add(key);
            }
        }
        return hit;
    }

    // ------------------------------------------------------------------ who was contacted

    public static final String KIND_PARTNER = 'partner';
    public static final String KIND_CONSUMER = 'consumer';
    /** Past client or borrower: a Past Client / converted lead, a client or borrower Person Account, or a loan. */
    public static final String KIND_CLIENT = 'client';
    private static final String PAST_CLIENT_SOURCE = 'Past Client';
    private static final String SOCIAL_KEY = 'social-engagement';

    /** Contact-bound categories and the kinds of contact each may be logged against. */
    private static final Map<String, Set<String>> KINDS_FOR_ACTIVITY = new Map<String, Set<String>>{
        'realtor-outreach' => new Set<String>{ KIND_PARTNER },
        'partner-meeting' => new Set<String>{ KIND_PARTNER },
        'consumer-conversation' => new Set<String>{ KIND_CONSUMER, KIND_CLIENT },
        'past-client-call' => new Set<String>{ KIND_CLIENT }
    };
    private static final Map<String, String> ACTIVITY_TARGET = new Map<String, String>{
        'realtor-outreach' => 'a realtor or partner',
        'partner-meeting' => 'a realtor or partner',
        'consumer-conversation' => 'a lead or borrower',
        'past-client-call' => 'a past client or borrower'
    };
    private static final Map<String, String> KIND_NOUN = new Map<String, String>{
        KIND_PARTNER => 'a realtor or partner',
        KIND_CONSUMER => 'a lead',
        KIND_CLIENT => 'a past client'
    };

    /**
     * partner | consumer | client for a Lead, Account, Contact or Transaction__c Id. Partner Workspace
     * (no tag mode) keeps its old rule that every Account it logs against is a partner.
     */
    public static String targetKind(Id recordId) {
        if (recordId == null) {
            return null;
        }
        SObjectType objectType = recordId.getSObjectType();
        if (objectType == Lead.SObjectType) {
            for (Lead leadRecord : [SELECT IsConverted, LeadSource FROM Lead WHERE Id = :recordId WITH SYSTEM_MODE]) {
                return leadRecord.IsConverted || leadRecord.LeadSource == PAST_CLIENT_SOURCE ? KIND_CLIENT : KIND_CONSUMER;
            }
            return KIND_CONSUMER;
        }
        if (objectType == Transaction__c.SObjectType) {
            return KIND_CLIENT;
        }
        Id accountId = recordId;
        if (objectType == Contact.SObjectType) {
            List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :recordId WITH SYSTEM_MODE];
            accountId = contacts.isEmpty() ? null : contacts[0].AccountId;
        }
        if (accountId == null || accountId.getSObjectType() != Account.SObjectType) {
            return null;
        }
        List<Account> accounts = [
            SELECT Id, BD_Industry__c, Is_Realtor__c, Type, Type__c, Group__pc
            FROM Account WHERE Id = :accountId WITH SYSTEM_MODE
        ];
        if (accounts.isEmpty()) {
            return null;
        }
        if (!LoWsPartnerTagService.isTagMode() || LoWsPartnerTagService.isPartner(accounts[0])) {
            return KIND_PARTNER;
        }
        return isPastClient(accounts[0]) ? KIND_CLIENT : KIND_CONSUMER;
    }

    private static Boolean isPastClient(Account accountRecord) {
        if ((accountRecord.Group__pc != null && accountRecord.Group__pc.split(';').contains('Client'))
            || accountRecord.Type__c == 'Borrower Account') {
            return true;
        }
        Id accountId = accountRecord.Id;
        return [SELECT COUNT() FROM Transaction__c WHERE Borrower_Name__c = :accountId WITH SYSTEM_MODE] > 0
            || [SELECT COUNT() FROM Lead WHERE ConvertedAccountId = :accountId WITH SYSTEM_MODE] > 0;
    }

    private static Boolean isClosedLoan(String status) {
        return LoWsPartnerTagService.CLOSED_STATUSES.contains(status);
    }

    /** The category a log against this contact credits when the LO doesn't choose one. */
    public static String defaultActivityKey(Id recordId, String kind, String channel) {
        if (kind == KIND_PARTNER) {
            return isMeetingChannel(channel) ? 'partner-meeting' : 'realtor-outreach';
        }
        if (recordId != null && recordId.getSObjectType() == Transaction__c.SObjectType) {
            List<Transaction__c> loans = [SELECT Status__c FROM Transaction__c WHERE Id = :recordId WITH SYSTEM_MODE];
            return !loans.isEmpty() && isClosedLoan(loans[0].Status__c) ? 'past-client-call' : 'consumer-conversation';
        }
        return defaultKeyFor(kind);
    }

    private static String defaultKeyFor(String kind) {
        return kind == KIND_PARTNER ? 'realtor-outreach'
            : kind == KIND_CLIENT ? 'past-client-call'
            : 'consumer-conversation';
    }

    private static void requireMatchingCategory(ExternalLoActivityCatalog.ActivityDefinition activity, String kind) {
        Set<String> allowed = KINDS_FOR_ACTIVITY.get(activity.activityKey);
        // Categories that need no contact (Social posts) and unknown kinds are not checked.
        if (allowed == null || activity.requiresContact != true || kind == null || allowed.contains(kind)) {
            return;
        }
        ExternalLoActivityCatalog.ActivityDefinition suggestion = ExternalLoActivityCatalog.activityByKey(defaultKeyFor(kind));
        throw new DomainException(
            activity.shortLabel + ' must be logged against ' + ACTIVITY_TARGET.get(activity.activityKey) + '.'
            + (suggestion == null ? '' : ' Pick ' + suggestion.shortLabel + ' for ' + KIND_NOUN.get(kind) + '.')
        );
    }

    /**
     * LO Workspace users may only log against records they can open. Partner Workspace users keep the
     * portal's own scoping (its partner list is not modelled by Account sharing).
     */
    public static void requireLoggable(Id recordId) {
        if (recordId != null && UserInfo.getUserType() == 'Standard') {
            RecordAccessGuard.requireRead(recordId);
        }
    }

    /**
     * Copies the log's notes to an Enhanced_Note__c on the Lead, loan or Account, the same row
     * /apex/AddNewNote creates (Type Note), so it shows on the record's Notes tab. ExternalLoStampEnhancedNote
     * stamps External_LO__c. LO Workspace (tag mode) only: the portal has no Notes tab.
     */
    public static void addNote(Id recordId, String subject, String notes) {
        if (!writesNote(recordId, notes)) {
            return;
        }
        Enhanced_Note__c note = new Enhanced_Note__c(
            Type__c = 'Note',
            Subject__c = subject.left(255),
            Body__c = notes.trim().escapeHtml4().replace('\r\n', '\n').replace('\n', '<br>')
        );
        SObjectType objectType = recordId.getSObjectType();
        if (objectType == Lead.SObjectType) {
            note.Lead__c = recordId;
        } else if (objectType == Transaction__c.SObjectType) {
            note.Transaction__c = recordId;
        } else {
            note.Account__c = recordId;
        }
        // Owner decision: a logged activity's note must not email the Lead Owner / Loan Partner.
        LeadNoteTeamNotifier.suppressForLoggedActivity = true;
        try {
            insert note;
        } finally {
            LeadNoteTeamNotifier.suppressForLoggedActivity = false;
        }
    }

    /**
     * True when addNote will write the note. The caller then sets Task.Create_Enhanced_Note__c = false
     * so flow Create_Enhanced_Note_on_New_Task doesn't add its own (Type Call) copy: one note per log.
     */
    public static Boolean writesNote(Id recordId, String notes) {
        if (recordId == null || String.isBlank(notes) || !LoWsPartnerTagService.isTagMode()) {
            return false;
        }
        SObjectType objectType = recordId.getSObjectType();
        return objectType == Lead.SObjectType || objectType == Transaction__c.SObjectType || objectType == Account.SObjectType;
    }



    public static String channelLabel(String channel) {
        switch on channel {
            when 'call' { return 'Call'; }
            when 'text' { return 'Text'; }
            when 'email' { return 'Email'; }
            when 'meeting' { return 'Meeting'; }
            when 'in-person' { return 'In person'; }
            when 'video' { return 'Video'; }
            when 'open-house' { return 'Open house'; }
            when else { return 'Activity'; }
        }
    }

    /** Task.Type is the dedicated channel field the Logged calls list reads (never Subject). */
    public static String taskTypeFor(String channel) {
        return channel == 'call' ? 'Call' : isMeetingChannel(channel) ? 'Meeting' : null;
    }

    private static Boolean isMeetingChannel(String channel) {
        return channel == 'meeting' || channel == 'in-person' || channel == 'video';
    }

    private static void validate(LogRequest request) {
        if (request == null || String.isBlank(request.activityKey)) {
            throw new DomainException('Choose an activity category to log.');
        }
        if (request.recordId != null && !String.isBlank(request.objectApiName)
            && !LOGGABLE_OBJECTS.contains(request.objectApiName)) {
            throw new DomainException('Log against a lead, partner, or loan record.');
        }
    }

    /**
     * Activity_Type__c from the channel and who was contacted. The channel's default types are agent
     * types (Call - Active Agent, Meeting (Active Agent)); for a lead, borrower or past client this
     * picks the category's own non-agent credit type of the same channel (Call - Prospecting), or
     * none. Goal credit itself comes from Activity_Category__c (ExternalLoActivityRollupBuilder).
     */
    public static String resolveActivityType(
        ExternalLoActivityCatalog.ActivityDefinition activity,
        String channel,
        String kind
    ) {
        String mapped = channelActivityType(channel);
        if (String.isBlank(mapped)) {
            return ExternalLoActivityCatalog.activityTypeForCategory(activity.categoryApiName);
        }
        if (kind == null || kind == KIND_PARTNER || !mapped.contains('Agent')) {
            return mapped;
        }
        String prefix = mapped.substringBefore(' ');
        for (String creditType : activity.creditActivityTypes ?? new List<String>()) {
            if (creditType.startsWith(prefix) && !creditType.contains('Agent')) {
                return creditType;
            }
        }
        return null;
    }

    private static String channelActivityType(String channel) {
        if (String.isBlank(channel)) {
            return null;
        }
        switch on channel {
            when 'call' {
                return 'Call - Active Agent';
            }
            when 'text' {
                return 'Text';
            }
            when 'email' {
                return 'Email';
            }
            when 'meeting', 'in-person', 'video' {
                return 'Meeting (Active Agent)';
            }
            when 'open-house' {
                return 'Open House';
            }
            when else {
                return null;
            }
        }
    }

    private static String buildSubject(ExternalLoActivityCatalog.ActivityDefinition activity, Integer countValue) {
        if (countValue > 1) {
            return '+' + String.valueOf(countValue) + ' ' + activity.unitNoun;
        }
        return activity.shortLabel;
    }

    private static void assignRelated(Task taskRecord, LogRequest request) {
        if (request == null || request.recordId == null) {
            return;
        }
        if (request.objectApiName == 'Lead' || request.objectApiName == 'Contact') {
            taskRecord.WhoId = request.recordId;
        } else {
            taskRecord.WhatId = request.recordId;
        }
    }

    // ------------------------------------------------------------------ lead status from a logged call

    /** Outcomes meaning the LO spoke with the lead; NO_CONTACT_OUTCOMES are attempts. Others don't move status. */
    private static final Set<String> REACHED_OUTCOMES = new Set<String>{
        'reached', 'connected', 'meeting-set', 'application-started', 'not-interested'
    };
    private static final Set<String> NO_CONTACT_OUTCOMES = new Set<String>{ 'left-voicemail', 'no-answer' };
    private static final String CONTACT_ATTEMPT = 'Contact Attempt ';

    public class LeadProgress {
        public String newStatus;
        public String warning;
        public String suffix() {
            if (newStatus != null) {
                return ' — lead moved to ' + newStatus + '.';
            }
            return warning == null ? '.' : '. ' + warning;
        }
    }

    /**
     * LO Workspace only (tag mode): after a Call is logged against a Lead, move it forward.
     * Reached: New / Contact Attempt N -> Working. Not reached: New -> Contact Attempt 1, Contact Attempt k -> k+1,
     * capped at the highest active Contact Attempt value. Never moves any other status (Working and later,
     * Pre-Approval, Nurture*, converted). Runs after the log Task insert, in system mode; a refusal keeps the log
     * and comes back as a warning.
     */
    public static LeadProgress progressLeadAfterCall(Id recordId, String channel, String outcome) {
        LeadProgress progress = new LeadProgress();
        if (recordId == null || recordId.getSObjectType() != Lead.SObjectType || channel != 'call'
            || String.isBlank(outcome) || !LoWsPartnerTagService.isTagMode()) {
            return progress;
        }
        List<Lead> leads = [SELECT Status, IsConverted FROM Lead WHERE Id = :recordId WITH SYSTEM_MODE];
        if (leads.isEmpty() || leads[0].IsConverted) {
            return progress;
        }
        String target = nextLeadStatus(leads[0].Status, outcome, maxContactAttempt());
        if (target == null) {
            return progress;
        }
        Database.SaveResult saved = Database.update(new Lead(Id = recordId, Status = target), false, AccessLevel.SYSTEM_MODE);
        if (saved.isSuccess()) {
            progress.newStatus = target;
        } else {
            List<String> messages = new List<String>();
            for (Database.Error error : saved.getErrors()) {
                messages.add(error.getMessage());
            }
            progress.warning = 'The lead status was not changed: ' + String.join(messages, ' ');
        }
        return progress;
    }

    @TestVisible
    static String nextLeadStatus(String current, String outcome, Integer maxAttempt) {
        Integer attempt = current != null && current.startsWith(CONTACT_ATTEMPT)
            && current.substringAfter(CONTACT_ATTEMPT).isNumeric()
            ? Integer.valueOf(current.substringAfter(CONTACT_ATTEMPT))
            : null;
        if (current != 'New' && attempt == null) {
            return null;
        }
        if (REACHED_OUTCOMES.contains(outcome)) {
            return 'Working';
        }
        if (NO_CONTACT_OUTCOMES.contains(outcome)) {
            Integer next = attempt == null ? 1 : attempt + 1;
            return next <= maxAttempt ? CONTACT_ATTEMPT + next : null;
        }
        return null;
    }

    /** Highest active "Contact Attempt N" Lead Status (6 today). */
    private static Integer maxContactAttempt() {
        Integer max = 0;
        for (Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            String value = entry.getValue();
            if (entry.isActive() && value.startsWith(CONTACT_ATTEMPT) && value.substringAfter(CONTACT_ATTEMPT).isNumeric()) {
                max = Math.max(max, Integer.valueOf(value.substringAfter(CONTACT_ATTEMPT)));
            }
        }
        return max;
    }

    public static final String FOLLOW_UP_ROW_PREFIX = 'task:';

    @TestVisible
    static Id followUpTaskIdFrom(String promptKey) {
        if (String.isBlank(promptKey) || !promptKey.trim().startsWith(FOLLOW_UP_ROW_PREFIX)) {
            return null;
        }
        try {
            Id taskId = Id.valueOf(promptKey.trim().substringAfter(FOLLOW_UP_ROW_PREFIX));
            if (taskId.getSObjectType() == Task.SObjectType) {
                return taskId;
            }
        } catch (Exception badId) {
            // fall through
        }
        throw new DomainException('That follow-up could not be found. Refresh Perfect Day and try again.');
    }

    /** Completes my own open follow-up Task (stamped today, like Mark complete). Someone else's is refused. */
    private static void completeFollowUpTask(Id userId, Id taskId) {
        if (taskId == null) {
            return;
        }
        List<Task> rows = [SELECT Id, OwnerId, IsClosed FROM Task WHERE Id = :taskId WITH SYSTEM_MODE];
        if (rows.isEmpty() || rows[0].OwnerId != userId) {
            throw new DomainException('That follow-up could not be found. Refresh Perfect Day and try again.');
        }
        if (rows[0].IsClosed) {
            return;
        }
        Database.update(new List<Task>{ new Task(Id = taskId, Status = 'Completed', ActivityDate = Date.today()) }, AccessLevel.SYSTEM_MODE);
    }

    private static void completeMatchingPromptTask(Id userId, String promptKey) {
        Task openPrompt = new TaskRepository().selectOpenPromptTask(userId, promptKey);
        if (openPrompt == null) {
            return;
        }
        Task updateShell = new Task(
            Id = openPrompt.Id,
            Status = 'Completed',
            ActivityDate = Date.today()
        );
        Database.update(new List<Task>{ updateShell }, AccessLevel.SYSTEM_MODE);
    }

    public class LogRequest {
        @AuraEnabled public String activityKey;
        @AuraEnabled public String channel;
        @AuraEnabled public Integer activityCount;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String notes;
        @AuraEnabled public String promptKey;
        /** none | tomorrow | 3-days | next-week | date:YYYY-MM-DD | exact:<ISO datetime>. Blank = none. */
        @AuraEnabled public String followUpOption;
        /** Call outcome on a Lead (reached | left-voicemail | no-answer); drives the lead status move. */
        @AuraEnabled public String callOutcome;
    }

    public class LogResult {
        @AuraEnabled public Id taskId;
        @AuraEnabled public Id followUpId;
        /** Set when a logged call should have moved the lead's status but Salesforce refused it. */
        @AuraEnabled public String statusWarning;
        @AuraEnabled public String userMessage;
        @AuraEnabled public String activityKey;
        @AuraEnabled public Integer activityCount;
    }

    public class SearchHit {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        /** The category picking this contact selects in the modal. */
        @AuraEnabled public String activityKey;
        /** Contact-bound categories this contact may be logged as. */
        @AuraEnabled public List<String> allowedKeys;
    }
}