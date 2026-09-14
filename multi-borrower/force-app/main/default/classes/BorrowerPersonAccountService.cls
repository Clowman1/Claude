/**
 * Resolves a Borrower__c row to a Person Account, creating one only when needed.
 *
 * Called from two places, deliberately sharing one code path:
 *   1. First outbound email to a borrower, so there is a real PersonContactId to use as
 *      setTargetObjectId (Messaging only accepts Contact/Lead/User, never a custom object).
 *   2. Conversion, via the record-triggered flows on Transaction__c.
 *
 * The primary borrower is never a Borrower__c row: it stays the Lead, and
 * Transaction__c.Borrower_Name__c after conversion.
 */
public with sharing class BorrowerPersonAccountService {
    // Record visibility is enforced (with sharing), but field access is deliberately left in system
    // mode. This runs from record-triggered flows during conversion; enforcing FLS here would fail
    // conversions for any ops user not assigned Borrower_Management, and the error surfaces as a
    // misleading "No such column". The fields touched are name, email and phone only.
    @TestVisible
    private static final String PERSON_ACCOUNT_RECORD_TYPE = 'PersonAccount';

    public class Request {
        @InvocableVariable(label='Transaction Id' description='Transaction whose converted Lead carries the Borrower__c rows' required=true)
        public Id transactionId;

        public Request() {
        }

        public Request(Id transactionId) {
            this.transactionId = transactionId;
        }
    }

    /**
     * Carries a converted Lead's borrowers onto its Transaction and gives each one a Person Account.
     * Safe to call more than once for the same Transaction, and safe when two flows both fire:
     * rows already stamped with Transaction__c are skipped, and matching is find-or-create.
     */
    @InvocableMethod(
        label='Link Borrower Person Accounts'
        description='Stamps a converted Lead\'s additional borrowers onto the Transaction and links each to a Person Account.'
        category='Borrowers'
    )
    public static void linkForTransactions(List<Request> requests) {
        Set<Id> transactionIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.transactionId != null) {
                transactionIds.add(request.transactionId);
            }
        }
        if (transactionIds.isEmpty()) {
            return;
        }

        List<Borrower__c> rows = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Phone__c, Account__c, Transaction__c,
                   Lead__r.Converted_Transaction_ID__c
            FROM Borrower__c
            WHERE Removed__c = FALSE
              AND Transaction__c = NULL
              AND Lead__r.Converted_Transaction_ID__c IN :transactionIds
        ];
        if (rows.isEmpty()) {
            return;
        }

        for (Borrower__c row : rows) {
            row.Transaction__c = row.Lead__r.Converted_Transaction_ID__c;
        }
        resolveAccounts(rows);
        update rows;
    }

    /**
     * Rows for the borrowerPanel LWC. Deliberately Apex rather than getRelatedListRecords, which
     * resolves an actual related list and so depends on Borrower__c being on the page layout.
     */
    @AuraEnabled(cacheable=true)
    public static List<Borrower__c> getBorrowers(Id recordId) {
        List<Borrower__c> rows = new List<Borrower__c>();
        if (recordId == null) {
            return rows;
        }
        String parentType = String.valueOf(recordId.getSObjectType());

        if (parentType == 'Lead') {
            return [
                SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Phone__c, Account__c
                FROM Borrower__c
                WHERE Lead__c = :recordId AND Removed__c = FALSE
                ORDER BY CreatedDate
            ];
        }
        if (parentType == 'Transaction__c') {
            return [
                SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Phone__c, Account__c
                FROM Borrower__c
                WHERE Transaction__c = :recordId AND Removed__c = FALSE
                ORDER BY CreatedDate
            ];
        }
        return rows;
    }

    /** How many live conditions each borrower owns, so the panel can warn and removal can decide. */
    @AuraEnabled(cacheable=true)
    public static Map<Id, Integer> getConditionCounts(Id recordId) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (recordId == null) {
            return counts;
        }
        String parentType = String.valueOf(recordId.getSObjectType());

        if (parentType == 'Lead') {
            for (AggregateResult row : [
                SELECT Borrower__c borrowerId, COUNT(Id) total
                FROM Lead_Document_Request__c
                WHERE Lead__c = :recordId AND Borrower__c != NULL
                GROUP BY Borrower__c
            ]) {
                counts.put((Id) row.get('borrowerId'), (Integer) row.get('total'));
            }
        } else if (parentType == 'Transaction__c') {
            for (AggregateResult row : [
                SELECT Borrower__c borrowerId, COUNT(Id) total
                FROM Condition__c
                WHERE Transaction__c = :recordId AND Borrower__c != NULL
                GROUP BY Borrower__c
            ]) {
                counts.put((Id) row.get('borrowerId'), (Integer) row.get('total'));
            }
        }
        return counts;
    }

    /**
     * Find-or-create the Person Account for each borrower. Returns borrower Id -> Account Id.
     * Used by the email path, where the Account must exist before the message is built.
     */
    public static Map<Id, Id> findOrCreate(Set<Id> borrowerIds) {
        Map<Id, Id> accountByBorrower = new Map<Id, Id>();
        if (borrowerIds == null || borrowerIds.isEmpty()) {
            return accountByBorrower;
        }

        List<Borrower__c> rows = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Phone__c, Account__c
            FROM Borrower__c
            WHERE Id IN :borrowerIds AND Removed__c = FALSE
        ];
        if (rows.isEmpty()) {
            return accountByBorrower;
        }

        resolveAccounts(rows);
        update rows;

        for (Borrower__c row : rows) {
            accountByBorrower.put(row.Id, row.Account__c);
        }
        return accountByBorrower;
    }

    /**
     * Sets Account__c and Name on each row in memory. No DML on Borrower__c: the caller saves,
     * so the Transaction stamp and the Account link go in one update.
     */
    private static void resolveAccounts(List<Borrower__c> rows) {
        List<Borrower__c> needAccount = new List<Borrower__c>();
        Set<String> emails = new Set<String>();

        for (Borrower__c row : rows) {
            row.Name = buildName(row);
            // Account.LastName is required, so a row without one cannot become a Person Account.
            if (row.Account__c != null || String.isBlank(row.Last_Name__c)) {
                continue;
            }
            needAccount.add(row);
            if (String.isNotBlank(row.Email__c)) {
                emails.add(row.Email__c.toLowerCase());
            }
        }
        if (needAccount.isEmpty()) {
            return;
        }

        // Matching is on email AND name, never email alone: spouses commonly share one address, and
        // matching on it by itself would collapse two borrowers onto a single Person Account.
        Map<String, Id> accountByKey = new Map<String, Id>();
        if (!emails.isEmpty()) {
            // Ascending, so the most recently modified match ends up in the map.
            for (Account existing : [
                SELECT Id, PersonEmail, FirstName, LastName
                FROM Account
                WHERE IsPersonAccount = TRUE AND PersonEmail != NULL AND PersonEmail IN :emails
                ORDER BY LastModifiedDate ASC
            ]) {
                accountByKey.put(matchKey(existing.PersonEmail, existing.FirstName, existing.LastName), existing.Id);
            }
        }

        Id personAccountRecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(PERSON_ACCOUNT_RECORD_TYPE)
            .getRecordTypeId();

        List<Account> toInsert = new List<Account>();
        List<Borrower__c> awaitingInsert = new List<Borrower__c>();

        for (Borrower__c row : needAccount) {
            // No email means no way to match safely, so a new Person Account is always created.
            String key = String.isBlank(row.Email__c)
                ? null
                : matchKey(row.Email__c, row.First_Name__c, row.Last_Name__c);
            if (key != null && accountByKey.containsKey(key)) {
                row.Account__c = accountByKey.get(key);
                continue;
            }
            toInsert.add(
                new Account(
                    RecordTypeId = personAccountRecordTypeId,
                    FirstName = row.First_Name__c,
                    LastName = row.Last_Name__c,
                    PersonEmail = row.Email__c,
                    PersonMobilePhone = row.Phone__c,
                    Is_Borrower__c = true
                )
            );
            awaitingInsert.add(row);
        }

        if (toInsert.isEmpty()) {
            return;
        }
        insert toInsert;
        for (Integer i = 0; i < awaitingInsert.size(); i++) {
            awaitingInsert[i].Account__c = toInsert[i].Id;
        }
    }

    /** Email plus name, lowercased and trimmed, so a shared household address cannot merge people. */
    private static String matchKey(String email, String firstName, String lastName) {
        return String.join(
            new List<String>{
                String.isBlank(email) ? '' : email.trim().toLowerCase(),
                String.isBlank(firstName) ? '' : firstName.trim().toLowerCase(),
                String.isBlank(lastName) ? '' : lastName.trim().toLowerCase()
            },
            '|'
        );
    }

    private static String buildName(Borrower__c row) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(row.First_Name__c)) {
            parts.add(row.First_Name__c.trim());
        }
        if (String.isNotBlank(row.Last_Name__c)) {
            parts.add(row.Last_Name__c.trim());
        }
        String built = String.join(parts, ' ');
        return String.isBlank(built) ? 'Borrower' : built.left(80);
    }
}
