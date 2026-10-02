@IsTest
private class RingSenseRelateCallInsightInvocableTest {
    @IsTest
    static void testResolveRelationshipsTransactionLeadAndAccountPriority() {
        Account accountWithLead = new Account(Name = 'Account With Lead');
        Account accountWithTransaction = new Account(Name = 'Account With Transaction');
        Account fallbackOnlyAccount = new Account(Name = 'Fallback Only Account');
        insert new List<Account>{ accountWithLead, accountWithTransaction, fallbackOnlyAccount };

        Contact contactWithLeadPhone = new Contact(
            FirstName = 'Lead',
            LastName = 'Contact',
            Phone = '+1 (954) 111-2222',
            AccountId = accountWithLead.Id
        );
        Contact contactWithTransactionPhone = new Contact(
            FirstName = 'Transaction',
            LastName = 'Contact',
            Phone = '+1 (954) 222-3333',
            AccountId = accountWithTransaction.Id
        );
        Contact fallbackContact = new Contact(
            FirstName = 'Fallback',
            LastName = 'Contact',
            Phone = '+1 (954) 333-4444',
            AccountId = fallbackOnlyAccount.Id
        );
        insert new List<Contact>{ contactWithLeadPhone, contactWithTransactionPhone, fallbackContact };

        Lead matchingLead = new Lead(
            FirstName = 'Priority',
            LastName = 'Lead',
            MobilePhone = '9541112222'
        );
        Lead lowerPriorityLead = new Lead(
            FirstName = 'Lower',
            LastName = 'Priority',
            MobilePhone = '9542223333'
        );
        insert new List<Lead>{ matchingLead, lowerPriorityLead };

        Id businessAccountRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Business_Account'
            LIMIT 1
        ].Id;
        Account lender = new Account(
            Name = 'Priority Lender',
            RecordTypeId = businessAccountRecordTypeId,
            Type = 'Investor'
        );
        insert lender;

        Transaction__c activeTransaction = new Transaction__c(
            Name = 'Priority Transaction',
            Status__c = 'Processing',
            Borrower_Name__c = accountWithTransaction.Id,
            Borrower_First_Name__c = 'Priority',
            Borrower_Last_Name__c = 'Borrower',
            Lender_lookup__c = lender.Id
        );
        insert activeTransaction;

        RingSenseRelateCallInsightInvocable.Input leadInput = new RingSenseRelateCallInsightInvocable.Input();
        leadInput.callInsightId = UserInfo.getUserId();
        leadInput.recipientPhoneNumber = '(954) 111-2222';

        RingSenseRelateCallInsightInvocable.Input transactionInput = new RingSenseRelateCallInsightInvocable.Input();
        transactionInput.callInsightId = UserInfo.getUserId();
        transactionInput.recipientPhoneNumber = '(954) 222-3333';

        RingSenseRelateCallInsightInvocable.Input fallbackInput = new RingSenseRelateCallInsightInvocable.Input();
        fallbackInput.callInsightId = UserInfo.getUserId();
        fallbackInput.recipientPhoneNumber = '(954) 333-4444';

        List<RingSenseRelateCallInsightInvocable.Output> outputRows = RingSenseRelateCallInsightInvocable.resolveRelationships(
            new List<RingSenseRelateCallInsightInvocable.Input>{ leadInput, transactionInput, fallbackInput }
        );

        System.assertEquals(3, outputRows.size());
        System.assertEquals(matchingLead.Id, outputRows[0].leadId);
        System.assertEquals(null, outputRows[0].accountId);
        System.assertEquals(null, outputRows[0].transactionId);

        System.assertEquals(null, outputRows[1].leadId);
        System.assertEquals(accountWithTransaction.Id, outputRows[1].accountId);
        System.assertEquals(activeTransaction.Id, outputRows[1].transactionId);

        System.assertEquals(null, outputRows[2].leadId);
        System.assertEquals(fallbackOnlyAccount.Id, outputRows[2].accountId);
    }
}