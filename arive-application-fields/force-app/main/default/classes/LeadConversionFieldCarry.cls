/**
 * Copies the TRID application pieces off a converted Lead the moment Converted_Transaction_ID__c is stamped
 * (both Convert_Lead and the TRID-date flow stamp it after the Transaction exists).
 *
 * Person Account: SSN, birthdate, loan amount, income, property value - overwritten whenever the Lead has a value,
 * since the Lead is the newest application. Lead convert field mapping can't do this: it cannot target the standard
 * PersonBirthdate, and cannot map an encrypted field to a plain-text one.
 * Transaction: subject property address - only into blank fields, so nothing typed on the file is overwritten.
 */
public without sharing class LeadConversionFieldCarry {
    public static void carry(Set<Id> leadIds) {
        List<SObject> updates = new List<SObject>();
        for (Lead l : [
            SELECT ConvertedAccountId, ConvertedAccount.IsPersonAccount,
                SSN__c, Birthdate__c, Loan_Amount__c, Household_Income__c, Value_of_Property__c,
                Subject_Property_Street__c, Subject_Property_City__c, Property_State__c, Subject_Property_Zip__c,
                Converted_Transaction_ID__c,
                Converted_Transaction_ID__r.Property_Address__c, Converted_Transaction_ID__r.Property_City__c,
                Converted_Transaction_ID__r.Property_State__c, Converted_Transaction_ID__r.Property_Postal_Code__c
            FROM Lead
            WHERE Id IN :leadIds AND Converted_Transaction_ID__c != null
        ]) {
            if (l.ConvertedAccountId != null && l.ConvertedAccount.IsPersonAccount) {
                Account acc = new Account(Id = l.ConvertedAccountId);
                Boolean changed = false;
                changed |= put(acc, 'SSN__pc', l.SSN__c);
                changed |= put(acc, 'PersonBirthdate', l.Birthdate__c);
                changed |= put(acc, 'Loan_Amount__pc', l.Loan_Amount__c);
                changed |= put(acc, 'Household_Income__pc', l.Household_Income__c);
                changed |= put(acc, 'Value_of_Property__pc', l.Value_of_Property__c);
                if (changed) {
                    updates.add(acc);
                }
            }

            Transaction__c existing = l.Converted_Transaction_ID__r;
            Transaction__c txn = new Transaction__c(Id = l.Converted_Transaction_ID__c);
            Boolean txnChanged = false;
            txnChanged |= String.isBlank(existing.Property_Address__c) && put(txn, 'Property_Address__c', l.Subject_Property_Street__c);
            txnChanged |= String.isBlank(existing.Property_City__c) && put(txn, 'Property_City__c', l.Subject_Property_City__c);
            txnChanged |= String.isBlank(existing.Property_State__c) && put(txn, 'Property_State__c', l.Property_State__c);
            txnChanged |= String.isBlank(existing.Property_Postal_Code__c) && put(txn, 'Property_Postal_Code__c', l.Subject_Property_Zip__c);
            if (txnChanged) {
                updates.add(txn);
            }
        }
        if (!updates.isEmpty()) {
            updates.sort(); // groups by type so one DML call never splits into more than two chunks
            update updates;
        }
    }

    private static Boolean put(SObject record, String field, Object value) {
        if (value == null || (value instanceof String && String.isBlank((String) value))) {
            return false;
        }
        record.put(field, value);
        return true;
    }
}
