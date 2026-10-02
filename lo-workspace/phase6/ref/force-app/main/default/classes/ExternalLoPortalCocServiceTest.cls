@IsTest
private class ExternalLoPortalCocServiceTest {
    @IsTest
    static void submitChangeRequest_createsCocForLoan() {
        Id investorRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
              AND DeveloperName = 'Business_Account'
            LIMIT 1
        ].Id;
        Account lenderAccount = new Account(
            Name = 'Portal COC Lender',
            Type = 'Investor',
            RecordTypeId = investorRecordTypeId
        );
        insert lenderAccount;

        Transaction__c loanRecord = new Transaction__c(
            Name = 'COC Loan',
            Loan_Officer__c = UserInfo.getUserId(),
            Status__c = 'Processing',
            Loan_Amount__c = 300000,
            Lender_1st__c = 'UWM',
            Lender_lookup__c = lenderAccount.Id,
            Closing_Date__c = Date.today().addDays(30)
        );
        insert loanRecord;

        ExternalLoPortalCocService.SubmitRequest request = new ExternalLoPortalCocService.SubmitRequest();
        request.loanId = loanRecord.Id;
        request.reason = 'Other';
        request.notes = 'Portal test COC';

        Test.startTest();
        ExternalLoPortalCocService.SubmitResult result =
            ExternalLoPortalCocService.submitChangeRequest(request);
        Test.stopTest();

        System.assertNotEquals(null, result.cocId);
        Change_of_Circumstance__c saved = [
            SELECT Id, Transaction__c, Notes__c
            FROM Change_of_Circumstance__c
            WHERE Id = :result.cocId
            LIMIT 1
        ];
        System.assertEquals(loanRecord.Id, saved.Transaction__c);
        System.assertEquals('Portal test COC', saved.Notes__c);
    }
}