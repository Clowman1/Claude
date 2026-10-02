@isTest
private class ExternalLoPartnerCsvImporterTest {

    @testSetup
    static void setupData() {
        ExternalLoPortalTestHelper.grantPortalAccess(UserInfo.getUserId());
    }

    @isTest
    static void partnerImport_sameFileDuplicateDoesNotCreateSecondAccount() {
        User testUser = ExternalLoPortalTestHelper.currentUser();
        ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
        String csvBody =
            'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
            'Dup,Realtor,2395550311,dup.realtor@example.com,Dup Realty,Naples,Realtor\n' +
            'Dup,Realtor,(239) 555-0311,dup.realtor@example.com,Dup Realty,Naples,Realtor\n';

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv('partner', csvBody);
            Test.stopTest();

            System.assertEquals(2, result.successCount, JSON.serialize(result));
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE PersonEmail = 'dup.realtor@example.com'],
                'Two CSV rows for one realtor must create a single Person Account.'
            );
            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM External_User_Assignment__c
                    WHERE User__c = :testUser.Id
                ],
                'In-file duplicates must not insert a second assignment.'
            );
        }
    }

    @isTest
    static void partnerImport_houseLockedMatchIsNotLinked() {
        User importer = ExternalLoPortalTestHelper.currentUser();
        Id personAccountRecordTypeId = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
        User ownerUser = ExternalLoPortalTestHelper.createStandardUser('hlown');
        Account houseLocked = new Account(
            RecordTypeId = personAccountRecordTypeId,
            FirstName = 'House',
            LastName = 'Locked',
            PersonEmail = 'house.locked@example.com',
            Phone = '2395550320',
            Group__pc = 'Realtor',
            Company__c = 'House Realty',
            OwnerId = ownerUser.Id,
            Biz_Dev_Designation__c = 'Biz Dev - Reach'
        );
        ExternalLoPortalTestHelper.insertAfterSetupDml(houseLocked);

        String csvBody =
            'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
            'House,Locked,2395550320,house.locked@example.com,House Realty,Naples,Realtor\n';
        System.runAs(importer) {
            Test.startTest();
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv('partner', csvBody);
            Test.stopTest();

            System.assertEquals(0, result.linkedCount, JSON.serialize(result));
            System.assertEquals(0, result.successCount, JSON.serialize(result));
            System.assertEquals(1, result.errorCount);
            System.assert(
                result.errors[0].message.contains('house team'),
                result.errors[0].message
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE PersonEmail = 'house.locked@example.com'],
                'House-locked partners must not be duplicated.'
            );
            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM External_User_Assignment__c
                    WHERE User__c = :importer.Id
                ]
            );
            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM AccountShare
                    WHERE AccountId = :houseLocked.Id
                      AND UserOrGroupId = :importer.Id
                      AND RowCause = 'Manual'
                ]
            );
        }
    }

    @isTest
    static void partnerImport_firstNameOnlyDoesNotWriteNullLiteral() {
        User testUser = ExternalLoPortalTestHelper.currentUser();
        ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
        String csvBody =
            'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
            'Pat,,2395550330,pat.only@example.com,Pat Realty,Naples,Realtor\n';
        System.runAs(testUser) {
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv('partner', csvBody);
            System.assertEquals(1, result.successCount, JSON.serialize(result.errors));
            Account imported = [
                SELECT FirstName, LastName
                FROM Account
                WHERE PersonEmail = 'pat.only@example.com'
                LIMIT 1
            ];
            System.assertEquals('Pat', imported.FirstName);
            System.assertNotEquals('null', imported.LastName);
        }
    }

    @isTest
    static void partnerImport_mapsTypesRejectsBlankNameAndDedupesByPhone() {
        User testUser = ExternalLoPortalTestHelper.currentUser();
        ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
        String csvBody =
            'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
            ',,,no.name@example.com,Missing Name Realty,Naples,Realtor\n' +
            'Title,Agent,2395550341,title.agent@example.com,Title Co,Naples,Title\n' +
            'Phone,Twin,2395550344,,Phone Realty,Naples,Realtor\n' +
            'Phone,Twin,(239) 555-0344,,Phone Realty,Naples,Realtor\n';
        System.runAs(testUser) {
            Test.startTest();
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv('partner', csvBody);
            Test.stopTest();

            System.assertEquals(1, result.errorCount, JSON.serialize(result.errors));
            System.assert(
                result.errors[0].message.contains('first and last name'),
                result.errors[0].message
            );
            Account titleAgent = [
                SELECT Group__pc
                FROM Account
                WHERE PersonEmail = 'title.agent@example.com'
                LIMIT 1
            ];
            System.assertEquals('Title Agent', titleAgent.Group__pc);
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE LastName = 'Twin' AND Company__c = 'Phone Realty'],
                'Two phone-only rows in one file must create a single Person Account.'
            );
        }
    }

    @isTest
    static void mapPartnerGroup_coversTypeAliases() {
        System.assertEquals('Realtor', ExternalLoPartnerCsvImporter.mapPartnerGroup(null));
        System.assertEquals('Realtor', ExternalLoPartnerCsvImporter.mapPartnerGroup('  '));
        System.assertEquals('Title Agent', ExternalLoPartnerCsvImporter.mapPartnerGroup('Title'));
        System.assertEquals('Insurance Agent', ExternalLoPartnerCsvImporter.mapPartnerGroup('Insurance'));
        System.assertEquals('Realtor Prospect', ExternalLoPartnerCsvImporter.mapPartnerGroup('Realtor Prospect'));
        System.assert(
            ExternalLoPartnerCsvImporter.userSafeDmlMessage(null).contains('couldn\'t be saved')
        );
        List<Database.SaveResult> failedShares = ExternalLoPartnerLinkWriter.insertAccountShares(
            new List<AccountShare>{ new AccountShare() }
        );
        System.assertNotEquals(null, ExternalLoPartnerCsvImporter.userSafeDmlMessage(failedShares[0]));
    }

    @isTest
    static void partnerImport_matchesExistingByPhoneOnly() {
        User testUser = ExternalLoPortalTestHelper.currentUser();
        Id personAccountRecordTypeId = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
        Account existing;
        System.runAs(testUser) {
            existing = new Account(
                RecordTypeId = personAccountRecordTypeId,
                FirstName = 'Phone',
                LastName = 'Match',
                PersonEmail = 'phone.match.original@example.com',
                Phone = '2395550350',
                Group__pc = 'Realtor',
                Company__c = 'Phone Match Realty',
                OwnerId = testUser.Id
            );
            insert existing;
        }
        String csvBody =
            'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
            'Phone,Match,(239) 555-0350,,Phone Match Realty,Naples,Realtor\n';
        System.runAs(testUser) {
            ExternalLoCsvImportService.ImportResult result = ExternalLoCsvImportService.importCsv('partner', csvBody);
            System.assertEquals(1, result.linkedCount, JSON.serialize(result));
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE PersonEmail = 'phone.match.original@example.com']
            );
        }
    }

    @isTest
    static void partnerImport_existingManualShareStillLinks() {
        Id personAccountRecordTypeId = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
        User ownerUser = ExternalLoPortalTestHelper.createStandardUser('shown');
        User importer = ExternalLoPortalTestHelper.createStandardUser('shimp');
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        Account shared = new Account(
            RecordTypeId = personAccountRecordTypeId,
            FirstName = 'Pre',
            LastName = 'Shared',
            PersonEmail = 'pre.shared@example.com',
            Phone = '2395550360',
            Group__pc = 'Realtor',
            Company__c = 'Pre Share Realty',
            OwnerId = ownerUser.Id
        );
        ExternalLoPortalTestHelper.insertAfterSetupDml(shared);
        shared = [SELECT Id, PersonContactId FROM Account WHERE Id = :shared.Id];
        AccountShare existingShare = new AccountShare(
            AccountId = shared.Id,
            UserOrGroupId = importer.Id,
            AccountAccessLevel = 'Read',
            OpportunityAccessLevel = 'None',
            CaseAccessLevel = 'None',
            RowCause = Schema.AccountShare.RowCause.Manual
        );
        ExternalLoPortalTestHelper.insertAfterSetupDml(existingShare);

        String csvBody =
            'FirstName,LastName,Phone,Email,Company,Market,PartnerType\n' +
            'Pre,Shared,2395550360,pre.shared@example.com,Pre Share Realty,Naples,Realtor\n';
        ExternalLoCsvImportService.ImportResult result;
        System.runAs(importer) {
            result = ExternalLoCsvImportService.importCsv('partner', csvBody);
        }
        System.assertEquals(1, result.linkedCount, JSON.serialize(result));
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AccountShare
                WHERE AccountId = :shared.Id
                  AND UserOrGroupId = :importer.Id
                  AND RowCause = 'Manual'
            ]
        );
    }
}