@IsTest
private class PayrollReviewControllerTest {

    static String people(Decimal total) {
        return JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{
            'name' => UserInfo.getName(), 'total' => total, 'lines' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'section' => 'As Loan Officer', 'loan' => 'Koko', 'loanAmount' => 342678,
                    'bizDev' => 'None (self-gen)', 'rate' => '150 BPS', 'commission' => 5140.17 },
                new Map<String, Object>{ 'section' => 'As LOA', 'loan' => 'Salas', 'loanAmount' => 278250,
                    'bizDev' => 'Biz Dev - Reach', 'rate' => '4 BPS', 'commission' => 111.30 }
            }
        }});
    }

    @IsTest
    static void loadReviewFeedbackAndReload() {
        Date closes = Date.today().addDays(3);
        PayrollReviewController.load('September 2026', Date.today(), closes, closes, people(5251.47));

        Payroll_Review__c mine = PayrollReviewController.getMine();
        Assert.areEqual(2, mine.Lines__r.size());
        Assert.areEqual('Koko', mine.Lines__r[0].Loan__c);
        Assert.areEqual(5251.47, mine.Total__c);
        Assert.areEqual('Not Reviewed', mine.Status__c);

        PayrollReviewController.markReviewed(mine.Id);
        Assert.areEqual('Reviewed', PayrollReviewController.getMine().Status__c);

        Test.startTest();
        PayrollReviewController.submitFeedback(mine.Id, 'Missing the Smith file');
        Test.stopTest();
        Payroll_Review__c disputed = [SELECT Status__c, Feedback__c FROM Payroll_Review__c WHERE Id = :mine.Id];
        Assert.areEqual('Disputed', disputed.Status__c);
        Assert.isTrue(disputed.Feedback__c.contains('Missing the Smith file'));

        // Sorted out with no change: the LO can still accept.
        PayrollReviewController.markReviewed(mine.Id);
        Assert.areEqual('Reviewed', [SELECT Status__c FROM Payroll_Review__c WHERE Id = :mine.Id].Status__c);

        // A corrected reload replaces the lines, resets the status and keeps the feedback.
        PayrollReviewController.load('September 2026', Date.today(), closes, closes, people(5300));
        Payroll_Review__c reloaded = [SELECT Status__c, Feedback__c, Total__c, (SELECT Id FROM Lines__r) FROM Payroll_Review__c];
        Assert.areEqual('Not Reviewed', reloaded.Status__c);
        Assert.areEqual(5300, reloaded.Total__c);
        Assert.areEqual(2, reloaded.Lines__r.size());
        Assert.isTrue(reloaded.Feedback__c.contains('Smith'));
    }

    @IsTest
    static void closedReviewIsHiddenAndLocked() {
        PayrollReviewController.load('August 2026', Date.today().addDays(-30), Date.today().addDays(-1), Date.today().addDays(-1), people(1));
        Assert.isNull(PayrollReviewController.getMine());
        Id reviewId = [SELECT Id FROM Payroll_Review__c].Id;
        try {
            PayrollReviewController.markReviewed(reviewId);
            Assert.fail('closed review should be locked');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void viewOnlyAfterFeedbackCloses() {
        PayrollReviewController.load('September 2026', Date.today(), Date.today().addDays(-1), Date.today().addDays(2), people(1));
        Payroll_Review__c mine = PayrollReviewController.getMine();
        Assert.isNotNull(mine, 'still viewable until Review Closes');
        try {
            PayrollReviewController.submitFeedback(mine.Id, 'too late');
            Assert.fail('feedback should be closed');
        } catch (AuraHandledException e) {
            Assert.areEqual('Not Reviewed', [SELECT Status__c FROM Payroll_Review__c].Status__c);
        }
    }

    @IsTest
    static void blankFeedbackRejectedAndUnknownNameLoadsNothing() {
        try {
            PayrollReviewController.submitFeedback(null, ' ');
            Assert.fail('blank feedback should fail');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
        try {
            PayrollReviewController.load('September 2026', Date.today(), Date.today(), Date.today(), '[{"name":"No Such Person zz","total":1,"lines":[]}]');
            Assert.fail('unknown name should fail');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('No Such Person zz'));
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Payroll_Review__c]);
    }
}
