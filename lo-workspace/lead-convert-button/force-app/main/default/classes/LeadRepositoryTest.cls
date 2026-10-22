@IsTest
private class LeadRepositoryTest {
    private static Lead createLeadForRepoTest() {
        Id realtorLeadRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND DeveloperName = 'Realtor_Lead_record_type'
            LIMIT 1
        ].Id;

        Lead leadRecord = new Lead(
            RecordTypeId = realtorLeadRecordTypeId,
            FirstName = 'Repo',
            LastName = 'Test',
            Company = 'Repo Co',
            Email = 'repo-test@example.com'
        );
        insert leadRecord;
        return leadRecord;
    }

    @IsTest
    static void testGetLeadById() {
        Lead leadRecord = createLeadForRepoTest();

        Test.startTest();
        Lead loadedLead = LeadRepository.getInstance().getLeadById(leadRecord.Id);
        Test.stopTest();

        System.assertNotEquals(null, loadedLead);
        System.assertEquals(leadRecord.Id, loadedLead.Id);
    }

    @IsTest
    static void selectPortalLeadForDocumentRequest_returnsOwnedLead() {
        User testUser = ExternalLoPortalTestHelper.createStandardUser('lrpdr');
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
                LastName = 'Repo',
                Company = 'Portal Co',
                Status = 'New',
                Email = 'portal.repo@example.com',
                OwnerId = testUser.Id
            );
            insert ownedLead;
        }

        System.runAs(testUser) {
            Test.startTest();
            Lead loaded = LeadRepository.getInstance()
                .selectPortalLeadForDocumentRequest(ownedLead.Id, testUser.Id);
            Test.stopTest();
            System.assertNotEquals(null, loaded);
            System.assertEquals(ownedLead.Id, loaded.Id);
        }
    }

    @IsTest
    static void selectPortalLeadForConversion_returnsOwnedLeadFields() {
        User testUser = ExternalLoPortalTestHelper.createStandardUser('lrpconv');
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
                LastName = 'Conversion',
                Company = 'Portal Co',
                Status = 'New',
                Email = 'portal.conversion@example.com',
                Street = '1 Main',
                City = 'Naples',
                State = 'FL',
                PostalCode = '34102',
                Loan_Amount__c = 250000,
                Value_of_Property__c = 300000,
                Household_Income__c = 90000,
                OwnerId = testUser.Id
            );
            insert ownedLead;
        }

        System.runAs(testUser) {
            Test.startTest();
            Lead loaded = LeadRepository.getInstance()
                .selectPortalLeadForConversion(ownedLead.Id, testUser.Id);
            Test.stopTest();
            System.assertNotEquals(null, loaded);
            System.assertEquals(ownedLead.Id, loaded.Id);
        }
    }

    @IsTest
    static void selectPortalLeadForConversion_allowsLoanPartnerOnly() {
        User partner = ExternalLoPortalTestHelper.createStandardUser('lrplp');
        User stranger = ExternalLoPortalTestHelper.createStandardUser('lrpxx');
        Lead l = new Lead(LastName = 'Partnered', Company = 'n/a', Status = 'Pre-Approval', Loan_Amount__c = 300000);
        insert l;
        // Loan_Partner__c is stamped on insert, so set it afterwards.
        update new Lead(Id = l.Id, Loan_Partner__c = partner.Id);
        System.assertEquals(partner.Id, [SELECT Loan_Partner__c FROM Lead WHERE Id = :l.Id].Loan_Partner__c);

        LeadRepository repo = LeadRepository.getInstance();
        System.assertNotEquals(null, repo.selectPortalLeadForConversion(l.Id, partner.Id), 'Loan Partner can convert.');
        System.assertEquals(null, repo.selectPortalLeadForConversion(l.Id, stranger.Id), 'Neither owner nor partner.');
    }

    @IsTest
    static void testSelectForRealtorConvert() {
        Lead leadRecord = createLeadForRepoTest();

        Test.startTest();
        Lead loadedLead = LeadRepository.getInstance().selectForRealtorConvert(leadRecord.Id);
        Test.stopTest();

        System.assertNotEquals(null, loadedLead);
        System.assertEquals(leadRecord.Id, loadedLead.Id);
        System.assertEquals('Realtor_Lead_record_type', loadedLead.RecordType.DeveloperName);
    }

    @IsTest
    static void testSelectSmsOptOutByIds() {
        Lead leadRecord = createLeadForRepoTest();

        Test.startTest();
        Map<Id, Lead> loadedLeads = LeadRepository.getInstance().selectSmsOptOutByIds(new Set<Id>{ leadRecord.Id });
        Map<Id, Lead> emptyResult = LeadRepository.getInstance().selectSmsOptOutByIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(true, loadedLeads.containsKey(leadRecord.Id));
        System.assertEquals(0, emptyResult.size());
    }

    @IsTest
    static void testSelectConvertedByIds_returns_converted_lead() {
        Lead l = new Lead(
            FirstName = 'Conv',
            LastName = 'Lead',
            Company = 'Test Co',
            Email = 'conv.lead.repo.test+' + String.valueOf(Crypto.getRandomInteger()) + '@example.com',
            Status = 'Open - Not Contacted'
        );
        insert l;

        LeadStatus convertedStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1];
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l.Id);
        lc.setConvertedStatus(convertedStatus.MasterLabel);
        Database.LeadConvertResult conv = Database.convertLead(lc);
        System.assertEquals(true, conv.isSuccess());

        Test.startTest();
        Map<Id, Lead> rows = LeadRepository.getInstance().selectConvertedByIds(new Set<Id>{ l.Id });
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(true, rows.get(l.Id).IsConverted);
        System.assertNotEquals(null, rows.get(l.Id).ConvertedAccountId);
    }
}