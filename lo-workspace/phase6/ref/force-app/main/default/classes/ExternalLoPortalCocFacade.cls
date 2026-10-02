public with sharing class ExternalLoPortalCocFacade {
    public class CocReasonOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class CocSubmitRequest {
        @AuraEnabled public String reason;
        @AuraEnabled public String notes;
        @AuraEnabled public Decimal newBaseLoanAmount;
        @AuraEnabled public Decimal newAppraisedValue;
        @AuraEnabled public Decimal newRate;
        @AuraEnabled public String newProgram;
    }

    public class CocSubmitResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String userMessage;
        @AuraEnabled public String cocKey;
        @AuraEnabled public String errorCode;
    }

    @AuraEnabled(cacheable=true)
    public static List<CocReasonOption> getReasonOptions() {
        List<CocReasonOption> options = new List<CocReasonOption>();
        Schema.DescribeFieldResult describeResult =
            Change_of_Circumstance__c.Reason_for_Change__c.getDescribe();
        for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            CocReasonOption option = new CocReasonOption();
            option.value = entry.getValue();
            option.label = entry.getLabel();
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static CocSubmitResult submitCocRequest(String contextLoanKey, CocSubmitRequest request) {
        CocSubmitResult result = new CocSubmitResult();
        result.success = false;

        Id loanId = parseContextKey(contextLoanKey);
        Transaction__c loanRecord = LoanRepository.getInstance().selectPortalLoanDetail(
            loanId,
            UserInfo.getUserId()
        );
        if (loanRecord == null) {
            result.errorCode = 'LOAN_NOT_FOUND';
            result.userMessage = 'Loan could not be found or is not visible.';
            return result;
        }
        if (request == null || String.isBlank(request.reason)) {
            result.errorCode = 'REASON_REQUIRED';
            result.userMessage = 'Select a reason for the change of circumstance.';
            return result;
        }

        try {
            ExternalLoPortalCocService.SubmitRequest serviceRequest = new ExternalLoPortalCocService.SubmitRequest();
            serviceRequest.loanId = loanRecord.Id;
            serviceRequest.reason = request.reason;
            serviceRequest.notes = request.notes;
            serviceRequest.newBaseLoanAmount = request.newBaseLoanAmount;
            serviceRequest.newAppraisedValue = request.newAppraisedValue;
            serviceRequest.newRate = request.newRate;
            serviceRequest.newProgram = request.newProgram;
            ExternalLoPortalCocService.SubmitResult serviceResult =
                ExternalLoPortalCocService.submitChangeRequest(serviceRequest);
            result.success = true;
            result.cocKey = String.valueOf(serviceResult.cocId);
            result.userMessage = 'Change of circumstance request submitted.';
        } catch (DomainException domainError) {
            result.errorCode = 'VALIDATION';
            result.userMessage = domainError.getMessage();
        } catch (Exception error) {
            result.errorCode = 'SUBMIT_FAILED';
            result.userMessage = error.getMessage();
        }
        return result;
    }

    private static Id parseContextKey(String contextKey) {
        if (String.isBlank(contextKey)) {
            return null;
        }
        return (Id) contextKey;
    }
}