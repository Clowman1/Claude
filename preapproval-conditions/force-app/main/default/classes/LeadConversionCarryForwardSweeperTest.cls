@IsTest
private class LeadConversionCarryForwardSweeperTest {

    // The Hall case: a Lead converted with its conditions never carried. The sweep has to finish
    // the job without anyone noticing it was left undone.
    @IsTest
    static void theSweepCarriesALeadTheTriggerMissed() {
        Transaction__c transactionRecord = createTransaction('Sweep Loan', 'LD-SWEEP');

        Lead leadRecord = new Lead(
            FirstName = 'Sweep',
            LastName = 'Borrower',
            Company = 'Sweep Borrower',
            Status = 'New',
            Email = 'sweep-carry@example.com'
        );
        insert leadRecord;

        insert new Lead_Document_Request__c(
            Lead__c = leadRecord.Id,
            Name = 'Income',
            Subject__c = 'Paystub',
            Description__c = 'Please upload your paystub',
            Category__c = 'Income',
            Type__c = 'Loan Officer',
            Status__c = 'Cleared'
        );

        // Stamped before converting: Salesforce locks a converted Lead against update, so a
        // test cannot reproduce the real order of events here.
        update new Lead(Id = leadRecord.Id, Converted_Transaction_ID__c = transactionRecord.Id);
        convert(leadRecord.Id);


        Test.startTest();
        Integer swept = LeadConversionCarryForwardSweeper.sweep();
        Test.stopTest();

        System.assert(swept > 0, 'The sweep found the Lead.');
        System.assertEquals(1, [
            SELECT COUNT() FROM Condition__c WHERE Transaction__c = :transactionRecord.Id
        ], 'The condition reached the Transaction.');
    }

    // Re-running over a Lead that carried correctly has to be free, because the sweep does not
    // detect anything - it just runs again.
    @IsTest
    static void sweepingTwiceDoesNotDuplicate() {
        Transaction__c transactionRecord = createTransaction('Idempotent Loan', 'LD-SWEEP2');

        Lead leadRecord = new Lead(
            FirstName = 'Twice',
            LastName = 'Borrower',
            Company = 'Twice Borrower',
            Status = 'New',
            Email = 'sweep-twice@example.com'
        );
        insert leadRecord;
        insert new Lead_Document_Request__c(
            Lead__c = leadRecord.Id,
            Name = 'Asset',
            Subject__c = 'Bank Statement',
            Description__c = 'Please upload your bank statement',
            Category__c = 'Asset',
            Type__c = 'Loan Officer',
            Status__c = 'Cleared'
        );
        // Stamped before converting: Salesforce locks a converted Lead against update, so a
        // test cannot reproduce the real order of events here.
        update new Lead(Id = leadRecord.Id, Converted_Transaction_ID__c = transactionRecord.Id);
        convert(leadRecord.Id);

        Test.startTest();
        LeadConversionCarryForwardSweeper.sweep();
        LeadConversionCarryForwardSweeper.sweep();
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM Condition__c WHERE Transaction__c = :transactionRecord.Id
        ], 'Two sweeps leave one condition, not two.');
    }

    private static Transaction__c createTransaction(String name, String loanNumber) {
        Transaction__c transactionRecord = new Transaction__c(
            Name = name,
            Status__c = TestDataFactory.getOpportunityStageName(),
            Loan_Number__c = loanNumber
        );
        insert transactionRecord;
        return transactionRecord;
    }

    private static void convert(Id leadId) {
        Database.LeadConvert request = new Database.LeadConvert();
        request.setLeadId(leadId);
        request.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1].MasterLabel);
        request.setDoNotCreateOpportunity(true);
        Database.convertLead(request, true);
    }
}
