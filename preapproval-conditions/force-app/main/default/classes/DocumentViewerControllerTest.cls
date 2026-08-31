/**
 * Covers the folder-grouped document viewer that sits on both the Transaction and the Lead.
 * The Lead branches on getLoanConditions and relateFileToCondition are what let a Loan Officer
 * move a misfiled pre-approval upload to the request it actually belongs to.
 */
@IsTest
private class DocumentViewerControllerTest {

    @IsTest
    static void getLoanConditionsReturnsLeadRequestsForALead() {
        Lead leadRecord = buildLead();
        Lead_Document_Request__c firstRequest = buildRequest(leadRecord.Id, 'Bank Statements', 'Asset');
        Lead_Document_Request__c secondRequest = buildRequest(leadRecord.Id, 'Recent Paystubs', 'Income');

        Test.startTest();
        List<SObject> options = DocumentViewerController.getLoanConditions(leadRecord.Id);
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        for (SObject record : options) {
            returnedIds.add((Id) record.get('Id'));
        }
        System.assertEquals(2, options.size(), 'Both Lead document requests should be offered as move targets.');
        System.assertEquals(true, returnedIds.contains(firstRequest.Id));
        System.assertEquals(true, returnedIds.contains(secondRequest.Id));
    }

    @IsTest
    static void getLoanConditionsReturnsConditionsForATransaction() {
        Transaction__c transactionRecord = buildTransaction();
        Condition__c conditionRecord = new Condition__c(
            Transaction__c = transactionRecord.Id,
            Name = 'W-2s',
            Status__c = 'Requested'
        );
        insert conditionRecord;

        Test.startTest();
        List<SObject> options = DocumentViewerController.getLoanConditions(transactionRecord.Id);
        Test.stopTest();

        System.assertEquals(1, options.size());
        System.assertEquals(conditionRecord.Id, (Id) options[0].get('Id'));
    }

    @IsTest
    static void relateFileToLeadRequestMovesTheFileAndRefilesTheFolder() {
        Lead leadRecord = buildLead();
        Lead_Document_Request__c wrongRequest = buildRequest(leadRecord.Id, 'Bank Statements', 'Asset');
        Lead_Document_Request__c rightRequest = buildRequest(leadRecord.Id, 'Retirement Statements', 'Income');
        ContentVersion version = buildContentVersion('retirement.pdf', wrongRequest.Id, 'Asset');
        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id
        ].ContentDocumentId;

        Test.startTest();
        DocumentViewerController.relateFileToCondition(contentDocumentId, rightRequest.Id);
        Test.stopTest();

        ContentVersion movedVersion = [
            SELECT Lead_Document_Request__c, Folder__c
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = TRUE
            LIMIT 1
        ];
        Lead_Document_Request__c updatedTarget = [
            SELECT Status__c FROM Lead_Document_Request__c WHERE Id = :rightRequest.Id
        ];

        System.assertEquals(rightRequest.Id, movedVersion.Lead_Document_Request__c,
            'The document should now hang off the request it was moved to.');
        System.assertEquals('Income', movedVersion.Folder__c,
            'The folder re-derives from the destination request category.');
        System.assertEquals('Review', updatedTarget.Status__c,
            'The destination request now has a document waiting to be reviewed.');
    }

    @IsTest
    static void documentSelectorsAndFolderMaintenanceRun() {
        Lead leadRecord = buildLead();
        Lead_Document_Request__c requestRecord = buildRequest(leadRecord.Id, 'Bank Statements', 'Asset');
        ContentVersion version = buildContentVersion('bank.pdf', requestRecord.Id, 'Asset');
        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id
        ].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = requestRecord.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        List<DocumentViewerController.DocumentWrapper> wrappers = DocumentViewerController.getDocs(requestRecord.Id);
        List<ContentDocument> files = DocumentViewerController.getFiles(requestRecord.Id);
        List<ContentDocumentLink> links = DocumentViewerController.retrieveContentDocLinks(new Set<Id>{ requestRecord.Id });
        List<ContentDocument> docs = DocumentViewerController.retrieveContentDocs(new Set<Id>{ contentDocumentId });
        DocumentViewerController.changeFolder(requestRecord.Id, contentDocumentId, 'Credit');
        DocumentViewerController.renameFile(contentDocumentId, 'renamed-bank');
        DocumentViewerController.renameFolder(requestRecord.Id, 'Credit', 'Income');
        Test.stopTest();

        System.assertEquals(1, wrappers.size());
        System.assertEquals(1, files.size());
        System.assertEquals(1, links.size());
        System.assertEquals(1, docs.size());
        System.assertEquals('renamed-bank', [
            SELECT Title FROM ContentDocument WHERE Id = :contentDocumentId
        ].Title);
    }

    @IsTest
    static void deleteFileRemovesTheDocument() {
        ContentVersion version = buildContentVersion('scrap.pdf', null, 'Income');
        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id
        ].ContentDocumentId;

        Test.startTest();
        DocumentViewerController.deleteFile(contentDocumentId);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :contentDocumentId]);
    }

    @IsTest
    static void errorPathsSurfaceAsAuraHandledExceptions() {
        Boolean relateFailed = false;
        Test.startTest();
        try {
            DocumentViewerController.relateFileToCondition(null, null);
        } catch (Exception expected) {
            relateFailed = true;
        }
        Test.stopTest();

        System.assertEquals(true, relateFailed, 'A missing file should not fail silently.');
    }

    private static Lead buildLead() {
        Lead leadRecord = new Lead(
            FirstName = 'Doc',
            LastName = 'Viewer',
            Company = 'Doc Viewer Test',
            Status = 'New',
            Email = 'doc-viewer@example.com'
        );
        insert leadRecord;
        return leadRecord;
    }

    private static Transaction__c buildTransaction() {
        Transaction__c transactionRecord = new Transaction__c(Name = 'Doc Viewer Loan');
        insert transactionRecord;
        return transactionRecord;
    }

    private static Lead_Document_Request__c buildRequest(Id leadId, String name, String category) {
        Lead_Document_Request__c requestRecord = new Lead_Document_Request__c(
            Lead__c = leadId,
            Name = name,
            Subject__c = name,
            Description__c = 'Please upload ' + name,
            Category__c = category,
            Type__c = 'Loan Officer',
            Status__c = 'Requested',
            Can_Borrower_See__c = true,
            Include_In_Email__c = true
        );
        insert requestRecord;
        return requestRecord;
    }

    private static ContentVersion buildContentVersion(String title, Id requestId, String folder) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title,
            VersionData = Blob.valueOf('test file body'),
            Folder__c = folder
        );
        if (requestId != null) {
            version.Lead_Document_Request__c = requestId;
        }
        insert version;
        return version;
    }
}
