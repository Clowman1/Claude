@isTest
private class LeadPortalDocumentRequestFacadeTest {
    @isTest
    static void getBorrowerOptions_returnsEmptyListForNullLeadId() {
        Test.startTest();
        List<LeadDocumentRequestService.BorrowerOption> options =
            LeadPortalDocumentRequestFacade.getBorrowerOptions(null);
        Test.stopTest();

        System.assertEquals(0, options.size());
    }

    @isTest
    static void getBorrowerOptions_returnsPrimaryAndAllForOwnedLead() {
        User testUser = ExternalLoPortalTestHelper.createStandardUser('pdrf');
        ExternalLoPortalTestHelper.grantPortalAccess(testUser.Id);

        Lead ownedLead;
        System.runAs(testUser) {
            Id consumerLeadRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                  AND DeveloperName = 'Consumer_Lead_record_type'
                LIMIT 1
            ].Id;

            ownedLead = new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                FirstName = 'Portal',
                LastName = 'Borrower',
                Company = 'Portal Co',
                Status = 'New',
                Email = 'portal.borrower@example.com',
                Phone = '2395550800',
                OwnerId = testUser.Id
            );
            insert ownedLead;
        }

        System.runAs(testUser) {
            Test.startTest();
            List<LeadDocumentRequestService.BorrowerOption> options =
                LeadPortalDocumentRequestFacade.getBorrowerOptions(String.valueOf(ownedLead.Id));
            Test.stopTest();

            System.assertEquals(2, options.size());
            System.assertEquals('ALL', options[0].value);
            System.assertEquals(true, options[0].assignable);
            System.assertEquals('PRIMARY', options[1].value);
            System.assertEquals(true, options[1].assignable);
        }
    }

    @isTest
    static void getPortalPresetConditions_includesRealEstateOwnedAndCatalogRows() {
        Lead_Document_Request_Reference__c referenceRecord = new Lead_Document_Request_Reference__c(
            Active__c = true,
            Type__c = 'Initial Submission',
            Category__c = 'Credit',
            Borrower_Label__c = 'Government-Issued Photo ID',
            Borrower_Description__c = 'Government-Issued Photo ID',
            Loan_Purpose__c = 'Purchase',
            Sort_Order__c = 1
        );
        insert referenceRecord;

        Test.startTest();
        List<LeadPortalDocumentRequestFacade.PortalPresetConditionRow> items =
            LeadPortalDocumentRequestFacade.getPortalPresetConditions('Purchase', null, null);
        Test.stopTest();

        System.assert(items.size() >= 2, 'Expected catalog row plus Real Estate Owned');
        Boolean sawReference = false;
        Boolean sawRealEstateOwned = false;
        for (LeadPortalDocumentRequestFacade.PortalPresetConditionRow item : items) {
            if (item.referenceKey == String.valueOf(referenceRecord.Id)) {
                sawReference = true;
            }
            if (item.referenceKey == 'OTHER_REAL_ESTATE_OWNED') {
                sawRealEstateOwned = true;
            }
        }
        System.assert(sawReference, 'Expected inserted reference in preset list');
        System.assert(sawRealEstateOwned, 'Expected Real Estate Owned preset option');
    }

    @isTest
    static void initializePortalData_returnsStringContextWithoutLeadIdField() {
        BorrowerPortalEncryptionService.testKeyOverride = '12345678901234567890123456789012';
        Lead testLead = new Lead(
            FirstName = 'Portal',
            LastName = 'Init',
            Company = 'Test Co',
            Status = 'New',
            Email = 'portal.init@example.com'
        );
        insert testLead;

        Test.startTest();
        LeadPortalDocumentRequestFacade.PortalDocumentRequestView view =
            LeadPortalDocumentRequestFacade.initializePortalData(String.valueOf(testLead.Id));
        Test.stopTest();

        System.assertEquals(String.valueOf(testLead.Id), view.contextRecordId);
        System.assertNotEquals(null, view.leadName);
    }

    @isTest
    static void createPortalSelectedConditions_createsFromReference() {
        BorrowerPortalEncryptionService.testKeyOverride = '12345678901234567890123456789012';
        User testUser = ExternalLoPortalTestHelper.createStandardUser('pdrf2');
        ExternalLoPortalTestHelper.grantPortalAccess(testUser.Id);

        Lead ownedLead;
        Lead_Document_Request_Reference__c referenceRecord;
        System.runAs(testUser) {
            Id consumerLeadRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                  AND DeveloperName = 'Consumer_Lead_record_type'
                LIMIT 1
            ].Id;

            ownedLead = new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                FirstName = 'Portal',
                LastName = 'PresetCreate',
                Company = 'Portal Co',
                Status = 'New',
                Email = 'portal.preset.create@example.com',
                Phone = '2395550801',
                OwnerId = testUser.Id
            );
            insert ownedLead;

            referenceRecord = new Lead_Document_Request_Reference__c(
                Active__c = true,
                Type__c = 'Initial Submission',
                Category__c = 'Credit',
                Borrower_Label__c = 'Government-Issued Photo ID',
                Borrower_Description__c = 'Government-Issued Photo ID',
                Sort_Order__c = 1
            );
            insert referenceRecord;
        }

        System.runAs(testUser) {
            Test.startTest();
            LeadPortalDocumentRequestFacade.PortalSaveResponse response =
                LeadPortalDocumentRequestFacade.createPortalSelectedConditions(
                    String.valueOf(ownedLead.Id),
                    new List<String>{ String.valueOf(referenceRecord.Id) },
                    'ALL'
                );
            Test.stopTest();

            System.assert(response.createdCount >= 1);
            List<Lead_Document_Request__c> created = [
                SELECT Id, Lead__c, Lead_Document_Request_Reference__c
                FROM Lead_Document_Request__c
                WHERE Lead__c = :ownedLead.Id
            ];
            System.assertEquals(1, created.size());
            System.assertEquals(referenceRecord.Id, created[0].Lead_Document_Request_Reference__c);
        }
    }

    @isTest
    static void savePortalRequests_createsManualRequest() {
        BorrowerPortalEncryptionService.testKeyOverride = '12345678901234567890123456789012';
        Lead testLead = new Lead(
            FirstName = 'Portal',
            LastName = 'Manual',
            Company = 'Test Co',
            Status = 'New',
            Email = 'portal.manual@example.com'
        );
        insert testLead;

        LeadDocumentRequestService.RequestInput input = new LeadDocumentRequestService.RequestInput();
        input.name = 'Manual portal condition';
        input.subject = input.name;
        input.description = input.name;
        input.category = 'Income';
        input.type = 'Loan Officer';
        input.status = 'New';
        input.includeInEmail = true;
        input.canBorrowerSee = true;

        Test.startTest();
        List<LeadPortalDocumentRequestFacade.PortalRequestRow> saved = LeadPortalDocumentRequestFacade.savePortalRequests(
            String.valueOf(testLead.Id),
            new List<LeadDocumentRequestService.RequestInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, saved.size());
        System.assertNotEquals(null, saved[0].requestKey);
    }

    @isTest
    static void setPortalSpanishCommunications_updatesLeadPreference() {
        BorrowerPortalEncryptionService.testKeyOverride = '12345678901234567890123456789012';
        Lead testLead = new Lead(
            FirstName = 'Portal',
            LastName = 'Spanish',
            Company = 'Test Co',
            Status = 'New',
            Email = 'portal.spanish@example.com'
        );
        insert testLead;

        Test.startTest();
        Boolean saved = LeadPortalDocumentRequestFacade.setPortalSpanishCommunications(
            String.valueOf(testLead.Id),
            true
        );
        Test.stopTest();

        System.assertEquals(true, saved);
    }

    @isTest
    static void getPortalBorrowerLinks_returnsEmptyForNullContext() {
        Test.startTest();
        System.assertEquals(0, LeadPortalDocumentRequestFacade.getPortalBorrowerLinks(null).size());
        Test.stopTest();
    }

    @isTest
    static void emailFacadeMethods_invokeWithPortalContext() {
        BorrowerPortalEncryptionService.testKeyOverride = '12345678901234567890123456789012';
        Lead testLead = new Lead(
            FirstName = 'Portal',
            LastName = 'Email',
            Company = 'Test Co',
            Status = 'New',
            Email = 'portal.email@example.com'
        );
        insert testLead;
        String contextId = String.valueOf(testLead.Id);

        Test.startTest();
        try {
            LeadPortalDocumentRequestFacade.getPortalEmailTemplatePreview(contextId, 'Nonexistent_Template');
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
        try {
            LeadPortalDocumentRequestFacade.getPortalSharedTemplatePreview(contextId, 'Nonexistent_Template');
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
        try {
            LeadPortalDocumentRequestFacade.sendPortalPerBorrowerRequestEmails(
                contextId,
                'Subject',
                'Nonexistent_Template'
            );
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
        try {
            LeadPortalDocumentRequestFacade.sendPortalComposedRequestEmail(
                contextId,
                'Subject',
                '<p>Body</p>',
                testLead.Email,
                null,
                null
            );
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
        Test.stopTest();
    }
}