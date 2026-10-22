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
            System.assert(
                realtorCompleted >= 1,
                'Credit_Activity_Types must back-credit a Call without Activity_Category__c.'
            );
        }
    }
}