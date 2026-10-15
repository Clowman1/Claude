/**
 * Builds up to eight computed activity prompts. Open snooze Tasks hide a
 * prompt until their due date. Completed Tasks with the same Prompt_Key__c
 * hide escrow / past-client forever for that record, and
 * hide milestone / recurring-partner for the current Monday–Sunday week.
 */
public with sharing class ExternalLoPromptService {
    public static final Integer MAX_PROMPTS = 8;

    public class PromptItem {
        @AuraEnabled public String promptKey;
        @AuraEnabled public String triggerType;
        @AuraEnabled public String title;
        @AuraEnabled public String script;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String contactName;
        @AuraEnabled public String reason;
        @AuraEnabled public String activityKey;
        @AuraEnabled public Boolean canLog;
        @AuraEnabled public Boolean canSnooze;
        /** Set on follow-up rows: the open Task that "Mark complete" closes and "Tomorrow" moves. */
        @AuraEnabled public Id taskId;
        @AuraEnabled public Boolean canComplete;
        /** High alert: the borrower uploaded documents waiting for this LO to review. */
        @AuraEnabled public Boolean canReview;
        @AuraEnabled public Boolean isHighAlert;
        /** Open all modal only: overdue / today / upcoming, and touch / task / appt / review / other. */
        @AuraEnabled public String upNextGroup;
        @AuraEnabled public String kind;
        /** comms-settings: a reply to an automated text (LoWsTextsService.replyPrompts). Open goes to openView, Texts. */
        @AuraEnabled public Boolean isTextReply;
        @AuraEnabled public Id messageId;
        @AuraEnabled public String openView;
    }

    /**
     * Open Tasks due today or overdue, as Up Next rows (they go ahead of the computed prompts).
     * The title comes from the related record, never Subject (org automation rewrites it on update).
     */
    private static final Set<String> LOGGABLE = new Set<String>{ 'Lead', 'Account', 'Transaction__c', 'Contact' };

    /**
     * HIGH ALERT rows: my leads with borrower uploads waiting for review (Lead_Document_Request__c
     * Status Review). One row per lead, ahead of everything else; Review documents opens the lead's
     * Document requests tab. They leave Up Next once every item is reviewed.
     */
    public static List<PromptItem> documentReviewPrompts(Id ownerId) {
        List<PromptItem> items = new List<PromptItem>();
        for (AggregateResult row : [
            SELECT Lead__c leadId, Lead__r.Name leadName, COUNT(Id) total
            FROM Lead_Document_Request__c
            WHERE Status__c = 'Review' AND Lead__r.OwnerId = :ownerId AND Lead__r.IsConverted = false
            WITH SYSTEM_MODE
            GROUP BY Lead__c, Lead__r.Name
            ORDER BY COUNT(Id) DESC
            LIMIT 8
        ]) {
            Integer total = (Integer) row.get('total');
            String name = (String) row.get('leadName');
            PromptItem item = item(
                'review:' + (Id) row.get('leadId'),
                'document-review',
                'Review documents: ' + name,
                total + (total == 1 ? ' document request has' : ' document requests have') + ' new borrower uploads waiting for your review.',
                (Id) row.get('leadId'),
                'Lead',
                name,
                'High alert · Documents received for review',
                null
            );
            item.canLog = false;
            item.canSnooze = false;
            item.canReview = true;
            item.isHighAlert = true;
            items.add(item);
        }
        return items;
    }

    public static List<PromptItem> followUpPrompts(List<Task> dueTasks) {
        List<PromptItem> items = new List<PromptItem>();
        if (dueTasks == null) {
            return items;
        }
        Date today = Date.today();
        for (Task t : dueTasks) {
            Boolean useWho = t.WhoId != null && (t.Who.Type == 'Lead' || t.WhatId == null);
            Id relatedId = useWho ? t.WhoId : t.WhatId;
            String relatedName = relatedId == null ? null : (useWho ? t.Who.Name : t.What.Name);
            String objectApiName = relatedId == null ? null : String.valueOf(relatedId.getSObjectType());
            PromptItem row = item(
                'task:' + t.Id,
                'follow-up',
                relatedName == null ? t.Subject : 'Follow up with ' + relatedName,
                t.Description,
                relatedId,
                objectApiName,
                relatedName,
                t.ActivityDate == today ? 'Follow-up due today' : 'Overdue · was due ' + t.ActivityDate.format(),
                // A starting category only; the log modal and server still check it against the contact.
                objectApiName == 'Account' ? 'realtor-outreach' : 'consumer-conversation'
            );
            row.canLog = LOGGABLE.contains(objectApiName);
            row.taskId = t.Id;
            row.canComplete = true;
            items.add(row);
        }
        return items;
    }

    public class PromptContext {
        public List<Transaction__c> milestoneLoans;
        public List<Account> realtorAccounts;
        public Map<Id, Datetime> lastTouchByAccountId;
        public List<Lead> pastClientLeads;
        public List<Transaction__c> fundedLoans;
        public Set<String> snoozedKeys;
        /** Pre-approvals due a weekly touch, longest without a touch first. */
        public List<Lead> touchDueLeads;
        public Map<Id, LoWsTouchService.Touch> touches;
    }

    /** Pre-approvals due a weekly touch, sorted longest-untouched first; fills context.touches. */
    public static List<Lead> touchDueLeads(List<Lead> preApprovals, PromptContext context) {
        Map<Id, LoWsTouchService.Touch> touches = LoWsTouchService.touchesFor(preApprovals);
        context.touches = touches;
        List<Lead> due = new List<Lead>();
        // ponytail: insertion sort by days since touch; per-LO pre-approval lists are small.
        for (Lead l : preApprovals == null ? new List<Lead>() : preApprovals) {
            LoWsTouchService.Touch t = touches.get(l.Id);
            if (t == null || t.due != true) {
                continue;
            }
            Integer i = 0;
            while (i < due.size() && touches.get(due[i].Id).daysSince >= t.daysSince) {
                i++;
            }
            if (i == due.size()) {
                due.add(l);
            } else {
                due.add(i, l);
            }
        }
        return due;
    }

    /**
     * Loads prompt sources for the running user and returns the ranked list.
     */
    public static List<PromptItem> getPrompts(Id userId) {
        return build(loadContext(userId));
    }

    private static PromptContext loadContext(Id userId) {
        PromptContext context = new PromptContext();
        LeadRepository leads = LeadRepository.getInstance();
        context.touchDueLeads = touchDueLeads(leads.selectPreApprovalsToReview(userId), context);
        ExternalLoPromptSelector promptSelector = new ExternalLoPromptSelector();
        context.pastClientLeads = leads.selectPastClientLeadsByOwner(userId);
        context.milestoneLoans = LoanRepository.getInstance().selectLoansNeedingMilestoneUpdates(userId);
        context.fundedLoans = promptSelector.selectFundedLoansByOfficer(userId);
        context.realtorAccounts = new PersonAccountRepository().selectRealtorPartnersByOwner(userId);
        context.lastTouchByAccountId = new TaskRepository().selectLastActivityDatetimeByWhatIds(
            new Map<Id, Account>(context.realtorAccounts).keySet(),
            userId
        );
        context.snoozedKeys = snoozedKeysFor(userId);
        return context;
    }

    /**
     * Everything for the Up Next "Open all" modal, uncapped: document reviews, follow-ups due or
     * overdue, weekly touches, the computed prompts, then tasks and appointments in the next 7 days.
     */
    public static List<PromptItem> getAllUpNext(Id userId) {
        PromptContext context = loadContext(userId);
        Date today = Date.today();
        List<PromptItem> rows = new List<PromptItem>();

        for (PromptItem item : LoWsTextsService.replyPrompts(userId)) {
            rows.add(tag(item, 'today', 'reply'));
        }
        for (PromptItem item : documentReviewPrompts(userId)) {
            rows.add(tag(item, 'today', 'review'));
        }
        List<Task> dueTasks = new TaskRepository().selectOpenDueTasksByOwner(userId, 200);
        List<PromptItem> followUps = followUpPrompts(dueTasks);
        for (Integer i = 0; i < followUps.size(); i++) {
            rows.add(tag(followUps[i], dueTasks[i].ActivityDate != null && dueTasks[i].ActivityDate < today ? 'overdue' : 'today', 'task'));
        }
        for (PromptItem item : touchPrompts(context.touchDueLeads, context.touches, context.snoozedKeys)) {
            Integer days = context.touches.get(item.recordId).daysSince;
            rows.add(tag(item, days > LoWsTouchService.TOUCH_DAYS ? 'overdue' : 'today', 'touch'));
        }
        context.touchDueLeads = null; // already listed above
        for (PromptItem item : build(context, false)) {
            rows.add(tag(item, 'today', 'other'));
        }

        for (Task t : [
            SELECT Id, Subject, ActivityDate, WhoId, Who.Name, Who.Type, WhatId, What.Name
            FROM Task
            WHERE OwnerId = :userId AND IsClosed = false
              AND ActivityDate > :today AND ActivityDate <= :today.addDays(7)
            WITH SYSTEM_MODE
            ORDER BY ActivityDate ASC
            LIMIT 100
        ]) {
            Boolean useWho = t.WhoId != null && (t.Who.Type == 'Lead' || t.WhatId == null);
            Id relatedId = useWho ? t.WhoId : t.WhatId;
            String name = relatedId == null ? null : (useWho ? t.Who.Name : t.What.Name);
            PromptItem row = item('task:' + t.Id, 'follow-up',
                name == null ? t.Subject : 'Follow up with ' + name, null, relatedId,
                relatedId == null ? null : String.valueOf(relatedId.getSObjectType()), name,
                'Task · due ' + t.ActivityDate.format(), null);
            rows.add(tag(row, 'upcoming', 'task'));
        }
        Datetime now = System.now();
        for (Event e : [
            SELECT Id, Subject, StartDateTime, WhoId, Who.Name, WhatId, What.Name
            FROM Event
            WHERE OwnerId = :userId AND StartDateTime >= :now AND StartDateTime <= :now.addDays(7)
            WITH SYSTEM_MODE
            ORDER BY StartDateTime ASC
            LIMIT 100
        ]) {
            Id relatedId = e.WhoId ?? e.WhatId;
            String name = e.WhoId != null ? e.Who.Name : (e.WhatId != null ? e.What.Name : null);
            PromptItem row = item('event:' + e.Id, 'appointment',
                String.isBlank(e.Subject) ? 'Appointment' : e.Subject, null, relatedId,
                relatedId == null ? null : String.valueOf(relatedId.getSObjectType()), name,
                'Appointment · ' + e.StartDateTime.format('EEE MMM d, h:mm a'), null);
            rows.add(tag(row, 'upcoming', 'appt'));
        }
        for (PromptItem row : rows) {
            row.canLog = false;
            row.canSnooze = false;
            row.canComplete = false;
            row.canReview = false;
        }
        return rows;
    }

    private static PromptItem tag(PromptItem item, String upNextGroup, String kind) {
        item.upNextGroup = upNextGroup;
        item.kind = kind;
        return item;
    }

    private static List<PromptItem> touchPrompts(
        List<Lead> leads,
        Map<Id, LoWsTouchService.Touch> touches,
        Set<String> snoozed
    ) {
        List<PromptItem> items = new List<PromptItem>();
        if (leads == null || touches == null) {
            return items;
        }
        for (Lead leadRecord : leads) {
            String promptKey = 'weekly-touch:' + leadRecord.Id;
            if (snoozed.contains(promptKey)) {
                continue;
            }
            LoWsTouchService.Touch t = touches.get(leadRecord.Id);
            String since = t?.lastTouch == null ? 'No touch yet' : 'Last touch ' + t.daysSince + ' days ago';
            items.add(item(
                promptKey,
                'weekly-touch',
                'Weekly touch: ' + leadRecord.Name,
                'A quick call, text or email keeps this pre-approved buyer shopping with you.',
                leadRecord.Id,
                'Lead',
                leadRecord.Name,
                (t != null && t.daysSince > LoWsTouchService.TOUCH_DAYS ? 'Overdue · ' : 'Due today · ') + since,
                'consumer-conversation'
            ));
        }
        return items;
    }

    /**
     * Open snooze keys plus completed prompt keys that should stay hidden.
     */
    public static Set<String> snoozedKeysFor(Id userId) {
        return suppressedKeysFrom(new TaskRepository().selectPromptTasksByOwner(userId), Date.today());
    }

    /**
     * escrow-analysis, past-client, and under-contract stay hidden for that
     * record after a completed log. milestone and recurring-partner hide only
     * for the current week so they can fire again next period.
     */
    @TestVisible
    static Set<String> suppressedKeysFrom(List<Task> promptTasks, Date today) {
        Set<String> keys = new Set<String>();
        if (promptTasks == null) {
            return keys;
        }
        Date weekStart = ExternalLoGoalMath.weekStartMonday(today);
        Date weekEnd = ExternalLoGoalMath.weekEndSunday(today);
        for (Task taskRecord : promptTasks) {
            if (String.isBlank(taskRecord.Prompt_Key__c)) {
                continue;
            }
            if (!isClosedPrompt(taskRecord)) {
                keys.add(taskRecord.Prompt_Key__c);
                continue;
            }
            String promptKey = taskRecord.Prompt_Key__c;
            if (isForeverTrigger(promptKey)) {
                keys.add(promptKey);
                continue;
            }
            if (isPeriodTrigger(promptKey)) {
                Date stamp = taskRecord.ActivityDate == null ? today : taskRecord.ActivityDate;
                if (stamp >= weekStart && stamp <= weekEnd) {
                    keys.add(promptKey);
                }
            }
        }
        return keys;
    }

    private static Boolean isClosedPrompt(Task taskRecord) {
        return taskRecord.IsClosed == true || taskRecord.Status == 'Completed';
    }

    private static Boolean isForeverTrigger(String promptKey) {
        return promptKey.startsWith('escrow-analysis:')
            || promptKey.startsWith('past-client:')
            || promptKey.startsWith('under-contract:');
    }

    private static Boolean isPeriodTrigger(String promptKey) {
        return promptKey.startsWith('milestone:')
            || promptKey.startsWith('recurring-partner:');
    }

    /**
     * Ranked prompts from already-loaded lists. Safe to call from getHomeData.
     */
    public static List<PromptItem> build(PromptContext context) {
        return build(context, true);
    }

    /** capped = the Up Next card (per-type caps, MAX_PROMPTS total); uncapped = the Open all modal. */
    public static List<PromptItem> build(PromptContext context, Boolean capped) {
        List<PromptItem> items = new List<PromptItem>();
        Set<String> snoozed = context?.snoozedKeys == null ? new Set<String>() : context.snoozedKeys;
        Integer max = capped ? MAX_PROMPTS : 100000;
        addAll(items, touchPrompts(context?.touchDueLeads, context?.touches, snoozed), capped ? 3 : max, max);
        addAll(items, milestonePrompts(context?.milestoneLoans, snoozed), capped ? 2 : max, max);
        addAll(items, partnerPrompts(context?.realtorAccounts, context?.lastTouchByAccountId, snoozed), capped ? 2 : max, max);
        addAll(items, pastClientPrompts(context?.pastClientLeads, context?.fundedLoans, snoozed), capped ? 1 : max, max);
        addAll(items, escrowPrompts(context?.fundedLoans, snoozed), capped ? 1 : max, max);
        if (items.size() > max) {
            List<PromptItem> clipped = new List<PromptItem>();
            for (Integer i = 0; i < max; i++) {
                clipped.add(items[i]);
            }
            return clipped;
        }
        return items;
    }

    private static void addAll(List<PromptItem> sink, List<PromptItem> source, Integer cap, Integer max) {
        if (source == null) {
            return;
        }
        Integer added = 0;
        for (PromptItem item : source) {
            if (added >= cap || sink.size() >= max) {
                return;
            }
            sink.add(item);
            added++;
        }
    }

    private static List<PromptItem> milestonePrompts(List<Transaction__c> loans, Set<String> snoozed) {
        List<PromptItem> items = new List<PromptItem>();
        if (loans == null) {
            return items;
        }
        for (Transaction__c loanRecord : loans) {
            String promptKey = 'milestone:' + loanRecord.Id;
            if (snoozed.contains(promptKey)) {
                continue;
            }
            String urgency = ExternalLOBaselineHelper.loanMilestoneUrgency(loanRecord);
            if (String.isBlank(urgency)) {
                continue;
            }
            String borrower = String.isBlank(loanRecord.Name) ? 'this loan' : loanRecord.Name;
            items.add(item(
                promptKey,
                'milestone',
                'Update ' + borrower,
                'This loan is Waiting On Loan Officer. Check what the processor needs.',
                loanRecord.Id,
                'Transaction__c',
                borrower,
                'Needs update',
                'consumer-conversation'
            ));
        }
        return items;
    }

    private static List<PromptItem> partnerPrompts(
        List<Account> accounts,
        Map<Id, Datetime> lastTouchByAccountId,
        Set<String> snoozed
    ) {
        List<PromptItem> items = new List<PromptItem>();
        if (accounts == null) {
            return items;
        }
        Map<Id, Datetime> lastTouch = lastTouchByAccountId == null
            ? new Map<Id, Datetime>()
            : lastTouchByAccountId;
        for (Account accountRecord : accounts) {
            String promptKey = 'recurring-partner:' + accountRecord.Id;
            if (snoozed.contains(promptKey)) {
                continue;
            }
            String urgency = ExternalLOBaselineHelper.realtorFollowUpUrgency(lastTouch.get(accountRecord.Id));
            if (String.isBlank(urgency)) {
                continue;
            }
            items.add(item(
                promptKey,
                'recurring-partner',
                'Touch base with ' + accountRecord.Name,
                'A quick call or drop-by keeps this partner from going quiet.',
                accountRecord.Id,
                'Account',
                accountRecord.Name,
                'Partner follow-up is due',
                'realtor-outreach'
            ));
        }
        return items;
    }

    private static List<PromptItem> pastClientPrompts(
        List<Lead> pastClients,
        List<Transaction__c> fundedLoans,
        Set<String> snoozed
    ) {
        List<PromptItem> items = new List<PromptItem>();
        Set<Integer> anniversaryMonths = anniversaryMonths(fundedLoans);
        if (pastClients == null) {
            return items;
        }
        Date today = Date.today();
        for (Lead leadRecord : pastClients) {
            String promptKey = 'past-client:' + leadRecord.Id;
            if (snoozed.contains(promptKey)) {
                continue;
            }
            Boolean anniversary = anniversaryMonths.contains(today.month());
            if (!anniversary && leadRecord.LastActivityDate != null
                && leadRecord.LastActivityDate.daysBetween(today) < 60) {
                continue;
            }
            items.add(item(
                promptKey,
                'past-client',
                'Call ' + leadRecord.Name,
                anniversary
                    ? 'Closing anniversary is this month. Ask how the home is treating them and if anyone they know is buying.'
                    : 'It has been a while. A short past-client call keeps you first in mind.',
                leadRecord.Id,
                'Lead',
                leadRecord.Name,
                anniversary ? 'Closing anniversary' : 'Past client follow-up',
                'past-client-call'
            ));
        }
        return items;
    }

    private static List<PromptItem> escrowPrompts(List<Transaction__c> fundedLoans, Set<String> snoozed) {
        List<PromptItem> items = new List<PromptItem>();
        if (fundedLoans == null) {
            return items;
        }
        Date today = Date.today();
        Date windowStart = today.addMonths(-13);
        Date windowEnd = today.addMonths(-11);
        for (Transaction__c loanRecord : fundedLoans) {
            if (loanRecord.Funded_Date__c == null
                || loanRecord.Funded_Date__c < windowStart
                || loanRecord.Funded_Date__c > windowEnd) {
                continue;
            }
            String promptKey = 'escrow-analysis:' + loanRecord.Id;
            if (snoozed.contains(promptKey)) {
                continue;
            }
            String borrower = loanRecord.Borrower_Name__r == null
                ? loanRecord.Name
                : loanRecord.Borrower_Name__r.Name;
            items.add(item(
                promptKey,
                'escrow-analysis',
                'Review escrow for ' + borrower,
                'They funded about a year ago. Offer an escrow analysis before the tax bill surprises them.',
                loanRecord.Id,
                'Transaction__c',
                borrower,
                '11–13 months after funding',
                'past-client-call'
            ));
        }
        return items;
    }

    private static Set<Integer> anniversaryMonths(List<Transaction__c> fundedLoans) {
        Set<Integer> months = new Set<Integer>();
        if (fundedLoans == null) {
            return months;
        }
        Integer thisMonth = Date.today().month();
        for (Transaction__c loanRecord : fundedLoans) {
            if (loanRecord.Funded_Date__c != null && loanRecord.Funded_Date__c.month() == thisMonth) {
                months.add(thisMonth);
            }
        }
        return months;
    }

    private static PromptItem item(
        String promptKey,
        String triggerType,
        String title,
        String script,
        Id recordId,
        String objectApiName,
        String contactName,
        String reason,
        String activityKey
    ) {
        PromptItem row = new PromptItem();
        row.promptKey = promptKey;
        row.triggerType = triggerType;
        row.title = title;
        row.script = script;
        row.recordId = recordId;
        row.objectApiName = objectApiName;
        row.contactName = contactName;
        row.reason = reason;
        row.activityKey = activityKey;
        row.canLog = true;
        row.canSnooze = true;
        return row;
    }
}