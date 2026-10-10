@isTest
private class ExternalLoCsvImportServiceTest {

    /**
     * These are Partner Workspace (portal-mode) tests. They used to run as the deploying admin, but
     * LoWsPartnerTagService.isTagMode() is true for holders of LO_Workspace_Demo (Chris, Brandon), which
     * switched the import onto the LO Workspace path. A dedicated admin without that permission keeps
     * the result independent of who runs the tests.
     */
    static User importer() {
        return [SELECT Id, Name FROM User WHERE Username LIKE 'csvimp.%@reach-csvimp.test' LIMIT 1];
    }

    @testSetup
    static void setupData() {
        String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User admin = new User(
            FirstName = 'Csv', LastName = 'Importer', Alias = 'csvimp',
            Email = 'csvimp@reach-csvimp.test', Username = 'csvimp.' + unique + '@reach-csvimp.test',
            ProfileId = UserInfo.getProfileId(), TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert admin;
        ExternalLoPortalTestHelper.grantPortalAccess(admin.Id);
        User testUser = importer();
        System.runAs(testUser) {
            Id consumerLeadRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                  AND DeveloperName = 'Consumer_Lead_record_type'
                LIMIT 1
            ].Id;
            insert new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                FirstName = 'Existing',
                LastName = 'Borrower',
                Company = 'Existing Borrower Household',
                Status = 'New',
                Email = 'existing.borrower@example.com',
                Phone = '2395550100'
            );
        }
    }

    @isTest
    static void consumerImport_addsRowsAndSilentlySkipsLeadMatches() {
        User testUser = importer();
        String csvBody =
            'FirstName,LastName,Phone,Email,Type,LoanAmount,Purpose,City,Notes\n' +
            'Existing,Borrower,2395550100,existing.borrower@example.com,Lead,250000,Purchase,Naples,skip me\n' +
            'Fresh,Buyer,2395550111,fresh.buyer@example.com,Lead,400000,Purchase,Fort Myers,new\n' +
            'Past,Client,2395550112,past.client@example.com,Past Client,300000,Refinance,Cape Coral,pc\n' +
            ',,,\n' +
            'No,Contact,,,,Lead,,,\n';

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoCsvImportService.ImportResult result = ExternalLoWorkspaceController.importCsv('consumer', csvBody);
            Integer queryCount = Limits.getQueries();
            Test.stopTest();

            System.assertEquals(2, result.successCount, 'Two new consumer rows should import.');
            System.assertEquals(0, result.linkedCount);
            System.assertEquals(1, result.errorCount, 'The row without contact info should be flagged.');
            System.assert(
                !JSON.serialize(result).toLowerCase().contains('duplicate'),
                'Matched leads must be skipped without a duplicate message.'
            );
            System.assert(queryCount <= 20, 'Import should stay bulk-safe. Queries=' + queryCount);

            List<Lead> owned = [
                SELECT Email, LeadSource
                FROM Lead
                WHERE OwnerId = :testUser.Id
                  AND Email IN ('existing.borrower@example.com', 'fresh.buyer@example.com', 'past.client@example.com')
            ];
            System.assertEquals(3, owned.size(), 'Existing matched lead stays once; two new rows are added.');
            Integer pastClientCount = 0;
            for (Lead leadRecord : owned) {
                if (leadRecord.LeadSource == 'Past Client') {
                    pastClientCount++;
                }
            }
            System.assertEquals(1, pastClientCount);
            System.assertEquals(1, ExternalLoPortalService.getPastClients(null).size());
        }
    }

    @isTest
    static void consumerImport_handlesTwoHundredRows() {
        User testUser = importer();
        List<String> lines = new List<String>{ 'FirstName,LastName,Phone,Email,Type' };
        for (Integer i = 0; i < 200; i++) {
            lines.add('Bulk' + i + ',Buyer,555000' + String.valueOf(i).leftPad(4, '0') + ',bulk' + i + '@example.com,Lead');
        }

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv(
                'consumer',
                String.join(lines, '\n')
            );
            Integer dmlRows = Limits.getDmlRows();
            Test.stopTest();

            System.assertEquals(200, result.successCount, 'All 200 unique consumer rows should import.');
            System.assertEquals(0, result.errorCount);
            System.assert(dmlRows >= 200, 'Bulk insert should write 200 leads in one DML.');
        }
    }

    @isTest
    static void partnerImport_linksSharedContactInsteadOfDuplicating() {
        User testUser = importer();
        Id personAccountRecordTypeId = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();

        Account shared;
        System.runAs(testUser) {
            shared = new Account(
                RecordTypeId = personAccountRecordTypeId,
                FirstName = 'Shared',
                LastName = 'Realtor',
                PersonEmail = 'shared.realtor@example.com',
                Phone = '2395550200',
                Group__pc = 'Realtor',
                Company__c = 'Shared Realty',
                OwnerId = testUser.Id
            );
            insert shared;
        }
        shared = [SELECT Id, PersonContactId FROM Account WHERE Id = :shared.Id];

        String csvBody =
            'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
            'Shared,Realtor,(239) 555-0200,shared.realtor@example.com,Shared Realty,Naples,Realtor\n' +
            'New,Partner,2395550211,new.partner@example.com,New Realty,Fort Myers,Realtor\n' +
            'Missing,Company,2395550212,missing.co@example.com,,,Realtor\n';

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoCsvImportService.ImportResult result = ExternalLoWorkspaceController.importCsv('partner', csvBody);
            Test.stopTest();

            System.assertEquals(2, result.successCount, 'Created plus linked rows both count as added. ' + JSON.serialize(result.errors));
            System.assertEquals(1, result.linkedCount, 'The shared realtor should be linked, not duplicated.');
            System.assertEquals(true, result.links.isEmpty(), 'The Aura list must not split linked rows.');
            System.assertEquals(2, result.successes.size());
            System.assertEquals('Shared Realtor', result.successes[0].name);
            System.assertEquals('New Partner', result.successes[1].name);
            System.assert(result.successes[0].rowKey.startsWith('a-'), result.successes[0].rowKey);
            System.assert(result.successes[1].rowKey.startsWith('a-'), result.successes[1].rowKey);
            System.assertEquals(1, result.errorCount, 'Missing company should be explained.');
            System.assert(!result.userMessage.contains('linked to existing'), result.userMessage);

            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE PersonEmail = 'shared.realtor@example.com'],
                'The shared realtor account must not be duplicated.'
            );
            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM External_User_Assignment__c
                    WHERE User__c = :testUser.Id
                      AND Contact__c = :shared.PersonContactId
                ]
            );
            Set<Id> assignedContacts = ExternalUserAssignmentRepository.getInstance()
                .selectContactIdsByUserId(testUser.Id);
            System.assert(assignedContacts.contains(shared.PersonContactId));
            System.assert(
                ExternalUserAssignmentRepository.getInstance()
                    .selectUniqueKeys(testUser.Id, assignedContacts)
                    .size() > 0
            );
        }
    }

    @isTest
    static void controllerAndRepository_coverErrorAndEmptyPaths() {
        User testUser = importer();
        System.runAs(testUser) {
            Test.startTest();
            Boolean caught = false;
            try {
                ExternalLoWorkspaceController.importCsv('unknown', 'FirstName,LastName\nA,B');
            } catch (AuraHandledException error) {
                caught = true;
            }
            System.assertEquals(true, caught, 'Unknown family should surface a user-safe error.');
            System.assertEquals(0, ExternalUserAssignmentRepository.getInstance().selectContactIdsByUserId(null).size());
            System.assertEquals(0, ExternalUserAssignmentRepository.getInstance().selectUniqueKeys(null, null).size());
            System.assertEquals(0, ExternalUserAssignmentRepository.getInstance().selectUniqueKeys(testUser.Id, new Set<Id>()).size());
            System.assertEquals(0, ExternalLoWorkspaceController.getPastClients('no-such-client').size());
            System.assertEquals(0, ExternalLoWorkspaceController.getPastClients(null).size());
            AuraHandledException wrapped = ExternalLoWorkspaceController.toAura(new CalloutException('hidden'));
            System.assertNotEquals(null, wrapped);
            try {
                insert new Lead();
                System.assert(false, 'Lead insert without last name should fail.');
            } catch (DmlException dmlError) {
                AuraHandledException dmlWrapped = ExternalLoWorkspaceController.toAura(dmlError);
                System.assertNotEquals(null, dmlWrapped.getMessage());
            }
            Test.stopTest();
        }
    }

    @isTest
    static void importCsv_negativeAndParserCases() {
        System.runAs(importer()) {
            Boolean blankCaught = false;
            try {
                ExternalLoCsvImportService.importCsv('consumer', '');
            } catch (DomainException error) {
                blankCaught = true;
                System.assert(error.getMessage().contains('CSV'));
            }
            System.assertEquals(true, blankCaught);

            Boolean familyCaught = false;
            try {
                ExternalLoCsvImportService.importCsv('unknown', 'FirstName,LastName\nA,B');
            } catch (DomainException error) {
                familyCaught = true;
            }
            System.assertEquals(true, familyCaught);

            ExternalLoCsvParser.Table table = ExternalLoCsvParser.parse(
                'FirstName,LastName,Notes\n"Jane","Doe","Said ""hello"", then left"\n'
            );
            System.assertEquals(1, table.rows.size());
            System.assertEquals('Jane', table.rows[0][0]);
            System.assert(table.rows[0][2].contains('hello'));

            Boolean tooLarge = false;
            try {
                String largeBody = 'a';
                while (largeBody.length() < 120001) {
                    largeBody += largeBody;
                }
                ExternalLoCsvImportService.importCsv('consumer', largeBody);
            } catch (DomainException error) {
                tooLarge = error.getMessage().contains('too large');
            }
            System.assertEquals(true, tooLarge);
            System.assertEquals(3, ExternalLoCsvImportService.estimatedLineCount('h\na\nb'));
            Boolean tooManyRows = false;
            try {
                String manyRows = 'FirstName,LastName\n';
                for (Integer i = 0; i < 202; i++) {
                    manyRows += 'A,B\n';
                }
                ExternalLoCsvImportService.importCsv('consumer', manyRows);
            } catch (DomainException error) {
                tooManyRows = error.getMessage().contains('200 rows');
            }
            System.assertEquals(true, tooManyRows);

            System.assertEquals(null, ExternalLoPhoneNormalizer.digits(null));
            System.assertEquals('2395550200', ExternalLoPhoneNormalizer.matchKey('+1 (239) 555-0200'));
            System.assertEquals('2395550200', ExternalLoPhoneNormalizer.matchKey('12395550200'));
            System.assert(ExternalLoPhoneNormalizer.soqlVariants('239-555-0200').contains('(239) 555-0200'));
            System.assertEquals(0, ExternalLoPhoneNormalizer.soqlVariants('').size());
            System.assertEquals(0, ExternalLoPhoneNormalizer.soqlVariants(new Set<String>()).size());
            System.assertEquals('Jane Doe', ExternalLoCsvImportService.resolveName('Jane', 'Doe', null));
            System.assertEquals('Jane', ExternalLoCsvImportService.resolveName('Jane', null, null));
            System.assertEquals('Doe', ExternalLoCsvImportService.resolveName(null, 'Doe', '  '));
            System.assertEquals('Full Name', ExternalLoCsvImportService.resolveName('A', 'B', 'Full Name'));
            System.assertEquals('', ExternalLoCsvImportService.resolveName(null, null, null));
            System.assertEquals(
                0,
                ExternalLoPartnerLinkWriter.insertAssignments(null).size()
            );
            System.assertEquals(
                0,
                ExternalLoPartnerLinkWriter.insertAssignments(new List<External_User_Assignment__c>()).size()
            );
            System.assertEquals(0, ExternalLoPartnerLinkWriter.insertAccountShares(null).size());
            System.assertEquals(0, ExternalLoPartnerLinkWriter.insertAccountShares(new List<AccountShare>()).size());
            List<Database.SaveResult> failedShares = ExternalLoPartnerLinkWriter.insertAccountShares(
                new List<AccountShare>{ new AccountShare() }
            );
            System.assertEquals(1, failedShares.size());
            System.assertEquals(false, failedShares[0].isSuccess());
            System.assertEquals(0, new AccountShareRepository().selectManualShares(null, null).size());
            System.assertEquals(0, new PersonAccountRepository().selectPartnersForImportMatch(null, null).size());
            System.assertEquals(
                0,
                LeadRepository.getInstance().selectPortalLeadsForImportMatch(null, null, null).size()
            );
            System.assertEquals(null, UserRepository.getInstance().selectPortalProfile(null));
            System.assertNotEquals(
                null,
                UserRepository.getInstance().queryPortalProfile(UserInfo.getUserId(), false)
            );
        }
    }

    @isTest
    static void partnerImport_doesNotMatchOnNameAlone() {
        User testUser = importer();
        Id personAccountRecordTypeId = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
        System.runAs(testUser) {
            insert new Account(
                RecordTypeId = personAccountRecordTypeId,
                FirstName = 'John',
                LastName = 'Smith',
                PersonEmail = 'john.smith.original@example.com',
                Phone = '2395550400',
                Group__pc = 'Realtor',
                Company__c = 'Smith Realty',
                OwnerId = testUser.Id
            );
            String csvBody =
                'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
                'John,Smith,2395550499,,Smith Realty,Naples,Realtor\n';
            Test.startTest();
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv('partner', csvBody);
            Test.stopTest();
            System.assertEquals(0, result.linkedCount, 'Name-only similarity must not link. ' + JSON.serialize(result));
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE PersonEmail = 'john.smith.original@example.com'],
                'The original John Smith must stay a single record.'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE LastName = 'Smith' AND Company__c = 'Smith Realty'],
                'A blocked duplicate-rule insert is acceptable; a silent name-link is not.'
            );
        }
    }

    @isTest
    static void partnerImport_linkedRealtorIsVisibleToNonOwner() {
        Id personAccountRecordTypeId = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();

        User ownerUser = ExternalLoPortalTestHelper.createStandardUser('ownr');
        User importer = ExternalLoPortalTestHelper.createStandardUser('cimp');
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);

        Account shared = new Account(
            RecordTypeId = personAccountRecordTypeId,
            FirstName = 'Owned',
            LastName = 'Elsewhere',
            PersonEmail = 'owned.elsewhere@example.com',
            Phone = '2395550200',
            Group__pc = 'Realtor',
            Company__c = 'Other Realty',
            OwnerId = ownerUser.Id
        );
        ExternalLoPortalTestHelper.insertAfterSetupDml(shared);
        shared = [SELECT Id, PersonContactId, OwnerId FROM Account WHERE Id = :shared.Id];

        String csvBody =
            'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
            'Owned,Elsewhere,(239) 555-0200,owned.elsewhere@example.com,Other Realty,Naples,Realtor\n';

        ExternalLoCsvImportService.ImportResult result;
        List<Account> visiblePartners;
        System.runAs(importer) {
            Test.startTest();
            result = ExternalLoCsvImportService.importCsv('partner', csvBody);
            visiblePartners = new PersonAccountRepository().selectPortalPartnersForUser(importer.Id);
            Test.stopTest();
        }

        System.assertEquals(1, result.linkedCount, 'The owned realtor should be linked. ' + JSON.serialize(result));
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AccountShare
                WHERE AccountId = :shared.Id
                  AND UserOrGroupId = :importer.Id
                  AND RowCause = 'Manual'
                  AND AccountAccessLevel = 'Read'
            ],
            'Linking must grant the importer Read AccountShare.'
        );
        Boolean found = false;
        for (Account partner : visiblePartners) {
            if (partner.Id == shared.Id) {
                found = true;
            }
        }
        System.assertEquals(true, found, 'Linked realtor must be visible to the importer via sharing.');
    }

    @isTest
    static void consumerImport_skipOnlyFileExplainsMatchesWereSkipped() {
        User testUser = importer();
        String csvBody =
            'FirstName,LastName,Phone,Email,Type\n' +
            'Existing,Borrower,239-555-0100,existing.borrower@example.com,Lead\n';
        System.runAs(testUser) {
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv('consumer', csvBody);
            System.assertEquals(0, result.successCount);
            System.assertEquals('No new rows were added.', result.userMessage);
        }
    }

    @isTest
    static void consumerImport_firstNameOnlyDoesNotWriteNullLiteral() {
        User testUser = importer();
        String csvBody =
            'FirstName,LastName,Phone,Email,Type\n' +
            'Jane,,2395550999,jane.only@example.com,Lead\n';
        System.runAs(testUser) {
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv('consumer', csvBody);
            System.assertEquals(1, result.successCount, JSON.serialize(result));
            List<Lead> imported = [
                SELECT FirstName, LastName, Company
                FROM Lead
                WHERE Email = 'jane.only@example.com'
                LIMIT 1
            ];
            System.assertEquals(1, imported.size(), 'The first-name-only row should insert a lead.');
            System.assertEquals('Jane', imported[0].FirstName);
            System.assertNotEquals('null', imported[0].LastName);
            System.assertNotEquals(null, imported[0].LastName);
        }
    }
}