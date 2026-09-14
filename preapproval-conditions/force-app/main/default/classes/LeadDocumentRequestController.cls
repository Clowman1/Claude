public with sharing class LeadDocumentRequestController {
    @AuraEnabled
    public static LeadDocumentRequestService.LeadDocumentRequestData initializeData(Id leadId) {
        return LeadDocumentRequestService.initializeInternalData(leadId);
    }

    @AuraEnabled
    public static List<LeadDocumentRequestService.RequestItem> saveRequests(
        Id leadId,
        List<LeadDocumentRequestService.RequestInput> requests
    ) {
        return LeadDocumentRequestService.saveRequests(leadId, requests);
    }

    @AuraEnabled
    public static void deleteRequest(Id requestId) {
        LeadDocumentRequestService.deleteRequest(requestId);
    }

    @AuraEnabled
    public static LeadDocumentRequestService.RequestItem saveNotes(Id requestId, String description) {
        return LeadDocumentRequestService.saveNotes(requestId, description);
    }

    @AuraEnabled
    public static LeadDocumentRequestService.RequestItem handleInternalFileUpload(
        Id requestId,
        List<Id> contentVersionIds
    ) {
        return LeadDocumentRequestService.handleInternalFileUpload(requestId, contentVersionIds);
    }

    @AuraEnabled(cacheable=true)
    public static List<LeadDocumentRequestService.DocumentItem> getRequestDocuments(Id requestId) {
        return LeadDocumentRequestService.getRequestDocuments(requestId);
    }

    @AuraEnabled
    public static LeadDocumentRequestService.RequestItem approveRequestDocument(
        Id requestId,
        Id contentDocumentId,
        Boolean closeWhenNoneRemaining
    ) {
        return LeadDocumentRequestService.approveRequestDocument(requestId, contentDocumentId, closeWhenNoneRemaining);
    }

    @AuraEnabled
    public static LeadDocumentRequestService.RequestItem markRequestDocumentNotNeeded(
        Id requestId,
        Id contentDocumentId,
        Boolean closeWhenNoneRemaining
    ) {
        return LeadDocumentRequestService.markRequestDocumentNotNeeded(
            requestId,
            contentDocumentId,
            closeWhenNoneRemaining
        );
    }

    @AuraEnabled
    public static LeadDocumentRequestService.RequestItem rejectRequestDocument(
        Id requestId,
        Id contentDocumentId,
        String rejectionReason,
        String updatedRequestDescription
    ) {
        return LeadDocumentRequestService.rejectRequestDocument(
            requestId,
            contentDocumentId,
            rejectionReason,
            updatedRequestDescription
        );
    }

    @AuraEnabled
    public static LeadDocumentRequestService.EmailInformation getEmailPreview(Id leadId) {
        return LeadDocumentRequestService.getEmailPreview(leadId);
    }

    @AuraEnabled(cacheable=true)
    public static List<LeadDocumentRequestService.EmailTemplateOption> getEmailTemplateOptions() {
        return LeadDocumentRequestService.getEmailTemplateOptions();
    }

    @AuraEnabled
    public static LeadDocumentRequestService.EmailInformation getEmailTemplatePreview(
        Id leadId,
        String templateDeveloperName
    ) {
        return LeadDocumentRequestService.getEmailTemplatePreview(leadId, templateDeveloperName);
    }

    // Returns null on a clean send, or a warning when the email left but Salesforce could not
    // finish updating the Lead - the sender needs to know the difference before resending.
    @AuraEnabled
    public static String sendRequestEmail(Id leadId) {
        return LeadDocumentRequestService.sendRequestEmail(leadId);
    }

    @AuraEnabled
    public static String sendEditedRequestEmail(Id leadId, String subject, String htmlBody) {
        return LeadDocumentRequestService.sendEditedRequestEmail(leadId, subject, htmlBody);
    }

    /**
     * One email per borrower, each listing only their own items plus anything shared with the file.
     * Returns a per-recipient summary so the sender can see who actually received what.
     */
    /** Read-only preview of the shared wording, without any one borrower's item list. */
    @AuraEnabled
    public static String getSharedTemplatePreview(Id leadId, String templateDeveloperName) {
        return LeadDocumentRequestService.getSharedTemplatePreview(leadId, templateDeveloperName);
    }

    @AuraEnabled
    public static List<String> sendPerBorrowerRequestEmails(Id leadId, String subject, String templateDeveloperName) {
        return LeadDocumentRequestService.sendPerBorrowerRequestEmails(leadId, subject, templateDeveloperName);
    }

    @AuraEnabled
    public static String sendComposedRequestEmail(
        Id leadId,
        String subject,
        String htmlBody,
        String toAddresses,
        String ccAddresses,
        String templateDeveloperName
    ) {
        return LeadDocumentRequestService.sendEditedRequestEmail(
            leadId,
            subject,
            htmlBody,
            toAddresses,
            ccAddresses,
            templateDeveloperName
        );
    }
}