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

    @AuraEnabled
    public static void notifyLeadTeamOfCompletedUpload(String hashFromURL, Id requestId, Integer fileCount) {
        try {
            LeadDocumentPortalService.notifyLeadTeamOfCompletedUpload(hashFromURL, requestId, fileCount);
        } catch (Exception ex) {
            // The borrower's documents are already saved; a failed notification must not surface
            // to them as a failed upload.
            System.debug(LoggingLevel.ERROR,
                'LeadDocumentPortalController.notifyLeadTeamOfCompletedUpload failed for requestId=' +
                requestId + ' :: ' + ex.getTypeName() + ': ' + ex.getMessage()
            );
        }
    }
}
