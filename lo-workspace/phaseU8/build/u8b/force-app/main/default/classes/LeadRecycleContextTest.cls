@isTest
private class LeadRecycleContextTest {

    private static final Id FAKE_LEAD = '00Q000000000001AAA';
    private static final Id FAKE_LOAN = 'a01000000000001AAA';

    @isTest
    static void silentWritesSkipOwnerEmailPartnerStampAndBdAttribution() {
        Lead l = new Lead(Id = FAKE_LEAD, LastName = 'Recycled', OwnerId = UserInfo.getUserId());
        LeadRecycleContext.silent = true;
        Test.startTest();
        ManualLeadOwnerNotificationService.notifyOwners(new List<Lead>{ l });
        LeadLoanPartnerAssignmentService.stampFromOwnerAssignments(new List<Lead>{ l }, null);
        LeadBdAttribution.apply(new List<Lead>{ l }, null);
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();
        System.assertEquals(0, emails, 'No owner email while the recycle write is silent.');
        System.assertEquals(null, l.Loan_Partner__c, 'Loan Partner is left exactly as cloned.');
    }

    @isTest
    static void bizDevPreApprovalWebhookNeverFiresForARecycledLead() {
        Lead before = new Lead(Id = FAKE_LEAD, Status = 'Working', Biz_Dev__c = 'Biz Dev - Reach');
        Lead after = new Lead(Id = FAKE_LEAD, Status = 'Pre-Approval', Biz_Dev__c = 'Biz Dev - Reach',
            Recycled_From_Transaction__c = FAKE_LOAN);
        Test.startTest();
        BizDevReachPreApprovalWebhookService.enqueueForStatusChanges(
            new List<Lead>{ after }, new Map<Id, Lead>{ FAKE_LEAD => before });
        Integer jobs = Limits.getQueueableJobs();
        Test.stopTest();
        System.assertEquals(0, jobs);
    }
}
