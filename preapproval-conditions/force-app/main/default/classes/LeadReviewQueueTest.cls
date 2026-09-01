/**
 * Covers pre-approval document requests appearing in the shared Pending Review tray, and the
 * review actions routing to the Lead service rather than the Transaction one.
 *
 * The rule under test: a Lead has no assignee, so both the Owner and the Loan Partner see the
 * item and either can clear it.
 */
@IsTest
private class LeadReviewQueueTest {

    @IsTest
    static void ownerSeesPendingLeadRequestsInTheQueue() {
        Lead leadRecord = buildLead(UserInfo.getUserId(), null);
        Lead_Document_Request__c requestRecord = buildRequest(leadRecord.Id, 'Bank Statements', 'Asset');
        attachDocument(requestRecord.Id, 'statement.pdf');

        Test.startTest();
        List<ConditionReviewQueueService.LoanQueueDto> queue = ConditionReviewQueueService.buildQueue();
        Test.stopTest();

        ConditionReviewQueueService.LoanQueueDto leadEntry = findEntry(queue, leadRecord.Id);
        System.assertNotEquals(null, leadEntry, 'The Lead Owner should see the pending request.');
        System.assertEquals('Pre-Approval', leadEntry.stage);
        System.assertEquals(1, leadEntry.pendingConditionsCount);
        System.assertEquals(0, leadEntry.unreadCommentsCount, 'Pre-approval conditions carry no comments.');
        System.assertEquals('Bank Statements', leadEntry.conditions[0].title);
        System.assertEquals(1, leadEntry.conditions[0].documentCount);
    }

    @IsTest
    static void loanPartnerSeesTheSameQueueAsTheOwner() {
        User otherOwner = buildUser();
        Lead leadRecord = buildLead(otherOwner.Id, UserInfo.getUserId());
        Lead_Document_Request__c requestRecord = buildRequest(leadRecord.Id, 'Recent Paystubs', 'Income');
        attachDocument(requestRecord.Id, 'paystub.pdf');

        Test.startTest();
        List<ConditionReviewQueueService.LoanQueueDto> queue = ConditionReviewQueueService.buildQueue();
        Test.stopTest();

        System.assertNotEquals(
            null,
            findEntry(queue, leadRecord.Id),
            'The Loan Partner is equally responsible, so the item belongs in their tray too.'
        );
    }

    @IsTest
    static void unrelatedUsersDoNotSeeTheRequest() {
        User otherOwner = buildUser();
        Lead leadRecord = buildLead(otherOwner.Id, otherOwner.Id);
        Lead_Document_Request__c requestRecord = buildRequest(leadRecord.Id, 'Gift Letter', 'Asset');
        attachDocument(requestRecord.Id, 'gift.pdf');

        Test.startTest();
        List<ConditionReviewQueueService.LoanQueueDto> queue = ConditionReviewQueueService.buildQueue();
        Test.stopTest();

        System.assertEquals(
            null,
            findEntry(queue, leadRecord.Id),
            'Someone who is neither Owner nor Loan Partner has no business reviewing this.'
        );
    }

    @IsTest
    static void requestsWithNoDocumentsStayOutOfTheTray() {
        Lead leadRecord = buildLead(UserInfo.getUserId(), null);
        buildRequest(leadRecord.Id, 'Nothing Uploaded Yet', 'Income');

        Test.startTest();
        List<ConditionReviewQueueService.LoanQueueDto> queue = ConditionReviewQueueService.buildQueue();
        Test.stopTest();

        System.assertEquals(
            null,
            findEntry(queue, leadRecord.Id),
            'Nothing to review means nothing in the tray.'
        );
    }

