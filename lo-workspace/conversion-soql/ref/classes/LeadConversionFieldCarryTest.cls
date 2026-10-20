@IsTest
private class LeadConversionFieldCarryTest {
    @IsTest
    static void stampingConvertedLeadCarriesFieldsToPersonAccountAndTransaction() {
        Lead leadRecord = new Lead(
            FirstName = 'Carry',
            LastName = 'Fields',
            Email = 'carry.fields@example.com',
            SSN__c = '123-45-6789',
            Birthdate__c = Date.newInstance(1985, 4, 12),
            Loan_Amount__c = 350000,
            Household_Income__c = 120000,
            Value_of_Property__c = 425000,
            Subject_Property_Street__c = '9 Gulf Shore Blvd',
            Subject_Property_City__c = 'Naples',
            Property_State__c = 'FL',
            Subject_Property_Zip__c = '34102'
        );
        insert leadRecord;
        Transaction__c transactionRecord = new Transaction__c(
            Name = 'Carry Fields',
            Status__c = TestDataFactory.getOpportunityStageName(),
            Loan_Number__c = 'CARRY-1',
            Property_City__c = 'Typed On File'
        );
        insert transactionRecord;

        Database.LeadConvert request = new Database.LeadConvert();
        request.setLeadId(leadRecord.Id);
        request.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1].MasterLabel);
        request.setDoNotCreateOpportunity(true);
        Id accountId = Database.convertLead(request, true).getAccountId();

        Test.startTest();
        update new Lead(Id = leadRecord.Id, Converted_Transaction_ID__c = transactionRecord.Id);
        Test.stopTest();

        Account acc = (Account) Database.query(
            'SELECT IsPersonAccount, SSN__pc, PersonBirthdate, Loan_Amount__pc, Household_Income__pc, Value_of_Property__pc'
            + ' FROM Account WHERE Id = :accountId'
        );
        System.assert(acc.IsPersonAccount, 'Lead without a company converts to a Person Account.');
        System.assertEquals('123-45-6789', acc.get('SSN__pc'));
        System.assertEquals(Date.newInstance(1985, 4, 12), acc.get('PersonBirthdate'));
        System.assertEquals(350000, acc.get('Loan_Amount__pc'));
        System.assertEquals(120000, acc.get('Household_Income__pc'));
        System.assertEquals(425000, acc.get('Value_of_Property__pc'));

        Transaction__c txn = [
            SELECT Property_Address__c, Property_City__c, Property_State__c, Property_Postal_Code__c
            FROM Transaction__c WHERE Id = :transactionRecord.Id
        ];
        System.assertEquals('9 Gulf Shore Blvd', txn.Property_Address__c);
        System.assertEquals('Typed On File', txn.Property_City__c, 'A value already on the file is never overwritten.');
        System.assertEquals('FL', txn.Property_State__c);
        System.assertEquals('34102', txn.Property_Postal_Code__c);
    }
}