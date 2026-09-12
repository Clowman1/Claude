@IsTest
private class BorrowerPersonAccountServiceTest {
    private static Id personAccountRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();
    }

    private static Transaction__c newTransaction() {
        Transaction__c txn = new Transaction__c(Name = 'Borrower Test File');
        insert txn;
        return txn;
    }

    private static Lead newConvertedLead(Id transactionId) {
        Lead theLead = new Lead(
            FirstName = 'Primary',
            LastName = 'Borrower',
            Company = 'Borrower Test',
            Email = 'primary.borrower@example.invalid',
            Converted_Transaction_ID__c = transactionId
        );
        insert theLead;
        return theLead;
    }

    @IsTest
    static void createsPersonAccountAndStampsTransaction() {
        Transaction__c txn = newTransaction();
        Lead theLead = newConvertedLead(txn.Id);
        insert new Borrower__c(
            Lead__c = theLead.Id,
            First_Name__c = 'Jane',
            Last_Name__c = 'Smith',
            Email__c = 'jane.smith@example.invalid',
            Phone__c = '5615551234'
        );

        Test.startTest();
        BorrowerPersonAccountService.linkForTransactions(
            new List<BorrowerPersonAccountService.Request>{
                new BorrowerPersonAccountService.Request(txn.Id)
            }
        );
        Test.stopTest();

        Borrower__c saved = [
            SELECT Name, Account__c, Transaction__c, Account__r.FirstName, Account__r.LastName,
                   Account__r.PersonEmail, Account__r.IsPersonAccount
            FROM Borrower__c
            LIMIT 1
        ];
        Assert.isNotNull(saved.Account__c, 'A Person Account should have been created');
        Assert.isTrue(saved.Account__r.IsPersonAccount, 'The new Account must be a Person Account');
        Assert.areEqual(txn.Id, saved.Transaction__c, 'The borrower should be stamped onto the Transaction');
        Assert.areEqual('Jane Smith', saved.Name, 'Name should be written as First Last');
        Assert.areEqual('jane.smith@example.invalid', saved.Account__r.PersonEmail);
    }

    @IsTest
    static void reusesExistingPersonAccountByEmailIgnoringCase() {
        Account existing = new Account(
            RecordTypeId = personAccountRecordTypeId(),
            FirstName = 'John',
            LastName = 'Doe',
            PersonEmail = 'John.Doe@example.invalid'
        );
        insert existing;

        Transaction__c txn = newTransaction();
        Lead theLead = newConvertedLead(txn.Id);
        insert new Borrower__c(
            Lead__c = theLead.Id,
            First_Name__c = 'John',
            Last_Name__c = 'Doe',
            Email__c = 'john.doe@EXAMPLE.invalid'
        );

        Integer accountsBefore = [SELECT COUNT() FROM Account WHERE IsPersonAccount = TRUE];

        Test.startTest();
        BorrowerPersonAccountService.linkForTransactions(
            new List<BorrowerPersonAccountService.Request>{
                new BorrowerPersonAccountService.Request(txn.Id)
            }
        );
        Test.stopTest();

        Borrower__c saved = [SELECT Account__c FROM Borrower__c LIMIT 1];
        Assert.areEqual(existing.Id, saved.Account__c, 'Should have matched the existing Person Account');
        Assert.areEqual(
            accountsBefore,
            [SELECT COUNT() FROM Account WHERE IsPersonAccount = TRUE],
            'No duplicate Person Account should be created'
        );
    }

    @IsTest
    static void sharedHouseholdEmailDoesNotMergeTwoBorrowers() {
        Account spouse = new Account(
            RecordTypeId = personAccountRecordTypeId(),
            FirstName = 'Dana',
            LastName = 'Whitfield',
            PersonEmail = 'whitfields@example.invalid'
        );
        insert spouse;

        Transaction__c txn = newTransaction();
        Lead theLead = newConvertedLead(txn.Id);
        // Same address as Dana, different person: the classic married-couple case.
        insert new Borrower__c(
            Lead__c = theLead.Id,
            First_Name__c = 'Rory',
            Last_Name__c = 'Whitfield',
            Email__c = 'whitfields@example.invalid'
        );

        Test.startTest();
        BorrowerPersonAccountService.linkForTransactions(
            new List<BorrowerPersonAccountService.Request>{
                new BorrowerPersonAccountService.Request(txn.Id)
            }
        );
        Test.stopTest();

        Borrower__c saved = [SELECT Account__c, Account__r.FirstName FROM Borrower__c LIMIT 1];
        Assert.areNotEqual(
            spouse.Id,
            saved.Account__c,
            'A shared household email must not merge Rory onto Dana\'s Person Account'
        );
        Assert.areEqual('Rory', saved.Account__r.FirstName, 'Rory should get his own Person Account');
    }

    @IsTest
    static void borrowerWithoutEmailOrPhoneStillGetsAnAccount() {
        Transaction__c txn = newTransaction();
        Lead theLead = newConvertedLead(txn.Id);
        insert new Borrower__c(Lead__c = theLead.Id, First_Name__c = 'Nameonly', Last_Name__c = 'Borrower');

        Test.startTest();
        BorrowerPersonAccountService.linkForTransactions(
            new List<BorrowerPersonAccountService.Request>{
                new BorrowerPersonAccountService.Request(txn.Id)
            }
        );
        Test.stopTest();

        Borrower__c saved = [SELECT Account__c, Transaction__c, Name FROM Borrower__c LIMIT 1];
        Assert.isNotNull(saved.Account__c, 'Name alone is enough to create a Person Account');
        Assert.areEqual(txn.Id, saved.Transaction__c);
        Assert.areEqual('Nameonly Borrower', saved.Name);
    }

    @IsTest
    static void skipsRowWithoutLastNameWithoutFailing() {
        Transaction__c txn = newTransaction();
        Lead theLead = newConvertedLead(txn.Id);
        insert new Borrower__c(
            Lead__c = theLead.Id,
            First_Name__c = 'NoSurname',
            Email__c = 'nosurname@example.invalid'
        );

        Test.startTest();
        BorrowerPersonAccountService.linkForTransactions(
            new List<BorrowerPersonAccountService.Request>{
                new BorrowerPersonAccountService.Request(txn.Id)
            }
        );
        Test.stopTest();

        Borrower__c saved = [SELECT Account__c, Transaction__c FROM Borrower__c LIMIT 1];
        Assert.isNull(saved.Account__c, 'Account.LastName is required, so no Person Account can be made');
        Assert.areEqual(txn.Id, saved.Transaction__c, 'The row should still carry onto the Transaction');
    }

    @IsTest
    static void secondCallIsANoOp() {
        Transaction__c txn = newTransaction();
        Lead theLead = newConvertedLead(txn.Id);
        insert new Borrower__c(
            Lead__c = theLead.Id,
            First_Name__c = 'Once',
            Last_Name__c = 'Only',
            Email__c = 'once.only@example.invalid'
        );
        List<BorrowerPersonAccountService.Request> requests =
            new List<BorrowerPersonAccountService.Request>{
                new BorrowerPersonAccountService.Request(txn.Id)
            };

        Test.startTest();
        BorrowerPersonAccountService.linkForTransactions(requests);
        Id firstAccountId = [SELECT Account__c FROM Borrower__c LIMIT 1].Account__c;
        BorrowerPersonAccountService.linkForTransactions(requests);
        Test.stopTest();

        Assert.areEqual(
            firstAccountId,
            [SELECT Account__c FROM Borrower__c LIMIT 1].Account__c,
            'Re-running must not repoint the borrower at a different Account'
        );
        Assert.areEqual(1, [SELECT COUNT() FROM Borrower__c], 'No extra rows');
    }

    @IsTest
    static void getBorrowersReturnsRowsForBothParents() {
        Transaction__c txn = newTransaction();
        Lead theLead = newConvertedLead(txn.Id);
        insert new List<Borrower__c>{
            new Borrower__c(Lead__c = theLead.Id, First_Name__c = 'Lead', Last_Name__c = 'Side'),
            new Borrower__c(Transaction__c = txn.Id, First_Name__c = 'Txn', Last_Name__c = 'Side'),
            new Borrower__c(Lead__c = theLead.Id, First_Name__c = 'Gone', Last_Name__c = 'Away', Removed__c = true)
        };

        Test.startTest();
        List<Borrower__c> leadRows = BorrowerPersonAccountService.getBorrowers(theLead.Id);
        List<Borrower__c> txnRows = BorrowerPersonAccountService.getBorrowers(txn.Id);
        List<Borrower__c> noneForOther = BorrowerPersonAccountService.getBorrowers(UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual(1, leadRows.size(), 'Removed rows must be excluded from the Lead panel');
        Assert.areEqual('Side', leadRows[0].Last_Name__c);
        Assert.areEqual(1, txnRows.size(), 'Transaction rows resolve off Transaction__c');
        Assert.areEqual('Txn', txnRows[0].First_Name__c);
        Assert.isTrue(noneForOther.isEmpty(), 'An unrelated parent type returns nothing rather than throwing');
        Assert.isTrue(BorrowerPersonAccountService.getBorrowers(null).isEmpty(), 'Null recordId is safe');
    }

    @IsTest
    static void findOrCreateResolvesByIdForTheEmailPath() {
        Transaction__c txn = newTransaction();
        Lead theLead = newConvertedLead(txn.Id);
        Borrower__c row = new Borrower__c(
            Lead__c = theLead.Id,
            First_Name__c = 'Email',
            Last_Name__c = 'Path',
            Email__c = 'email.path@example.invalid'
        );
        insert row;

        Test.startTest();
        Map<Id, Id> resolved = BorrowerPersonAccountService.findOrCreate(new Set<Id>{ row.Id });
        Test.stopTest();

        Assert.areEqual(1, resolved.size(), 'One borrower in, one mapping out');
        Assert.isNotNull(resolved.get(row.Id), 'The email path needs a real Person Account to merge against');
        Assert.isNull(
            [SELECT Transaction__c FROM Borrower__c WHERE Id = :row.Id].Transaction__c,
            'findOrCreate must not stamp the Transaction: that only happens at conversion'
        );
    }
}
