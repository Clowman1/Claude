/**
 * LO Workspace lead Overview: the borrower switcher (primary = the Lead itself, co-borrowers =
 * Borrower__c rows, per the multi-borrower model). The list uses the same filter as
 * BorrowerPersonAccountService.getBorrowers (the internal borrowerPanel), plus Relationship__c.
 *
 * Read: the lead must be visible (with sharing). An outside LO also passes the Borrower__c restriction
 * rule, because ExternalLoStampBorrower stamps External_LO__c from the parent lead's owner.
 * Add / remove: only on a lead the running user owns (not converted). SYSTEM_MODE DML after that check,
 * as in LoWsContactService. Editing a co-borrower goes through LoWsContactService.updateContact.
 */
public with sharing class LoWsBorrowerService {

    public static final String HAS_ASSIGNMENTS =
        'This borrower has document requests or conditions assigned. Reassign or delete them first.';

    public class BorrowerPill {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean primary = false;
        @AuraEnabled public Boolean noEmail = false; // co-borrower without an email: warn on the pill
        BorrowerPill(Id id, String label, Boolean primary) {
            this.id = id;
            this.label = label;
            this.primary = primary;
        }
    }

    public class BorrowerList {
        @AuraEnabled public List<BorrowerPill> pills = new List<BorrowerPill>();
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public List<String> relationships = new List<String>();
    }

    public static BorrowerList listBorrowers(Id leadId) {
        Lead l = requireLead(leadId);
        BorrowerList out = new BorrowerList();
        out.canEdit = LoWsContactService.leadEditBlocker(l) == null;
        out.pills.add(new BorrowerPill(l.Id, l.Name + ' (Primary)', true));
        out.relationships = LoWsContactService.relationshipValues();
        // Same filter as BorrowerPersonAccountService.getBorrowers, plus Relationship__c for the label.
        for (Borrower__c b : [
            SELECT Id, Name, Email__c, Relationship__c FROM Borrower__c
            WHERE Lead__c = :leadId AND Removed__c = false ORDER BY CreatedDate
        ]) {
            String name = String.isBlank(b.Name) ? 'Co-borrower' : b.Name;
            BorrowerPill pill = new BorrowerPill(b.Id, String.isBlank(b.Relationship__c) ? name : name + ' (' + b.Relationship__c + ')', false);
            pill.noEmail = String.isBlank(b.Email__c);
            out.pills.add(pill);
        }
        return out;
    }

    /** First + last name required; phone, email, relationship optional. Returns the new Borrower__c Id. */
    public static Id addBorrower(Id leadId, String firstName, String lastName, String phone, String email, String relationship) {
        requireOwnedLead(leadId);
        Borrower__c b = LoWsContactService.borrowerFields(firstName, lastName, phone, email, relationship);
        b.Lead__c = leadId;
        Database.insert(b, AccessLevel.SYSTEM_MODE);
        return b.Id;
    }

    /**
     * Only when nothing is assigned to them: Lead_Document_Request__c / Condition__c point at a
     * borrower with Restrict lookups, and removing one must never turn their private items shared.
     */
    public static void removeBorrower(Id borrowerId) {
        LoWsContactService.ContactInfo current = LoWsContactService.getContact(borrowerId);
        if (current.isBorrower != true) throw new DomainException(LoWsContactService.NOT_FOUND);
        if (current.canEdit != true) throw new DomainException(current.note ?? LoWsContactService.NOT_OWNER_NOTE);
        Integer assigned = [SELECT COUNT() FROM Lead_Document_Request__c WHERE Borrower__c = :borrowerId WITH SYSTEM_MODE]
            + [SELECT COUNT() FROM Condition__c WHERE Borrower__c = :borrowerId WITH SYSTEM_MODE];
        if (assigned > 0) throw new DomainException(HAS_ASSIGNMENTS);
        try {
            Database.delete(new Borrower__c(Id = borrowerId), AccessLevel.SYSTEM_MODE);
        } catch (DmlException e) {
            // Any other Restrict lookup added later: say so instead of a raw DELETE_FAILED.
            throw new DomainException(HAS_ASSIGNMENTS);
        }
    }

    private static Lead requireLead(Id leadId) {
        LoWsContactService.requireInternal();
        List<Lead> leads = [SELECT Id, Name, OwnerId, IsConverted FROM Lead WHERE Id = :leadId];
        if (leads.isEmpty()) throw new DomainException(LoWsContactService.NOT_FOUND);
        return leads[0];
    }

    private static void requireOwnedLead(Id leadId) {
        String blocker = LoWsContactService.leadEditBlocker(requireLead(leadId));
        if (blocker != null) throw new DomainException(blocker);
    }
}