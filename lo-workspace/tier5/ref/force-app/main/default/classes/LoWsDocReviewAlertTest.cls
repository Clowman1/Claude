@IsTest
private class LoWsDocReviewAlertTest {
    @IsTest
    static void uploadsWaitingForReviewRaiseAHighAlertUntilDecisioned() {
        Lead l = new Lead(LastName = 'Alertson', Company = 'n/a', Status = 'Working', OwnerId = UserInfo.getUserId());
        insert l;
        List<Lead_Document_Request__c> requests = new List<Lead_Document_Request__c>{
            new Lead_Document_Request__c(Lead__c = l.Id, Name = 'Pay stubs', Status__c = 'Review'),
            new Lead_Document_Request__c(Lead__c = l.Id, Name = 'W-2s', Status__c = 'Review'),
            new Lead_Document_Request__c(Lead__c = l.Id, Name = 'ID', Status__c = 'Requested')
        };
        insert requests;

        List<ExternalLoPromptService.PromptItem> alerts = ExternalLoPromptService.documentReviewPrompts(UserInfo.getUserId());
        System.assertEquals(1, alerts.size(), 'One alert per lead.');
        System.assertEquals(l.Id, alerts[0].recordId);
        System.assert(alerts[0].isHighAlert && alerts[0].canReview, 'High alert with Review documents.');
        System.assert(!alerts[0].canSnooze && alerts[0].canComplete != true, 'It cannot be snoozed or completed away.');
        System.assert(alerts[0].script.startsWith('2 '), alerts[0].script);

        requests[0].Status__c = 'Approved';
        requests[1].Status__c = 'Approved';
        update requests;
        System.assertEquals(0, ExternalLoPromptService.documentReviewPrompts(UserInfo.getUserId()).size(),
            'Gone once every upload is decisioned.');
    }
}