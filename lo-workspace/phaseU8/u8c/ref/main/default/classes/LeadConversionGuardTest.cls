@IsTest
private class LeadConversionGuardTest {
    @IsTest
    static void anOpenConditionRefusesTheConversion() {
        Lead leadRecord = createLead();
        createRequest(leadRecord.Id, 'Review');

        String message = attemptConversion(leadRecord.Id);

        System.assertNotEquals(null, message, 'A Lead in review must not convert.');
        System.assert(
            message.contains('Unable to convert to Transaction with outstanding Pre-Approval Conditions'),
            'The Loan Officer is told why, not just refused: ' + message
        );
        System.assertEquals(
            false,
            [SELECT IsConverted FROM Lead WHERE Id = :leadRecord.Id].IsConverted,
            'And the refusal actually holds.'
        );
    }

    // Requested means the borrower has not sent anything yet; Review means nobody has decisioned
    // what they did send. Both are the state this guard exists to catch.
    @IsTest
    static void aRequestedConditionAlsoRefusesTheConversion() {
        Lead leadRecord = createLead();
        createRequest(leadRecord.Id, 'Requested');

        System.assertNotEquals(null, attemptConversion(leadRecord.Id));
    }

    @IsTest
    static void aFinishedConditionLetsTheLeadThrough() {
        Lead leadRecord = createLead();
        createRequest(leadRecord.Id, 'Cleared');

        System.assertEquals(
            null,
            attemptConversion(leadRecord.Id),
            'Every condition is finished, so nothing should stand in the way.'
        );
    }

    // Most Leads never raise a condition at all, and those have always converted freely.
    @IsTest
    static void aLeadWithNoConditionsIsUntouched() {
        Lead leadRecord = createLead();

        System.assertEquals(null, attemptConversion(leadRecord.Id));
    }

    // The guard keys off the conversion itself, not off the Lead being saved.
    @IsTest
    static void anOrdinaryEditIsNotBlocked() {
        Lead leadRecord = createLead();
        createRequest(leadRecord.Id, 'Review');

        Test.startTest();
        update new Lead(Id = leadRecord.Id, Status = 'Working');
        Test.stopTest();

        System.assertEquals(
            'Working',
            [SELECT Status FROM Lead WHERE Id = :leadRecord.Id].Status,
            'Editing a Lead mid-review is normal and must keep working.'
        );
    }

    /** Returns the error the conversion produced, or null when it went through. */
    private static String attemptConversion(Id leadId) {
        Database.LeadConvert convertRequest = new Database.LeadConvert();
        convertRequest.setLeadId(leadId);
        convertRequest.setConvertedStatus(convertedStatus());
        convertRequest.setDoNotCreateOpportunity(true);

        Database.LeadConvertResult result = Database.convertLead(convertRequest, false);
        if (result.isSuccess()) {
            return null;
        }
        return result.getErrors()[0].getMessage();
    }

    private static String convertedStatus() {
        return [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1].MasterLabel;
    }

    private static Lead createLead() {
        Lead leadRecord = new Lead(
            FirstName = 'Guard',
            LastName = 'Borrower',
            Company = 'Guard Borrower',
            Status = 'New',
            Email = 'guard-borrower@example.com'
        );
        insert leadRecord;
        return leadRecord;
    }

    private static Lead_Document_Request__c createRequest(Id leadId, String status) {
        Lead_Document_Request__c requestRecord = new Lead_Document_Request__c(
            Lead__c = leadId,
            Name = 'Paystub',
            Subject__c = 'Paystub',
            Description__c = 'Please upload your paystub',
            Category__c = 'Income',
            Type__c = 'Loan Officer',
            Status__c = status
        );
        insert requestRecord;
        return requestRecord;
    }
}