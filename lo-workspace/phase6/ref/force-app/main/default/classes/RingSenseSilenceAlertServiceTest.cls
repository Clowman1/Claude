@IsTest
private class RingSenseSilenceAlertServiceTest {
    @IsTest
    static void repository_returns_latest_created_date() {
        insert new Call_Insight__c(Title__c = 'Silence repo check');
        System.assertNotEquals(null, CallInsightRepository.selectLatestCreatedDate());
    }

    @IsTest
    static void run_skips_email_when_insight_is_recent() {
        insert new Call_Insight__c(Title__c = 'Recent insight');
        Test.startTest();
        RingSenseSilenceAlertService.RunResult result = RingSenseSilenceAlertService.run();
        Test.stopTest();
        System.assertEquals(false, result.alerted);
        System.assertNotEquals(null, result.latestCreatedDate);
        List<Custom_Log__c> logs = [
            SELECT Data__c
            FROM Custom_Log__c
            WHERE Source__c = 'RingSense Silence Alert'
        ];
        System.assertEquals(1, logs.size());
        System.assert(logs[0].Data__c.contains('Feed healthy'));
    }

    @IsTest
    static void run_alerts_when_no_insights() {
        RingSenseSilenceAlertService.minCallsForAlert = 0;
        Test.startTest();
        RingSenseSilenceAlertService.RunResult result = RingSenseSilenceAlertService.run();
        Test.stopTest();
        System.assertEquals(true, result.alerted);
        System.assertEquals(null, result.latestCreatedDate);
        List<Custom_Log__c> logs = [
            SELECT Data__c
            FROM Custom_Log__c
            WHERE Source__c = 'RingSense Silence Alert'
        ];
        System.assertEquals(1, logs.size());
        System.assert(logs[0].Data__c.contains('never'));
    }

    @IsTest
    static void run_skips_email_when_no_calls_happened() {
        Test.startTest();
        RingSenseSilenceAlertService.RunResult result = RingSenseSilenceAlertService.run();
        Test.stopTest();
        System.assertEquals(false, result.alerted);
        System.assert(result.message.contains('Quiet period'));
    }

    @IsTest
    static void scheduler_invokes_service() {
        insert new Call_Insight__c(Title__c = 'Scheduled health');
        Test.startTest();
        String jobId = RingSenseSilenceAlertScheduler.schedule();
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void repository_returns_null_when_empty() {
        System.assertEquals(null, CallInsightRepository.selectLatestCreatedDate());
    }
}