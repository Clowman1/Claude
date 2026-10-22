/**
 * LO Workspace (O3, ONBOARDING-GRILL Q27-Q29): which Twilio texts (TwilioSF__Message__c) an LO may see.
 *
 * Stamp (trigger ExternalLoStampTwilioMessage, before insert/update), set once and never moved by later edits:
 *  - Outbound: origin = TwilioSF__SF_Parent_Record_Id__c when it is a Transaction__c or Lead (every sending
 *    flow passes its own record as recordId); with no parent at all, TwilioSF__Lead__c. Account/Contact parents
 *    (birthday/anniversary texts, realtor referral thank-yous, event invites) name no loan, so stay unstamped.
 *  - Inbound: origin = that of the most recent outbound text to the same number within THREAD_DAYS (the thread),
 *    even when that one is unstamped, so a reply to another LO's text never lands with this LO.
 *  - Workspace LO (External_LO__c) = ExternalLoStampService rules on the origin loan/lead.
 * Reads run in SYSTEM_MODE (LOs have no object access); LO Workspace LOs only ever get rows stamped with them.
 */
public without sharing class LoWsTextsService {
    @TestVisible static final Integer THREAD_DAYS = 30;
    static final Integer MAX_TEXTS = 200;
    static final Integer BODY_LIMIT = 2000;
    static final Integer REPLY_DAYS = 7;
    static final Integer MAX_REPLIES = 3;
    public static final String REPLY_KEY = 'text_reply';

    // ------------------------------------------------------------------ stamping

    public static void stamp(List<TwilioSF__Message__c> rows, Map<Id, SObject> oldMap) {
        List<TwilioSF__Message__c> replies = new List<TwilioSF__Message__c>();
        for (TwilioSF__Message__c m : rows) {
            TwilioSF__Message__c old = oldMap == null ? null : (TwilioSF__Message__c) oldMap.get(m.Id);
            Boolean inbound = m.TwilioSF__Direction__c == 'inbound';
            String key = phoneKey(inbound ? m.TwilioSF__From_Number__c : m.TwilioSF__To_Number__c);
            if (key != null) {
                m.LoWs_Phone_Key__c = key;
            }
            if (m.LoWs_Transaction__c != null || m.LoWs_Lead__c != null) {
                continue; // origin is set once
            }
            if (inbound) {
                // Thread once: on insert, or the first time a pre-O3 row is touched (backfill).
                if (key != null && (old == null || old.LoWs_Phone_Key__c == null)) {
                    replies.add(m);
                }
                continue;
            }
            Id parent = toId(m.TwilioSF__SF_Parent_Record_Id__c);
            if (parent == null) {
                m.LoWs_Lead__c = m.TwilioSF__Lead__c;
            } else if (parent.getSObjectType() == Transaction__c.SObjectType) {
                m.LoWs_Transaction__c = parent;
            } else if (parent.getSObjectType() == Lead.SObjectType) {
                m.LoWs_Lead__c = parent;
            }
        }
        threadReplies(replies);
        ExternalLoStampService.stampChildren(rows, oldMap);
    }

    static void threadReplies(List<TwilioSF__Message__c> replies) {
        if (replies.isEmpty()) {
            return;
        }
        Set<String> keys = new Set<String>();
        Datetime latest;
        Datetime earliest;
        for (TwilioSF__Message__c m : replies) {
            keys.add(m.LoWs_Phone_Key__c);
            Datetime at = m.CreatedDate ?? Datetime.now();
            latest = latest == null || at > latest ? at : latest;
            earliest = earliest == null || at < earliest ? at : earliest;
        }
        Datetime since = earliest.addDays(-THREAD_DAYS);
        Map<String, List<TwilioSF__Message__c>> outboundByKey = new Map<String, List<TwilioSF__Message__c>>();
        for (TwilioSF__Message__c o : [
            SELECT LoWs_Phone_Key__c, LoWs_Transaction__c, LoWs_Lead__c, CreatedDate, TwilioSF__From_Number__c
            FROM TwilioSF__Message__c
            WHERE LoWs_Phone_Key__c IN :keys AND TwilioSF__Direction__c != 'inbound'
              AND CreatedDate >= :since AND CreatedDate <= :latest
            ORDER BY CreatedDate DESC
            LIMIT 2000
        ]) {
            if (!outboundByKey.containsKey(o.LoWs_Phone_Key__c)) {
                outboundByKey.put(o.LoWs_Phone_Key__c, new List<TwilioSF__Message__c>());
            }
            outboundByKey.get(o.LoWs_Phone_Key__c).add(o); // newest first
        }
        for (TwilioSF__Message__c m : replies) {
            Datetime at = m.CreatedDate ?? Datetime.now();
            Boolean toNoReply = isNoReplyNumber(m.TwilioSF__To_Number__c); // comms-settings: thread with our own sends only
            for (TwilioSF__Message__c o : outboundByKey.get(m.LoWs_Phone_Key__c) ?? new List<TwilioSF__Message__c>()) {
                if (toNoReply != isNoReplyNumber(o.TwilioSF__From_Number__c)) {
                    continue;
                }
                if (o.CreatedDate <= at && o.CreatedDate >= at.addDays(-THREAD_DAYS)) {
                    m.LoWs_Transaction__c = o.LoWs_Transaction__c;
                    m.LoWs_Lead__c = o.LoWs_Lead__c;
                    break;
                }
            }
        }
    }

    // ------------------------------------------------------------------ reads

    /** Texts sent from (or replying to) these loans/leads: the Communications tab's Texts list. */
    public static List<LoWsCommunicationsService.Item> forRecords(Set<Id> recordIds) {
        return toItems(query('(LoWs_Transaction__c IN :recordIds OR LoWs_Lead__c IN :recordIds)',
            new Map<String, Object>{ 'recordIds' => recordIds }));
    }

    /** Texts with one realtor/partner (their numbers, or the package's Account/Contact match). */
    public static List<LoWsCommunicationsService.Item> forPartner(Id accountId) {
        Account a = [
            SELECT Phone, PersonMobilePhone, PersonHomePhone, PersonContactId
            FROM Account WHERE Id = :accountId WITH SYSTEM_MODE
        ];
        Set<Id> contactIds = new Set<Id>();
        if (a.PersonContactId != null) {
            contactIds.add(a.PersonContactId);
        }
        Set<String> keys = new Set<String>();
        for (String p : new List<String>{ a.Phone, a.PersonMobilePhone, a.PersonHomePhone }) {
            if (phoneKey(p) != null) {
                keys.add(phoneKey(p));
            }
        }
        return toItems(query('(LoWs_Phone_Key__c IN :keys OR TwilioSF__Account__c = :accountId OR TwilioSF__Contact__c IN :contactIds)',
            new Map<String, Object>{ 'keys' => keys, 'accountId' => accountId, 'contactIds' => contactIds }));
    }

    /** Perfect Day Recent log: the LO's newest text replies first (automated sends are not activity). */
    public static List<PerfectDayHomeModels.RecentLogEntry> withReplies(List<PerfectDayHomeModels.RecentLogEntry> entries) {
        List<PerfectDayHomeModels.RecentLogEntry> result = new List<PerfectDayHomeModels.RecentLogEntry>();
        if (isLo()) {
            List<LoWsCommunicationsService.Item> items = toItems(query('TwilioSF__Direction__c = \'inbound\' AND CreatedDate >= :since',
                new Map<String, Object>{ 'since' => Datetime.now().addDays(-REPLY_DAYS), 'maxRows' => MAX_REPLIES }));
            for (Integer k = items.size() - 1; k >= 0; k--) { // newest first
                LoWsCommunicationsService.Item i = items[k];
                PerfectDayHomeModels.RecentLogEntry e = new PerfectDayHomeModels.RecentLogEntry();
                e.taskId = i.id;
                e.activityKey = REPLY_KEY;
                e.shortLabel = 'Text reply';
                e.subject = i.replyHint;
                e.contactName = i.fromLabel;
                e.activityCount = 1;
                e.activityDateLabel = i.at.date().format();
                e.notes = i.body;
                result.add(e);
            }
        }
        if (entries != null) {
            result.addAll(entries);
        }
        return result;
    }

    // ------------------------------------------------------------------ Up Next: replies to the no-reply number

    static final Set<String> CLOSED_LOAN = new Set<String>{ 'Post-Closed', 'PC Review', 'Cancelled', 'Lost' };

    /**
     * comms-settings (SPEC): one High alert per unhandled reply to the no-reply number, until Mark handled.
     * Agent reply -> realtor page; borrower -> lead (unconverted) -> active loan -> past client page.
     */
    public static List<ExternalLoPromptService.PromptItem> replyPrompts(Id userId) {
        List<ExternalLoPromptService.PromptItem> items = new List<ExternalLoPromptService.PromptItem>();
        String key = phoneKey(System.Label.LoWs_Twilio_From_Number);
        if (key == null) {
            return items;
        }
        String toLike = '%' + key;
        List<TwilioSF__Message__c> replies = [
            SELECT Id, TwilioSF__Body__c, LoWs_Phone_Key__c, LoWs_Lead__c, LoWs_Transaction__c, CreatedDate
            FROM TwilioSF__Message__c
            WHERE External_LO__c = :userId AND TwilioSF__Direction__c = 'inbound'
              AND TwilioSF__To_Number__c LIKE :toLike AND LoWs_Reply_Handled__c = false
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 8
        ];
        if (replies.isEmpty()) {
            return items; // one query on a quiet day (Perfect Day query budget)
        }
        Set<Id> leadIds = new Set<Id>();
        Set<Id> loanIds = new Set<Id>();
        for (TwilioSF__Message__c m : replies) {
            if (m.LoWs_Lead__c != null) leadIds.add(m.LoWs_Lead__c);
            if (m.LoWs_Transaction__c != null) loanIds.add(m.LoWs_Transaction__c);
        }
        Map<Id, Lead> leads = new Map<Id, Lead>([
            SELECT Id, Name, IsConverted, ConvertedAccountId, Realtor_Buying_Agent__c, Realtor_Buying_Agent__r.Name,
                Realtor_Buying_Agent__r.PersonMobilePhone
            FROM Lead WHERE Id IN :leadIds WITH SYSTEM_MODE
        ]);
        Set<Id> convertedAccounts = new Set<Id>();
        for (Lead l : leads.values()) {
            if (l.IsConverted) convertedAccounts.add(l.ConvertedAccountId);
        }
        Map<Id, Transaction__c> loans = new Map<Id, Transaction__c>([
            SELECT Id, Name, Status__c, Borrower_Name__c, Borrower_Name__r.Name, Realtor_Buying_Agent__c,
                Realtor_Buying_Agent__r.Name, Realtor_Buying_Agent__r.PersonMobilePhone
            FROM Transaction__c WHERE Id IN :loanIds WITH SYSTEM_MODE
        ]);
        Map<Id, Transaction__c> activeLoanByAccount = new Map<Id, Transaction__c>();
        for (Transaction__c t : [
            SELECT Id, Borrower_Name__c FROM Transaction__c
            WHERE Borrower_Name__c IN :convertedAccounts AND Status__c NOT IN :CLOSED_LOAN
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC
        ]) {
            if (!activeLoanByAccount.containsKey(t.Borrower_Name__c)) activeLoanByAccount.put(t.Borrower_Name__c, t);
        }
        for (TwilioSF__Message__c m : replies) {
            Lead l = leads.get(m.LoWs_Lead__c);
            Transaction__c t = loans.get(m.LoWs_Transaction__c);
            Account agent = t != null ? t.Realtor_Buying_Agent__r : l?.Realtor_Buying_Agent__r;
            String name;
            Id target;
            String view;
            if (agent != null && phoneKey(agent.PersonMobilePhone) == m.LoWs_Phone_Key__c) {
                name = agent.Name;
                target = t != null ? t.Realtor_Buying_Agent__c : l.Realtor_Buying_Agent__c;
                view = 'realtors';
            } else if (t != null) {
                name = t.Borrower_Name__r?.Name ?? t.Name;
                Boolean active = !CLOSED_LOAN.contains(t.Status__c);
                target = active ? t.Id : t.Borrower_Name__c;
                view = active ? 'loans' : 'realtors'; // the shell turns a past client's Account into Past Clients
            } else if (l != null) {
                name = l.Name;
                Transaction__c active = l.IsConverted ? activeLoanByAccount.get(l.ConvertedAccountId) : null;
                target = !l.IsConverted ? l.Id : (active != null ? active.Id : l.ConvertedAccountId);
                view = !l.IsConverted ? 'leads' : (active != null ? 'loans' : 'realtors');
            }
            String sender = name ?? formatPhone(m.LoWs_Phone_Key__c);
            ExternalLoPromptService.PromptItem item = new ExternalLoPromptService.PromptItem();
            item.promptKey = 'reply:' + m.Id;
            item.triggerType = 'text-reply';
            item.title = 'Text reply from ' + sender;
            item.script = '"' + (m.TwilioSF__Body__c ?? '').abbreviate(80) + '"  Reply from your phone to ' + formatPhone(m.LoWs_Phone_Key__c);
            item.reason = 'High alert · Reply to an automated text';
            item.recordId = target;
            item.objectApiName = target == null ? null : String.valueOf(target.getSObjectType());
            item.contactName = sender;
            item.canLog = false;
            item.canSnooze = false;
            item.isHighAlert = true;
            item.isTextReply = true;
            item.messageId = m.Id;
            item.openView = view;
            items.add(item);
        }
        return items;
    }

    /** Mark handled: only the LO the reply is stamped with. */
    public static void markReplyHandled(Id messageId) {
        List<TwilioSF__Message__c> rows = [
            SELECT Id FROM TwilioSF__Message__c WHERE Id = :messageId AND External_LO__c = :UserInfo.getUserId() WITH SYSTEM_MODE
        ];
        if (rows.isEmpty()) {
            throw new DomainException('This reply is not yours to mark handled.');
        }
        rows[0].LoWs_Reply_Handled__c = true;
        Database.update(rows, AccessLevel.SYSTEM_MODE);
    }

    @TestVisible
    static Boolean isNoReplyNumber(String phone) {
        String key = phoneKey(phone);
        return key != null && key == phoneKey(System.Label.LoWs_Twilio_From_Number);
    }

    // ------------------------------------------------------------------ helpers

    /** SYSTEM_MODE read, newest MAX_TEXTS; LO Workspace LOs only get rows stamped with them. */
    static List<TwilioSF__Message__c> query(String whereClause, Map<String, Object> binds) {
        binds.put('me', UserInfo.getUserId());
        if (!binds.containsKey('maxRows')) {
            binds.put('maxRows', MAX_TEXTS);
        }
        return Database.queryWithBinds(
            'SELECT Id, TwilioSF__Direction__c, TwilioSF__Body__c, TwilioSF__To_Number__c, TwilioSF__From_Number__c, '
            + 'LoWs_Phone_Key__c, TwilioSF__Contact__c, TwilioSF__Lead__c, CreatedDate, CreatedBy.Name '
            + 'FROM TwilioSF__Message__c WHERE ' + whereClause + (isLo() ? ' AND External_LO__c = :me' : '')
            + ' ORDER BY CreatedDate DESC LIMIT :maxRows',
            binds, AccessLevel.SYSTEM_MODE
        );
    }

    static Boolean isLo() {
        return FeatureManagement.checkPermission('External_LO');
    }

    /** Oldest first (a text thread reads top to bottom). Names only when the linked record really has that number. */
    static List<LoWsCommunicationsService.Item> toItems(List<TwilioSF__Message__c> rows) {
        Set<Id> whoIds = new Set<Id>();
        for (TwilioSF__Message__c m : rows) {
            if (m.TwilioSF__Contact__c != null) whoIds.add(m.TwilioSF__Contact__c);
            if (m.TwilioSF__Lead__c != null) whoIds.add(m.TwilioSF__Lead__c);
        }
        Map<Id, Map<String, String>> namesByWho = new Map<Id, Map<String, String>>();
        for (Contact c : [SELECT Id, Name, Phone, MobilePhone FROM Contact WHERE Id IN :whoIds WITH SYSTEM_MODE]) {
            namesByWho.put(c.Id, namesFor(c.Name, new List<String>{ c.Phone, c.MobilePhone }));
        }
        for (Lead l : [SELECT Id, Name, Phone, MobilePhone FROM Lead WHERE Id IN :whoIds WITH SYSTEM_MODE]) {
            namesByWho.put(l.Id, namesFor(l.Name, new List<String>{ l.Phone, l.MobilePhone }));
        }
        List<LoWsCommunicationsService.Item> items = new List<LoWsCommunicationsService.Item>();
        for (Integer k = rows.size() - 1; k >= 0; k--) {
            TwilioSF__Message__c m = rows[k];
            Boolean inbound = m.TwilioSF__Direction__c == 'inbound';
            String phoneLabel = formatPhone(inbound ? m.TwilioSF__From_Number__c : m.TwilioSF__To_Number__c);
            String name = (namesByWho.get(m.TwilioSF__Contact__c) ?? new Map<String, String>()).get(m.LoWs_Phone_Key__c)
                ?? (namesByWho.get(m.TwilioSF__Lead__c) ?? new Map<String, String>()).get(m.LoWs_Phone_Key__c);
            String other = name == null ? phoneLabel : name + ' (' + phoneLabel + ')';
            LoWsCommunicationsService.Item i = new LoWsCommunicationsService.Item();
            i.id = m.Id;
            i.at = m.CreatedDate;
            i.direction = inbound ? 'in' : 'out';
            i.fromBorrower = inbound; // "them" side of the thread
            i.fromLabel = inbound ? other : m.CreatedBy.Name;
            i.toLabel = inbound ? null : other;
            i.body = m.TwilioSF__Body__c == null ? null : m.TwilioSF__Body__c.abbreviate(BODY_LIMIT);
            i.logged = false;
            i.replyHint = inbound && phoneLabel != null ? 'Reply from your phone: ' + phoneLabel : null;
            items.add(i);
        }
        return items;
    }

    static Map<String, String> namesFor(String name, List<String> phones) {
        Map<String, String> byKey = new Map<String, String>();
        for (String p : phones) {
            if (phoneKey(p) != null) {
                byKey.put(phoneKey(p), name);
            }
        }
        return byKey;
    }

    @TestVisible
    static String phoneKey(String phone) {
        String digits = phone == null ? '' : phone.replaceAll('[^0-9]', '');
        return digits.length() >= 10 ? digits.right(10) : null;
    }

    @TestVisible
    static String formatPhone(String phone) {
        String key = phoneKey(phone);
        return key == null ? phone : key.left(3) + '-' + key.mid(3, 3) + '-' + key.right(4);
    }

    static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }
}