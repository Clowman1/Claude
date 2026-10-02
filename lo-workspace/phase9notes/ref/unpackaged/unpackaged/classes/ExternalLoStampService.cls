/**
 * Keeps External_LO__c current on the eight objects guarded by the External LO restriction
 * rules (lo-workspace/OUTLINE.md, Phase 2). A blank stamp means outside LOs can't see the record.
 *
 * The stamp is the outside LO on the record's most specific parent:
 *   Transaction__c : Loan_Officer__c, then Loan_Partner__c, then OwnerId
 *   Lead           : OwnerId, then Loan_Partner__c
 *   Account        : OwnerId
 *   Zoom_Meeting__c: its own stamp (for Zoom_Recording__c)
 * Only users in the External Loan Officer role count, so internal-only records stay blank and
 * every call returns early while no outside LO is involved.
 *
 * Without sharing on purpose: the stamp must be computed from parents the running user may not see.
 */
public without sharing class ExternalLoStampService {

    public static final String ROLE_DEVELOPER_NAME = 'External_Loan_Officer';

    /** Child object -> parent lookup fields, most specific first. */
    @TestVisible
    static final Map<SObjectType, List<SObjectField>> PARENT_FIELDS = new Map<SObjectType, List<SObjectField>>{
        Call_Insight__c.SObjectType => new List<SObjectField>{ Call_Insight__c.Transaction__c, Call_Insight__c.Lead__c, Call_Insight__c.Account__c },
        Borrower__c.SObjectType => new List<SObjectField>{ Borrower__c.Transaction__c, Borrower__c.Lead__c, Borrower__c.Account__c },
        Enhanced_Note__c.SObjectType => new List<SObjectField>{ Enhanced_Note__c.Transaction__c, Enhanced_Note__c.Lead__c, Enhanced_Note__c.Account__c },
        Lead_Document_Request__c.SObjectType => new List<SObjectField>{ Lead_Document_Request__c.Lead__c },
        Zoom_Meeting__c.SObjectType => new List<SObjectField>{ Zoom_Meeting__c.Lead__c, Zoom_Meeting__c.Account__c },
        Zoom_Recording__c.SObjectType => new List<SObjectField>{ Zoom_Recording__c.Zoom_Meeting__c },
        Checklist__c.SObjectType => new List<SObjectField>{ Checklist__c.Transaction__c },
        Appraisal_Order__c.SObjectType => new List<SObjectField>{ Appraisal_Order__c.Loan__c }
    };

    /** Parent object -> the fields whose change can move the stamp. */
    static final Map<SObjectType, List<SObjectField>> PARENT_TRIGGER_FIELDS = new Map<SObjectType, List<SObjectField>>{
        Lead.SObjectType => new List<SObjectField>{ Lead.OwnerId, Lead.Loan_Partner__c },
        Transaction__c.SObjectType => new List<SObjectField>{ Transaction__c.Loan_Officer__c, Transaction__c.Loan_Partner__c, Transaction__c.OwnerId },
        Account.SObjectType => new List<SObjectField>{ Account.OwnerId },
        Zoom_Meeting__c.SObjectType => new List<SObjectField>{ Zoom_Meeting__c.External_LO__c }
    };

    static Set<Id> externalLoIds;

    public static Set<Id> externalLoIds() {
        if (externalLoIds == null) {
            externalLoIds = new Map<Id, User>([
                SELECT Id FROM User WHERE UserRole.DeveloperName = :ROLE_DEVELOPER_NAME AND IsActive = TRUE
            ]).keySet();
        }
        return externalLoIds;
    }

    @TestVisible
    static void resetCache() {
        externalLoIds = null;
    }

    // ------------------------------------------------------------------ child triggers (before)

    /** Before insert / before update on a child. Recomputes only new rows or rows whose parent changed. */
    public static void stampChildren(List<SObject> records, Map<Id, SObject> oldMap) {
        if (records.isEmpty() || externalLoIds().isEmpty()) {
            return;
        }
        List<SObjectField> parents = PARENT_FIELDS.get(records[0].getSObjectType());
        List<SObject> toStamp = new List<SObject>();
        for (SObject rec : records) {
            if (oldMap == null || parentChanged(rec, oldMap.get(rec.Id), parents)) {
                toStamp.add(rec);
            }
        }
        applyStamps(toStamp, parents);
    }

    // ------------------------------------------------------------------ parent triggers (after update)

    /** After update on Lead / Transaction__c / Account / Zoom_Meeting__c: re-stamp children in the background. */
    public static void restampChildrenOf(List<SObject> records, Map<Id, SObject> oldMap) {
        if (records.isEmpty()) {
            return;
        }
        Set<Id> external = externalLoIds();
        List<SObjectField> fields = PARENT_TRIGGER_FIELDS.get(records[0].getSObjectType());
        Set<Id> changed = new Set<Id>();
        for (SObject rec : records) {
            SObject old = oldMap.get(rec.Id);
            for (SObjectField f : fields) {
                Object before = old.get(f);
                Object after = rec.get(f);
                if (before != after && (external.contains((Id) before) || external.contains((Id) after))) {
                    changed.add(rec.Id);
                    break;
                }
            }
        }
        if (changed.isEmpty()) {
            return;
        }
        if (System.isQueueable() || System.isBatch() || System.isFuture() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            restamp(changed);
        } else {
            System.enqueueJob(new RestampJob(changed));
        }
    }

    public class RestampJob implements Queueable {
        final Set<Id> parentIds;
        public RestampJob(Set<Id> parentIds) {
            this.parentIds = parentIds;
        }
        public void execute(QueueableContext context) {
            restamp(parentIds);
        }
    }

    /** Recomputes the stamp on every child that points at one of these parents and saves the ones that moved. */
    @TestVisible
    static void restamp(Set<Id> parentIds) {
        for (SObjectType childType : PARENT_FIELDS.keySet()) {
            List<SObjectField> parents = PARENT_FIELDS.get(childType);
            List<String> clauses = new List<String>();
            for (SObjectField f : parents) {
                clauses.add(f.getDescribe().getName() + ' IN :parentIds');
            }
            List<String> selectFields = new List<String>{ 'Id', 'External_LO__c' };
            for (SObjectField f : parents) {
                selectFields.add(f.getDescribe().getName());
            }
            List<SObject> children = Database.query(
                'SELECT ' + String.join(selectFields, ', ') + ' FROM ' + childType.getDescribe().getName()
                + ' WHERE ' + String.join(clauses, ' OR ')
            );
            if (children.isEmpty()) {
                continue;
            }
            Map<Id, Object> before = new Map<Id, Object>();
            for (SObject c : children) {
                before.put(c.Id, c.get('External_LO__c'));
            }
            applyStamps(children, parents);
            List<SObject> moved = new List<SObject>();
            for (SObject c : children) {
                if (c.get('External_LO__c') != before.get(c.Id)) {
                    moved.add(c);
                }
            }
            if (!moved.isEmpty()) {
                update moved;
            }
        }
    }

    // ------------------------------------------------------------------ shared

    static Boolean parentChanged(SObject rec, SObject old, List<SObjectField> parents) {
        for (SObjectField f : parents) {
            if (rec.get(f) != old.get(f)) {
                return true;
            }
        }
        return false;
    }

    /** Sets External_LO__c on each record from its first parent that belongs to an outside LO. */
    static void applyStamps(List<SObject> records, List<SObjectField> parents) {
        if (records.isEmpty()) {
            return;
        }
        Set<Id> parentIds = new Set<Id>();
        for (SObject rec : records) {
            for (SObjectField f : parents) {
                Id pid = (Id) rec.get(f);
                if (pid != null) {
                    parentIds.add(pid);
                }
            }
        }
        Map<Id, Id> loByParent = resolveParents(parentIds);
        for (SObject rec : records) {
            Id stamp = null;
            for (SObjectField f : parents) {
                Id pid = (Id) rec.get(f);
                if (pid != null && loByParent.containsKey(pid)) {
                    stamp = loByParent.get(pid);
                    break;
                }
            }
            rec.put('External_LO__c', stamp);
        }
    }

    /** Parent Id -> the outside LO on it, for parents that have one. */
    static Map<Id, Id> resolveParents(Set<Id> parentIds) {
        Set<Id> external = externalLoIds();
        Map<Id, Id> result = new Map<Id, Id>();
        Set<Id> leadIds = new Set<Id>();
        Set<Id> loanIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> meetingIds = new Set<Id>();
        for (Id pid : parentIds) {
            SObjectType t = pid.getSobjectType();
            if (t == Lead.SObjectType) leadIds.add(pid);
            else if (t == Transaction__c.SObjectType) loanIds.add(pid);
            else if (t == Account.SObjectType) accountIds.add(pid);
            else if (t == Zoom_Meeting__c.SObjectType) meetingIds.add(pid);
        }
        if (!loanIds.isEmpty()) {
            for (Transaction__c t : [SELECT Id, Loan_Officer__c, Loan_Partner__c, OwnerId FROM Transaction__c WHERE Id IN :loanIds]) {
                putFirstExternal(result, t.Id, new List<Id>{ t.Loan_Officer__c, t.Loan_Partner__c, t.OwnerId }, external);
            }
        }
        if (!leadIds.isEmpty()) {
            for (Lead l : [SELECT Id, OwnerId, Loan_Partner__c FROM Lead WHERE Id IN :leadIds]) {
                putFirstExternal(result, l.Id, new List<Id>{ l.OwnerId, l.Loan_Partner__c }, external);
            }
        }
        if (!accountIds.isEmpty()) {
            for (Account a : [SELECT Id, OwnerId FROM Account WHERE Id IN :accountIds]) {
                putFirstExternal(result, a.Id, new List<Id>{ a.OwnerId }, external);
            }
        }
        if (!meetingIds.isEmpty()) {
            for (Zoom_Meeting__c m : [SELECT Id, External_LO__c FROM Zoom_Meeting__c WHERE Id IN :meetingIds AND External_LO__c != null]) {
                result.put(m.Id, m.External_LO__c);
            }
        }
        return result;
    }

    // ponytail: one stamp per record; if a loan ever has two different outside LOs (LO + LP), only the first one sees it
    static void putFirstExternal(Map<Id, Id> result, Id parentId, List<Id> candidates, Set<Id> external) {
        for (Id c : candidates) {
            if (c != null && external.contains(c)) {
                result.put(parentId, c);
                return;
            }
        }
    }
}