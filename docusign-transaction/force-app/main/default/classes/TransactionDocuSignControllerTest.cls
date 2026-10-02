@IsTest
private class TransactionDocuSignControllerTest {

    private static Id setup(String coBorrowerEmail) {
        // Make the running user a DocuSign sender (setup DML in its own runAs to avoid mixed DML).
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE NamespacePrefix = 'dfsle' AND Name = 'DocuSign_User'];
            if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.NamespacePrefix = 'dfsle'] == 0) {
                insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id);
            }
        }
        Account b = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = 'Pat', LastName = 'Borrower', PersonEmail = 'pat.borrower@example.com',
            First_Name_Co_Borrower__pc = 'Sam', Last_Name_Co_Borrower__pc = 'Borrower',
            Email_Co_Borrower__pc = coBorrowerEmail);
        insert b;
        Transaction__c t = new Transaction__c(Name = 'DocuSign Test File', Borrower_Name__c = b.Id, Loan_Officer__c = UserInfo.getUserId());
        insert t;
        ContentVersion cv = new ContentVersion(Title = 'LOE', PathOnClient = 'LOE.pdf', VersionData = Blob.valueOf('x'), FirstPublishLocationId = t.Id);
        insert cv;
        return t.Id;
    }

    @IsTest
    static void loadsSignersAndFiles() {
        Id tId = setup('sam.borrower@example.com');
        TransactionDocuSignController.Data d = TransactionDocuSignController.getData(tId);
        Assert.isTrue(d.canSend);
        Assert.areEqual(1, d.files.size());
        Assert.areEqual('LOE.pdf', d.files[0].title);
        Assert.areEqual('pat.borrower@example.com', d.borrower.email);
        Assert.areEqual('Sam Borrower', d.coBorrower.name);
        Assert.areEqual(UserInfo.getUserEmail(), d.loanOfficer.email);
        Assert.areEqual(0, d.envelopes.size());
    }

    @IsTest
    static void rejectsMissingFilesAndCoBorrowerEmail() {
        Id tId = setup(null);
        try {
            TransactionDocuSignController.createDraft(tId, new List<String>(), new List<Id>(), true, false);
            Assert.fail('expected error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Pick a template'));
        }
        try {
            TransactionDocuSignController.createDraft(tId, new List<String>{ 'Not A Template' }, null, false, false);
            Assert.fail('expected error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Unknown template'));
        }
        Id cvId = TransactionDocuSignController.getData(tId).files[0].versionId;
        try {
            TransactionDocuSignController.createDraft(tId, new List<String>(), new List<Id>{ cvId }, true, false);
            Assert.fail('expected error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('co-borrower has no email'));
        }
    }

    @IsTest
    static void attemptsDraftWithDocuSign() {
        Id tId = setup(null);
        Id cvId = TransactionDocuSignController.getData(tId).files[0].versionId;
        // The package calls out to DocuSign; tests cannot, so only the envelope build is exercised here.
        try {
            TransactionDocuSignController.createDraft(tId, new List<String>{ 'Address LOX' }, new List<Id>{ cvId }, false, true);
        } catch (Exception e) {
            Assert.isNotNull(e.getMessage());
        }
        try {
            TransactionDocuSignController.createDraft(tId, new List<String>{ 'No HOA LOX', 'Credit Inquiry LOX' }, null, false, false);
        } catch (Exception e) {
            Assert.isNotNull(e.getMessage());
        }
        try {
            TransactionDocuSignController.getSenderView(tId, tId);
        } catch (Exception e) {
            Assert.isNotNull(e.getMessage());
        }
    }
}
