public with sharing class ExternalLoPortalCocFacade {
    public class CocReasonOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class CocSubmitRequest {
        // get/set required: Lightning Experience's Apex transport leaves plain fields null on inbound objects.
        @AuraEnabled public String reason { get; set; } // multi-select, ';' separated
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Decimal newBaseLoanAmount { get; set; }
        @AuraEnabled public Decimal newAppraisedValue { get; set; }
        @AuraEnabled public Decimal newRate { get; set; }
        @AuraEnabled public String newProgram { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String lockPeriod { get; set; }
        @AuraEnabled public Decimal daysExtended { get; set; }
        @AuraEnabled public Date newLockExpiration { get; set; }
        @AuraEnabled public Decimal newFico { get; set; }
        @AuraEnabled public Decimal newTerm { get; set; }
        @AuraEnabled public String reasonForRestructure { get; set; }
        @AuraEnabled public String newInvestor { get; set; }
        @AuraEnabled public String otherReason { get; set; }
    }

    public class CocSubmitResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String userMessage;
        @AuraEnabled public String cocKey;
        @AuraEnabled public String errorCode;
    }

    /** Everything the COC wizard shows: who is asking, the loan's current values, and the picklists. */
    public class CocContext {
        @AuraEnabled public String firstName;
        @AuraEnabled public String borrower;
        @AuraEnabled public String loanName;
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public Decimal appraisedValue;
        @AuraEnabled public Decimal purchasePrice;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Decimal term;
        @AuraEnabled public Decimal fico;
        @AuraEnabled public String program;
        @AuraEnabled public String lender;
        @AuraEnabled public Date lockExpiration;
        @AuraEnabled public List<CocReasonOption> reasons;
        @AuraEnabled public List<CocReasonOption> lockPeriods;
        @AuraEnabled public List<CocReasonOption> investors;
    }

    // Not @AuraEnabled: no Aura/LWC/VF in the org calls it (checked 2026-10-20); getCocContext carries the reasons.
    public static List<CocReasonOption> getReasonOptions() {
        return options(Change_of_Circumstance__c.Reason_for_Change__c.getDescribe());
    }

    @AuraEnabled(cacheable=true)
    public static CocContext getCocContext(String contextLoanKey) {
        Id me = UserInfo.getUserId();
        Id loanId = parseContextKey(contextLoanKey);
        // System mode: outside LOs lack FLS on several of these; the WHERE keeps it to the caller's own loans.
        List<Transaction__c> loans = [
            SELECT Name, Borrower_Name__r.Name, Loan_Amount_1st__c, Appraised_Value__c, Purchase_Price__c,
                   Rate_1st_TD__c, Term_1st__c, FICO__c, Loan_Program_1st__c, Lender_1st__c, Rate_Lock_Exp_Date__c
            FROM Transaction__c
            WHERE Id = :loanId AND (Loan_Officer__c = :me OR OwnerId = :me)
            WITH SYSTEM_MODE
        ];
        if (loans.isEmpty()) {
            throw new AuraHandledException('Loan could not be found or is not visible.');
        }
        Transaction__c t = loans[0];
        CocContext c = new CocContext();
        c.firstName = UserInfo.getFirstName();
        c.borrower = t.Borrower_Name__r?.Name;
        c.loanName = t.Name;
        c.loanAmount = t.Loan_Amount_1st__c;
        c.appraisedValue = t.Appraised_Value__c;
        c.purchasePrice = t.Purchase_Price__c;
        c.rate = t.Rate_1st_TD__c;
        c.term = t.Term_1st__c;
        c.fico = t.FICO__c;
        c.program = t.Loan_Program_1st__c;
        c.lender = t.Lender_1st__c;
        c.lockExpiration = t.Rate_Lock_Exp_Date__c;
        c.reasons = getReasonOptions();
        c.lockPeriods = options(Change_of_Circumstance__c.Lock_Period__c.getDescribe());
        c.investors = options(Change_of_Circumstance__c.New_Investor__c.getDescribe());
        return c;
    }

    private static List<CocReasonOption> options(Schema.DescribeFieldResult describeResult) {
        List<CocReasonOption> options = new List<CocReasonOption>();
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

        // COC and its Case save together: a failure after the COC insert must not leave a COC with no Case.
        Savepoint sp = Database.setSavepoint();
        try {
            ExternalLoPortalCocService.SubmitRequest serviceRequest = new ExternalLoPortalCocService.SubmitRequest();
            serviceRequest.loanId = loanRecord.Id;
            serviceRequest.reason = request.reason;
            serviceRequest.notes = request.notes;
            serviceRequest.newBaseLoanAmount = request.newBaseLoanAmount;
            serviceRequest.newAppraisedValue = request.newAppraisedValue;
            serviceRequest.newRate = request.newRate;
            serviceRequest.newProgram = request.newProgram;
            serviceRequest.amount = request.amount;
            serviceRequest.lockPeriod = request.lockPeriod;
            serviceRequest.daysExtended = request.daysExtended;
            serviceRequest.newLockExpiration = request.newLockExpiration;
            serviceRequest.newFico = request.newFico;
            serviceRequest.newTerm = request.newTerm;
            serviceRequest.reasonForRestructure = request.reasonForRestructure;
            serviceRequest.newInvestor = request.newInvestor;
            serviceRequest.otherReason = request.otherReason;
            ExternalLoPortalCocService.SubmitResult serviceResult =
                ExternalLoPortalCocService.submitChangeRequest(serviceRequest);
            result.success = true;
            result.cocKey = String.valueOf(serviceResult.cocId);
            result.userMessage = 'Change of circumstance request submitted.';
        } catch (DomainException domainError) {
            Database.rollback(sp);
            result.errorCode = 'VALIDATION';
            result.userMessage = domainError.getMessage();
        } catch (Exception error) {
            Database.rollback(sp);
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