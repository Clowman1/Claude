@IsTest
private class TwilioStopKeywordServiceTest {

    @IsTest
    static void stopOptsOutLinkedAndSameNumberRecordsButOtherTextsDoNot() {
        Id personRt = ExternalLoPortalTestHelper.requirePersonAccountRecordTypeId();
        Account borrower = new Account(RecordTypeId = personRt, FirstName = 'Stop', LastName = 'Borrower',
            PersonMobilePhone = '407-555-0161');
        insert borrower;
        Lead sameNumber = new Lead(FirstName = 'Stop', LastName = 'Lead', Company = 'Stop Co', MobilePhone = '407-555-0161');
        Lead other = new Lead(FirstName = 'Keep', LastName = 'Lead', Company = 'Keep Co', MobilePhone = '407-555-0162');
        insert new List<Lead>{ sameNumber, other };

        Test.startTest();
        insert new List<TwilioSF__Message__c>{
            // Linked to the Account; the Lead is found by the same number.
            new TwilioSF__Message__c(TwilioSF__Direction__c = 'inbound', TwilioSF__Account__c = borrower.Id,
                TwilioSF__From_Number_Unformatted__c = '4075550161', TwilioSF__Body__c = ' Stop. '),
            // Not a keyword: "please don't stop" is a conversation, not an opt-out.
            new TwilioSF__Message__c(TwilioSF__Direction__c = 'inbound',
                TwilioSF__From_Number_Unformatted__c = '4075550162', TwilioSF__Body__c = 'Please don\'t stop texting')
        };
        Test.stopTest();

        System.assertEquals(true, [SELECT SMS_Opt_Out__c FROM Account WHERE Id = :borrower.Id].SMS_Opt_Out__c);
        Lead l = [SELECT Opt_Out_from_SMS_Automation__c, smagicinteract__SMSOptOut__c FROM Lead WHERE Id = :sameNumber.Id];
        System.assertEquals(true, l.Opt_Out_from_SMS_Automation__c);
        System.assertEquals(true, l.smagicinteract__SMSOptOut__c);
        System.assertEquals(false, [SELECT Opt_Out_from_SMS_Automation__c FROM Lead WHERE Id = :other.Id].Opt_Out_from_SMS_Automation__c);
    }
}
