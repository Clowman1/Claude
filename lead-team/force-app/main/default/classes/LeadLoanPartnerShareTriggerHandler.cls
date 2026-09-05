/**
 * Keeps per-Lead sharing in step with the Lead Team lookups.
 *
 * Loan Partner and Other Lead Team Member each get a Manual / Edit LeadShare -- the same
 * share the Loan Partner has always had -- so the two roles have matching access by
 * construction. Edit on the Lead is what lets them log calls, schedule events and post notes.
 */
public without sharing class LeadLoanPartnerShareTriggerHandler {
    private static final String LOAN_PARTNER_FIELD = 'Loan_Partner__c';
    private static final String OTHER_TEAM_MEMBER_FIELD = 'Other_Lead_Team_Member__c';

    private final List<Lead> newLeads;
    private final Map<Id, Lead> oldLeadsById;

    public LeadLoanPartnerShareTriggerHandler() {
        this.newLeads = (List<Lead>) Trigger.new;
        this.oldLeadsById = (Map<Id, Lead>) Trigger.oldMap;
    }

    public void handleAfterInsertOrUpdate() {
        if (newLeads == null || newLeads.isEmpty()) {
            return;
        }

        // One pass per field: syncLeadShares keys its maps by Lead Id, so a single map
        // cannot carry both team members for the same lead.
        syncField(LOAN_PARTNER_FIELD, false);
        syncField(OTHER_TEAM_MEMBER_FIELD, true);
    }

    /**
     * @param reshareOnOwnerChange Salesforce drops Manual shares when a Lead changes owner.
     *        Loan Partner recovers on its own because LeadLoanPartnerAssignment rewrites that
     *        field whenever the owner changes; Other Lead Team Member has no such backstop, so
     *        its share is re-created here instead of being silently lost.
     */
    private void syncField(String fieldApiName, Boolean reshareOnOwnerChange) {
        Map<Id, Id> createShareByLeadId = new Map<Id, Id>();
        Map<Id, Id> deleteShareByLeadId = new Map<Id, Id>();

        for (Lead leadRecord : newLeads) {
            Lead oldLead = (oldLeadsById == null) ? null : oldLeadsById.get(leadRecord.Id);
            Id newUserId = (Id) leadRecord.get(fieldApiName);
            Id oldUserId = (oldLead == null) ? null : (Id) oldLead.get(fieldApiName);

            Boolean fieldChanged = (oldUserId != newUserId);
            Boolean ownerChanged = (oldLead != null && oldLead.OwnerId != leadRecord.OwnerId);
            if (!fieldChanged && !(reshareOnOwnerChange && ownerChanged)) {
                continue;
            }

            if (fieldChanged && oldUserId != null) {
                deleteShareByLeadId.put(leadRecord.Id, oldUserId);
            }
            // The owner already holds full access, and sharing a record with its own owner is rejected.
            if (newUserId != null && newUserId != leadRecord.OwnerId) {
                createShareByLeadId.put(leadRecord.Id, newUserId);
            }
        }

        if (createShareByLeadId.isEmpty() && deleteShareByLeadId.isEmpty()) {
            return;
        }

        LoanPartnerLeadShareService.syncLeadShares(createShareByLeadId, deleteShareByLeadId);
    }
}
