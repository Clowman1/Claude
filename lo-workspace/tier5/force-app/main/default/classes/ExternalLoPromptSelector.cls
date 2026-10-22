/**
 * Read-model queries for activity-plan prompts. Canonical Lead/Loan repos stay
 * free of prompt-only filters (under-contract RT, funded-date window).
 */
public with sharing class ExternalLoPromptSelector {
    /**
     * Consumer leads currently under contract.
     */
    public List<Lead> selectUnderContractLeadsByOwner(Id ownerId) {
        if (ownerId == null) {
            return new List<Lead>();
        }
        return [
            SELECT Id, Name, Phone, Email, Status, LeadSource, RecordType.DeveloperName
            FROM Lead
            WHERE OwnerId = :ownerId
              AND IsConverted = false
              AND RecordType.DeveloperName = 'Consumer_Under_Contract_Lead_Record_Type'
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 50
        ];
    }

    /**
     * Funded loans for anniversary and escrow-analysis prompts.
     */
    public List<Transaction__c> selectFundedLoansByOfficer(Id userId) {
        if (userId == null) {
            return new List<Transaction__c>();
        }
        Date earliest = Date.today().addMonths(-18);
        return [
            SELECT Id, Name, Funded_Date__c, Borrower_Name__c, Borrower_Name__r.Name, Status__c
            FROM Transaction__c
            WHERE (Loan_Officer__c = :userId OR OwnerId = :userId)
              AND Funded_Date__c != null
              AND Funded_Date__c >= :earliest
            WITH SYSTEM_MODE
            ORDER BY Funded_Date__c DESC
            LIMIT 200
        ];
    }
}