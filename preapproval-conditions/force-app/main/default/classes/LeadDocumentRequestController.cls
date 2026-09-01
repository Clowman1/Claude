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

    @AuraEnabled
    public static void sendRequestEmail(Id leadId) {
        LeadDocumentRequestService.sendRequestEmail(leadId);
    }

    @AuraEnabled
    public static void sendEditedRequestEmail(Id leadId, String subject, String htmlBody) {
        LeadDocumentRequestService.sendEditedRequestEmail(leadId, subject, htmlBody);
    }

    // Separate name rather than an overload: @AuraEnabled methods cannot be overloaded.
    @AuraEnabled
    public static void sendComposedRequestEmail(
        Id leadId,
        String subject,
        String htmlBody,
        String toAddresses,
        String ccAddresses,
        String templateDeveloperName
    ) {
        LeadDocumentRequestService.sendEditedRequestEmail(
            leadId,
            subject,
            htmlBody,
            toAddresses,
            ccAddresses,
            templateDeveloperName
        );
    }
}