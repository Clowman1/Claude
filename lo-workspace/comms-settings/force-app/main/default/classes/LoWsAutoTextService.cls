/**
 * LO Workspace Communication Settings (lo-workspace/comms-settings/SPEC.md).
 *
 * Automated texts for files whose LO is an External LO (ExternalLoStampService role) go out from the
 * no-reply number in $Label.LoWs_Twilio_From_Number ONLY; the org's shared-number flows skip those files
 * (User.LoWs_External_LO__c gate). Each LO can switch every message off or rewrite it; settings live as
 * JSON in User.LoWs_Comm_Settings__c ({key: {on, body}}), no row = default ON + default body.
 * A contact with LoWs_Texts_Off__c (Lead or Account) gets none of these texts.
 *
 * Without sharing on purpose: triggers fire for any user, and LOs have no FLS on the LoWs_ fields.
 */
public without sharing class LoWsAutoTextService {

    public static final String FOOTER = 'No-reply';
    static final String SIGN = ' - Reach Home Loans';
    static final Set<Integer> REMINDER_DAYS = new Set<Integer>{ 3, 6, 9, 12, 15 };
    static final Set<String> OPEN_REQUEST = new Set<String>{ 'Requested', 'In Progress' };

    public class Def {
        @AuraEnabled public String key;
        @AuraEnabled public String audience;
        @AuraEnabled public String label;
        @AuraEnabled public String whenText;
        @AuraEnabled public String defaultBody;
        @AuraEnabled public List<String> tokens;
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public String body;
        @AuraEnabled public Boolean customized;
        Def(String key, String audience, String label, String whenText, String defaultBody, List<String> tokens) {
            this.key = key;
            this.audience = audience;
            this.label = label;
            this.whenText = whenText;
            this.defaultBody = defaultBody;
            this.tokens = tokens;
        }
    }

    static final List<String> LEAD_AGENT = new List<String>{ '{Lead Name}', '{Agent First Name}', '{LO Name}' };
    static final List<String> LOAN_AGENT = new List<String>{ '{Borrower Name}', '{Agent First Name}', '{LO Name}', '{Closing Date}' };
    static final List<String> BORROWER = new List<String>{ '{First Name}', '{LO Name}' };

    @TestVisible
    static final List<Def> CATALOG = new List<Def>{
        new Def('A2', 'Agent', 'Documents requested', 'First document request sent to the borrower',
            'Documents have been requested from {Lead Name} to complete the Pre-Approval.' + SIGN, LEAD_AGENT),
        new Def('A3', 'Agent', 'Pre-Approved', 'Lead moves to Pre-Approval, or a letter is finalized at a new price',
            'Great news! {Lead Name} is Pre-Approved.{Letter Details}' + SIGN,
            new List<String>{ '{Lead Name}', '{Agent First Name}', '{LO Name}', '{Letter Details}', '{Purchase Price}', '{Loan Amount}' }),
        new Def('A5', 'Agent', 'Disclosures sent', 'Disclosures Out Date is set',
            'Disclosures have been sent to {Borrower Name} for review and signatures. We will let you know when they are executed.' + SIGN, LOAN_AGENT),
        new Def('A6', 'Agent', 'Appraisal ordered', 'Appraisal ordered date is set',
            'The appraisal for {Borrower Name} has been ordered.' + SIGN, LOAN_AGENT),
        new Def('A7', 'Agent', 'Appraisal received', 'Appraisal received date is set',
            'We have received the appraisal report for {Borrower Name}.' + SIGN, LOAN_AGENT),
        new Def('A8', 'Agent', 'Submitted to underwriting', 'Loan status moves to Submitted',
            'Loan documents for {Borrower Name} have been submitted to underwriting for initial review.' + SIGN, LOAN_AGENT),
        new Def('A9', 'Agent', 'Clear to Close', 'Loan status moves to Approved',
            '{Borrower Name} is Clear To Close!' + SIGN, LOAN_AGENT),
        new Def('N2', 'Agent', 'Closed / funded', 'Funded date is set',
            '{Borrower Name} is officially closed! Thank you for the referral, it was a pleasure working with you.' + SIGN, LOAN_AGENT),
        new Def('N4', 'Borrower', 'Documents requested', 'A document request is sent',
            'Hi {First Name}, I\'ve requested a few items to complete your pre-approval. Upload them here: {Portal Link}' + SIGN,
            new List<String>{ '{First Name}', '{LO Name}', '{Portal Link}' }),
        new Def('N5', 'Borrower', 'Documents reminder', 'Every 3 days while requests are open (stops after 15 days)',
            'Hi {First Name}, friendly reminder: {Open Count} items are still needed for your pre-approval: {Portal Link}' + SIGN,
            new List<String>{ '{First Name}', '{LO Name}', '{Open Count}', '{Portal Link}' }),
        new Def('N6', 'Borrower', 'Pre-Approved', 'Lead moves to Pre-Approval',
            'Congrats {First Name}, you\'re pre-approved! Your letter is headed to your inbox.' + SIGN, BORROWER),
        new Def('N7', 'Borrower', 'Disclosures sent', 'Disclosures Out Date is set',
            'Hi {First Name}, your loan disclosures were just emailed for e-signature. Please sign within 3 days to keep things moving.' + SIGN, BORROWER),
        new Def('N8', 'Borrower', 'Clear to Close', 'Loan status moves to Approved',
            '{First Name}, you\'re Clear to Close! We\'ll confirm your signing details shortly.' + SIGN,
            new List<String>{ '{First Name}', '{LO Name}', '{Closing Date}' }),
        new Def('B2', 'Borrower', 'Birthday', 'Past client\'s birthday',
            '{First Name}, Happy Birthday from all of us at Reach Home Loans! Please don\'t hesitate to reach out if you have questions on your current or future mortgage needs.' + SIGN, BORROWER),
        new Def('B3', 'Borrower', 'Loan anniversary', 'Past client\'s loan anniversary',
            '{First Name}, congrats on completing another loan anniversary with Reach Home Loans. We\'re always available if you have questions on your current or future mortgage needs.' + SIGN, BORROWER)
    };

    static Map<String, Def> defsByKey() {
        Map<String, Def> m = new Map<String, Def>();
        for (Def d : CATALOG) {
            m.put(d.key, d);
        }
        return m;
    }

    // ------------------------------------------------------------------ settings (modal)

    public static List<Def> settingsFor(Id userId) {
        Map<String, Object> saved = readSettings(new Set<Id>{ userId }).get(userId);
        List<Def> rows = new List<Def>();
        for (Def d : CATALOG) {
            Def row = new Def(d.key, d.audience, d.label, d.whenText, d.defaultBody, d.tokens);
            Map<String, Object> s = (Map<String, Object>) saved.get(d.key);
            row.enabled = s == null || s.get('on') != false;
            String body = s == null ? null : (String) s.get('body');
            row.customized = String.isNotBlank(body);
            row.body = row.customized ? body : d.defaultBody;
            rows.add(row);
        }
        return rows;
    }

    /** body blank = back to the default. */
    public static void saveSetting(Id userId, String key, Boolean enabled, String body) {
        Def d = defsByKey().get(key);
        if (d == null) {
            throw new DomainException('Unknown message.');
        }
        Map<String, Object> saved = readSettings(new Set<Id>{ userId }).get(userId);
        String clean = String.isBlank(body) || body.trim() == d.defaultBody ? null : body.trim().left(1000);
        if (enabled != false && clean == null) {
            saved.remove(key);
        } else {
            saved.put(key, new Map<String, Object>{ 'on' => enabled != false, 'body' => clean });
        }
        Database.update(new User(Id = userId, LoWs_Comm_Settings__c = saved.isEmpty() ? null : JSON.serialize(saved)), AccessLevel.SYSTEM_MODE);
    }

    static Map<Id, Map<String, Object>> readSettings(Set<Id> userIds) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        for (User u : [SELECT Id, LoWs_Comm_Settings__c FROM User WHERE Id IN :userIds WITH SYSTEM_MODE]) {
            Map<String, Object> m = new Map<String, Object>();
            if (String.isNotBlank(u.LoWs_Comm_Settings__c)) {
                try {
                    m = (Map<String, Object>) JSON.deserializeUntyped(u.LoWs_Comm_Settings__c);
                } catch (Exception e) {
                    m = new Map<String, Object>(); // corrupt JSON = defaults
                }
            }
            result.put(u.Id, m);
        }
        return result;
    }

    // ------------------------------------------------------------------ per-contact switch

    public static void setTextsOff(Id recordId, Boolean off) {
        SObjectType t = recordId.getSObjectType();
        if (t != Lead.SObjectType && t != Account.SObjectType) {
            throw new DomainException('Texts can only be switched off for a lead or a contact.');
        }
        SObject rec = t.newSObject(recordId);
        rec.put('LoWs_Texts_Off__c', off == true);
        Database.update(rec, AccessLevel.SYSTEM_MODE);
    }

    // ------------------------------------------------------------------ outgoing

    /** One text to send. contactOff = the recipient's LoWs_Texts_Off__c. */
    @TestVisible
    class Outgoing {
        String key;
        Id loId;
        Id parentId;
        String toNumber;
        Boolean contactOff;
        Map<String, String> values;
        Outgoing(String key, Id loId, Id parentId, String toNumber, Boolean contactOff, Map<String, String> values) {
            this.key = key;
            this.loId = loId;
            this.parentId = parentId;
            this.toNumber = toNumber;
            this.contactOff = contactOff == true;
            this.values = values;
        }
    }

    static Set<String> sentThisTransaction = new Set<String>(); // workflow re-fires keep their original oldMap
    @TestVisible static List<Map<String, Object>> sentForTest = new List<Map<String, Object>>();

    @TestVisible
    static void send(List<Outgoing> outs) {
        Set<Id> loIds = new Set<Id>();
        for (Outgoing o : outs) {
            loIds.add(o.loId);
        }
        Map<Id, Map<String, Object>> settings = readSettings(loIds);
        Map<String, Def> defs = defsByKey();
        List<Map<String, Object>> batch = new List<Map<String, Object>>();
        for (Outgoing o : outs) {
            String dedupe = o.parentId + ':' + o.key + ':' + o.toNumber;
            if (o.contactOff || String.isBlank(o.toNumber) || sentThisTransaction.contains(dedupe)) {
                continue;
            }
            Map<String, Object> s = (Map<String, Object>) (settings.get(o.loId) ?? new Map<String, Object>()).get(o.key);
            if (s != null && s.get('on') == false) {
                continue;
            }
            String body = s == null || String.isBlank((String) s.get('body')) ? defs.get(o.key).defaultBody : (String) s.get('body');
            sentThisTransaction.add(dedupe);
            batch.add(new Map<String, Object>{
                'toNumber' => o.toNumber,
                'message' => render(body, o.values) + '\n' + FOOTER,
                'recordId' => o.parentId,
                'fromNumber' => System.Label.LoWs_Twilio_From_Number
            });
        }
        if (batch.isEmpty()) {
            return;
        }
        if (Test.isRunningTest()) {
            sentForTest.addAll(batch);
            return;
        }
        // The package's own invocable (what the org's flows call); it queues the Twilio callout itself.
        Invocable.Action action = Invocable.Action.createCustomAction('apex', 'TwilioSF', 'TwilioSendSMS');
        for (Map<String, Object> m : batch) {
            Invocable.Action call = action.addInvocation();
            for (String p : m.keySet()) {
                call.setInvocationParameter(p, m.get(p));
            }
        }
        for (Invocable.Action.Result r : action.invoke()) {
            if (!r.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'LoWs text failed: ' + r.getErrors());
            }
        }
    }

    @TestVisible
    static String render(String body, Map<String, String> values) {
        String out = body;
        for (String token : values.keySet()) {
            out = out.replace(token, values.get(token) ?? '');
        }
        return out.replaceAll('\\{[A-Za-z \\-]+\\}', '').replaceAll('  +', ' ').trim();
    }

    // ------------------------------------------------------------------ Transaction__c

    public static void onTransactions(List<Transaction__c> rows, Map<Id, Transaction__c> oldMap) {
        Set<Id> los = ExternalLoStampService.externalLoIds();
        Set<Id> ids = new Set<Id>();
        for (Transaction__c t : rows) {
            if (t.Loan_Officer__c != null && los.contains(t.Loan_Officer__c) && !loanKeys(t, oldMap?.get(t.Id)).isEmpty()) {
                ids.add(t.Id);
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        Map<Id, Transaction__c> byId = new Map<Id, Transaction__c>([
            SELECT Id, Loan_Officer__c, Loan_Officer__r.Name, Closing_Date__c,
                Borrower_Name__r.FirstName, Borrower_Name__r.LastName, Borrower_Name__r.PersonMobilePhone,
                Borrower_Name__r.Phone, Borrower_Name__r.LoWs_Texts_Off__c,
                Realtor_Buying_Agent__r.FirstName, Realtor_Buying_Agent__r.PersonMobilePhone, Realtor_Buying_Agent__r.LoWs_Texts_Off__c
            FROM Transaction__c WHERE Id IN :ids WITH SYSTEM_MODE
        ]);
        List<Outgoing> outs = new List<Outgoing>();
        for (Transaction__c t : rows) {
            Transaction__c q = byId.get(t.Id);
            if (q == null) {
                continue;
            }
            Account b = q.Borrower_Name__r;
            Account a = q.Realtor_Buying_Agent__r;
            Map<String, String> values = new Map<String, String>{
                '{Borrower Name}' => b == null ? '' : join(b.FirstName, b.LastName),
                '{First Name}' => b?.FirstName,
                '{Agent First Name}' => a?.FirstName,
                '{LO Name}' => q.Loan_Officer__r.Name,
                '{Closing Date}' => q.Closing_Date__c?.format()
            };
            for (String key : loanKeys(t, oldMap?.get(t.Id))) {
                if (key.startsWith('A') || key == 'N2') {
                    if (a != null) {
                        outs.add(new Outgoing(key, q.Loan_Officer__c, t.Id, a.PersonMobilePhone, a.LoWs_Texts_Off__c, values));
                    }
                } else if (b != null) {
                    outs.add(new Outgoing(key, q.Loan_Officer__c, t.Id, b.PersonMobilePhone ?? b.Phone, b.LoWs_Texts_Off__c, values));
                }
            }
        }
        send(outs);
    }

    @TestVisible
    static List<String> loanKeys(Transaction__c t, Transaction__c old) {
        List<String> keys = new List<String>();
        if (t.Disclosures_Out_Date__c != null && old?.Disclosures_Out_Date__c == null) {
            keys.addAll(new List<String>{ 'A5', 'N7' });
        }
        if (t.Appraisal_1_Ordered_Date__c != null && old?.Appraisal_1_Ordered_Date__c == null) {
            keys.add('A6');
        }
        if (t.Appraisal_1_Received_Date__c != null && old?.Appraisal_1_Received_Date__c == null) {
            keys.add('A7');
        }
        if (t.Status__c != old?.Status__c && t.Status__c == 'Submitted') {
            keys.add('A8');
        }
        if (t.Status__c != old?.Status__c && t.Status__c == 'Approved') {
            keys.addAll(new List<String>{ 'A9', 'N8' });
        }
        if (t.Funded_Date__c != null && old?.Funded_Date__c == null) {
            keys.add('N2');
        }
        return keys;
    }

    // ------------------------------------------------------------------ Lead

    public static void onLeads(List<Lead> rows, Map<Id, Lead> oldMap) {
        Set<Id> los = ExternalLoStampService.externalLoIds();
        List<Lead> mine = new List<Lead>();
        for (Lead l : rows) {
            Lead old = oldMap?.get(l.Id);
            // No queries unless a text-worthy change happened on an External LO lead.
            if (los.contains(l.OwnerId) && !l.IsConverted && !silentRecycle(l, old) && (
                (l.Initial_Docs_Requested_Date__c != null && old?.Initial_Docs_Requested_Date__c == null)
                || (l.Status == 'Pre-Approval' && (old?.Status != 'Pre-Approval' || (l.Letter_Completed__c == true && old.Letter_Completed__c != true)))
            )) {
                mine.add(l);
            }
        }
        if (mine.isEmpty()) {
            return;
        }
        List<Outgoing> outs = new List<Outgoing>();
        Map<Id, Account> agents = agentsFor(mine);
        Map<Id, String> names = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :los WITH SYSTEM_MODE]) {
            names.put(u.Id, u.Name);
        }
        for (Lead l : mine) {
            Lead old = oldMap?.get(l.Id);
            Account a = agents.get(l.Realtor_Buying_Agent__c);
            Map<String, String> values = new Map<String, String>{
                '{Lead Name}' => join(l.FirstName, l.LastName),
                '{First Name}' => l.FirstName,
                '{Agent First Name}' => a?.FirstName,
                '{LO Name}' => names.get(l.OwnerId),
                '{Purchase Price}' => money(l.Purchase_Price__c),
                '{Loan Amount}' => money(l.Loan_Amount__c),
                '{Letter Details}' => l.Purchase_Price__c == null || l.Loan_Amount__c == null ? ''
                    : ' The Pre-Approval letter for Purchase Price ' + money(l.Purchase_Price__c)
                        + ' and Loan Amount ' + money(l.Loan_Amount__c) + ' is on the way!'
            };
            Boolean toPreApproval = l.Status == 'Pre-Approval' && old?.Status != 'Pre-Approval';
            Boolean letterFinalized = l.Status == 'Pre-Approval' && l.Letter_Completed__c == true && old != null && old.Letter_Completed__c != true;
            if (a != null && l.Initial_Docs_Requested_Date__c != null && old?.Initial_Docs_Requested_Date__c == null) {
                outs.add(new Outgoing('A2', l.OwnerId, l.Id, a.PersonMobilePhone, a.LoWs_Texts_Off__c, values));
            }
            if (a != null && (toPreApproval || letterFinalized)) {
                outs.add(new Outgoing('A3', l.OwnerId, l.Id, a.PersonMobilePhone, a.LoWs_Texts_Off__c, values));
            }
            if (toPreApproval) {
                outs.add(new Outgoing('N6', l.OwnerId, l.Id, l.MobilePhone ?? l.Phone, l.LoWs_Texts_Off__c, values));
            }
        }
        send(outs);
    }

    static Boolean silentRecycle(Lead l, Lead old) {
        return (old == null && l.Recycled_From_Transaction__c != null)
            || (old != null && l.Recycle_Reactivated_At__c != old.Recycle_Reactivated_At__c);
    }

    static Map<Id, Account> agentsFor(List<Lead> rows) {
        Set<Id> ids = new Set<Id>();
        for (Lead l : rows) {
            if (l.Realtor_Buying_Agent__c != null) {
                ids.add(l.Realtor_Buying_Agent__c);
            }
        }
        return ids.isEmpty() ? new Map<Id, Account>() : new Map<Id, Account>([
            SELECT Id, FirstName, PersonMobilePhone, LoWs_Texts_Off__c FROM Account WHERE Id IN :ids WITH SYSTEM_MODE
        ]);
    }

    // ------------------------------------------------------------------ Lead_Document_Request__c (N4)

    public static void onDocRequests(List<Lead_Document_Request__c> rows, Map<Id, Lead_Document_Request__c> oldMap) {
        Set<Id> leadIds = new Set<Id>();
        for (Lead_Document_Request__c r : rows) {
            Lead_Document_Request__c old = oldMap?.get(r.Id);
            if (r.Lead__c != null && r.Status__c == 'Requested' && old?.Status__c != 'Requested') {
                leadIds.add(r.Lead__c);
            }
        }
        if (leadIds.isEmpty()) {
            return;
        }
        Set<Id> los = ExternalLoStampService.externalLoIds();
        List<Outgoing> outs = new List<Outgoing>();
        for (Lead l : [
            SELECT Id, OwnerId, Owner.Name, FirstName, MobilePhone, Phone, LoWs_Texts_Off__c, Lead_Portal_Link_As_URL__c
            FROM Lead WHERE Id IN :leadIds AND IsConverted = false WITH SYSTEM_MODE
        ]) {
            if (los.contains(l.OwnerId)) {
                outs.add(new Outgoing('N4', l.OwnerId, l.Id, l.MobilePhone ?? l.Phone, l.LoWs_Texts_Off__c, new Map<String, String>{
                    '{First Name}' => l.FirstName, '{LO Name}' => l.Owner.Name, '{Portal Link}' => l.Lead_Portal_Link_As_URL__c
                }));
            }
        }
        send(outs);
    }

    // ------------------------------------------------------------------ daily (N5, B2, B3)

    public static void runDaily(Date today) {
        Set<Id> los = ExternalLoStampService.externalLoIds();
        if (los.isEmpty()) {
            return;
        }
        List<Outgoing> outs = new List<Outgoing>();

        // N5: every 3 days after the newest open request, through day 15.
        Map<Id, Date> newest = new Map<Id, Date>();
        Map<Id, Integer> open = new Map<Id, Integer>();
        for (Lead_Document_Request__c r : [
            SELECT Lead__c, Requested_Date__c, CreatedDate FROM Lead_Document_Request__c
            WHERE Status__c IN :OPEN_REQUEST AND Lead__r.OwnerId IN :los AND Lead__r.IsConverted = false
            WITH SYSTEM_MODE LIMIT 5000
        ]) {
            Date d = r.Requested_Date__c ?? r.CreatedDate.date();
            if (!newest.containsKey(r.Lead__c) || d > newest.get(r.Lead__c)) {
                newest.put(r.Lead__c, d);
            }
            open.put(r.Lead__c, (open.get(r.Lead__c) ?? 0) + 1);
        }
        Set<Id> due = new Set<Id>();
        for (Id leadId : newest.keySet()) {
            if (REMINDER_DAYS.contains(newest.get(leadId).daysBetween(today))) {
                due.add(leadId);
            }
        }
        for (Lead l : [
            SELECT Id, OwnerId, Owner.Name, FirstName, MobilePhone, Phone, LoWs_Texts_Off__c, Lead_Portal_Link_As_URL__c
            FROM Lead WHERE Id IN :due WITH SYSTEM_MODE
        ]) {
            outs.add(new Outgoing('N5', l.OwnerId, l.Id, l.MobilePhone ?? l.Phone, l.LoWs_Texts_Off__c, new Map<String, String>{
                '{First Name}' => l.FirstName, '{LO Name}' => l.Owner.Name,
                '{Open Count}' => String.valueOf(open.get(l.Id)), '{Portal Link}' => l.Lead_Portal_Link_As_URL__c
            }));
        }

        // B2 / B3: the External LO's own closed clients (Account owner, as ExternalLoStampService).
        // Sent against the client's newest loan so a reply threads to this LO (Account parents stay unstamped).
        List<Account> clients = [
            SELECT Id, OwnerId, Owner.Name, FirstName, PersonMobilePhone, Phone, LoWs_Texts_Off__c,
                SMS_Birth_date_Field__pc, Loan_Anniversary_Date__pc, Closing_Date__pc
            FROM Account
            WHERE OwnerId IN :los AND Stage__pc = 'Closed Client' AND SMS_Opt_Out__c = false
              AND (SMS_Birth_date_Field__pc = :today OR Loan_Anniversary_Date__pc = :today)
            WITH SYSTEM_MODE LIMIT 2000
        ];
        Map<Id, Id> loanByClient = new Map<Id, Id>();
        for (Transaction__c t : [
            SELECT Id, Borrower_Name__c FROM Transaction__c WHERE Borrower_Name__c IN :clients
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC
        ]) {
            if (!loanByClient.containsKey(t.Borrower_Name__c)) {
                loanByClient.put(t.Borrower_Name__c, t.Id);
            }
        }
        for (Account a : clients) {
            Map<String, String> values = new Map<String, String>{ '{First Name}' => a.FirstName, '{LO Name}' => a.Owner.Name };
            String phone = a.PersonMobilePhone ?? a.Phone;
            Id parent = loanByClient.get(a.Id) ?? a.Id;
            if (a.SMS_Birth_date_Field__pc == today) {
                outs.add(new Outgoing('B2', a.OwnerId, parent, phone, a.LoWs_Texts_Off__c, values));
            }
            if (a.Loan_Anniversary_Date__pc == today && a.Closing_Date__pc != null && a.Closing_Date__pc.year() != today.year()) {
                outs.add(new Outgoing('B3', a.OwnerId, parent, phone, a.LoWs_Texts_Off__c, values));
            }
        }
        send(outs);
    }

    // ------------------------------------------------------------------ helpers

    static String join(String first, String last) {
        return ((first ?? '') + ' ' + (last ?? '')).trim();
    }

    @TestVisible
    static String money(Decimal amount) {
        if (amount == null) {
            return '';
        }
        return '$' + amount.setScale(0).format();
    }
}
