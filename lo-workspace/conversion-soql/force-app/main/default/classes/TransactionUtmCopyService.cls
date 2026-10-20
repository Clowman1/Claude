public without sharing class TransactionUtmCopyService {
    private static Boolean isRunning = false;

    public static void copyFromConvertedLeads(List<Transaction__c> newRecords) {
        copyFromConvertedLeads(newRecords, null);
    }

    /**
     * Before insert: writes the converted Lead's values straight onto the new Transaction, so no follow-up update
     * (and no second run of the Transaction update automation, 7 SOQL each) is needed. While the Lead is not yet
     * linked to a Transaction - a conversion in progress - it also fills the subject property, webinar date and
     * Application Summary snapshot, which LeadConversionFieldCarry, ApplicationSummaryService and flow
     * Transaction_Stamp_Webinar_Date_From_Converted_Lead would otherwise each write in a separate update.
     * Blank fields only.
     */
    public static void fillOnInsert(List<Transaction__c> newRecords) {
        Map<Id, Lead> leadByAccountId = new Map<Id, Lead>();
        loadConvertedLeads(new Set<Id>(), accountIdsOf(newRecords), new Map<Id, Lead>(), leadByAccountId);
        for (Transaction__c transactionRecord : newRecords) {
            Lead sourceLead = sourceLeadFor(transactionRecord, new Map<Id, Lead>(), leadByAccountId);
            if (sourceLead == null) {
                continue;
            }
            copyBlankUtmFields(transactionRecord, transactionRecord, sourceLead);
            copyLeadLoanPartner(transactionRecord, transactionRecord, sourceLead, null);
            if (sourceLead.Converted_Transaction_ID__c == null) {
                copyConversionFields(transactionRecord, sourceLead);
            }
        }
    }

    public static void copyFromConvertedLeads(List<Transaction__c> newRecords, Map<Id, Transaction__c> oldMap) {
        if (isRunning || newRecords == null || newRecords.isEmpty()) {
            return;
        }
        // On update only a re-pointed borrower needs a fresh copy; fillOnInsert did the rest at insert.
        if (oldMap != null) {
            List<Transaction__c> repointed = new List<Transaction__c>();
            for (Transaction__c transactionRecord : newRecords) {
                Transaction__c oldRecord = oldMap.get(transactionRecord.Id);
                if (oldRecord == null
                    || oldRecord.Borrower_Name__c != transactionRecord.Borrower_Name__c
                    || oldRecord.Account__c != transactionRecord.Account__c) {
                    repointed.add(transactionRecord);
                }
            }
            if (repointed.isEmpty()) {
                return;
            }
            newRecords = repointed;
        }

        Set<Id> transactionIds = new Set<Id>();
        Set<Id> borrowerAccountIds = new Set<Id>();
        for (Transaction__c transactionRecord : newRecords) {
            transactionIds.add(transactionRecord.Id);
            if (transactionRecord.Borrower_Name__c != null) {
                borrowerAccountIds.add(transactionRecord.Borrower_Name__c);
            }
            if (transactionRecord.Account__c != null) {
                borrowerAccountIds.add(transactionRecord.Account__c);
            }
        }

        if (transactionIds.isEmpty() && borrowerAccountIds.isEmpty()) {
            return;
        }

        Map<Id, Lead> leadByTransactionId = new Map<Id, Lead>();
        Map<Id, Lead> leadByAccountId = new Map<Id, Lead>();
        loadConvertedLeads(transactionIds, borrowerAccountIds, leadByTransactionId, leadByAccountId);

        List<Transaction__c> updates = new List<Transaction__c>();
        for (Transaction__c transactionRecord : newRecords) {
            Lead sourceLead = sourceLeadFor(transactionRecord, leadByTransactionId, leadByAccountId);
            if (sourceLead == null) {
                continue;
            }

            Transaction__c updateRecord = new Transaction__c(Id = transactionRecord.Id);
            Boolean hasChanges = copyBlankUtmFields(updateRecord, transactionRecord, sourceLead);
            hasChanges = copyLeadLoanPartner(updateRecord, transactionRecord, sourceLead, oldMap) || hasChanges;
            if (hasChanges) {
                updates.add(updateRecord);
            }
        }

        if (!updates.isEmpty()) {
            isRunning = true;
            try {
                update updates;
            } finally {
                isRunning = false;
            }
        }
    }

    private static void loadConvertedLeads(
        Set<Id> transactionIds,
        Set<Id> borrowerAccountIds,
        Map<Id, Lead> leadByTransactionId,
        Map<Id, Lead> leadByAccountId
    ) {
        transactionIds.remove(null);
        if (transactionIds.isEmpty() && borrowerAccountIds.isEmpty()) {
            return;
        }
        for (Lead leadRecord : [
            SELECT Id, Converted_Transaction_ID__c, ConvertedAccountId, ConvertedDate,
                First_UTM_Campaign__c, First_UTM_Content__c, First_UTM_Medium__c,
                First_UTM_Source__c, First_UTM_Term__c, Last_UTM_Campaign__c,
                Last_UTM_Content__c, Last_UTM_Medium__c, Last_UTM_Source__c,
                Last_UTM_Term__c, Meta_Campaign_ID__c, Meta_Adset_ID__c,
                Meta_Ad_ID__c, Hyros_Ad_ID__c, FB_Click_ID__c, Source_URL__c,
                Form_Name__c, Landing_Page__c, Referrer__c, Loan_Partner__c,
                Subject_Property_Street__c, Subject_Property_City__c, Property_State__c,
                Subject_Property_Zip__c, Webinar_Date__c, App_Summary_Household__c,
                App_Summary_Borrower_1__c, App_Summary_Borrower_2__c, App_Summary_Income_B1__c,
                App_Summary_Income_B2__c, App_Summary_Property__c, App_Summary_Assets__c,
                App_Summary_Credit__c, App_Summary_Goals__c, App_Summary_Other_Points__c
            FROM Lead
            WHERE IsConverted = true
            AND (
                Converted_Transaction_ID__c IN :transactionIds
                OR ConvertedAccountId IN :borrowerAccountIds
            )
            ORDER BY ConvertedDate DESC, LastModifiedDate DESC
        ]) {
            if (
                leadRecord.Converted_Transaction_ID__c != null &&
                transactionIds.contains(leadRecord.Converted_Transaction_ID__c) &&
                !leadByTransactionId.containsKey(leadRecord.Converted_Transaction_ID__c)
            ) {
                leadByTransactionId.put(leadRecord.Converted_Transaction_ID__c, leadRecord);
            }
            if (
                leadRecord.ConvertedAccountId != null &&
                borrowerAccountIds.contains(leadRecord.ConvertedAccountId) &&
                !leadByAccountId.containsKey(leadRecord.ConvertedAccountId)
            ) {
                leadByAccountId.put(leadRecord.ConvertedAccountId, leadRecord);
            }
        }
    }

    private static Set<Id> accountIdsOf(List<Transaction__c> records) {
        Set<Id> accountIds = new Set<Id>();
        for (Transaction__c transactionRecord : records) {
            if (transactionRecord.Borrower_Name__c != null) {
                accountIds.add(transactionRecord.Borrower_Name__c);
            }
            if (transactionRecord.Account__c != null) {
                accountIds.add(transactionRecord.Account__c);
            }
        }
        return accountIds;
    }

    private static Lead sourceLeadFor(
        Transaction__c transactionRecord,
        Map<Id, Lead> leadByTransactionId,
        Map<Id, Lead> leadByAccountId
    ) {
        Lead sourceLead = transactionRecord.Id == null ? null : leadByTransactionId.get(transactionRecord.Id);
        if (sourceLead == null && transactionRecord.Borrower_Name__c != null) {
            sourceLead = leadByAccountId.get(transactionRecord.Borrower_Name__c);
        }
        if (sourceLead == null && transactionRecord.Account__c != null) {
            sourceLead = leadByAccountId.get(transactionRecord.Account__c);
        }
        return sourceLead;
    }

    @TestVisible
    private static void copyConversionFields(Transaction__c target, Lead source) {
        setValueIfBlank(target, source.Subject_Property_Street__c, 'Property_Address__c');
        setValueIfBlank(target, source.Subject_Property_City__c, 'Property_City__c');
        setValueIfBlank(target, source.Property_State__c, 'Property_State__c');
        setValueIfBlank(target, source.Subject_Property_Zip__c, 'Property_Postal_Code__c');
        setValueIfBlank(target, source.Webinar_Date__c, 'Webinar_Date__c');
        setValueIfBlank(target, ApplicationSummaryService.buildSnapshot(source), 'App_Summary_Snapshot__c');
    }

    private static void setValueIfBlank(SObject target, Object value, String fieldName) {
        if (value == null || target.get(fieldName) != null) {
            return;
        }
        if (value instanceof String && String.isBlank((String) value)) {
            return;
        }
        target.put(fieldName, value);
    }

    @TestVisible
    private static Boolean copyBlankUtmFields(Transaction__c target, Transaction__c existing, Lead source) {
        Boolean changed = false;
        changed = setIfBlank(target, existing, source, 'First_UTM_Campaign__c') || changed;
        changed = setIfBlank(target, existing, source, 'First_UTM_Content__c') || changed;
        changed = setIfBlank(target, existing, source, 'First_UTM_Medium__c') || changed;
        changed = setIfBlank(target, existing, source, 'First_UTM_Source__c') || changed;
        changed = setIfBlank(target, existing, source, 'First_UTM_Term__c') || changed;
        changed = setIfBlank(target, existing, source, 'Last_UTM_Campaign__c') || changed;
        changed = setIfBlank(target, existing, source, 'Last_UTM_Content__c') || changed;
        changed = setIfBlank(target, existing, source, 'Last_UTM_Medium__c') || changed;
        changed = setIfBlank(target, existing, source, 'Last_UTM_Source__c') || changed;
        changed = setIfBlank(target, existing, source, 'Last_UTM_Term__c') || changed;
        changed = setIfBlank(target, existing, source, 'Meta_Campaign_ID__c') || changed;
        changed = setIfBlank(target, existing, source, 'Meta_Adset_ID__c') || changed;
        changed = setIfBlank(target, existing, source, 'Meta_Ad_ID__c') || changed;
        changed = setIfBlank(target, existing, source, 'Hyros_Ad_ID__c') || changed;
        changed = setIfBlank(target, existing, source, 'FB_Click_ID__c') || changed;
        changed = setIfBlank(target, existing, source, 'Source_URL__c') || changed;
        changed = setIfBlank(target, existing, source, 'Form_Name__c') || changed;
        changed = setIfBlank(target, existing, source, 'Landing_Page__c') || changed;
        changed = setIfBlank(target, existing, source, 'Referrer__c') || changed;
        return changed;
    }

    @TestVisible
    private static Boolean copyLeadLoanPartner(
        Transaction__c target,
        Transaction__c existing,
        Lead source,
        Map<Id, Transaction__c> oldMap
    ) {
        if (source == null || source.Loan_Partner__c == null || existing == null) {
            return false;
        }

        Boolean isInsertContext = oldMap == null || !oldMap.containsKey(existing.Id);
        Boolean isBlankUpdate = !isInsertContext && existing.Loan_Partner__c == null;
        if (!isInsertContext && !isBlankUpdate) {
            return false;
        }

        if (existing.Loan_Partner__c == source.Loan_Partner__c) {
            return false;
        }

        target.Loan_Partner__c = source.Loan_Partner__c;
        return true;
    }

    private static Boolean setIfBlank(SObject target, SObject existing, SObject source, String fieldName) {
        Object sourceValue = source.get(fieldName);
        if (sourceValue == null || existing.get(fieldName) != null) {
            return false;
        }

        if (sourceValue instanceof String && String.isBlank((String) sourceValue)) {
            return false;
        }

        target.put(fieldName, sourceValue);
        return true;
    }
}