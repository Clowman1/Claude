/**
 * LO Workspace co-borrowers and loan borrower names, run as a real outside loan officer
 * (External Loan Officer Profile + role, permission set group External_Loan_Officer).
 *
 * Proves: the owner adds a co-borrower and sees it (the Borrower__c restriction rule passes because
 * the row is stamped from the lead owner); edits it through the Contact card; a non-owner is refused;
 * removal is refused while a document request is assigned; My Loans shows the borrower's name, never
 * the raw Account Id.
 */
@IsTest
private class LoWsBorrowerServiceTest {

    @TestSetup
    static void setup() {
        User lo = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p9bor' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p9.test',
            Email = 'p9bor@reach-p9.test',
            LastName = 'p9bor',
            Alias = 'p9bor',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert lo;
            insert new PermissionSetAssignment(AssigneeId = lo.Id,
                PermissionSetGroupId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'External_Loan_Officer'].Id);
        }
        Id consumerRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId();
        insert new List<Lead>{
            new Lead(RecordTypeId = consumerRt, FirstName = 'Mia', LastName = 'Mine', Company = 'n/a', Status = 'New',
                OwnerId = lo.Id, Email = 'p9b.mine@example.com'),
            new Lead(RecordTypeId = consumerRt, FirstName = 'Oscar', LastName = 'Other', Company = 'n/a', Status = 'Working',
                Email = 'p9b.other@example.com')
        };
        insert new LeadShare(LeadId = leadId('p9b.other@example.com'), UserOrGroupId = lo.Id, LeadAccessLevel = 'Read', RowCause = 'Manual');
        Account borrower = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = 'Bo', LastName = 'Loanborrower', PersonEmail = 'p9b.loan@example.com');
        insert borrower;
        insert new Transaction__c(Name = 'P9B Loan', Loan_Officer__c = lo.Id, Borrower_Name__c = borrower.Id, Status__c = 'TRID Application');
    }

    static User lo() {
        return [SELECT Id FROM User WHERE Alias = 'p9bor' LIMIT 1];
    }

    static Id leadId(String email) {
        return [SELECT Id FROM Lead WHERE Email = :email LIMIT 1].Id;
    }

    @IsTest
    static void ownerAddsSeesEditsAndRemovesACoBorrower() {
        Id mine = leadId('p9b.mine@example.com');
        System.runAs(lo()) {
            Id b = ExternalLoPortalController.addLeadBorrower(mine, 'Ben', 'Second', '(407) 555-0191', 'p9b.ben@example.com', null);
            LoWsBorrowerService.BorrowerList borrowers = ExternalLoPortalController.getLeadBorrowers(mine);
            System.assertEquals(true, borrowers.canEdit);
            System.assertEquals(2, borrowers.pills.size(), 'primary + the new co-borrower (visible through the restriction rule)');
            System.assertEquals('Mia Mine (Primary)', borrowers.pills[0].label);
            System.assertEquals(true, borrowers.pills[0].primary);
            System.assertEquals(b, borrowers.pills[1].id);

            LoWsContactService.ContactInfo c = ExternalLoPortalController.getContactInfo(b);
            System.assertEquals(true, c.isBorrower);
            System.assertEquals(true, c.canEdit);
            System.assertEquals('Ben', c.firstName);
            c = ExternalLoPortalController.updateContactInfo(b, 'Benny', 'Second', '407-555-0192', 'p9b.benny@example.com',
                'ignored street', null, null, null, null);
            System.assertEquals('Benny', c.firstName);
            System.assertEquals('407-555-0192', c.phone);

            ExternalLoPortalController.removeLeadBorrower(b);
            System.assertEquals(1, ExternalLoPortalController.getLeadBorrowers(mine).pills.size());
        }
        System.assertEquals(0, [SELECT COUNT() FROM Borrower__c WHERE Lead__c = :mine]);
    }

    @IsTest
    static void onlyNamesAreRequiredAndFilledFieldsAreChecked() {
        Id mine = leadId('p9b.mine@example.com');
        System.runAs(lo()) {
            expectError(mine, 'Ben', '', null, null, 'first and last name');
            expectError(mine, 'Ben', 'Second', '555-12', null, '10-digit');
            expectError(mine, 'Ben', 'Second', null, 'na@na.com', 'real email');
            expectError(mine, 'Ben', 'Second', null, 'not-an-email', 'real email');
            System.assertEquals(0, [SELECT COUNT() FROM Borrower__c]);
            try {
                ExternalLoPortalController.addLeadBorrower(mine, 'Ben', 'Second', null, null, 'Neighbour');
                System.assert(false, 'unknown relationship must fail');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('relationship'), e.getMessage());
            }

            // Name only, with a relationship: allowed, and flagged as unreachable.
            Id b = ExternalLoPortalController.addLeadBorrower(mine, 'Jane', 'Smith', null, null, 'Spouse');
            LoWsBorrowerService.BorrowerList borrowers = ExternalLoPortalController.getLeadBorrowers(mine);
            System.assertEquals('Jane Smith (Spouse)', borrowers.pills[1].label);
            System.assertEquals(true, borrowers.pills[1].noEmail);
            System.assertEquals(8, borrowers.relationships.size());
            LoWsContactService.ContactInfo c = ExternalLoPortalController.getContactInfo(b);
            System.assertEquals('Spouse', c.relationship);
            System.assertEquals(LoWsContactService.NO_EMAIL_WARNING, c.noEmailWarning);
            c = ExternalLoPortalController.updateContactInfo(b, 'Jane', 'Smith', null, 'jane@example.com', null, null, null, null, 'Partner');
            System.assertEquals(null, c.noEmailWarning, 'an email clears the warning');
            System.assertEquals('Partner', c.relationship);
        }
    }

    @IsTest
    static void documentRequestSendExplainsANoEmailCoBorrower() {
        // Saving a request mints an AES-encrypted portal hash (same settings as LeadConditionAssignmentTest).
        insert new AesKey__c(SetupOwnerId = UserInfo.getOrganizationId(), AesKey__c = '12345678901234567890123456789012');
        insert new BorrowerPortalSettings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Borrower_Home_Url__c = 'https://example.force.com/documents/s/');
        Id mine = leadId('p9b.mine@example.com');
        Borrower__c ben = new Borrower__c(Lead__c = mine, Name = 'Ben Second', First_Name__c = 'Ben', Last_Name__c = 'Second',
            Email__c = 'p9b.ben@example.com');
        insert ben;
        LeadDocumentRequestService.RequestInput input = new LeadDocumentRequestService.RequestInput();
        input.name = 'W-2';
        input.subject = 'W-2';
        input.description = 'Most recent W-2';
        input.category = 'Income';
        input.canBorrowerSee = true;
        input.includeInEmail = true;
        input.assignment = String.valueOf(ben.Id);
        LeadDocumentRequestService.saveRequests(mine, new List<LeadDocumentRequestService.RequestInput>{ input });
        // The email is removed after the item was assigned: the send must say why Ben got nothing.
        update new Borrower__c(Id = ben.Id, Email__c = null);
        List<String> outcomes = LeadDocumentRequestService.sendPerBorrowerRequestEmails(mine, 'Items Needed', null);
        String joined = String.join(outcomes, ' | ');
        System.assert(joined.contains('Ben Second' + LeadDocumentRequestService.NO_EMAIL_OUTCOME), joined);
        // And the picker still lists him, as not assignable, so the UI can show "No email".
        Boolean listed = false;
        for (LeadDocumentRequestService.BorrowerOption o : LeadDocumentRequestService.getBorrowerOptions(mine)) {
            if (o.value == String.valueOf(ben.Id)) listed = o.assignable == false;
        }
        System.assert(listed, 'no-email co-borrower is listed as not assignable');
    }

    @IsTest
    static void nonOwnerIsRefused() {
        Id other = leadId('p9b.other@example.com');
        Borrower__c existing = new Borrower__c(Lead__c = other, First_Name__c = 'Ola', Last_Name__c = 'Other', Name = 'Ola Other',
            Phone__c = '(407) 555-0193', Email__c = 'p9b.ola@example.com', External_LO__c = lo().Id);
        insert existing;
        System.runAs(lo()) {
            LoWsBorrowerService.BorrowerList borrowers = ExternalLoPortalController.getLeadBorrowers(other);
            System.assertEquals(false, borrowers.canEdit);
            expectError(other, 'Ben', 'Second', '(407) 555-0191', 'p9b.ben@example.com', LoWsContactService.NOT_OWNER_NOTE);
            try {
                ExternalLoPortalController.updateContactInfo(existing.Id, 'X', 'Y', '(407) 555-0194', 'x@example.com', null, null, null, null, null);
                System.assert(false, 'non-owner edit must fail');
            } catch (AuraHandledException e) {
                // Refused either way: not my lead, or (restriction rule) the row is not stamped for me.
                System.assert(e.getMessage() == LoWsContactService.NOT_OWNER_NOTE || e.getMessage() == LoWsContactService.NOT_FOUND, e.getMessage());
            }
            try {
                ExternalLoPortalController.removeLeadBorrower(existing.Id);
                System.assert(false, 'non-owner remove must fail');
            } catch (AuraHandledException e) {
                // Refused either way: not my lead, or (restriction rule) the row is not stamped for me.
                System.assert(e.getMessage() == LoWsContactService.NOT_OWNER_NOTE || e.getMessage() == LoWsContactService.NOT_FOUND, e.getMessage());
            }
        }
        System.assertEquals('Ola', [SELECT First_Name__c FROM Borrower__c WHERE Id = :existing.Id].First_Name__c);
    }

    @IsTest
    static void removalIsRefusedWhileADocumentRequestIsAssigned() {
        Id mine = leadId('p9b.mine@example.com');
        Id b;
        System.runAs(lo()) {
            b = ExternalLoPortalController.addLeadBorrower(mine, 'Ben', 'Second', '(407) 555-0191', 'p9b.ben@example.com', null);
        }
        insert new Lead_Document_Request__c(Lead__c = mine, Borrower__c = b, Name = 'Pay stubs');
        System.runAs(lo()) {
            try {
                ExternalLoPortalController.removeLeadBorrower(b);
                System.assert(false, 'must be refused');
            } catch (AuraHandledException e) {
                System.assertEquals(LoWsBorrowerService.HAS_ASSIGNMENTS, e.getMessage());
            }
        }
        System.assertEquals(1, [SELECT COUNT() FROM Borrower__c WHERE Id = :b]);
    }

    @IsTest
    static void myLoansShowTheBorrowerNameNeverTheId() {
        Account borrower = [SELECT Id FROM Account WHERE PersonEmail = 'p9b.loan@example.com'];
        System.runAs(lo()) {
            List<ExternalLoPortalService.LoanRow> rows = ExternalLoPortalController.getLoans('all', null);
            System.assertEquals(1, rows.size());
            System.assertEquals('Bo Loanborrower', rows[0].borrower);
            System.assertNotEquals(String.valueOf(borrower.Id), rows[0].borrower);
            System.assertEquals('Bo Loanborrower', ExternalLoPortalController.getLoanDetail(rows[0].id).summary.borrower);
        }
    }

    static void expectError(Id leadId, String first, String last, String phone, String email, String expected) {
        try {
            ExternalLoPortalController.addLeadBorrower(leadId, first, last, phone, email, null);
            System.assert(false, 'expected: ' + expected);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains(expected), e.getMessage());
        }
    }
}