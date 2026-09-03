/**
 * Backs the "Reach Mobile - LO" phone app.
 *
 * Transactions: Loan_Officer__c is the assigned LO on Transaction__c -- OwnerId is NOT
 * (35 of 47 live files are owned by an ops user, not the LO). Standard list views can only
 * scope "mine" to OwnerId, so they cannot express this filter.
 *
 * Leads: OwnerId *is* the LO, so a list view could work -- but list views must be shared to
 * be visible, which would surface them on the desktop Leads tab, and ListView metadata has
 * no sort element. Querying here keeps the desktop untouched and the sort deterministic.
 */
public with sharing class LOMobileTransactionsController {

    private static final Set<String> CLOSED_STATUSES   = new Set<String>{'PC Review', 'Post-Closed'};
    private static final Set<String> INACTIVE_STATUSES = new Set<String>{'Cancelled', 'PC Review', 'Post-Closed', 'Lost'};

    // The 18 lead statuses that count as active. Deliberately an inclusion list: 739 leads sit
    // on orphaned status values ('Contact_Attempt_6', 'Nurture-Pre-Approval', 'Contact Attempt 7/8')
    // that are no longer active picklist entries and must not appear.
    private static final Set<String> ACTIVE_LEAD_STATUSES = new Set<String>{
        'New', 'Contacted/Call Back',
        'Contact Attempt 1', 'Contact Attempt 2', 'Contact Attempt 3',
        'Contact Attempt 4', 'Contact Attempt 5', 'Contact Attempt 6',
        'Working', 'Application Link Out', 'Application',
        'Documents Requested', 'Documents Received for Review',
        'Scheduling Meeting', 'Call - Referral Pending',
        'Meeting Set', 'Meeting Complete', 'Active'
    };

    private static final String CONSUMER_RT = 'Consumer_Lead_record_type';

    @AuraEnabled(cacheable=true)
    public static List<Transaction__c> getTransactions(String mode) {
        Id me = UserInfo.getUserId();

        if (mode == 'closed') {
            // Current calendar year only -- older closings are a desktop/report job.
            return [
                SELECT Id, Name, Status__c, Closing_Date__c, Loan_Amount__c,
                       Property_Address__c, Borrower_Name__r.Name
                FROM Transaction__c
                WHERE Loan_Officer__c = :me
                  AND Status__c IN :CLOSED_STATUSES
                  AND Closing_Date__c = THIS_YEAR
                ORDER BY Closing_Date__c DESC
                LIMIT 200
            ];
        }

        return [
            SELECT Id, Name, Status__c, Closing_Date__c, Loan_Amount__c,
                   Property_Address__c, Borrower_Name__r.Name
            FROM Transaction__c
            WHERE Loan_Officer__c = :me
              AND Status__c NOT IN :INACTIVE_STATUSES
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Lead> getLeads(String mode) {
        Id me = UserInfo.getUserId();

        if (mode == 'preapproved') {
            return [
                SELECT Id, Name, Status, Phone, Email, LastActivityDate, LastModifiedDate
                FROM Lead
                WHERE OwnerId = :me
                  AND IsConverted = false
                  AND RecordType.DeveloperName = :CONSUMER_RT
                  AND Status = 'Pre-Approval'
                ORDER BY LastModifiedDate DESC
                LIMIT 200
            ];
        }

        return [
            SELECT Id, Name, Status, Phone, Email, LastActivityDate, LastModifiedDate
            FROM Lead
            WHERE OwnerId = :me
              AND IsConverted = false
              AND RecordType.DeveloperName = :CONSUMER_RT
              AND Status IN :ACTIVE_LEAD_STATUSES
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ];
    }
}
