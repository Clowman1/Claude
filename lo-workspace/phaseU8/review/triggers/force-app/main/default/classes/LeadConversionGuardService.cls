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
        'Unable to convert to Transaction with outstanding Pre-Approval Conditions and Documents. ' +
        'All conditions must be cleared and documents decisioned before a Lead can be converted.';

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

        Set<Id> blockedLeadIds = leadsWithOpenConditions(convertingLeadIds);
        for (Lead updatedLead : updatedLeads) {
            if (blockedLeadIds.contains(updatedLead.Id)) {
                updatedLead.addError(BLOCK_MESSAGE);
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