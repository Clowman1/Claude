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
    static void moveFilesRefilesAndOrdersTheDestinationFolder() {
        Lead leadRecord = buildLead();
        Id first = linkedDocument('first.pdf', 'Asset', leadRecord.Id);
        Id second = linkedDocument('second.pdf', 'Income', leadRecord.Id);
        Id notOnLead = [
            SELECT ContentDocumentId FROM ContentVersion
            WHERE Id = :buildContentVersion('stray.pdf', null, 'Asset').Id
        ].ContentDocumentId;

        Test.startTest();
        // Drop "first" into Income, ahead of the file already there.
        DocumentViewerController.moveFiles(leadRecord.Id, 'Income', new List<Id>{ first, second });
        Boolean refused = false;
        try {
            DocumentViewerController.moveFiles(leadRecord.Id, 'Income', new List<Id>{ notOnLead });
        } catch (AuraHandledException e) {
            refused = true;
        }
        List<DocumentViewerController.DocumentWrapper> wrappers = DocumentViewerController.getDocs(leadRecord.Id);
        Test.stopTest();

        System.assert(refused, 'A file that is not on the record must not be moved.');
        Map<Id, DocumentViewerController.DocumentWrapper> byId = new Map<Id, DocumentViewerController.DocumentWrapper>();
        for (DocumentViewerController.DocumentWrapper wrapper : wrappers) {
            byId.put(wrapper.id, wrapper);
        }
        System.assertEquals('Income', byId.get(first).folderName);
        System.assertEquals(0, byId.get(first).sortOrder);
        System.assertEquals(1, byId.get(second).sortOrder);
        System.assertEquals('Asset', [
            SELECT Folder__c FROM ContentVersion WHERE ContentDocumentId = :notOnLead
        ].Folder__c);
    }

    @IsTest
    static void finishMergeFilesTheMergedPdfAndDeletesOnlyTheParts() {
        Lead leadRecord = buildLead();
        Lead_Document_Request__c requestRecord = buildRequest(leadRecord.Id, 'Bank Statements', 'Asset');
        Id partTwo = linkedDocument('May Statement (part 2 of 2)', 'Asset', leadRecord.Id);
        Id partOne = linkedDocument('May Statement (part 1 of 2)', 'Asset', leadRecord.Id);
        Id letter = linkedDocument('Explanation letter', 'Conditions', leadRecord.Id);
        // The portal links its uploads to the request; the merged file must be counted there too.
        insert new ContentDocumentLink(ContentDocumentId = partOne, LinkedEntityId = requestRecord.Id, ShareType = 'V', Visibility = 'AllUsers');
        update new ContentVersion(Id = latestVersionId(partOne), Sort_Order__c = 3);
        // Stands in for the file the bridge page creates through the REST API.
        ContentVersion merged = new ContentVersion(
            Title = 'May Statement', PathOnClient = 'May Statement.pdf',
            VersionData = Blob.valueOf('merged'), FirstPublishLocationId = leadRecord.Id
        );
        insert merged;
        Id strangerFile = [
            SELECT ContentDocumentId FROM ContentVersion
            WHERE Id = :buildContentVersion('stray.pdf', null, 'Asset').Id
        ].ContentDocumentId;

        Test.startTest();
        // Clicked part 1 first, so its folder and position win.
        Integer deleted = DocumentViewerController.finishMerge(
            leadRecord.Id, merged.Id, new List<Id>{ partOne, partTwo, letter }
        );
        Boolean refused = false;
        try {
            DocumentViewerController.finishMerge(leadRecord.Id, merged.Id, new List<Id>{ strangerFile });
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        ContentVersion filed = [
            SELECT Folder__c, Sort_Order__c, ContentDocumentId FROM ContentVersion WHERE Id = :merged.Id
        ];
        System.assertEquals(2, deleted, 'Both portal parts are replaced by the merged file.');
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id IN (:partOne, :partTwo)]);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :letter], 'Other sources are kept.');
        System.assertEquals('Asset', filed.Folder__c);
        System.assertEquals(3, filed.Sort_Order__c);
        System.assertEquals(1, [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE ContentDocumentId = :filed.ContentDocumentId AND LinkedEntityId = :requestRecord.Id
        ], 'The merged file inherits the request link.');
        System.assert(refused, 'A file that is not on the record must not be touched.');
    }

    @IsTest
    static void rotationReadsTheFileAndSavesANewVersionOfIt() {
        ContentVersion original = buildContentVersion('licence.pdf', null, 'ID');
        Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :original.Id].ContentDocumentId;

        Test.startTest();
        DocumentViewerController.DocumentContentDto content = DocumentViewerController.getDocumentContent(documentId);
        Id rotatedId = DocumentViewerController.saveRotatedDocument(
            documentId, EncodingUtil.base64Encode(Blob.valueOf('rotated')), null
        );
        Test.stopTest();

        System.assertEquals('test file body', EncodingUtil.base64Decode(content.base64Data).toString());
        ContentVersion rotated = [SELECT ContentDocumentId, Folder__c, IsLatest FROM ContentVersion WHERE Id = :rotatedId];
        System.assertEquals(documentId, rotated.ContentDocumentId, 'A rotation is a new version of the same file.');
        System.assertEquals('ID', rotated.Folder__c);
        System.assert(rotated.IsLatest);
    }

    private static Id latestVersionId(Id documentId) {
        return [SELECT LatestPublishedVersionId FROM ContentDocument WHERE Id = :documentId].LatestPublishedVersionId;
    }

    private static Id linkedDocument(String title, String folder, Id recordId) {
        Id documentId = [
            SELECT ContentDocumentId FROM ContentVersion
            WHERE Id = :buildContentVersion(title, null, folder).Id
        ].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId = documentId, LinkedEntityId = recordId, ShareType = 'V');
        return documentId;
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

    @IsTest
    static void addingADocumentFilesItAndUsesTheTypedLabel() {
        Lead leadRecord = buildLead();
        ContentVersion uploaded = buildContentVersion('scan0001.pdf', null, null);
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :uploaded.Id]
                .ContentDocumentId,
            LinkedEntityId = leadRecord.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert link;

        Test.startTest();
        // The label is typed with an extension on purpose: viewers append the real one, so
        // "W2 2025.pdf" would otherwise display as "W2 2025.pdf.pdf".
        DocumentViewerController.applyUploadDetails(
            new List<Id>{ uploaded.Id }, 'Income', 'W2 2025.pdf'
        );
        Test.stopTest();

        ContentVersion filed = [
            SELECT Title, Folder__c FROM ContentVersion WHERE Id = :uploaded.Id
        ];
        System.assertEquals('Income', filed.Folder__c, 'It lands in the folder that was chosen.');
        System.assertEquals('W2 2025', filed.Title, 'The label names the document, without the extension.');
    }

    @IsTest
    static void severalFilesAtOnceKeepTheirOwnNames() {
        ContentVersion first = buildContentVersion('bank-jan.pdf', null, null);
        ContentVersion second = buildContentVersion('bank-feb.pdf', null, null);

        Test.startTest();
        DocumentViewerController.applyUploadDetails(
            new List<Id>{ first.Id, second.Id }, 'Asset', 'Bank Statements'
        );
        DocumentViewerController.applyUploadDetails(new List<Id>(), 'Asset', 'ignored');
        DocumentViewerController.applyUploadDetails(null, 'Asset', 'ignored');
        Test.stopTest();

        List<ContentVersion> filed = [
            SELECT Title, Folder__c FROM ContentVersion
            WHERE Id IN (:first.Id, :second.Id) ORDER BY Title
        ];
        System.assertEquals('Asset', filed[0].Folder__c);
        System.assertEquals('Asset', filed[1].Folder__c);
        System.assertEquals(
            'bank-feb.pdf',
            filed[0].Title,
            'One label cannot name two files, so each keeps its own.'
        );
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