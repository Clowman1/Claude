@IsTest
private class ExternalLoPortalCocFacadeTest {
    @IsTest
    static void getReasonOptions_returnsPicklistValues() {
        Test.startTest();
        List<ExternalLoPortalCocFacade.CocReasonOption> options =
            ExternalLoPortalCocFacade.getReasonOptions();
        Test.stopTest();
        System.assert(!options.isEmpty(), 'Expected COC reason options from picklist metadata.');
    }

    @IsTest
    static void submitCocRequest_requiresReason() {
        ExternalLoPortalCocFacade.CocSubmitResult result =
            ExternalLoPortalCocFacade.submitCocRequest(
                String.valueOf(UserInfo.getUserId()),
                new ExternalLoPortalCocFacade.CocSubmitRequest()
            );
        System.assertEquals(false, result.success);
        System.assert(
            result.errorCode == 'REASON_REQUIRED' || result.errorCode == 'LOAN_NOT_FOUND',
            result.errorCode
        );
    }

    @IsTest
    static void submitCocRequest_successForOwnedLoan() {
        Id investorRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
              AND DeveloperName = 'Business_Account'
            LIMIT 1
        ].Id;
        Account lenderAccount = new Account(
            Name = 'Facade COC Lender',
            Type = 'Investor',
            RecordTypeId = investorRecordTypeId
        );
        insert lenderAccount;

        User testUser = ExternalLoPortalTestHelper.createStandardUser('cocfx');
        ExternalLoPortalTestHelper.grantPortalAccess(testUser.Id);

        Transaction__c loanRecord = new Transaction__c(
            Name = 'Facade COC Loan',
            Loan_Officer__c = testUser.Id,
            Status__c = 'Processing',
            Loan_Amount__c = 300000,
            Lender_1st__c = 'UWM',
            Lender_lookup__c = lenderAccount.Id,
            Closing_Date__c = Date.today().addDays(30)
        );
        insert loanRecord;

        ExternalLoPortalCocFacade.CocSubmitRequest request = new ExternalLoPortalCocFacade.CocSubmitRequest();
        request.reason = 'Other';
        request.notes = 'Facade submit path';
        request.newBaseLoanAmount = 310000;
        request.newRate = 6.25;

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoPortalCocFacade.CocContext context = ExternalLoPortalCocFacade.getCocContext(String.valueOf(loanRecord.Id));
            ExternalLoPortalCocFacade.CocSubmitResult result =
                ExternalLoPortalCocFacade.submitCocRequest(String.valueOf(loanRecord.Id), request);
            Test.stopTest();
            System.assertEquals(true, result.success, result.userMessage);
            System.assertEquals('Facade COC Loan', context.loanName);
            System.assert(!context.reasons.isEmpty(), 'Reason picklist values');
            System.assert(!context.lockPeriods.isEmpty(), 'Lock period picklist values');
        }
    }

    @IsTest
    static void getCocContext_refusesSomeoneElsesLoan() {
        Transaction__c loanRecord = new Transaction__c(Name = 'Not Mine', Loan_Officer__c = UserInfo.getUserId());
        insert loanRecord;
        User other = ExternalLoPortalTestHelper.createStandardUser('cocno');
        System.runAs(other) {
            try {
                ExternalLoPortalCocFacade.getCocContext(String.valueOf(loanRecord.Id));
                System.assert(false, 'expected an error');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }
}