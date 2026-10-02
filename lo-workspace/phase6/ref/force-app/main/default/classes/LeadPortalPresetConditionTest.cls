@isTest
private class LeadPortalPresetConditionTest {
    private static final String TEST_AES_KEY = '12345678901234567890123456789012';

    @isTest
    static void getPresetConditions_andPortalVariant_returnFilteredCatalog() {
        Lead_Document_Request_Reference__c idReference = createReference(
            'Initial Submission',
            'Government-Issued Photo ID',
            'Credit',
            null,
            'Purchase',
            null,
            null
        );
        Lead_Document_Request_Reference__c assetReference = createReference(
            'Initial Submission',
            'Assets',
            'Asset',
            null,
            'Purchase',
            null,
            null
        );
        Lead_Document_Request_Reference__c refinanceOnly = createReference(
            'Initial Submission',
            'Refi Only',
            'Identification',
            null,
            'Refinance',
            null,
            null
        );
        insert new List<Lead_Document_Request_Reference__c>{ idReference, assetReference, refinanceOnly };

        Test.startTest();
        List<LeadPresetConditionSelectorController.PresetConditionItem> purchaseItems =
            LeadPresetConditionSelectorController.getPresetConditions('Purchase', null, null);
        List<LeadPresetConditionSelectorController.PresetConditionItem> portalItems =
            LeadPresetConditionSelectorController.getPortalPresetConditions('Purchase', 'Self Employed', 'Sole Proprietor');
        Test.stopTest();

        System.assert(purchaseItems.size() >= 3, 'Expected catalog rows plus Real Estate Owned');
        assertContainsKey(purchaseItems, String.valueOf(idReference.Id));
        assertContainsKey(purchaseItems, String.valueOf(assetReference.Id));
        System.assert(!containsKey(purchaseItems, String.valueOf(refinanceOnly.Id)), 'Refinance-only row should filter out');
        System.assert(portalItems.size() >= 2, 'Portal variant should return the same catalog shape');
        assertContainsKey(portalItems, 'OTHER_REAL_ESTATE_OWNED');
    }

    @isTest
    static void createSelectedConditionKeys_createsReferenceAndRealEstateRows() {
        BorrowerPortalEncryptionService.testKeyOverride = TEST_AES_KEY;
        Lead testLead = createOwnedLead();

        Lead_Document_Request_Reference__c referenceRecord = createReference(
            'Initial Submission',
            'Government-Issued Photo ID',
            'Credit',
            null,
            null,
            null,
            null
        );
        insert referenceRecord;

        Test.startTest();
        LeadPresetConditionSelectorController.SaveResponse response =
            LeadPresetConditionSelectorController.createSelectedConditionKeys(
                testLead.Id,
                new List<String>{
                    String.valueOf(referenceRecord.Id),
                    'OTHER_REAL_ESTATE_OWNED',
                    'not-an-id'
                },
                'ALL'
            );
        Test.stopTest();

        List<Lead_Document_Request__c> created = [
            SELECT Id, Lead_Document_Request_Reference__c, Category__c
            FROM Lead_Document_Request__c
            WHERE Lead__c = :testLead.Id
        ];
        System.assertEquals(2, created.size());
        System.assert(response.createdCount >= 2, 'Save response should reflect created rows');
    }

    @isTest
    static void createSelectedConditionKeys_requiresSelection() {
        Lead testLead = createOwnedLead();

        Boolean threw = false;
        Test.startTest();
        try {
            LeadPresetConditionSelectorController.createSelectedConditionKeys(
                testLead.Id,
                new List<String>(),
                null
            );
        } catch (LeadDocumentRequestService.LeadDocumentRequestException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Select at least one condition'));
        }
        Test.stopTest();

        System.assert(threw, 'Expected validation when nothing is selected');
    }

    private static Lead createOwnedLead() {
        Id consumerLeadRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
              AND DeveloperName = 'Consumer_Lead_record_type'
            LIMIT 1
        ].Id;

        Lead testLead = new Lead(
            RecordTypeId = consumerLeadRecordTypeId,
            FirstName = 'Preset',
            LastName = 'Selector',
            Company = 'Test Co',
            Status = 'New',
            Email = 'preset.selector@example.com',
            Phone = '2395550900'
        );
        insert testLead;
        return testLead;
    }

    private static Lead_Document_Request_Reference__c createReference(
        String referenceType,
        String borrowerLabel,
        String category,
        String packageName,
        String loanPurpose,
        String employmentType,
        String selfEmploymentType
    ) {
        return new Lead_Document_Request_Reference__c(
            Active__c = true,
            Borrower_Label__c = borrowerLabel,
            Borrower_Description__c = borrowerLabel,
            Category__c = category,
            Package__c = packageName,
            Type__c = referenceType,
            Loan_Purpose__c = loanPurpose,
            Employment_Type__c = employmentType,
            Self_Employment_Type__c = selfEmploymentType,
            Reference_Id__c = referenceType.replace(' ', '_') + '_' + borrowerLabel.replace(' ', '_'),
            Include_In_Email__c = true,
            Can_Borrower_See__c = true,
            Sort_Order__c = 1
        );
    }

    private static Boolean containsKey(
        List<LeadPresetConditionSelectorController.PresetConditionItem> items,
        String key
    ) {
        for (LeadPresetConditionSelectorController.PresetConditionItem item : items) {
            if (item.key == key) {
                return true;
            }
        }
        return false;
    }

    private static void assertContainsKey(
        List<LeadPresetConditionSelectorController.PresetConditionItem> items,
        String key
    ) {
        System.assert(containsKey(items, key), 'Expected preset key ' + key);
    }
}