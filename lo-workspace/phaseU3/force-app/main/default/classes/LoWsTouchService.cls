/**
 * Weekly pre-approval touch (decided 2026-10-08): a completed call / text / email Task, a meeting
 * (Event), or any email to or from the lead's address. A lead is due once 7+ days pass without one.
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
        Map<String, Set<Id>> leadIdsByEmail = new Map<String, Set<Id>>();
        for (Lead l : leads) {
            if (String.isNotBlank(l.Email)) {
                String key = l.Email.toLowerCase();
                if (!leadIdsByEmail.containsKey(key)) {
                    leadIdsByEmail.put(key, new Set<Id>());
                }
                leadIdsByEmail.get(key).add(l.Id);
            }
        }
        Datetime since = System.now().addDays(-LOOKBACK_DAYS);
        Datetime now = System.now();
        Map<Id, Datetime> last = new Map<Id, Datetime>();

        for (AggregateResult row : [
            SELECT WhoId leadId, MAX(CreatedDate) lastAt
            FROM Task
            WHERE WhoId IN :leadIds
              AND Status = 'Completed'
              AND CreatedDate >= :since
              AND (TaskSubtype IN ('Call', 'Email') OR InteractionType__c IN ('Call', 'Sms')
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

        Set<String> emails = leadIdsByEmail.keySet();
        for (EmailMessageRelation rel : [
            SELECT RelationId, RelationAddress, EmailMessage.MessageDate
            FROM EmailMessageRelation
            WHERE (RelationId IN :leadIds OR RelationAddress IN :emails)
              AND EmailMessage.MessageDate >= :since
            WITH SYSTEM_MODE
            ORDER BY EmailMessage.MessageDate DESC
            LIMIT 2000
        ]) {
            Datetime at = rel.EmailMessage.MessageDate;
            if (leadIds.contains(rel.RelationId)) {
                keepLatest(last, rel.RelationId, at);
            }
            Set<Id> byAddress = rel.RelationAddress == null ? null : leadIdsByEmail.get(rel.RelationAddress.toLowerCase());
            if (byAddress != null) {
                for (Id leadId : byAddress) {
                    keepLatest(last, leadId, at);
                }
            }
        }
        return last;
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
