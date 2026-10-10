/**
 * Created by zeyad on 7/13/2020.
 */


public with sharing class LoanRepository {
    private static List<String> LOAN_FIELDS;
    private static LoanRepository self;
    static{
        List<String> fields = new List<String>();
        Set<String> ownerFields = new Set<String>();
        Set<String> excludedUserFields = new Set<String>{
                'profilephotoid','bannerphotoid', 'userpreferencessendviainternalemailservice', 'companyname', 'division',
                'department', 'street', 'city', 'state', 'postalcode', 'country', 'latitude', 'longitude', 'geocodeaccuracy',
                'address', 'emailpreferencesautobcc', 'emailpreferencesautobccstayintouch', 'emailpreferencesstayintouchreminder',
                'senderemail' , 'sendername', 'sign', 'signature', 'stayintouchsubject', 'stayintouchsignature', 'stayintouchnote',
                'fax', 'mobilephone', 'communitynickname', 'badgetext', 'timezonesidkey'

        };
        Set<String> relatedAccountFields = new Set<String>();
        List<String> relatedPartnerFields = new List<String>();
        List<String> relatedContactAccount = new List<String>();
        Map<String, SObjectField> transactionFieldMap = Schema.getGlobalDescribe().get('Transaction__c').getDescribe().fields.getMap();
        Map<String, SObjectField> accountFieldMap = Schema.getGlobalDescribe().get('Account').getDescribe().fields.getMap();
        Map<String, SObjectField> userFieldMap = Schema.getGlobalDescribe().get('User').getDescribe().fields.getMap();
        for(String fieldName : transactionFieldMap.keySet())
        {
            fields.add(fieldName);
        }
        for(String fieldName : accountFieldMap.keySet()){
            relatedAccountFields.add('Borrower_Name__r.' + fieldName);
        }
        for(String fieldName : userFieldMap.keySet()){
            if(!excludedUserFields.contains(fieldName)){
//                ownerFields.add('Owner.'+fieldName);
            }
        }
        fields.addAll(ownerFields);
        fields.addAll(relatedAccountFields);

        LOAN_FIELDS = fields;
    }
    public static LoanRepository getInstance(){
        if(self==null){
            self = new LoanRepository();
        }
        return self;
    }
    
    public Map<Id, Loan> getLoanMapByIds(Set<Id> loanIds){
        String query = 'SELECT ' + String.join(LOAN_FIELDS, ',')
                + ' FROM Transaction__c where Id IN: loanIds';
        Map<Id, Loan> loans = new Map<Id, Loan>();
        for(Transaction__c deal :  (List<Transaction__c>)Database.query(query)){
            loans.put(deal.Id, new Loan(deal));
        }
        return loans;
    }

    public Loan getLoanById(String loanId){
        String query = 'SELECT ' + String.join(LOAN_FIELDS, ',') + ',Owner.Email'
                + ' FROM Transaction__c WHERE Id=:loanId';
        Transaction__c deal = (Transaction__c)Database.query(query);
        system.debug(new Loan(deal));
        return new Loan(deal);
    }

    public Loan getLoanForBorrowerPortalById(Id loanId) {
        if (loanId == null) {
            return null;
        }

        String query = buildBorrowerPortalQuery()
            + ' WHERE Id = :loanId LIMIT 1';
        List<Transaction__c> deals = Database.query(query);
        return deals.isEmpty() ? null : new Loan(deals[0]);
    }

    public Loan getFirstLoanWithPortalHash() {
        String query = buildBorrowerPortalQuery()
            + ' WHERE Portal_Hash_Parameter__c != NULL LIMIT 1';
        List<Transaction__c> deals = Database.query(query);
        return deals.isEmpty() ? null : new Loan(deals[0]);
    }

    public List<Transaction__c> selectTransactionsByIds(Set<Id> transactionIds) {
        if (transactionIds == null || transactionIds.isEmpty()) {
            return new List<Transaction__c>();
        }

        return [
            SELECT Id, Portal_Hash_Parameter__c
            FROM Transaction__c
            WHERE Id IN :transactionIds
        ];
    }

    public Database.QueryLocator getBorrowerPortalHashRefreshScope() {
        return Database.getQueryLocator([
            SELECT Id
            FROM Transaction__c
            WHERE Portal_Hash_Parameter__c != NULL
        ]);
    }
    
    public Loan getLoanByFedexTrackingNumber(String fedexNumber){
        String query = 'SELECT ' + String.join(LOAN_FIELDS, ',') + ',Owner.Email'
                + ' FROM Transaction__c WHERE FedexTrackingNumber__c=:fedexNumber';
        Transaction__c deal = (Transaction__c)Database.query(query);
        system.debug(new Loan(deal));
        return new Loan(deal);
    }

    private String buildBorrowerPortalQuery() {
        return 'SELECT ' + String.join(LOAN_FIELDS, ',') + ' FROM Transaction__c';
    }

    /**
     * Active loans assigned to the user that are Waiting On Loan Officer.
     */
    public List<Transaction__c> selectLoansNeedingMilestoneUpdates(Id userId) {
        if (userId == null) {
            return new List<Transaction__c>();
        }

        return [
            SELECT Id, Name, Status__c, Current_Status_Since__c, Closing_Date__c, Borrower_Name__c
            FROM Transaction__c
            WHERE (Loan_Officer__c = :userId OR OwnerId = :userId)
              AND Status__c IN :ExternalLOBaselineHelper.ACTIVE_LOAN_STATUSES
              AND Status__c = 'Waiting On Loan Officer'
            WITH USER_MODE
            ORDER BY Current_Status_Since__c ASC NULLS FIRST, LastModifiedDate ASC
            LIMIT 500
        ];
    }

    public List<Transaction__c> selectPortalLoansByUser(Id userId) {
        return selectPortalLoansByUser(userId, ExternalLOBaselineHelper.ACTIVE_LOAN_STATUSES, false);
    }

    /** My Loans tabs: active loans soonest closing first; closed / cancelled most recent first. */
    public List<Transaction__c> selectPortalLoansByUser(Id userId, List<String> statuses, Boolean newestFirst) {
        if (userId == null) {
            return new List<Transaction__c>();
        }
        if (newestFirst == true) {
            return [
                SELECT Id, Name, Status__c, Current_Status_Since__c, Closing_Date__c,
                       Borrower_Name__c, Borrower_Name__r.Name, Loan_Amount__c, Loan_Amount_1st__c, Loan_Program_1st__c, Clear_to_Close_Date__c,
                       Loan_Officer__c, Processor__c, Processor__r.Name
                FROM Transaction__c
                WHERE (Loan_Officer__c = :userId OR OwnerId = :userId)
                  AND Status__c IN :statuses
                WITH USER_MODE
                ORDER BY Closing_Date__c DESC NULLS LAST, LastModifiedDate DESC
                LIMIT 500
            ];
        }
        return [
            SELECT Id, Name, Status__c, Current_Status_Since__c, Closing_Date__c,
                   Borrower_Name__c, Borrower_Name__r.Name, Loan_Amount__c, Loan_Amount_1st__c, Loan_Program_1st__c, Clear_to_Close_Date__c,
                   Loan_Officer__c, Processor__c, Processor__r.Name
            FROM Transaction__c
            WHERE (Loan_Officer__c = :userId OR OwnerId = :userId)
              AND Status__c IN :statuses
            WITH USER_MODE
            ORDER BY Closing_Date__c ASC NULLS LAST, LastModifiedDate DESC
            LIMIT 500
        ];
    }

    public Integer countPortalLoansByUser(Id userId, List<String> statuses) {
        if (userId == null) {
            return 0;
        }
        return [
            SELECT COUNT() FROM Transaction__c
            WHERE (Loan_Officer__c = :userId OR OwnerId = :userId)
              AND Status__c IN :statuses
            WITH USER_MODE
        ];
    }

    public List<Condition__c> selectPortalConditionSnapshotByLoanId(Id loanId) {
        if (loanId == null) {
            return new List<Condition__c>();
        }
        List<Condition__c> visible = new List<Condition__c>();
        for (Condition__c c : [
            SELECT Id, Name, Status__c, Type__c, Description__c, Category__c
            FROM Condition__c
            WHERE Transaction__c = :loanId
            WITH USER_MODE
            ORDER BY Status__c ASC, Name ASC
            LIMIT 500
        ]) {
            if (!isClosingCondition(c.Category__c) && visible.size() < 200) {
                visible.add(c);
            }
        }
        return visible;
    }

    // Closing / title-company (TC) / post-close conditions are not the LO's to chase (decided 2026-10-08).
    @TestVisible
    private static Boolean isClosingCondition(String category) {
        if (String.isBlank(category)) {
            return false;
        }
        String c = category.toLowerCase();
        // 'TC' is matched as a leading word: prod has 'TC' and 'TC Evidence Signor is authorized'.
        return c.contains('closing') || c.contains('post clos') || c.contains('final docs')
            || c == 'tc' || c.startsWith('tc ');
    }

    public Transaction__c selectPortalLoanDetail(Id loanId, Id userId) {
        if (loanId == null || userId == null) {
            return null;
        }
        List<Transaction__c> loans = [
            SELECT Id, Name, Status__c, Current_Status_Since__c, Closing_Date__c,
                   Borrower_Name__c, Borrower_Name__r.Name, Loan_Amount__c, Loan_Amount_1st__c, Loan_Program_1st__c, Clear_to_Close_Date__c,
                   Loan_Officer__c, Processor__c, Processor__r.Name, Purchase_Price__c,
                   Interest_Rate__c, Rate_1st_TD__c, LTV__c, DTI_Back_End__c, Property_Address__c, Property_Unit__c, Property_City__c, Property_State__c, Property_Postal_Code__c, Lock_Exp_Date_1st_TD__c, Rate_Lock_Exp_Date__c
            FROM Transaction__c
            WHERE Id = :loanId
              AND (Loan_Officer__c = :userId OR OwnerId = :userId)
            WITH USER_MODE
            LIMIT 1
        ];
        return loans.isEmpty() ? null : loans[0];
    }
}