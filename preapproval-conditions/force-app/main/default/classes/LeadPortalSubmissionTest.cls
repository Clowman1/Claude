@IsTest
private class LeadPortalSubmissionTest {

    // The portal hash is AES encrypted, so every test here needs the key and the portal URL
    // settings in place before a lead can be reached by hash.
    @TestSetup
    static void setupSettings() {
        insert new AesKey__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            AesKey__c = '12345678901234567890123456789012'
        );
        BorrowerPortalSettings__c settings = new BorrowerPortalSettings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Borrower_Home_Url__c = 'https://example.force.com/documents/s/'
        );
        if (BorrowerPortalSettings__c.SObjectType.getDescribe().fields.getMap().containsKey('Lead_Borrower_Home_Url__c')) {
            settings.put('Lead_Borrower_Home_Url__c', 'https://example.force.com/documents/s/lead');
        }
        insert settings;
    }

    @IsTest
    static void anUploadSitsInTheBasketAndTellsNobody() {
        Lead leadRecord = createLead();
        Lead_Document_Request__c request = createRequest(leadRecord.Id, 'Income');

        Test.startTest();
        LeadDocumentPortalService.PortalRequest result = LeadDocumentPortalService.uploadBorrowerDocument(
            portalHash(leadRecord), request.Id, 'paystub.pdf', base64('paystub')
        );
        Test.stopTest();

        System.assertEquals(1, result.pendingFiles.size(), 'The file shows in the basket for this request.');
        System.assertEquals(
            'Requested',
            [SELECT Status__c FROM Lead_Document_Request__c WHERE Id = :request.Id].Status__c,
            'Uploading must not move the condition; only submitting does.'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :leadRecord.Id],
            'Nothing is linked to the Lead yet, so it stays out of the Documents tab.'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :request.Id],
            'And out of the Pending Review tray, which counts links on the request.'
        );
    }

    @IsTest
    static void submittingLinksEverythingAndMovesTheConditions() {
        Lead leadRecord = createLead();
        Lead_Document_Request__c income = createRequest(leadRecord.Id, 'Income');
        Lead_Document_Request__c asset = createRequest(leadRecord.Id, 'Asset');
        String hash = portalHash(leadRecord);

        LeadDocumentPortalService.uploadBorrowerDocument(hash, income.Id, 'paystub.pdf', base64('one'));
        LeadDocumentPortalService.uploadBorrowerDocument(hash, income.Id, 'w2.pdf', base64('two'));
        LeadDocumentPortalService.uploadBorrowerDocument(hash, asset.Id, 'bank.pdf', base64('three'));

        Test.startTest();
        LeadDocumentPortalService.PortalData afterSubmit =
            LeadDocumentPortalService.submitPendingDocuments(hash);
        Test.stopTest();

        System.assertEquals(0, afterSubmit.pendingSubmissionCount, 'The basket empties on submit.');
        System.assertEquals(
            3,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :leadRecord.Id],
            'Every submitted file reaches the Lead, so the Documents tab shows them.'
        );
        Map<Id, Lead_Document_Request__c> requests = new Map<Id, Lead_Document_Request__c>([
            SELECT Id, Status__c FROM Lead_Document_Request__c WHERE Id IN (:income.Id, :asset.Id)
        ]);
        System.assertEquals('Review', requests.get(income.Id).Status__c);
        System.assertEquals('Review', requests.get(asset.Id).Status__c);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentVersion WHERE Portal_Upload_Pending__c = TRUE],
            'Nothing is left pending afterwards.'
        );
    }

    @IsTest
    static void submittingReopensAConditionClearedWhileTheBasketWasOpen() {
        Lead leadRecord = createLead();
        Lead_Document_Request__c request = createRequest(leadRecord.Id, 'Income');
        String hash = portalHash(leadRecord);
        LeadDocumentPortalService.uploadBorrowerDocument(hash, request.Id, 'late.pdf', base64('late'));

        // The lead team clears the condition while the borrower is still uploading.
        update new Lead_Document_Request__c(Id = request.Id, Status__c = 'Cleared');

        Test.startTest();
        LeadDocumentPortalService.submitPendingDocuments(hash);
        Test.stopTest();

        System.assertEquals(
            'Review',
            [SELECT Status__c FROM Lead_Document_Request__c WHERE Id = :request.Id].Status__c,
            'A document nobody has looked at must not land on a closed condition.'
        );
    }

    @IsTest
    static void aBorrowerCanRemoveTheirOwnPendingFileButNotASubmittedOne() {
        Lead leadRecord = createLead();
        Lead_Document_Request__c request = createRequest(leadRecord.Id, 'Income');
        String hash = portalHash(leadRecord);
        LeadDocumentPortalService.uploadBorrowerDocument(hash, request.Id, 'wrong.pdf', base64('wrong'));
        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Portal_Upload_Pending__c = TRUE LIMIT 1
        ].ContentDocumentId;

        Test.startTest();
        Integer remaining = LeadDocumentPortalService.removePendingDocument(hash, contentDocumentId);

        // A second removal has nothing left to act on, which is what a submitted file looks like.
        Boolean refusedSecondTime = false;
        try {
            LeadDocumentPortalService.removePendingDocument(hash, contentDocumentId);
        } catch (Exception expected) {
            refusedSecondTime = true;
        }
        Test.stopTest();

        System.assertEquals(0, remaining, 'The basket is empty again.');
        System.assertEquals(true, refusedSecondTime);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentDocument WHERE Id = :contentDocumentId],
            'A removed file is deleted rather than orphaned; it was linked to nothing.'
        );
    }

    @IsTest
    static void theSweepSubmitsAnAbandonedBasketAndLeavesAFreshOneAlone() {
        Lead abandoned = createLead();
        Lead_Document_Request__c oldRequest = createRequest(abandoned.Id, 'Income');
        LeadDocumentPortalService.uploadBorrowerDocument(
            portalHash(abandoned), oldRequest.Id, 'abandoned.pdf', base64('old')
        );
        // Only the clock separates an abandoned basket from an active one.
        Test.setCreatedDate(
            [SELECT Id FROM ContentVersion WHERE Portal_Upload_Pending__c = TRUE LIMIT 1].Id,
            Datetime.now().addHours(-5)
        );

        Lead active = createLead('fresh-basket@example.com');
        Lead_Document_Request__c newRequest = createRequest(active.Id, 'Asset');
        LeadDocumentPortalService.uploadBorrowerDocument(
            portalHash(active), newRequest.Id, 'fresh.pdf', base64('new')
        );

        Test.startTest();
        Integer submitted = LeadPortalPendingUploadSweeper.sweep();
        Test.stopTest();

        System.assertEquals(1, submitted, 'Only the quiet basket is swept.');
        System.assertEquals(
            'Review',
            [SELECT Status__c FROM Lead_Document_Request__c WHERE Id = :oldRequest.Id].Status__c
        );
        System.assertEquals(
            'Requested',
            [SELECT Status__c FROM Lead_Document_Request__c WHERE Id = :newRequest.Id].Status__c,
            'A borrower still uploading must not have their session cut short.'
        );
    }

    @IsTest
    static void theSubmissionEmailNamesEveryConditionAndWhatIsLeft() {
        Lead leadRecord = createLead();
        Lead_Document_Request__c income = createRequest(leadRecord.Id, 'Income');
        createRequest(leadRecord.Id, 'Still Outstanding');
        String hash = portalHash(leadRecord);
        LeadDocumentPortalService.uploadBorrowerDocument(hash, income.Id, 'paystub.pdf', base64('body'));

        ContentVersion pending = [
            SELECT Id, ContentDocumentId, Title, PathOnClient, CreatedDate, Lead_Document_Request__c
            FROM ContentVersion WHERE Portal_Upload_Pending__c = TRUE LIMIT 1
        ];

        Test.startTest();
        String body = LeadDocumentPortalService.buildSubmissionNotificationBody(
            [SELECT Id, Name, FirstName, LastName FROM Lead WHERE Id = :leadRecord.Id],
            new Map<Id, List<ContentVersion>>{ income.Id => new List<ContentVersion>{ pending } },
            new Map<Id, Lead_Document_Request__c>([
                SELECT Id, Name, Subject__c, Category__c FROM Lead_Document_Request__c WHERE Id = :income.Id
            ]),
            1,
            1,
            true
        );
        Test.stopTest();

        System.assertEquals(true, body.contains('paystub.pdf'), 'The email names the file.');
        System.assertEquals(true, body.contains('Documents Submitted'));
        System.assertEquals(true, body.contains('condition is still outstanding'),
            'The tail is the part a Loan Officer acts on.');
        System.assertEquals(true, body.contains('did not press submit'),
            'A swept batch says so; a borrower who pressed submit is a different signal.');
    }

    // The portal talks to the controller, not the service, so its wrappers and the errors they
    // hand back to the borrower need covering too.
    @IsTest
    static void theControllerSubmitsRemovesAndReportsFailuresToTheBorrower() {
        Lead leadRecord = createLead();
        Lead_Document_Request__c request = createRequest(leadRecord.Id, 'Income');
        String hash = portalHash(leadRecord);
        LeadDocumentPortalController.uploadBorrowerDocument(hash, request.Id, 'first.pdf', base64('a'));
        LeadDocumentPortalController.uploadBorrowerDocument(hash, request.Id, 'second.pdf', base64('b'));
        Id firstDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion
            WHERE Portal_Upload_Pending__c = TRUE ORDER BY CreatedDate LIMIT 1
        ].ContentDocumentId;

        Boolean removeRefused = false;
        Boolean submitRefused = false;

        Test.startTest();
        Integer remaining = LeadDocumentPortalController.removePendingDocument(hash, firstDocumentId);
        LeadDocumentPortalService.PortalData data =
            LeadDocumentPortalController.submitPendingDocuments(hash);

        // A hash that resolves to nothing is what a tampered or expired link looks like.
        try {
            LeadDocumentPortalController.removePendingDocument('not-a-real-hash', firstDocumentId);
        } catch (Exception expected) {
            removeRefused = true;
        }
        try {
            LeadDocumentPortalController.submitPendingDocuments('not-a-real-hash');
        } catch (Exception expected) {
            submitRefused = true;
        }
        Test.stopTest();

        System.assertEquals(1, remaining, 'One of the two files was removed before submitting.');
        System.assertEquals(0, data.pendingSubmissionCount, 'Submitting empties the basket.');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :leadRecord.Id],
            'Only the file that survived removal reaches the Lead.'
        );
        System.assertEquals(true, removeRefused, 'A bad portal link cannot remove anything.');
        System.assertEquals(true, submitRefused, 'Nor submit anything.');
    }

    private static Lead createLead() {
        return createLead('session-upload@example.com');
    }

    private static Lead createLead(String email) {
        Lead leadRecord = new Lead(
            FirstName = 'Session', LastName = 'Borrower', Company = 'Portal Session Test',
            Status = 'New', Email = email
        );
        insert leadRecord;
        LeadDocumentRequestService.populateMissingPortalHashes(new Set<Id>{ leadRecord.Id });
        return [
            SELECT Id, Name, FirstName, LastName, Email, OwnerId, Portal_Hash_Parameter__c
            FROM Lead WHERE Id = :leadRecord.Id
        ];
    }

    // The stored hash is encrypted and needs the portal AES key to resolve; the service hands
    // tests the plain value instead.
    private static String portalHash(Lead leadRecord) {
        Lead leadWithHash = LeadDocumentRequestRepository.getInstance()
            .selectLeadsByIds(new Set<Id>{ leadRecord.Id }).get(leadRecord.Id);
        return LeadDocumentRequestService.getLeadPortalHash(leadWithHash);
    }

    private static Lead_Document_Request__c createRequest(Id leadId, String name) {
        Lead_Document_Request__c request = new Lead_Document_Request__c(
            Lead__c = leadId,
            Name = name,
            Description__c = name + ' documents',
            Status__c = 'Requested',
            Category__c = 'Income',
            Can_Borrower_See__c = true,
            Include_In_Email__c = true
        );
        insert request;
        return request;
    }

    private static String base64(String body) {
        return EncodingUtil.base64Encode(Blob.valueOf(body));
    }
}
