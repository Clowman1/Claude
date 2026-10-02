public with sharing class ExternalLoPortalCocService {
    public class SubmitRequest {
        public Id loanId;
        public String reason;
        public String notes;
        public Decimal newBaseLoanAmount;
        public Decimal newAppraisedValue;
        public Decimal newRate;
        public String newProgram;
    }

    public class SubmitResult {
        public Id cocId;
    }

    public static SubmitResult submitChangeRequest(SubmitRequest request) {
        if (request == null || request.loanId == null) {
            throw new DomainException('Loan is required.');
        }
        if (String.isBlank(request.reason)) {
            throw new DomainException('Select a reason for the change of circumstance.');
        }

        Change_of_Circumstance__c cocRecord = new Change_of_Circumstance__c();
        cocRecord.Transaction__c = request.loanId;
        cocRecord.Reason_for_Change__c = request.reason;
        cocRecord.Notes__c = request.notes;
        cocRecord.New_Base_Loan_Amount__c = request.newBaseLoanAmount;
        cocRecord.New_Appraised_Value__c = request.newAppraisedValue;
        cocRecord.New_Rate__c = request.newRate;
        cocRecord.New_Program__c = request.newProgram;

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<Change_of_Circumstance__c>{ cocRecord }
        );
        insert decision.getRecords();

        SubmitResult result = new SubmitResult();
        result.cocId = ((Change_of_Circumstance__c) decision.getRecords()[0]).Id;
        return result;
    }
}