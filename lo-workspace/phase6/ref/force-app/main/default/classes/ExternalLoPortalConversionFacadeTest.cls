@IsTest
private class ExternalLoPortalConversionFacadeTest {
    @IsTest
    static void preview_and_conversion_require_acknowledgment() {
        User testUser = ExternalLoPortalTestHelper.createStandardUser('convfac');
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
                FirstName = 'Convert',
                LastName = 'Preview',
                Company = 'Portal Co',
                Status = 'New',
                Email = 'convert.preview@example.com',
                Street = '123 Main St',
                City = 'Naples',
                State = 'FL',
                PostalCode = '34102',
                Loan_Amount__c = 350000,
                Value_of_Property__c = 425000,
                Household_Income__c = 120000,
                OwnerId = testUser.Id
            );
            Map<String, Schema.SObjectField> leadFields = Schema.SObjectType.Lead.fields.getMap();
            if (leadFields.containsKey('SSN__c')) {
                ownedLead.put('SSN__c', '123-45-6789');
            } else if (leadFields.containsKey('Borrower_SSN__c')) {
                ownedLead.put('Borrower_SSN__c', '123-45-6789');
            }
            insert ownedLead;
        }

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoPortalConversionFacade.ConversionPreview preview =
                ExternalLoPortalConversionFacade.getConversionPreview(String.valueOf(ownedLead.Id));
            ExternalLoPortalConversionFacade.ConversionResult blocked =
                ExternalLoPortalConversionFacade.confirmConversion(String.valueOf(ownedLead.Id), false);
            Test.stopTest();

            System.assertEquals('Convert Preview', preview.borrowerName);
            System.assert(preview.ssnPresent == true || preview.missingFields.contains('Borrower Social Security number'));
            if (preview.ssnPresent) {
                System.assert(preview.ssnMasked.contains('6789'));
            }
            System.assertEquals(false, preview.alreadyConverted);
            System.assertEquals(false, blocked.success);
            System.assertEquals('ACK_REQUIRED', blocked.errorCode);
        }
    }

    @IsTest
    static void preview_listsMissingFieldsWhenIncomplete() {
        User testUser = ExternalLoPortalTestHelper.createStandardUser('convinc');
        ExternalLoPortalTestHelper.grantPortalAccess(testUser.Id);

        Lead sparseLead;
        System.runAs(testUser) {
            Id consumerLeadRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                  AND DeveloperName = 'Consumer_Lead_record_type'
                LIMIT 1
            ].Id;

            sparseLead = new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                LastName = 'Sparse',
                Company = 'Portal Co',
                Status = 'New',
                OwnerId = testUser.Id
            );
            insert sparseLead;
        }

        System.runAs(testUser) {
            ExternalLoPortalConversionFacade.ConversionPreview preview =
                ExternalLoPortalConversionFacade.getConversionPreview(String.valueOf(sparseLead.Id));
            System.assertEquals(false, preview.readyToConvert);
            System.assert(!preview.missingFields.isEmpty());
            System.assertEquals('—', preview.ssnMasked);
        }
    }

    @IsTest
    static void confirmConversion_rejectsMissingTridFields() {
        User testUser = ExternalLoPortalTestHelper.createStandardUser('convbad');
        ExternalLoPortalTestHelper.grantPortalAccess(testUser.Id);

        Lead sparseLead;
        System.runAs(testUser) {
            Id consumerLeadRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                  AND DeveloperName = 'Consumer_Lead_record_type'
                LIMIT 1
            ].Id;
            sparseLead = new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                LastName = 'Incomplete',
                Company = 'Portal Co',
                Status = 'New',
                OwnerId = testUser.Id
            );
            insert sparseLead;
        }

        System.runAs(testUser) {
            ExternalLoPortalConversionFacade.ConversionResult result =
                ExternalLoPortalConversionFacade.confirmConversion(String.valueOf(sparseLead.Id), true);
            System.assertEquals(false, result.success);
            System.assertEquals('MISSING_TRID_FIELDS', result.errorCode);
        }
    }
}