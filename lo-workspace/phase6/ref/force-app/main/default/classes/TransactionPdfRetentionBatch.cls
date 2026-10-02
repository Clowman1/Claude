public without sharing class TransactionPdfRetentionBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final Integer RETENTION_DAYS = 30;
    // The approved historical cleanup begins with the supplied February 2025 report.
    public static final Date INITIAL_BACKFILL_START_DATE = Date.newInstance(2025, 2, 1);
    public Integer permanentlyDeleted = 0;
    public Integer skippedShared = 0;
    public Integer failed = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        Date cutoffDate = Date.today().addDays(-RETENTION_DAYS);
        return Database.getQueryLocator([
            SELECT Id, Name
            FROM Transaction__c
            WHERE Status__c = 'Post-Closed'
              AND Post_Closed_Date__c != NULL
              AND Post_Closed_Date__c >= :INITIAL_BACKFILL_START_DATE
              AND Post_Closed_Date__c <= :cutoffDate
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Set<Id> transactionIds = new Map<Id, SObject>(scope).keySet();
        Map<Id, Id> transactionByDocumentId = new Map<Id, Id>();
        Map<Id, String> nameByDocumentId = new Map<Id, String>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :transactionIds
              AND ContentDocument.FileExtension = 'pdf'
        ]) {
            transactionByDocumentId.put(link.ContentDocumentId, link.LinkedEntityId);
            nameByDocumentId.put(link.ContentDocumentId, link.ContentDocument.Title + '.pdf');
        }
        if (transactionByDocumentId.isEmpty()) return;

        Set<String> documentIdTexts = new Set<String>();
        for (Id documentId : transactionByDocumentId.keySet()) documentIdTexts.add(String.valueOf(documentId));
        Set<String> alreadyLoggedSharedDocumentIds = new Set<String>();
        for (Transaction_PDF_Cleanup_Log__c logRecord : [
            SELECT Content_Document_Id__c
            FROM Transaction_PDF_Cleanup_Log__c
            WHERE Content_Document_Id__c IN :documentIdTexts
              AND Outcome__c = 'Skipped Shared File'
        ]) {
            alreadyLoggedSharedDocumentIds.add(logRecord.Content_Document_Id__c);
        }

        Map<Id, Set<Id>> businessLinksByDocumentId = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :transactionByDocumentId.keySet()
        ]) {
            // Salesforce creates an inferred ContentDocumentLink to the uploading User.
            // It is not a business-record attachment and is intentionally ignored.
            if (!String.valueOf(link.LinkedEntityId).startsWith('005')) {
                if (!businessLinksByDocumentId.containsKey(link.ContentDocumentId)) {
                    businessLinksByDocumentId.put(link.ContentDocumentId, new Set<Id>());
                }
                businessLinksByDocumentId.get(link.ContentDocumentId).add(link.LinkedEntityId);
            }
        }

        List<ContentDocument> documentsToDelete = new List<ContentDocument>();
        List<Transaction_PDF_Cleanup_Log__c> logs = new List<Transaction_PDF_Cleanup_Log__c>();
        for (Id documentId : transactionByDocumentId.keySet()) {
            if (!businessLinksByDocumentId.containsKey(documentId)
                || businessLinksByDocumentId.get(documentId).size() != 1
                || !businessLinksByDocumentId.get(documentId).contains(transactionByDocumentId.get(documentId))) {
                skippedShared++;
                if (!alreadyLoggedSharedDocumentIds.contains(String.valueOf(documentId))) {
                    logs.add(newLog(transactionByDocumentId.get(documentId), documentId, nameByDocumentId.get(documentId), 'Skipped Shared File', 'File is linked to another Salesforce business record.'));
                }
            } else {
                documentsToDelete.add(new ContentDocument(Id = documentId));
            }
        }

        Database.DeleteResult[] deleteResults = Database.delete(documentsToDelete, false);
        List<ContentDocument> deletedDocuments = new List<ContentDocument>();
        for (Integer index = 0; index < deleteResults.size(); index++) {
            Id documentId = documentsToDelete[index].Id;
            if (deleteResults[index].isSuccess()) {
                deletedDocuments.add(documentsToDelete[index]);
            } else {
                failed++;
                logs.add(newLog(transactionByDocumentId.get(documentId), documentId, nameByDocumentId.get(documentId), 'Delete Failed', deleteResults[index].getErrors()[0].getMessage()));
            }
        }
        if (!deletedDocuments.isEmpty()) {
            try {
                if (!Test.isRunningTest()) Database.emptyRecycleBin(deletedDocuments);
                permanentlyDeleted += deletedDocuments.size();
                for (ContentDocument documentRecord : deletedDocuments) logs.add(newLog(transactionByDocumentId.get(documentRecord.Id), documentRecord.Id, nameByDocumentId.get(documentRecord.Id), 'Permanently Deleted', 'PDF was exclusively linked to this eligible Post-Closed Transaction.'));
            } catch (Exception error) {
                failed += deletedDocuments.size();
                for (ContentDocument documentRecord : deletedDocuments) logs.add(newLog(transactionByDocumentId.get(documentRecord.Id), documentRecord.Id, nameByDocumentId.get(documentRecord.Id), 'Recycle Bin Retained', error.getMessage()));
            }
        }
        if (!logs.isEmpty()) insert logs;
    }

    public void finish(Database.BatchableContext context) { }

    private static Transaction_PDF_Cleanup_Log__c newLog(Id transactionId, Id documentId, String fileName, String outcome, String reason) {
        return new Transaction_PDF_Cleanup_Log__c(Transaction__c = transactionId, Content_Document_Id__c = String.valueOf(documentId), File_Name__c = fileName, Outcome__c = outcome, Reason__c = reason, Processed_At__c = System.now());
    }
}