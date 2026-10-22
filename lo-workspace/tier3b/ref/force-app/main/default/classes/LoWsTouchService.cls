/**
 * Weekly pre-approval touch (decided 2026-10-08, refined 2026-10-20): a human contact = a completed
 * call / text / email Task on the lead, a RingCentral call or text to/from the lead's number (RingCentral
 * often leaves WhoId blank), a meeting (Event), or an email on the lead that the borrower sent or a
 * Reach user sent from their own address (shared/system addresses such as reachus@ don't count).
 * A lead is due once 7+ days pass without one.
 * Reads run in SYSTEM_MODE but only for the leads passed in, which callers have already scoped to
 * the running LO.
 */
public with sharing class LoWsTouchService {
    public static final Integer TOUCH_DAYS = 7;
    // ponytail: touches older than 90 days are ignored; the lead falls back to its pre-approval / created date.
    private static final Integer LOOKBACK_DAYS = 90;

    public class Touch {
        public Datetime lastTouch;
        public Integer daysSince;
        public Boolean due;
    }

    public static Map<Id, Touch> touchesFor(List<Lead> leads) {
        Map<Id, Touch> out = new Map<Id, Touch>();
        if (leads == null || leads.isEmpty()) {
            return out;
        }
        Map<Id, Datetime> last = lastTouchByLead(leads);
        Datetime now = System.now();
        for (Lead l : leads) {
            Touch t = new Touch();
            t.lastTouch = last.get(l.Id);
            Datetime baseline = t.lastTouch
                ?? (l.Pre_Approval_Date__c == null ? null : Datetime.newInstance(l.Pre_Approval_Date__c, Time.newInstance(0, 0, 0, 0)))
                ?? l.CreatedDate
                ?? now;
            t.daysSince = baseline.date().daysBetween(now.date());
            t.due = t.daysSince >= TOUCH_DAYS;
            out.put(l.Id, t);
        }
        return out;
    }

    @TestVisible
    private static Map<Id, Datetime> lastTouchByLead(List<Lead> leads) {
        Set<Id> leadIds = new Map<Id, Lead>(leads).keySet();
        Datetime since = System.now().addDays(-LOOKBACK_DAYS);
        Datetime now = System.now();
        Map<Id, Datetime> last = new Map<Id, Datetime>();

        for (AggregateResult row : [
            SELECT WhoId leadId, MAX(CreatedDate) lastAt
            FROM Task
            WHERE WhoId IN :leadIds
              AND Status = 'Completed'
              AND CreatedDate >= :since
              // Email activity Tasks are skipped: Salesforce makes one for every logged email, system ones
              // included; emails are judged below on their sender. Manual email logs carry Activity_Type__c.
              AND TaskSubtype != 'Email'
              AND (TaskSubtype = 'Call' OR InteractionType__c IN ('Call', 'Sms')
                   OR Type = 'Call' OR Activity_Type__c != null)
            WITH SYSTEM_MODE
            GROUP BY WhoId
        ]) {
            keepLatest(last, (Id) row.get('leadId'), (Datetime) row.get('lastAt'));
        }

        for (AggregateResult row : [
            SELECT WhoId leadId, MAX(StartDateTime) lastAt
            FROM Event
            WHERE WhoId IN :leadIds AND StartDateTime >= :since AND StartDateTime <= :now
            WITH SYSTEM_MODE
            GROUP BY WhoId
        ]) {
            keepLatest(last, (Id) row.get('leadId'), (Datetime) row.get('lastAt'));
        }

        // RingCentral calls/texts by number (E.164 "+1XXXXXXXXXX"), whoever on the Reach side made them.
        Map<String, Set<Id>> leadIdsByNumber = new Map<String, Set<Id>>();
        for (Lead l : [SELECT Id, Phone, MobilePhone FROM Lead WHERE Id IN :leadIds WITH SYSTEM_MODE]) {
            for (String phone : new List<String>{ l.Phone, l.MobilePhone }) {
                String e164 = toE164(phone);
                if (e164 != null) {
                    if (!leadIdsByNumber.containsKey(e164)) {
                        leadIdsByNumber.put(e164, new Set<Id>());
                    }
                    leadIdsByNumber.get(e164).add(l.Id);
                }
            }
        }
        Set<String> numbers = leadIdsByNumber.keySet();
        if (!numbers.isEmpty()) {
            for (Task t : [
                SELECT CreatedDate, rcsfl__from_number__c, rcsfl__to_number__c
                FROM Task
                WHERE CreatedDate >= :since
                  AND InteractionType__c IN ('Call', 'Sms')
                  AND (rcsfl__from_number__c IN :numbers OR rcsfl__to_number__c IN :numbers)
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 2000
            ]) {
                for (String n : new List<String>{ t.rcsfl__from_number__c, t.rcsfl__to_number__c }) {
                    for (Id leadId : leadIdsByNumber.get(n) ?? new Set<Id>()) {
                        keepLatest(last, leadId, t.CreatedDate);
                    }
                }
            }
        }

        // Emails on the lead record (RelationId is indexed; matching on the address alone scanned the
        // whole table on every Home load). Human only: from the borrower, or from a Reach user's own address.
        Set<String> reachSenders = reachUserAddresses();
        for (EmailMessageRelation rel : [
            SELECT RelationId, EmailMessage.MessageDate, EmailMessage.Incoming, EmailMessage.FromAddress
            FROM EmailMessageRelation
            WHERE RelationId IN :leadIds
              AND EmailMessage.MessageDate >= :since
            WITH SYSTEM_MODE
            ORDER BY EmailMessage.MessageDate DESC
            LIMIT 2000
        ]) {
            String sender = rel.EmailMessage.FromAddress == null ? null : rel.EmailMessage.FromAddress.toLowerCase();
            if (rel.EmailMessage.Incoming == true || reachSenders.contains(sender)) {
                keepLatest(last, rel.RelationId, rel.EmailMessage.MessageDate);
            }
        }
        return last;
    }

    /** Active internal users' own email addresses (never an org-wide/shared address). */
    private static Set<String> reachUserAddresses() {
        Set<String> out = new Set<String>();
        for (User u : [SELECT Email FROM User WHERE IsActive = true AND UserType = 'Standard' WITH SYSTEM_MODE]) {
            if (u.Email != null) {
                out.add(u.Email.toLowerCase());
            }
        }
        for (OrgWideEmailAddress o : [SELECT Address FROM OrgWideEmailAddress WITH SYSTEM_MODE]) {
            out.remove(o.Address.toLowerCase());
        }
        return out;
    }

    @TestVisible
    private static String toE164(String phone) {
        String d = phone == null ? '' : phone.replaceAll('[^0-9]', '');
        if (d.length() == 11 && d.startsWith('1')) {
            d = d.substring(1);
        }
        return d.length() == 10 ? '+1' + d : null;
    }

    private static void keepLatest(Map<Id, Datetime> last, Id leadId, Datetime at) {
        if (leadId == null || at == null) {
            return;
        }
        Datetime current = last.get(leadId);
        if (current == null || at > current) {
            last.put(leadId, at);
        }
    }
}