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

    @IsTest
    static void infoReceivedClearsMissingFieldsAndSsnIsNeverRequired() {
        User testUser = ExternalLoPortalTestHelper.createStandardUser('convrcv');
        ExternalLoPortalTestHelper.grantPortalAccess(testUser.Id);
        Lead sparseLead;
        System.runAs(testUser) {
            sparseLead = new Lead(
                RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND DeveloperName = 'Consumer_Lead_record_type' LIMIT 1].Id,
                LastName = 'Received', Company = 'Portal Co', Status = 'New', OwnerId = testUser.Id
            );
            insert sparseLead;
        }
        System.runAs(testUser) {
            ExternalLoPortalConversionFacade.ConversionPreview preview =
                ExternalLoPortalConversionFacade.getConversionPreview(String.valueOf(sparseLead.Id));
            System.assert(!preview.missingFields.contains('Borrower Social Security number'), String.valueOf(preview.missingFields));
            List<String> partial = new List<String>(preview.missingFields);
            String leftOut = partial.remove(0);
            ExternalLoPortalConversionFacade.ConversionResult blocked =
                ExternalLoPortalConversionFacade.confirmConversionWithReceived(String.valueOf(sparseLead.Id), true, partial);
            System.assertEquals('MISSING_TRID_FIELDS', blocked.errorCode);
            System.assert(blocked.userMessage.contains(leftOut), blocked.userMessage);
            ExternalLoPortalConversionFacade.ConversionResult attempted =
                ExternalLoPortalConversionFacade.confirmConversionWithReceived(String.valueOf(sparseLead.Id), true, preview.missingFields);
            System.assertNotEquals('MISSING_TRID_FIELDS', attempted.errorCode, 'Info received clears every missing item.');
        }
    }

    @IsTest
    static void infoReceivedIsSavedAsANoteOnTheLead() {
        Lead l = new Lead(LastName = 'NoteCheck', Company = 'n/a', Status = 'New');
        insert l;
        ExternalLoPortalConversionFacade.recordInfoReceived(
            l.Id, new List<String>{ 'Borrower income', 'Subject property' }, new Set<String>{ 'Borrower income' });
        Enhanced_Note__c note = [SELECT Subject__c, Body__c, Type__c FROM Enhanced_Note__c WHERE Lead__c = :l.Id];
        System.assertEquals('Note', note.Type__c);
        System.assert(note.Body__c.contains('Borrower income') && !note.Body__c.contains('Subject property'), note.Body__c);
        ExternalLoPortalConversionFacade.recordInfoReceived(l.Id, new List<String>{ 'Loan amount' }, new Set<String>());
        System.assertEquals(1, [SELECT COUNT() FROM Enhanced_Note__c WHERE Lead__c = :l.Id], 'Nothing confirmed, no note.');
    }

    @IsTest
    static void preApprovalLeadsAreReleasedBeforeConverting() {
        Lead l = new Lead(LastName = 'Releaser', Company = 'n/a', Status = 'Pre-Approval', Loan_Amount__c = 350000);
        insert l;
        ExternalLoPortalConversionFacade.releaseScheduledAutomation(l.Id);
        System.assertEquals(Label.Consumer_Lead_Process, [SELECT Status FROM Lead WHERE Id = :l.Id].Status);
        Lead working = new Lead(LastName = 'Untouched', Company = 'n/a', Status = 'Working');
        insert working;
        ExternalLoPortalConversionFacade.releaseScheduledAutomation(working.Id);
        System.assertEquals('Working', [SELECT Status FROM Lead WHERE Id = :working.Id].Status, 'Only Pre-Approval leads move.');
    }

    @IsTest
    static void conversionCreatesTheLoanLikeTheTridFlow() {
        Lead l = new Lead(
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND DeveloperName = 'Consumer_Lead_record_type' LIMIT 1].Id,
            FirstName = 'Loan', LastName = 'Maker', Company = 'n/a', Status = 'Working', Email = 'loan.maker@example.com',
            Loan_Amount__c = 300000
        );
        insert l;
        insert new Enhanced_Note__c(Lead__c = l.Id, Type__c = 'Note', Subject__c = 'Before conversion', Body__c = 'x');
        Borrower__c co = new Borrower__c(Lead__c = l.Id, Name = 'Co Maker', First_Name__c = 'Co', Last_Name__c = 'Maker', Email__c = 'co.maker@example.com');
        insert co;
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l.Id);
        lc.setConvertedStatus(Label.Consumer_Lead_Process);
        lc.setDoNotCreateOpportunity(true);
        Database.convertLead(lc);

        Id loanId = ExternalLoPortalConversionFacade.createTransactionForConvertedLead(l.Id);
        System.assertNotEquals(null, loanId);
        Transaction__c loan = [SELECT Status__c, Loan_Officer__c, OwnerId, Borrower_Name__c, Name FROM Transaction__c WHERE Id = :loanId];
        System.assertEquals('TRID Application', loan.Status__c);
        System.assertEquals(UserInfo.getUserId(), loan.Loan_Officer__c);
        System.assertEquals([SELECT ConvertedAccountId FROM Lead WHERE Id = :l.Id].ConvertedAccountId, loan.Borrower_Name__c);
        System.assertEquals(loanId, [SELECT Converted_Transaction_ID__c FROM Lead WHERE Id = :l.Id].Converted_Transaction_ID__c);
        System.assertEquals(1, [SELECT COUNT() FROM Enhanced_Note__c WHERE Transaction__c = :loanId], 'Notes move to the loan.');
        System.assertEquals(loanId, [SELECT Transaction__c FROM Borrower__c WHERE Id = :co.Id].Transaction__c, 'Co-borrower follows the lead onto the loan.');
        System.assertEquals(loanId, ExternalLoPortalConversionFacade.createTransactionForConvertedLead(l.Id), 'A second call creates nothing.');
        System.assertEquals(1, [SELECT COUNT() FROM Transaction__c WHERE Borrower_Name__c = :loan.Borrower_Name__c]);
    }
}