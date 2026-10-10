/**
 * Read-only Communications tab (LO Workspace, decided 2026-10-08): every Reach user's calls, texts and
 * emails with one borrower, for a Lead, Transaction__c or Person Account.
 *
 * Access: RecordAccessGuard.requireRead on the record the LO opened, then SYSTEM_MODE reads scoped to
 * that borrower's own records, phone numbers and email addresses. RingCentral often logs with no
 * WhoId/WhatId, so calls and texts also match on rcsfl__from/to_number__c (E.164, "+1XXXXXXXXXX").
 */
public with sharing class LoWsCommunicationsService {
    private static final Integer MAX_ROWS = 300;
    private static final Integer BODY_LIMIT = 4000;
    private static final Set<String> LOGGED_CALL_TYPES = new Set<String>{ 'Call - Active Agent', 'Call - Prospecting' };

    public class Item {
        @AuraEnabled public String id;
        @AuraEnabled public String direction; // in / out / missed
        @AuraEnabled public String fromLabel;
        @AuraEnabled public String toLabel;
        @AuraEnabled public Datetime at;
        @AuraEnabled public String durationLabel;
        @AuraEnabled public String body;
        @AuraEnabled public String summary;
        @AuraEnabled public Boolean logged;
        @AuraEnabled public Boolean fromBorrower;
    }

    public class EmailThread {
        @AuraEnabled public String key;
        @AuraEnabled public String subject;
        @AuraEnabled public Datetime lastAt;
        @AuraEnabled public String participants;
        @AuraEnabled public Integer count;
        @AuraEnabled public List<EmailItem> messages = new List<EmailItem>();
    }

    public class EmailItem {
        @AuraEnabled public String id;
        @AuraEnabled public String fromLabel;
        @AuraEnabled public String toLabel;
        @AuraEnabled public Datetime at;
        @AuraEnabled public String body;
        @AuraEnabled public Boolean incoming;
    }

    public class Result {
        @AuraEnabled public String borrowerName;
        @AuraEnabled public List<Item> calls = new List<Item>();
        @AuraEnabled public List<Item> sms = new List<Item>();
        @AuraEnabled public List<EmailThread> emails = new List<EmailThread>();
    }

    /** The borrower behind the record: linked record Ids, E.164 phones and lower-case emails. */
    @TestVisible
    private class Borrower {
        String name;
        Set<Id> ids = new Set<Id>();
        Set<String> phones = new Set<String>();
        Set<String> emails = new Set<String>();
    }

    @AuraEnabled(cacheable=true)
    public static Result getCommunications(Id recordId) {
        RecordAccessGuard.requireRead(recordId);
        Borrower b = resolveBorrower(recordId);
        Result r = new Result();
        r.borrowerName = b.name;
        loadCallsAndTexts(b, r);
        r.emails = loadEmails(b);
        return r;
    }

    // ---------- Who is the borrower ----------

    @TestVisible
    private static Borrower resolveBorrower(Id recordId) {
        Borrower b = new Borrower();
        b.ids.add(recordId);
        String type = String.valueOf(recordId.getSObjectType());
        Id accountId;
        if (type == 'Lead') {
            Lead l = [
                SELECT Name, Phone, MobilePhone, Email, ConvertedAccountId
                FROM Lead WHERE Id = :recordId WITH SYSTEM_MODE
            ];
            b.name = l.Name;
            addPhone(b, l.Phone);
            addPhone(b, l.MobilePhone);
            addEmail(b, l.Email);
            accountId = l.ConvertedAccountId;
        } else if (type == 'Transaction__c') {
            accountId = [SELECT Borrower_Name__c FROM Transaction__c WHERE Id = :recordId WITH SYSTEM_MODE].Borrower_Name__c;
        } else if (type == 'Account') {
            accountId = recordId;
        }
        if (accountId != null) {
            b.ids.add(accountId);
            for (Account a : [
                SELECT Name, Phone, PersonMobilePhone, PersonHomePhone, PersonEmail, PersonContactId
                FROM Account WHERE Id = :accountId WITH SYSTEM_MODE
            ]) {
                b.name = b.name ?? a.Name;
                addPhone(b, a.Phone);
                addPhone(b, a.PersonMobilePhone);
                addPhone(b, a.PersonHomePhone);
                addEmail(b, a.PersonEmail);
                if (a.PersonContactId != null) {
                    b.ids.add(a.PersonContactId);
                }
            }
            // Converted leads keep their history: the pre-approval conversation stays visible on the loan.
            for (Lead l : [
                SELECT Id, Phone, MobilePhone, Email FROM Lead
                WHERE ConvertedAccountId = :accountId WITH SYSTEM_MODE LIMIT 20
            ]) {
                b.ids.add(l.Id);
                addPhone(b, l.Phone);
                addPhone(b, l.MobilePhone);
                addEmail(b, l.Email);
            }
            for (Transaction__c t : [
                SELECT Id FROM Transaction__c WHERE Borrower_Name__c = :accountId WITH SYSTEM_MODE LIMIT 20
            ]) {
                b.ids.add(t.Id);
            }
        }
        return b;
    }

    @TestVisible
    private static String toE164(String phone) {
        String digits = phone == null ? '' : phone.replaceAll('[^0-9]', '');
        if (digits.length() == 10) {
            return '+1' + digits;
        }
        if (digits.length() == 11 && digits.startsWith('1')) {
            return '+' + digits;
        }
        return null;
    }

    private static void addPhone(Borrower b, String phone) {
        String e164 = toE164(phone);
        if (e164 != null) {
            b.phones.add(e164);
        }
    }

    private static void addEmail(Borrower b, String email) {
        // na@na.com is the deliberate placeholder on email-less Realtor form leads; never match on it.
        if (String.isNotBlank(email) && email.toLowerCase() != 'na@na.com') {
            b.emails.add(email.toLowerCase());
        }
    }

    // ---------- Calls and texts ----------

    private static void loadCallsAndTexts(Borrower b, Result r) {
        Map<Id, Task> tasks = new Map<Id, Task>([
            SELECT Id, Subject, Description, InteractionType__c, Activity_Type__c, TaskSubtype, Direction__c,
                   rcsfl__from_number__c, rcsfl__to_number__c, rcsfl__call_start_time__c, CallDurationInSeconds, rcsfl__RC_Logging_Type__c,
                   CreatedDate, Owner.Name
            FROM Task
            WHERE (WhoId IN :b.ids OR WhatId IN :b.ids)
              AND (InteractionType__c IN ('Call', 'Sms') OR TaskSubtype = 'Call'
                   OR Activity_Type__c IN :LOGGED_CALL_TYPES OR Activity_Type__c = 'Text')
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_ROWS
        ]);
        if (!b.phones.isEmpty()) {
            tasks.putAll(new Map<Id, Task>([
                SELECT Id, Subject, Description, InteractionType__c, Activity_Type__c, TaskSubtype, Direction__c,
                       rcsfl__from_number__c, rcsfl__to_number__c, rcsfl__call_start_time__c, CallDurationInSeconds, rcsfl__RC_Logging_Type__c,
                       CreatedDate, Owner.Name
                FROM Task
                WHERE CreatedDate = LAST_N_DAYS:365
                  AND InteractionType__c IN ('Call', 'Sms')
                  AND (rcsfl__from_number__c IN :b.phones OR rcsfl__to_number__c IN :b.phones)
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT :MAX_ROWS
            ]));
        }
        String borrower = b.name ?? 'Borrower';
        for (Task t : tasks.values()) {
            Boolean isSms = t.InteractionType__c == 'Sms' || t.Activity_Type__c == 'Text';
            Boolean fromBorrower = t.rcsfl__from_number__c != null && b.phones.contains(t.rcsfl__from_number__c);
            if (t.Direction__c == 'Inbound') {
                fromBorrower = true;
            }
            Item i = new Item();
            i.id = t.Id;
            i.at = t.rcsfl__call_start_time__c ?? t.CreatedDate;
            i.fromBorrower = fromBorrower;
            i.fromLabel = fromBorrower ? borrower : t.Owner.Name;
            i.toLabel = fromBorrower ? t.Owner.Name : borrower;
            // Logged by hand = no RingCentral data and no system-captured duration ("X Called Y" auto-logs have one).
            i.logged = t.InteractionType__c == null && t.rcsfl__from_number__c == null
                && t.rcsfl__RC_Logging_Type__c == null && t.CallDurationInSeconds == null;
            i.body = clip(t.Description);
            if (isSms) {
                i.direction = fromBorrower ? 'in' : 'out';
                r.sms.add(i);
            } else {
                Boolean missed = (t.Subject ?? '').containsIgnoreCase('missed');
                i.direction = missed ? 'missed' : (fromBorrower ? 'in' : 'out');
                i.durationLabel = durationLabel(t.CallDurationInSeconds);
                r.calls.add(i);
            }
        }
        attachCallInsights(b, r.calls, borrower);
        r.calls.sort(new NewestFirst());
        r.sms.sort(new OldestFirst()); // a text thread reads top to bottom
    }

    /**
     * RingSense summaries: attached to the matching RingCentral call (same borrower, start within
     * 5 minutes); an insight with no matching call is listed as its own call.
     */
    private static void attachCallInsights(Borrower b, List<Item> calls, String borrower) {
        List<Call_Insight__c> insights = [
            SELECT Id, Title__c, Summary__c, Bulleted_Summary__c, Recording_Start_DateTime__c, Direction__c,
                   Duration__c, Salesforce_User__r.Name, CreatedDate
            FROM Call_Insight__c
            WHERE Source__c = 'RingSense'
              AND (Lead__c IN :b.ids OR Account__c IN :b.ids OR Transaction__c IN :b.ids
                   OR Recipient_Phone_Number__c IN :b.phones)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
        for (Call_Insight__c ci : insights) {
            String summary = clip(String.isNotBlank(ci.Bulleted_Summary__c) ? ci.Bulleted_Summary__c : ci.Summary__c);
            Datetime at = ci.Recording_Start_DateTime__c ?? ci.CreatedDate;
            Item match;
            for (Item c : calls) {
                if (c.summary == null && c.at != null && Math.abs(c.at.getTime() - at.getTime()) <= 5 * 60 * 1000) {
                    match = c;
                    break;
                }
            }
            if (match != null) {
                match.summary = summary;
                continue;
            }
            Item i = new Item();
            i.id = ci.Id;
            i.at = at;
            i.fromBorrower = ci.Direction__c == 'Inbound';
            i.direction = i.fromBorrower ? 'in' : 'out';
            i.fromLabel = i.fromBorrower ? borrower : ci.Salesforce_User__r?.Name;
            i.toLabel = i.fromBorrower ? ci.Salesforce_User__r?.Name : borrower;
            i.durationLabel = ci.Duration__c;
            i.summary = summary;
            i.logged = false;
            calls.add(i);
        }
    }

    // ---------- Emails ----------

    private static List<EmailThread> loadEmails(Borrower b) {
        Set<Id> messageIds = new Set<Id>();
        for (EmailMessageRelation rel : [
            SELECT EmailMessageId FROM EmailMessageRelation
            WHERE RelationId IN :b.ids OR RelationAddress IN :b.emails
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            messageIds.add(rel.EmailMessageId);
        }
        Map<String, EmailThread> threads = new Map<String, EmailThread>();
        for (EmailMessage m : [
            SELECT Id, Subject, TextBody, FromName, FromAddress, ToAddress, MessageDate, Incoming, ThreadIdentifier
            FROM EmailMessage
            WHERE Id IN :messageIds
            WITH SYSTEM_MODE
            ORDER BY MessageDate DESC
            LIMIT 150
        ]) {
            String key = String.isNotBlank(m.ThreadIdentifier) ? m.ThreadIdentifier : threadSubject(m.Subject).toLowerCase();
            EmailThread t = threads.get(key);
            if (t == null) {
                t = new EmailThread();
                t.key = key;
                t.subject = String.isBlank(m.Subject) ? '(no subject)' : threadSubject(m.Subject);
                t.lastAt = m.MessageDate;
                threads.put(key, t);
            }
            EmailItem e = new EmailItem();
            e.id = m.Id;
            e.fromLabel = String.isNotBlank(m.FromName) ? m.FromName : m.FromAddress;
            e.toLabel = m.ToAddress;
            e.at = m.MessageDate;
            e.body = clip(m.TextBody);
            e.incoming = m.Incoming;
            // Query is newest first; a thread reads oldest first. (Apex add(0, x) fails on an empty list.)
            if (t.messages.isEmpty()) {
                t.messages.add(e);
            } else {
                t.messages.add(0, e);
            }
        }
        for (EmailThread t : threads.values()) {
            t.count = t.messages.size();
            Set<String> names = new Set<String>();
            for (EmailItem e : t.messages) {
                if (e.fromLabel != null) {
                    names.add(e.fromLabel);
                }
            }
            t.participants = String.join(new List<String>(names), ', ');
        }
        return threads.values(); // insertion order = newest thread first
    }

    @TestVisible
    private static String threadSubject(String subject) {
        return (subject ?? '').replaceAll('(?i)^((re|fw|fwd)\\s*:\\s*)+', '').trim();
    }

    // ---------- Helpers ----------

    private static String clip(String value) {
        return value == null ? null : value.abbreviate(BODY_LIMIT);
    }

    @TestVisible
    private static String durationLabel(Integer seconds) {
        if (seconds == null || seconds <= 0) {
            return null;
        }
        Integer m = seconds / 60;
        Integer s = Math.mod(seconds, 60);
        return m > 0 ? m + 'm ' + (s < 10 ? '0' : '') + s + 's' : s + 's';
    }

    private class NewestFirst implements System.Comparator<Item> {
        public Integer compare(Item a, Item b) {
            Long x = a.at == null ? 0 : a.at.getTime();
            Long y = b.at == null ? 0 : b.at.getTime();
            return x == y ? 0 : (x > y ? -1 : 1);
        }
    }

    private class OldestFirst implements System.Comparator<Item> {
        public Integer compare(Item a, Item b) {
            Long x = a.at == null ? 0 : a.at.getTime();
            Long y = b.at == null ? 0 : b.at.getTime();
            return x == y ? 0 : (x < y ? -1 : 1);
        }
    }
}