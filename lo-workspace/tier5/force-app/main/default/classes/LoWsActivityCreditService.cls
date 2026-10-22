/**
 * Perfect Day credit by WHO was contacted (owner rules, 2026-10-21). A completed Task with no
 * Activity_Category__c earns: an open consumer Lead -> consumer-conversation; a borrower with a
 * closed loan -> past-client-call; a realtor (Group__pc, BD_Industry__c or the LO's tag) ->
 * realtor-outreach; anyone else -> nothing. The contact comes from WhoId/WhatId, else from the
 * RingCentral to-number. Meeting types still credit partner-meeting and other non-contact types
 * (social) still credit by Activity_Type__c. RingCentral Tasks count outbound only, and one within
 * 15 minutes of a manual log to the same person is dropped (the manual one is kept).
 * Bulk: at most 4 SOQL per pass; results are cached by Task Id for the transaction, and
 * TaskRepository registers its range rows so one pass covers today/week/month together.
 */
public with sharing class LoWsActivityCreditService {

    public static final String CONSUMER = 'consumer-conversation';
    public static final String PAST_CLIENT = 'past-client-call';
    public static final String REALTOR = 'realtor-outreach';
    public static final String PARTNER_MEETING = 'partner-meeting';
    static final Set<String> WHO_KEYS = new Set<String>{ CONSUMER, PAST_CLIENT, REALTOR };
    static final Set<String> RC_TYPES = new Set<String>{ 'Call', 'Sms' };
    static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Funding', 'PC Review', 'Post-Closed' };
    static final Set<String> REALTOR_GROUPS = new Set<String>{ 'Realtor', 'Realtor Prospect' };
    static final Set<String> NON_CONSUMER_LEAD_TYPES = new Set<String>{ 'Realtor_Lead_record_type', 'Loan_Officer_Lead_Record_Type' };
    static final Long DEDUPE_MS = 15 * 60 * 1000;

    static Map<Id, String> keyById = new Map<Id, String>();
    static List<Task> pending = new List<Task>();

    /** Queues rows so the next keysFor call classifies them in the same pass. */
    public static void register(List<Task> tasks) {
        if (tasks != null) {
            pending.addAll(tasks);
        }
    }

    /** True once the Task has been classified in this transaction. */
    public static Boolean isClassified(Id taskId) {
        return taskId != null && keyById.containsKey(taskId);
    }

    public static String classifiedKey(Id taskId) {
        return keyById.get(taskId);
    }

    /** Activity key per Task, parallel to tasks; null = no credit. */
    public static List<String> keysFor(List<Task> tasks) {
        if (tasks == null || tasks.isEmpty()) {
            return new List<String>();
        }
        for (Task t : tasks) {
            if (t.Id == null) {
                return classify(tasks); // unsaved rows (tests): not cached
            }
        }
        List<Task> todo = new List<Task>();
        Set<Id> queued = new Set<Id>();
        for (List<Task> source : new List<List<Task>>{ tasks, pending }) {
            for (Task t : source) {
                if (t.Id != null && !keyById.containsKey(t.Id) && queued.add(t.Id)) {
                    todo.add(t);
                }
            }
        }
        pending = new List<Task>();
        if (!todo.isEmpty()) {
            List<String> fresh = classify(todo);
            for (Integer i = 0; i < todo.size(); i++) {
                keyById.put(todo[i].Id, fresh[i]);
            }
        }
        List<String> keys = new List<String>();
        for (Task t : tasks) {
            keys.add(keyById.get(t.Id));
        }
        return keys;
    }

    static List<String> classify(List<Task> tasks) {
        Directory dir = new Directory(tasks);
        List<ExternalLoActivityCatalog.ActivityDefinition> catalog = ExternalLoActivityCatalog.activeActivities();
        List<String> keys = new List<String>();
        List<Id> people = new List<Id>();
        for (Task t : tasks) {
            Id person = null;
            String key = null;
            ExternalLoActivityCatalog.ActivityDefinition byCategory = String.isBlank(t.Activity_Category__c)
                ? null : ExternalLoActivityCatalog.activityByCategory(t.Activity_Category__c);
            if (byCategory != null) {
                key = byCategory.activityKey; // the workspace log form's explicit category wins
            } else if (!(isRingCentral(t) && t.CallType != 'Outbound') && t.CallType != 'Inbound') {
                String byType = typeKey(t, catalog);
                if (byType != PARTNER_MEETING && isContactActivity(t)) {
                    person = dir.personFor(t);
                    key = dir.keyFor(person, t.OwnerId);
                }
                key = key == null ? byType : key;
            }
            keys.add(key);
            people.add(key == null ? null : person);
        }
        dedupe(tasks, keys, people);
        return keys;
    }

    /**
     * A RingCentral Task to someone the LO also logged by hand within 15 minutes counts once (the
     * manual log). The same call logged twice by RingCentral (CTI + sync, same start time) counts once.
     */
    static void dedupe(List<Task> tasks, List<String> keys, List<Id> people) {
        Map<String, List<Datetime>> manualTimes = new Map<String, List<Datetime>>();
        for (Integer i = 0; i < tasks.size(); i++) {
            Datetime at = timeOf(tasks[i]);
            if (people[i] == null || isRingCentral(tasks[i]) || at == null) {
                continue;
            }
            String k = '' + tasks[i].OwnerId + '|' + people[i];
            if (!manualTimes.containsKey(k)) {
                manualTimes.put(k, new List<Datetime>());
            }
            manualTimes.get(k).add(at);
        }
        Set<String> seenCalls = new Set<String>();
        for (Integer i = 0; i < tasks.size(); i++) {
            Datetime at = timeOf(tasks[i]);
            if (people[i] == null || !isRingCentral(tasks[i]) || at == null) {
                continue;
            }
            String k = '' + tasks[i].OwnerId + '|' + people[i];
            if (!seenCalls.add(k + '|' + at.getTime())) {
                keys[i] = null;
                continue;
            }
            for (Datetime manualAt : manualTimes.containsKey(k) ? manualTimes.get(k) : new List<Datetime>()) {
                if (Math.abs(manualAt.getTime() - at.getTime()) <= DEDUPE_MS) {
                    keys[i] = null;
                    break;
                }
            }
        }
    }

    /** RingCentral sync (InteractionType__c) or its CTI call log (carries the rcsfl numbers). */
    static Boolean isRingCentral(Task t) {
        return RC_TYPES.contains(t.InteractionType__c) || String.isNotBlank(t.rcsfl__to_number__c);
    }

    /** Calls, texts and typed logs; emails and automation Tasks never earn contact credit. */
    static Boolean isContactActivity(Task t) {
        return isRingCentral(t) || t.TaskSubtype == 'Call' || String.isNotBlank(t.Activity_Type__c);
    }

    /** RingCentral rows are synced late, so use the call/text start time when present. */
    static Datetime timeOf(Task t) {
        return t.rcsfl__call_start_time__c != null ? t.rcsfl__call_start_time__c : t.CreatedDate;
    }

    /** Activity_Type__c credit for non-contact activities only (partner meetings, social). */
    static String typeKey(Task t, List<ExternalLoActivityCatalog.ActivityDefinition> catalog) {
        if (String.isBlank(t.Activity_Type__c)) {
            return null;
        }
        for (ExternalLoActivityCatalog.ActivityDefinition item : catalog) {
            if (!WHO_KEYS.contains(item.activityKey)
                && item.creditActivityTypes != null
                && item.creditActivityTypes.contains(t.Activity_Type__c)) {
                return item.activityKey;
            }
        }
        return null;
    }

    /** Leads, accounts, closed-loan borrowers and the LOs' tags behind one pass of Tasks. */
    class Directory {
        Map<Id, Lead> leads = new Map<Id, Lead>();
        Map<Id, Account> accounts = new Map<Id, Account>();
        Map<Id, Id> accountByContact = new Map<Id, Id>();
        Set<Id> pastClients = new Set<Id>();
        Set<String> tags = new Set<String>(); // ownerId|contactId
        Map<String, List<Id>> byNumber = new Map<String, List<Id>>(); // open leads first, then accounts

        Directory(List<Task> tasks) {
            Set<Id> leadIds = new Set<Id>();
            Set<Id> contactIds = new Set<Id>();
            Set<Id> accountIds = new Set<Id>();
            Set<Id> ownerIds = new Set<Id>();
            Set<String> numbers = new Set<String>();
            for (Task t : tasks) {
                if (!String.isBlank(t.Activity_Category__c) || !isContactActivity(t)) {
                    continue;
                }
                ownerIds.add(t.OwnerId);
                Id who = whoOf(t);
                if (who == null) {
                    String n = ExternalLoPhoneNormalizer.matchKey(t.rcsfl__to_number__c);
                    if (n != null && t.CallType == 'Outbound') {
                        numbers.add(n);
                    }
                } else if (who.getSObjectType() == Lead.SObjectType) {
                    leadIds.add(who);
                } else if (who.getSObjectType() == Contact.SObjectType) {
                    contactIds.add(who);
                } else {
                    accountIds.add(who);
                }
            }
            Set<String> variants = ExternalLoPhoneNormalizer.soqlVariants(numbers);
            if (!leadIds.isEmpty() || !variants.isEmpty()) {
                for (Lead l : [
                    SELECT Id, OwnerId, IsConverted, ConvertedAccountId, RecordType.DeveloperName, Phone, MobilePhone
                    FROM Lead
                    WHERE Id IN :leadIds
                       OR (IsConverted = false AND (Phone IN :variants OR MobilePhone IN :variants))
                    WITH SYSTEM_MODE
                    LIMIT 2000
                ]) {
                    leads.put(l.Id, l);
                    if (l.ConvertedAccountId != null) {
                        accountIds.add(l.ConvertedAccountId);
                    }
                    if (!l.IsConverted) {
                        index(l.Id, new List<String>{ l.Phone, l.MobilePhone }, numbers);
                    }
                }
            }
            if (!accountIds.isEmpty() || !contactIds.isEmpty() || !variants.isEmpty()) {
                for (Account a : [
                    SELECT Id, OwnerId, PersonContactId, Group__pc, BD_Industry__c, Phone, PersonMobilePhone
                    FROM Account
                    WHERE Id IN :accountIds
                       OR PersonContactId IN :contactIds
                       OR (IsPersonAccount = true AND (Phone IN :variants OR PersonMobilePhone IN :variants))
                    WITH SYSTEM_MODE
                    LIMIT 2000
                ]) {
                    accounts.put(a.Id, a);
                    if (a.PersonContactId != null) {
                        accountByContact.put(a.PersonContactId, a.Id);
                        contactIds.add(a.PersonContactId);
                    }
                    index(a.Id, new List<String>{ a.Phone, a.PersonMobilePhone }, numbers);
                }
            }
            if (!accounts.isEmpty()) {
                Set<Id> borrowerIds = accounts.keySet();
                for (AggregateResult ar : [
                    SELECT Borrower_Name__c b
                    FROM Transaction__c
                    WHERE Borrower_Name__c IN :borrowerIds AND Status__c IN :CLOSED_STATUSES
                    WITH SYSTEM_MODE
                    GROUP BY Borrower_Name__c
                ]) {
                    pastClients.add((Id) ar.get('b'));
                }
            }
            if (!contactIds.isEmpty() && !ownerIds.isEmpty()) {
                for (External_User_Assignment__c tag : [
                    SELECT User__c, Contact__c
                    FROM External_User_Assignment__c
                    WHERE User__c IN :ownerIds AND Contact__c IN :contactIds
                    WITH SYSTEM_MODE
                ]) {
                    tags.add('' + tag.User__c + '|' + tag.Contact__c);
                }
            }
        }

        /** Only numbers asked for are indexed (a variant query can return near-misses). */
        void index(Id recordId, List<String> phones, Set<String> numbers) {
            for (String phone : phones) {
                String n = ExternalLoPhoneNormalizer.matchKey(phone);
                if (n == null || !numbers.contains(n)) {
                    continue;
                }
                if (!byNumber.containsKey(n)) {
                    byNumber.put(n, new List<Id>());
                }
                byNumber.get(n).add(recordId);
            }
        }

        /** Lead, Account or Contact the Task is about: WhoId/WhatId, else the number dialled. */
        Id personFor(Task t) {
            Id who = whoOf(t);
            if (who != null) {
                if (who.getSObjectType() == Lead.SObjectType) {
                    Lead l = leads.get(who);
                    return l != null && l.IsConverted ? l.ConvertedAccountId : who;
                }
                if (who.getSObjectType() == Contact.SObjectType && accountByContact.containsKey(who)) {
                    return accountByContact.get(who);
                }
                return who;
            }
            List<Id> matches = byNumber.get(ExternalLoPhoneNormalizer.matchKey(t.rcsfl__to_number__c));
            if (matches == null) {
                return null;
            }
            // Several people share the number: the LO's own (owned or tagged) creditable record wins.
            Id fallback = null;
            for (Id candidate : matches) {
                if (keyFor(candidate, t.OwnerId) == null) {
                    continue;
                }
                if (isMine(candidate, t.OwnerId)) {
                    return candidate;
                }
                fallback = fallback == null ? candidate : fallback;
            }
            return fallback;
        }

        Boolean isMine(Id recordId, Id ownerId) {
            if (leads.containsKey(recordId)) {
                return leads.get(recordId).OwnerId == ownerId;
            }
            Account a = accounts.get(recordId);
            return a != null && (a.OwnerId == ownerId || tags.contains('' + ownerId + '|' + a.PersonContactId));
        }

        String keyFor(Id recordId, Id ownerId) {
            if (recordId == null) {
                return null;
            }
            Lead l = leads.get(recordId);
            if (l != null) {
                if (l.IsConverted) {
                    return null;
                }
                // A Realtor-record-type lead is a realtor: contacting one is realtor outreach (2026-10-21).
                if (l.RecordType?.DeveloperName == 'Realtor_Lead_record_type') {
                    return REALTOR;
                }
                return NON_CONSUMER_LEAD_TYPES.contains(l.RecordType?.DeveloperName) ? null : CONSUMER;
            }
            Account a = accounts.get(recordId);
            if (a != null) {
                if (pastClients.contains(a.Id)) {
                    return PAST_CLIENT;
                }
                Set<String> groups = new Set<String>(a.Group__pc == null ? new List<String>() : a.Group__pc.split(';'));
                groups.retainAll(REALTOR_GROUPS);
                Boolean isRealtor = !groups.isEmpty() || a.BD_Industry__c == 'Realtor'
                    || tags.contains('' + ownerId + '|' + a.PersonContactId);
                return isRealtor ? REALTOR : null;
            }
            // A business Contact counts only when the LO tagged it as a partner.
            return tags.contains('' + ownerId + '|' + recordId) ? REALTOR : null;
        }
    }

    /** WhoId (Lead/Contact), else an Account WhatId; Transactions etc. fall through to the number. */
    static Id whoOf(Task t) {
        if (t.WhoId != null) {
            return t.WhoId;
        }
        return t.WhatId != null && t.WhatId.getSObjectType() == Account.SObjectType ? t.WhatId : null;
    }
}
