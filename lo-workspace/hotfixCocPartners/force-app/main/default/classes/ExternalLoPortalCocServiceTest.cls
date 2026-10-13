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
        request.reason = 'Other;Float to Lock';
        request.notes = 'Portal test COC';
        request.otherReason = 'Borrower asked';
        request.lockPeriod = '30 Days';

        ExternalLoPortalCocService.SubmitRequest missingRate = request;
        try {
            ExternalLoPortalCocService.submitChangeRequest(missingRate);
            System.assert(false, 'Float to Lock needs a rate, like the flow');
        } catch (DomainException e) {
            System.assert(e.getMessage().contains('rate'), e.getMessage());
        }
        request.newRate = 6.875;

        Test.startTest();
        ExternalLoPortalCocService.SubmitResult result =
            ExternalLoPortalCocService.submitChangeRequest(request);
        Test.stopTest();

        System.assertNotEquals(null, result.cocId);
        Change_of_Circumstance__c saved = [
            SELECT Id, Transaction__c, Notes__c, OwnerId, Reason_for_Change__c
            FROM Change_of_Circumstance__c
            WHERE Id = :result.cocId
            LIMIT 1
        ];
        System.assertEquals(loanRecord.Id, saved.Transaction__c);
        System.assertEquals('- Portal test COC', saved.Notes__c, 'Same format as the COC_Request flow.');
        System.assertEquals(new Set<String>{ 'Other', 'Float to Lock' }, new Set<String>(saved.Reason_for_Change__c.split(';')));
        Change_of_Circumstance__c extra = [SELECT Lock_Period__c, Other_Reason_for_COC__c, New_Rate__c FROM Change_of_Circumstance__c WHERE Id = :saved.Id];
        System.assertEquals('30 Days', extra.Lock_Period__c);
        System.assertEquals('Borrower asked', extra.Other_Reason_for_COC__c);
        System.assertEquals(6.875, extra.New_Rate__c);
        System.assertEquals(ExternalLoPortalCocService.COC_DESK_OWNER_ID, saved.OwnerId);
        Case cocCase = [SELECT Type, Transaction__c, Subject, Change_of_Circumstance__c FROM Case WHERE Id = :result.caseId];
        System.assertEquals('COC Request', cocCase.Type, 'The Case is what fires the COC notification flows.');
        System.assertEquals(saved.Id, cocCase.Change_of_Circumstance__c);
        System.assertEquals(loanRecord.Id, cocCase.Transaction__c);
        System.assertEquals('Change of Circumstances for COC Loan', cocCase.Subject);
    }
}