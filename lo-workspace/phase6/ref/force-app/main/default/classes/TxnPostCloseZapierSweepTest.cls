@IsTest
private class TxnPostCloseZapierSweepTest {

    private class OkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('ok');
            return res;
        }
    }

    // Mirrors the live failure: Zapier 404s when the Zap is switched off.
    private class ZapOffMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('please unsubscribe me!');
            return res;
        }
    }

    private static Transaction__c newEligible(String loanNumber, Date postClosed) {
        return new Transaction__c(
            Status__c = 'Post-Closed',
            Biz_Dev__c = 'Biz Dev - Reach',
            Loan_Purpose__c = 'Purchase',
            Loan_Number__c = loanNumber,
            Post_Closed_Date__c = postClosed
        );
    }

    @IsTest
    static void resendsFileWhoseWebhookNeverLanded() {
        Transaction__c txn = newEligible('SWEEP-0000000001', Date.newInstance(2026, 8, 20));
        insert txn;
        // Simulate the live state: flow fired, callout failed, nothing recorded.
        update new Transaction__c(Id = txn.Id, Zapier_Post_Closed_Webhook_Sent_At__c = null);

        Test.setMock(HttpCalloutMock.class, new OkMock());
        Test.startTest();
        Integer picked = TxnPostCloseZapierSweep.sweep();
        Test.stopTest();

        System.assert(picked >= 1, 'Sweep should have picked up the unsent file');
        Transaction__c after = [
            SELECT Zapier_Post_Closed_Webhook_Sent_At__c FROM Transaction__c WHERE Id = :txn.Id
        ];
        System.assertNotEquals(null, after.Zapier_Post_Closed_Webhook_Sent_At__c,
            'Sweep should have recorded the send');
    }

    @IsTest
    static void ignoresFilesFromBeforeTheFlowExisted() {
        Transaction__c old = newEligible('SWEEP-0000000002', Date.newInstance(2025, 3, 1));
        insert old;
        // Org automation stamps Post_Closed_Date__c on insert, so backdate afterwards.
        update new Transaction__c(Id = old.Id, Post_Closed_Date__c = Date.newInstance(2025, 3, 1));
        System.assertEquals(Date.newInstance(2025, 3, 1),
            [SELECT Post_Closed_Date__c FROM Transaction__c WHERE Id = :old.Id].Post_Closed_Date__c,
            'Backdate did not stick; cutoff test would be meaningless');

        // 404 keeps the timestamp null, so only the cutoff can exclude this record.
        Test.setMock(HttpCalloutMock.class, new ZapOffMock());
        Test.startTest();
        Integer picked = TxnPostCloseZapierSweep.sweep();
        Test.stopTest();

        System.assertEquals(0, picked,
            'Pre-flow historical files must never be pushed to Zapier');
    }

    @IsTest
    static void alertsWhenAFileIsStuck() {
        Transaction__c txn = newEligible('SWEEP-0000000003', Date.today().addDays(-5));
        insert txn;
        update new Transaction__c(Id = txn.Id,
            Post_Closed_Date__c = Date.today().addDays(-5),
            Zapier_Post_Closed_Webhook_Sent_At__c = null);

        Test.startTest();
        Integer reported = TxnPostCloseZapierSweep.alertIfBacklogged();
        Test.stopTest();

        System.assert(reported >= 1, 'A file stuck for 5 days should be reported');
    }

    @IsTest
    static void staysQuietWhenNothingIsStuck() {
        // Post-closed today: still in flight, not stuck. Must not alert.
        Transaction__c txn = newEligible('SWEEP-0000000004', Date.today());
        insert txn;
        update new Transaction__c(Id = txn.Id,
            Post_Closed_Date__c = Date.today(),
            Zapier_Post_Closed_Webhook_Sent_At__c = null);

        Test.startTest();
        Integer reported = TxnPostCloseZapierSweep.alertIfBacklogged();
        Test.stopTest();

        System.assertEquals(0, reported, 'Same-day files must not raise an alert');
    }

    @IsTest
    static void schedulableEntryPointRuns() {
        Test.setMock(HttpCalloutMock.class, new OkMock());
        Test.startTest();
        System.schedule('ZapierSweepTest', '0 0 1 * * ?', new TxnPostCloseZapierSweep());
        Test.stopTest();
    }
}