    @IsTest
    static void reviewActionsRouteToTheLeadService() {
        Lead leadRecord = buildLead(UserInfo.getUserId(), null);
        Lead_Document_Request__c acceptRequest = buildRequest(leadRecord.Id, 'Accept Me', 'Income');
        Lead_Document_Request__c rejectRequest = buildRequest(leadRecord.Id, 'Send Me Back', 'Income');
        Id acceptDocumentId = attachDocument(acceptRequest.Id, 'accept.pdf');
        Id rejectDocumentId = attachDocument(rejectRequest.Id, 'reject.pdf');

        Test.startTest();
        ConditionReviewQueueController.approveDocument(acceptRequest.Id, acceptDocumentId, true);
        ConditionReviewQueueController.rejectDocument(
            rejectRequest.Id,
            rejectDocumentId,
            'Please send every page.',
            true,
            null
        );
        List<ConditionReviewQueueService.LoanQueueDto> documents =
            ConditionReviewQueueController.getQueue();
        Test.stopTest();

        System.assertEquals('Cleared', [
            SELECT Status__c FROM Lead_Document_Request__c WHERE Id = :acceptRequest.Id
        ].Status__c, 'Accepting the last document with close chosen clears the request.');

        Lead_Document_Request__c rejected = [
            SELECT Status__c, Rejection_Notes__c
            FROM Lead_Document_Request__c
            WHERE Id = :rejectRequest.Id
        ];
        System.assertEquals('Requested', rejected.Status__c);
        System.assertEquals('Please send every page.', rejected.Rejection_Notes__c);
        System.assertNotEquals(null, documents);
    }

    @IsTest
    static void conditionDocumentsLoadForALeadRequest() {
        Lead leadRecord = buildLead(UserInfo.getUserId(), null);
        Lead_Document_Request__c requestRecord = buildRequest(leadRecord.Id, 'Bank Statements', 'Asset');
        attachDocument(requestRecord.Id, 'statement.pdf');

        Test.startTest();
        List<ConditionReviewQueueController.ConditionDocumentDto> documents =
            ConditionReviewQueueController.getConditionDocuments(requestRecord.Id);
        Test.stopTest();

        System.assertEquals(1, documents.size(), 'The reviewer needs to see the uploaded file.');
        System.assertEquals('statement.pdf', documents[0].filename);
    }

    @IsTest
    static void documentContentComesBackForRotation() {
        Lead leadRecord = buildLead(UserInfo.getUserId(), null);
        Lead_Document_Request__c requestRecord = buildRequest(leadRecord.Id, 'Bank Statements', 'Asset');
        Id contentDocumentId = attachDocumentReturningDocId(requestRecord.Id, 'statement.pdf');

        Test.startTest();
        DocumentViewerController.DocumentContentDto content =
            DocumentViewerController.getDocumentContent(contentDocumentId);
        Test.stopTest();

        System.assertEquals('statement', content.title);
        System.assertEquals('pdf', content.extension);
        System.assertNotEquals(null, content.base64Data, 'The browser needs the bytes to rotate them.');
    }

    @IsTest
    static void rotatedSaveAddsAVersionAndKeepsTheLinks() {
        Lead leadRecord = buildLead(UserInfo.getUserId(), null);
        Lead_Document_Request__c requestRecord = buildRequest(leadRecord.Id, 'Bank Statements', 'Asset');
        Id contentDocumentId = attachDocumentReturningDocId(requestRecord.Id, 'statement.pdf');
        Integer linksBefore = [
            SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :contentDocumentId
        ];

        Test.startTest();
        DocumentViewerController.saveRotatedDocument(
            contentDocumentId,
            EncodingUtil.base64Encode(Blob.valueOf('rotated bytes')),
            null
        );
        Test.stopTest();

        List<ContentVersion> versions = [
            SELECT Id, IsLatest, Folder__c, Lead_Document_Request__c
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY CreatedDate
        ];
        Integer linksAfter = [
            SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :contentDocumentId
        ];

        System.assertEquals(2, versions.size(), 'Rotating adds a version rather than a second file.');
        System.assertEquals(
            linksBefore,
            linksAfter,
            'Every link survives the rotation, so the document cannot be orphaned by it.'
        );
        System.assertEquals(
            requestRecord.Id,
            [SELECT Lead_Document_Request__c FROM ContentVersion
             WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE LIMIT 1].Lead_Document_Request__c,
            'The rotated version stays attached to its condition.'
        );
    }

