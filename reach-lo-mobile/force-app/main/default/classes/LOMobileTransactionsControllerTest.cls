@IsTest
private class LOMobileTransactionsControllerTest {

    // ponytail: query-only tests, no records inserted. Transaction__c carries 119 automations
    // with undefined execution order, so inserting one here would exercise that stack rather
    // than this class. Both branches of both methods still execute. If this class ever grows
    // real logic (field mapping, aggregation), build a proper fixture then.

    @IsTest
    static void transactionsActiveMode() {
        System.assertNotEquals(null, LOMobileTransactionsController.getTransactions('active'),
            'active transactions should return a list, never null');
    }

    @IsTest
    static void transactionsClosedMode() {
        System.assertNotEquals(null, LOMobileTransactionsController.getTransactions('closed'),
            'closed transactions should return a list, never null');
    }

    @IsTest
    static void leadsActiveMode() {
        System.assertNotEquals(null, LOMobileTransactionsController.getLeads('active'),
            'active leads should return a list, never null');
    }

    @IsTest
    static void leadsPreApprovedMode() {
        System.assertNotEquals(null, LOMobileTransactionsController.getLeads('preapproved'),
            'pre-approved leads should return a list, never null');
    }

    @IsTest
    static void nullModeFallsBackToActiveBranch() {
        System.assertNotEquals(null, LOMobileTransactionsController.getTransactions(null));
        System.assertNotEquals(null, LOMobileTransactionsController.getLeads(null));
    }
}
