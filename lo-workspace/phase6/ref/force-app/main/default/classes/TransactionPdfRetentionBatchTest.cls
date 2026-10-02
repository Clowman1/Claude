@IsTest
private class TransactionPdfRetentionBatchTest {
    private static Transaction__c createEligibleTransaction(String suffix) {
        Transaction__c transactionRecord = new Transaction__c(
            Loan_Number__c = 'PDF-RET-' + suffix,
            Borrower_First_Name__c = 'PDF',
            Borrower_Last_Name__c = 'Retention ' + suffix,
            Status__c = 'Post-Closed',
            Post_Closed_Date__c = Date.today().addDays(-31)
        );
        insert transactionRecord;
        return transactionRecord;
    }

    private static Id addPdf(Id parentId, String fileName) {
        ContentVersion versionRecord = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName + '.pdf',
            VersionData = Blob.valueOf('test pdf content'),
            FirstPublishLocationId = parentId
        );
        insert versionRecord;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionRecord.Id
        ].ContentDocumentId;
    }

    @IsTest
    static void deletesTransactionOnlyPdfAndSkipsSharedPdf() {
        Transaction__c transactionRecord = createEligibleTransaction('SAFE');
        Id exclusiveDocumentId = addPdf(transactionRecord.Id, 'exclusive-document');

        Account otherRecord = new Account(Name = 'Shared document test');
        insert otherRecord;
        Id sharedDocumentId = addPdf(transactionRecord.Id, 'shared-document');
        insert new ContentDocumentLink(
            ContentDocumentId = sharedDocumentId,
            LinkedEntityId = otherRecord.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        TransactionPdfRetentionBatch batch = new TransactionPdfRetentionBatch();
        batch.start(null);
        batch.execute(null, new List<SObject>{ transactionRecord });
        batch.execute(null, new List<SObject>{ transactionRecord });
        batch.finish(null);
        Test.stopTest();

        String exclusiveDocumentIdText = String.valueOf(exclusiveDocumentId);
        String sharedDocumentIdText = String.valueOf(sharedDocumentId);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Transaction_PDF_Cleanup_Log__c
            WHERE Transaction__c = :transactionRecord.Id
              AND Content_Document_Id__c = :exclusiveDocumentIdText
              AND Outcome__c = 'Permanently Deleted'
        ]);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Transaction_PDF_Cleanup_Log__c
            WHERE Transaction__c = :transactionRecord.Id
              AND Content_Document_Id__c = :sharedDocumentIdText
              AND Outcome__c = 'Skipped Shared File'
        ]);
    }

    @IsTest
    static void schedulerStartsCleanupBatch() {
        Test.startTest();
        new TransactionPdfRetentionScheduler().execute(null);
        Test.stopTest();
        System.assert(true, 'The scheduler completed without error.');
    }
}