    @IsTest
    static void rotateAndContentRejectMissingInput() {
        Boolean rotateRejected = false;
        Boolean contentRejected = false;

        Test.startTest();
        try {
            DocumentViewerController.saveRotatedDocument(null, null, null);
        } catch (Exception expected) {
            rotateRejected = true;
        }
        try {
            DocumentViewerController.getDocumentContent(null);
        } catch (Exception expected) {
            contentRejected = true;
        }
        Test.stopTest();

        System.assertEquals(true, rotateRejected);
        System.assertEquals(true, contentRejected);
    }

    private static Id attachDocumentReturningDocId(Id requestId, String title) {
        ContentVersion version = new ContentVersion(
            Title = title.substringBeforeLast('.'),
            PathOnClient = title,
            VersionData = Blob.valueOf('rotate test file'),
            Lead_Document_Request__c = requestId,
            Folder__c = 'Asset'
        );
        insert version;
        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id
        ].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = requestId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        return contentDocumentId;
    }

    // ---------- helpers ----------

    private static ConditionReviewQueueService.LoanQueueDto findEntry(
        List<ConditionReviewQueueService.LoanQueueDto> queue,
        Id leadId
    ) {
        for (ConditionReviewQueueService.LoanQueueDto entry : queue) {
            if (entry.loanId == leadId) {
                return entry;
            }
        }
        return null;
    }

    private static User buildUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String unique = String.valueOf(System.currentTimeMillis()) + String.valueOf(Integer.valueOf(Math.random() * 10000));
        User userRecord = new User(
            FirstName = 'Queue',
            LastName = 'Tester',
            Alias = 'qtst',
            Email = 'queue.tester@example.com',
            Username = 'queue.tester.' + unique + '@example.com',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert userRecord;
        return userRecord;
    }

    private static Lead buildLead(Id ownerId, Id loanPartnerId) {
        Lead leadRecord = new Lead(
            FirstName = 'Queue',
            LastName = 'Borrower',
            Company = 'Queue Test',
            Status = 'New',
            Email = 'queue.borrower@example.com',
            OwnerId = ownerId
        );
        if (loanPartnerId != null) {
            leadRecord.put('Loan_Partner__c', loanPartnerId);
        }
        insert leadRecord;
        // The Lead trigger stamps its own Loan Partner on insert, so set it back afterwards.
        if (loanPartnerId != null) {
            update new Lead(Id = leadRecord.Id, Loan_Partner__c = loanPartnerId);
        }
        if (ownerId != null) {
            update new Lead(Id = leadRecord.Id, OwnerId = ownerId);
        }
        return [
            SELECT Id, Name, FirstName, LastName, OwnerId, Loan_Partner__c
            FROM Lead
            WHERE Id = :leadRecord.Id
        ];
    }

    private static Lead_Document_Request__c buildRequest(Id leadId, String subject, String category) {
        Lead_Document_Request__c requestRecord = new Lead_Document_Request__c(
            Lead__c = leadId,
            Name = category,
            Subject__c = subject,
            Description__c = subject,
            Category__c = category,
            Type__c = 'Loan Officer',
            Status__c = 'Review',
            Can_Borrower_See__c = true,
            Include_In_Email__c = true
        );
        insert requestRecord;
        return requestRecord;
    }

    private static Id attachDocument(Id requestId, String title) {
        ContentVersion version = new ContentVersion(
            Title = title.substringBeforeLast('.'),
            PathOnClient = title,
            VersionData = Blob.valueOf('queue test file'),
            Lead_Document_Request__c = requestId
        );
        insert version;
        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id
        ].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = requestId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        return contentDocumentId;
    }
}
