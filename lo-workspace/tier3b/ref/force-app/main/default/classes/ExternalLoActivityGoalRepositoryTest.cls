@isTest
private class ExternalLoActivityGoalRepositoryTest {

    @testSetup
    static void setupCommunityUser() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
    }

    @isTest
    static void selectByUserIdReturnsOnlyThatUsersRows() {
        User portalUser = [
            SELECT Id FROM User WHERE Alias = 'cimp' ORDER BY CreatedDate DESC LIMIT 1
        ];
        ExternalLoPortalTestHelper.grantPortalAccess(portalUser.Id);
        System.runAs(portalUser) {
            List<External_LO_Activity_Goal__c> seed = new List<External_LO_Activity_Goal__c>{
                new External_LO_Activity_Goal__c(
                    Activity_Key__c = 'realtor-outreach',
                    Weekly_Target__c = 25,
                    Is_Enabled__c = true
                )
            };
            ExternalLoActivityGoalWriter.upsertGoals(portalUser.Id, seed);

            Test.startTest();
            List<External_LO_Activity_Goal__c> rows = ExternalLoActivityGoalRepository.getInstance()
                .selectByUserId(portalUser.Id);
            Map<String, External_LO_Activity_Goal__c> byKey = ExternalLoActivityGoalRepository.getInstance()
                .selectMapByUserId(portalUser.Id);
            List<External_LO_Activity_Goal__c> empty = ExternalLoActivityGoalRepository.getInstance()
                .selectByUserId(null);
            Test.stopTest();

            System.assertEquals(1, rows.size(), 'Repository must see the row written in SYSTEM_MODE.');
            System.assertEquals(25, byKey.get('realtor-outreach').Weekly_Target__c);
            System.assertEquals(0, empty.size());
        }
    }

    @isTest
    static void writerUpsertsTwoHundredRowsWithoutSoqlInLoop() {
        User portalUser = [
            SELECT Id FROM User WHERE Alias = 'cimp' ORDER BY CreatedDate DESC LIMIT 1
        ];
        ExternalLoPortalTestHelper.grantPortalAccess(portalUser.Id);
        System.runAs(portalUser) {
            List<External_LO_Activity_Goal__c> goals = new List<External_LO_Activity_Goal__c>();
            for (Integer i = 0; i < 200; i++) {
                goals.add(new External_LO_Activity_Goal__c(
                    Activity_Key__c = 'bulk-' + String.valueOf(i),
                    Weekly_Target__c = 1,
                    Is_Enabled__c = true
                ));
            }

            Test.startTest();
            ExternalLoActivityGoalWriter.upsertGoals(portalUser.Id, goals);
            ExternalLoActivityGoalWriter.upsertGoals(portalUser.Id, goals);
            Integer queries = Limits.getQueries();
            Test.stopTest();

            List<External_LO_Activity_Goal__c> rows = ExternalLoActivityGoalRepository.getInstance()
                .selectByUserId(portalUser.Id);
            System.assertEquals(200, rows.size(), 'Unique_Key__c upsert must keep a single row per key.');
            System.assert(queries <= 2, 'Writer must not query per row. Queries=' + queries);
        }
    }

    @isTest
    static void writerSkipsBlankKeys() {
        User portalUser = [
            SELECT Id FROM User WHERE Alias = 'cimp' ORDER BY CreatedDate DESC LIMIT 1
        ];
        ExternalLoPortalTestHelper.grantPortalAccess(portalUser.Id);
        System.runAs(portalUser) {
            Test.startTest();
            ExternalLoActivityGoalWriter.upsertGoals(portalUser.Id, new List<External_LO_Activity_Goal__c>{
                new External_LO_Activity_Goal__c(Activity_Key__c = null, Weekly_Target__c = 5)
            });
            ExternalLoActivityGoalWriter.upsertGoals(null, new List<External_LO_Activity_Goal__c>());
            Test.stopTest();
            System.assertEquals(0, ExternalLoActivityGoalRepository.getInstance().selectByUserId(portalUser.Id).size());
        }
    }
}