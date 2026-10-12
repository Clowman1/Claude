/**
 * Stops a Lead converting while its Pre-Approval Conditions are still open.
 *
 * A Lead that converts mid-review takes its documents to the Transaction undecisioned, and because
 * filing happens on the decision rather than on the upload, those documents land in no folder at
 * all. The Ashwin Patel file converted that way on 15 Sep 2026.
 *
 * Runs without sharing on purpose: a guard that can be walked past by someone who simply cannot see
 * the conditions is not a guard. Nothing here is returned to the caller, so no record the running
 * user could not otherwise reach is exposed - only the Lead in front of them is blocked.
 */
public without sharing class LeadConversionGuardService {
    @TestVisible
    private static final String BLOCK_MESSAGE =
        // externalLoLeadConversionModal recognises the block by its first sentence; keep them in step.
        'Finish the document review first. This lead can\'t convert until (1) every uploaded document ' +
        'is approved or rejected, and (2) every open document request is cleared, approved or completed. ' +
        'Nothing on the lead has changed.';

    /**
     * The three statuses the borrower portal already treats as finished. A request holding a
     * document that nobody has decisioned yet sits in Review, and a request with nothing against it
     * sits in Requested or New, so the request status covers conditions and documents together.
     */
    private static final Set<String> FINISHED_STATUSES = new Set<String>{
        'Cleared',
        'Approved',
        'Completed'
    };

    public static void blockConversionWithOpenConditions(List<Lead> updatedLeads, Map<Id, Lead> priorLeads) {
        if (updatedLeads == null || priorLeads == null) {
            return;
        }

        Set<Id> convertingLeadIds = new Set<Id>();
        for (Lead updatedLead : updatedLeads) {
            Lead priorLead = priorLeads.get(updatedLead.Id);
            if (updatedLead.IsConverted == true && priorLead != null && priorLead.IsConverted == false) {
                convertingLeadIds.add(updatedLead.Id);
            }
        }
        if (convertingLeadIds.isEmpty()) {
            return;
        }

        requireRecycledBorrowerAccount(updatedLeads, convertingLeadIds);

        Set<Id> blockedLeadIds = leadsWithOpenConditions(convertingLeadIds);
        for (Lead updatedLead : updatedLeads) {
            if (blockedLeadIds.contains(updatedLead.Id)) {
                updatedLead.addError(BLOCK_MESSAGE);
            }
        }
    }

    @TestVisible
    private static final String RECYCLED_ACCOUNT_MESSAGE =
        'This lead came back from a cancelled loan. Convert it into the borrower\'s existing account (';

    /**
     * U8: a recycled lead must convert into the Person Account of the loan it was recycled from, so the
     * borrower never gets a duplicate account. Covers the standard Convert button; ConvertLeadsInvocable
     * already passes that account for the flow and LO Workspace paths.
     */
    private static void requireRecycledBorrowerAccount(List<Lead> updatedLeads, Set<Id> convertingLeadIds) {
        Set<Id> loanIds = new Set<Id>();
        for (Lead l : updatedLeads) {
            if (convertingLeadIds.contains(l.Id) && l.Recycled_From_Transaction__c != null) {
                loanIds.add(l.Recycled_From_Transaction__c);
            }
        }
        if (loanIds.isEmpty()) {
            return;
        }
        Map<Id, Transaction__c> loans = new Map<Id, Transaction__c>([
            SELECT Id, Borrower_Name__c, Borrower_Name__r.Name FROM Transaction__c WHERE Id IN :loanIds
        ]);
        for (Lead l : updatedLeads) {
            Transaction__c t = loans.get(l.Recycled_From_Transaction__c);
            if (convertingLeadIds.contains(l.Id) && t != null && t.Borrower_Name__c != null
                && l.ConvertedAccountId != t.Borrower_Name__c) {
                l.addError(RECYCLED_ACCOUNT_MESSAGE + t.Borrower_Name__r.Name + ').');
            }
        }
    }

    // Filtered in Apex rather than in SOQL: a NOT IN clause would quietly let a request with no
    // status at all through, and an unset status is the one case most in need of a look.
    private static Set<Id> leadsWithOpenConditions(Set<Id> leadIds) {
        Set<Id> blockedLeadIds = new Set<Id>();
        for (Lead_Document_Request__c requestRecord : [
            SELECT Lead__c, Status__c
            FROM Lead_Document_Request__c
            WHERE Lead__c IN :leadIds
            WITH SYSTEM_MODE
        ]) {
            if (!FINISHED_STATUSES.contains(requestRecord.Status__c)) {
                blockedLeadIds.add(requestRecord.Lead__c);
            }
        }
        return blockedLeadIds;
    }
}