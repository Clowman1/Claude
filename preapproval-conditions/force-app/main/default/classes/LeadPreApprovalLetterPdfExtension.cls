/**
 * Feeds the finalized letter into the PDF page. The HTML is read straight off the Lead because
 * that is where Finalize stored it: Salesforce renders a PDF only from a Visualforce page, and a
 * whole letter will not survive a URL parameter.
 */
public with sharing class LeadPreApprovalLetterPdfExtension {
    private final Id leadId;

    public LeadPreApprovalLetterPdfExtension(ApexPages.StandardController controller) {
        this.leadId = controller.getId();
    }

    public String getLetterHtml() {
        List<Lead> leads = [
            SELECT Id, Pre_Approval_Letter_HTML__c
            FROM Lead
            WHERE Id = :leadId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (leads.isEmpty() || String.isBlank(leads[0].Pre_Approval_Letter_HTML__c)) {
            return '<p style="font-family:Arial,sans-serif;">No pre-approval letter has been finalized for this Lead yet.</p>';
        }
        return leads[0].Pre_Approval_Letter_HTML__c;
    }
}
