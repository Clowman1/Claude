/**
 * LO Workspace / Partner Workspace COC submit. Mirrors the back-office COC_Request screen flow
 * (Transaction branch) so a workspace COC runs the same downstream process: COC owned by the COC
 * desk, notes in the flow's "- note" format, and a linked "COC Request" Case, which is what fires
 * the COC Request Case notification flows. The flow runs SystemModeWithoutSharing, so this inserts
 * without FLS stripping too (outside LOs have no FLS on the COC fields); the facade has already
 * checked the loan is the caller's.
 */
public with sharing class ExternalLoPortalCocService {
    // Same owner the COC_Request flow hardcodes on both the COC and its Case.
    @TestVisible
    private static final Id COC_DESK_OWNER_ID = '005f2000009OtLnAAK';

    public class SubmitRequest {
        public Id loanId;
        public String reason;
        public String notes;
        public Decimal newBaseLoanAmount;
        public Decimal newAppraisedValue;
        public Decimal newRate;
        public String newProgram;
        public Decimal amount;
        public String lockPeriod;
        public Decimal daysExtended;
        public Date newLockExpiration;
        public Decimal newFico;
        public Decimal newTerm;
        public String reasonForRestructure;
        public String newInvestor;
        public String otherReason;
    }

    public class SubmitResult {
        public Id cocId;
        public Id caseId;
    }

    public static SubmitResult submitChangeRequest(SubmitRequest request) {
        if (request == null || request.loanId == null) {
            throw new DomainException('Loan is required.');
        }
        if (String.isBlank(request.reason)) {
            throw new DomainException('Select a reason for the change of circumstance.');
        }
        // The values the COC_Request flow marks required for these reasons.
        Set<String> reasons = new Set<String>(request.reason.split(';'));
        if (reasons.contains('Loan Amount') && request.newBaseLoanAmount == null) {
            throw new DomainException('Enter the new loan amount.');
        }
        if (reasons.contains('Appraisal/LTV') && request.newAppraisedValue == null) {
            throw new DomainException('Enter the new appraised value.');
        }
        if ((reasons.contains('Rate Change') || reasons.contains('Float Down') || reasons.contains('Float to Lock'))
            && request.newRate == null) {
            throw new DomainException('Enter the new rate.');
        }
        Transaction__c loan = [SELECT Id, Name FROM Transaction__c WHERE Id = :request.loanId WITH SYSTEM_MODE];

        Change_of_Circumstance__c cocRecord = new Change_of_Circumstance__c(
            Transaction__c = loan.Id,
            OwnerId = COC_DESK_OWNER_ID,
            Reason_for_Change__c = request.reason,
            // The flow's UpdatedNotesCombined on a new COC; Salesforce drops its leading newline on save.
            Notes__c = String.isBlank(request.notes) ? null : '\n- ' + request.notes,
            New_Base_Loan_Amount__c = request.newBaseLoanAmount,
            New_Appraised_Value__c = request.newAppraisedValue,
            New_Rate__c = request.newRate,
            New_Program__c = request.newProgram,
            Amount__c = request.amount,
            Lock_Period__c = request.lockPeriod,
            Amount_of_Days_Extended__c = request.daysExtended,
            New_Lock_Expiration_Date__c = request.newLockExpiration,
            New_FICO__c = request.newFico,
            New_Term__c = request.newTerm,
            Reason_for_Restructure__c = request.reasonForRestructure,
            New_Investor__c = request.newInvestor,
            Other_Reason_for_COC__c = request.otherReason
        );
        insert as system cocRecord;

        Case cocCase = new Case(
            Change_of_Circumstance__c = cocRecord.Id,
            Origin = 'Internal',
            OwnerId = COC_DESK_OWNER_ID,
            Priority = 'Medium',
            Status = 'New',
            Subject = 'Change of Circumstances for ' + loan.Name,
            Transaction__c = loan.Id,
            Type = 'COC Request'
        );
        insert as system cocCase;

        SubmitResult result = new SubmitResult();
        result.cocId = cocRecord.Id;
        result.caseId = cocCase.Id;
        return result;
    }
}