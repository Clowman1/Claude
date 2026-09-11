public with sharing class LeadDocumentPortalController {
    @AuraEnabled
    public static LeadDocumentPortalService.PortalData initializeData(String hashFromURL, Boolean isInSitePreview) {
        try {
            return LeadDocumentPortalService.initializeData(hashFromURL, isInSitePreview);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static LeadDocumentPortalService.PortalRequest updateRequestOnFileUpload(
        List<Id> contentVersionIds,
        Id requestId,
        String hashFromURL
    ) {
        try {
            return LeadDocumentPortalService.updateRequestOnFileUpload(contentVersionIds, requestId, hashFromURL);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'LeadDocumentPortalController.updateRequestOnFileUpload failed for requestId=' +
                requestId + ' hash=' + hashFromURL + ' versions=' + contentVersionIds + ' :: ' +
                ex.getTypeName() + ': ' + ex.getMessage() + '\n' + ex.getStackTraceString()
            );
            throw new AuraHandledException(ex.getTypeName() + ': ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static LeadDocumentPortalService.PortalRequest uploadBorrowerDocument(
        String hashFromURL,
        Id requestId,
        String fileName,
        String base64Data
    ) {
        try {
            return LeadDocumentPortalService.uploadBorrowerDocument(hashFromURL, requestId, fileName, base64Data);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'LeadDocumentPortalController.uploadBorrowerDocument failed for requestId=' + requestId +
                ' hash=' + hashFromURL + ' :: ' + ex.getTypeName() + ': ' + ex.getMessage()
            );
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * Submits everything in the borrower's basket and sends the lead team one email for the
     * session. Returns the refreshed portal so the pills and counts settle in one round trip.
     */
    @AuraEnabled
    public static LeadDocumentPortalService.PortalData submitPendingDocuments(String hashFromURL) {
        try {
            return LeadDocumentPortalService.submitPendingDocuments(hashFromURL);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // Removing is only ever possible before submitting, so the borrower can correct a mistake
    // without the lead team having seen it.
    @AuraEnabled
    public static Integer removePendingDocument(String hashFromURL, Id contentDocumentId) {
        try {
            return LeadDocumentPortalService.removePendingDocument(hashFromURL, contentDocumentId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }
}
