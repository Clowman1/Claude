@isTest
private class ExternalLoProgressServiceTest {

    @isTest
    static void getProgress_backCreditsHistoricalActivityType() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        System.runAs(importer) {
            insert new Task(
                Subject = 'Legacy call',
                Status = 'Completed',
                Activity_Type__c = 'Call - Active Agent',
                ActivityDate = Date.today(),
                OwnerId = UserInfo.getUserId()
            );

            Test.startTest();
            ExternalLoProgressService.ProgressPayload payload = ExternalLoProgressService.getProgress(
                UserInfo.getUserId()
            );
            Test.stopTest();

            System.assertNotEquals(null, payload.week);
            System.assertNotEquals(null, payload.month);
            System.assertNotEquals(null, payload.quarter);
            Integer realtorCompleted = 0;
            for (ExternalLoActivityRollupBuilder.CategoryScore row : payload.week.rows) {
                if (row.activityKey == 'realtor-outreach') {
                    realtorCompleted = row.completed;
                }
            }
            // 2026-10-21: an uncategorised call is credited by who was contacted; no contact, no credit.
            System.assertEquals(
                0,
                realtorCompleted,
                'A call type alone (no contact, no category) must not credit realtor outreach.'
            );
        }
    }
}