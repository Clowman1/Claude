/**
 * LO Workspace contact card, run as a real outside loan officer (External Loan Officer Profile +
 * role, permission set group External_Loan_Officer; the two permsets alone hit the tmpVar1 note
 * trigger quirk).
 *
 * Proves: the owner edits their lead, partner and past client; only the contact fields change;
 * a tagged shared partner and a borrower on the LO's loan are read-only and refused; na@na.com is
 * shown blank and never overwritten by a blank save; bad email / phone are rejected; a record the
 * LO cannot see is refused.
 */
@IsTest
private class LoWsContactServiceTest {

    static final String NAME = 'Zedcon'; // short: long Person Account last names did not query back by LastName in prod tests

    @TestSetup
    static void setup() {
        User lo = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p9con' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p9.test',
            Email = 'p9con@reach-p9.test',
            LastName = 'p9con',
            Alias = 'p9con',
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
        Id personRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Id consumerRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId();
        List<Account> accounts = new List<Account>{
            // Created via Add partner: owned by the LO.
            new Account(RecordTypeId = personRt, FirstName = 'Olive', LastName = NAME + 'Owned', Is_Realtor__c = true,
                PersonEmail = 'p9c.owned@example.com', Company__c = 'Own Realty', OwnerId = lo.Id),
            // Shared Reach partner (admin-owned), tagged by the LO below.
            new Account(RecordTypeId = personRt, FirstName = 'Rita', LastName = NAME + 'Shared', Is_Realtor__c = true,
                PersonEmail = 'p9c.shared@example.com', Phone = '(407) 555-0100', Company__c = 'Reach Realty'),
            // Imported past client with the placeholder email.
            new Account(RecordTypeId = personRt, FirstName = 'Cal', LastName = NAME + 'Client', PersonEmail = 'na@na.com',
                Group__pc = 'Client', Type__c = 'Borrower Account', BillingCity = 'Orlando', OwnerId = lo.Id),
            // Borrower on the LO's loan, owned by the admin.
            new Account(RecordTypeId = personRt, FirstName = 'Bo', LastName = NAME + 'Borrower',
                PersonEmail = 'p9c.borrower@example.com', PersonMailingCity = 'Tampa'),
            // Never shared with the LO.
            new Account(RecordTypeId = personRt, FirstName = 'Sam', LastName = NAME + 'Stranger',
                PersonEmail = 'p9c.stranger@example.com')
        };
        insert accounts;
        insert new Lead(RecordTypeId = consumerRt, FirstName = 'Lee', LastName = NAME + 'Lead', Company = 'n/a',
            Status = 'New', LeadSource = 'Test', OwnerId = lo.Id);
        insert new Transaction__c(Name = NAME + ' Loan', Loan_Officer__c = lo.Id, Borrower_Name__c = accounts[3].Id);
        System.runAs(lo) {
            LoWsPartnerTagService.tagAccounts(new Set<Id>{ accounts[1].Id });
        }
    }

    static User lo() {
        return [SELECT Id FROM User WHERE Alias = 'p9con' LIMIT 1];
    }

    static Id account(String suffix) {
        return [SELECT Id FROM Account WHERE LastName = :(NAME + suffix) LIMIT 1].Id;
    }

    @IsTest
    static void ownerEditsLeadAndOnlyContactFieldsChange() {
        Lead before = [SELECT Id, LeadSource, Status, OwnerId, LastName FROM Lead WHERE LeadSource = 'Test'];
        System.runAs(lo()) {
            LoWsContactService.ContactInfo c = ExternalLoPortalController.getContactInfo(before.Id);
            System.assertEquals(true, c.canEdit, 'the owner can edit');
            c = ExternalLoPortalController.updateContactInfo(before.Id, null, null, ' (407) 555-1212 ',
                'lee@example.com', '1 Main St', 'Orlando', 'FL', '32801', null);
            System.assertEquals('407-555-1212', c.phone);
            System.assertEquals('lee@example.com', c.email);
            System.assertEquals('32801', c.postalCode);
        }
        Lead after = [SELECT LeadSource, Status, OwnerId, LastName, Phone, MobilePhone, Street, City, State FROM Lead WHERE Id = :before.Id];
        System.assertEquals('407-555-1212', after.MobilePhone, 'one Phone is saved to both phone fields');
        System.assertEquals(before.LeadSource, after.LeadSource, 'Lead Source untouched');
        System.assertEquals(before.Status, after.Status);
        System.assertEquals(before.OwnerId, after.OwnerId, 'owner untouched');
        System.assertEquals(before.LastName, after.LastName);
        System.assertEquals('407-555-1212', after.Phone);
        System.assertEquals('1 Main St', after.Street);
        System.assertEquals('Orlando', after.City);
        System.assertEquals('FL', after.State);
    }

    @IsTest
    static void ownedPartnerAndPastClientAreEditable() {
        Id ownedId = account('Owned');
        Id clientId = account('Client');
        System.runAs(lo()) {
            LoWsContactService.ContactInfo partner = ExternalLoPortalController.getContactInfo(ownedId);
            System.assertEquals(true, partner.canEdit);
            System.assertEquals('Own Realty', partner.company);
            ExternalLoPortalController.updateContactInfo(ownedId, null, null, '407-555-0001', 'olive@example.com',
                '2 Oak Ave', 'Winter Park', 'FL', '32789', null);

            LoWsContactService.ContactInfo client = ExternalLoPortalController.getContactInfo(clientId);
            System.assertEquals(true, client.canEdit);
            System.assertEquals(null, client.email, 'na@na.com is shown blank');
            System.assertEquals('Orlando', client.city, 'Billing city is the display fallback');
            client = ExternalLoPortalController.updateContactInfo(clientId, null, null, '(321) 555-0002', '', null, 'Kissimmee', null, null, null);
            System.assertEquals('Kissimmee', client.city);
        }
        Account p = [SELECT Phone, PersonEmail, PersonMailingStreet, PersonMailingPostalCode, OwnerId FROM Account WHERE Id = :ownedId];
        System.assertEquals('407-555-0001', p.Phone);
        System.assertEquals('olive@example.com', p.PersonEmail);
        System.assertEquals('2 Oak Ave', p.PersonMailingStreet);
        System.assertEquals('32789', p.PersonMailingPostalCode);
        Account c = [SELECT PersonEmail, Phone, PersonMobilePhone, PersonMailingCity FROM Account WHERE Id = :clientId];
        System.assertEquals('321-555-0002', c.Phone, 'one Phone is saved to both phone fields');
        System.assertEquals('na@na.com', c.PersonEmail, 'a blank save leaves the placeholder alone');
        System.assertEquals('321-555-0002', c.PersonMobilePhone);
        System.assertEquals('Kissimmee', c.PersonMailingCity);
    }

    @IsTest
    static void sharedPartnerIsReadOnlyAndRefused() {
        Id sharedId = account('Shared');
        System.runAs(lo()) {
            LoWsContactService.ContactInfo c = ExternalLoPortalController.getContactInfo(sharedId);
            System.assertEquals(false, c.canEdit);
            System.assertEquals(LoWsContactService.SHARED_PARTNER_NOTE, c.note);
            System.assertEquals('407-555-0100', c.phone, 'shown read-only');
            System.assertEquals('Reach Realty', c.company);
            assertRefused(sharedId, LoWsContactService.SHARED_PARTNER_NOTE);
        }
        Account a = [SELECT Phone, PersonEmail FROM Account WHERE Id = :sharedId];
        System.assertEquals('407-555-0100', a.Phone, 'unchanged');
        System.assertEquals('p9c.shared@example.com', a.PersonEmail);
    }

    @IsTest
    static void borrowerOnMyLoanIsReadOnly() {
        Id loanId = [SELECT Id FROM Transaction__c WHERE Loan_Officer__c = :lo().Id].Id;
        Id borrowerId = account('Borrower');
        System.runAs(lo()) {
            LoWsContactService.ContactInfo c = ExternalLoPortalController.getContactInfo(loanId);
            System.assertEquals(borrowerId, c.recordId);
            System.assertEquals('p9c.borrower@example.com', c.email);
            System.assertEquals('Tampa', c.city);
            System.assertEquals(false, c.canEdit);
            System.assertEquals(LoWsContactService.BORROWER_NOTE, c.note);
            assertRefused(loanId, LoWsContactService.BORROWER_NOTE);
        }
    }

    @IsTest
    static void unseenRecordAndBadFormatsAreRefused() {
        Id leadId = [SELECT Id FROM Lead WHERE LeadSource = 'Test'].Id;
        Id strangerId = account('Stranger');
        System.runAs(lo()) {
            assertRefused(strangerId, LoWsContactService.NOT_FOUND);
            assertRefused(UserInfo.getUserId(), LoWsContactService.NOT_FOUND);
            try {
                ExternalLoPortalController.updateContactInfo(leadId, null, null, null, 'not-an-email', null, null, null, null, null);
                System.assert(false, 'bad email must fail');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('valid email'), e.getMessage());
            }
            try {
                ExternalLoPortalController.updateContactInfo(leadId, null, null, '555-12', null, null, null, null, null, null);
                System.assert(false, 'bad phone must fail');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('10-digit'), e.getMessage());
            }
        }
        System.assertEquals(null, [SELECT Phone FROM Lead WHERE Id = :leadId].Phone, 'nothing saved');
    }

    @IsTest
    static void nextAppointmentShowsMyEarliestFutureEventOnly() {
        Lead l = [SELECT Id, Status FROM Lead WHERE LeadSource = 'Test'];
        User me = lo();
        System.runAs(me) {
            Datetime now = Datetime.now();
            // One insert each: EventTriggerHandler throws "Duplicate id in list" for 2+ Events on one lead in a batch.
            insert new Event(OwnerId = me.Id, WhoId = l.Id, Subject = 'Past call', StartDateTime = now.addDays(-1), DurationInMinutes = 30);
            insert new Event(OwnerId = me.Id, WhoId = l.Id, Subject = 'Later meeting', StartDateTime = now.addDays(5), DurationInMinutes = 30);
            insert new Event(OwnerId = me.Id, WhoId = l.Id, Subject = 'Pre-approval review', StartDateTime = now.addDays(2), DurationInMinutes = 30);
            String next = ExternalLoPortalController.getContactInfo(l.Id).nextAppointment;
            System.assert(next.startsWith('Next appointment: '), next);
            System.assert(next.endsWith(' — Pre-approval review'), 'the earliest future one: ' + next);
            Boolean onRow = false;
            for (ExternalLoPortalService.LeadRow row : ExternalLoPortalController.getLeads('all', null, null)) {
                if (row.id == l.Id) onRow = row.nextAppointment == next;
            }
            System.assert(onRow, 'My Leads row carries the same badge text');
        }
        System.assertEquals(l.Status, [SELECT Status FROM Lead WHERE Id = :l.Id].Status, 'an appointment never changes the status');
        System.assertEquals(null, ExternalLoPortalController.getContactInfo(l.Id).nextAppointment, 'not my events: nothing shown');
    }

    @IsTest
    static void ownerLinksLeadToAriveOnce() {
        Id leadId = [SELECT Id FROM Lead WHERE LeadSource = 'Test'].Id;
        Lead other = new Lead(FirstName = 'Other', LastName = NAME + 'Other', Company = 'n/a', Status = 'New', LeadSource = 'Test');
        insert other;
        update new Lead(Id = other.Id, AriveId__c = '99887766');
        Assert.areEqual('99887766', [SELECT AriveId__c FROM Lead WHERE Id = :other.Id].AriveId__c, 'setup: other lead keeps its Arive ID');
        System.runAs(lo()) {
            for (String bad : new List<String>{ '', 'abc', '99887766' }) {
                try {
                    ExternalLoPortalController.linkToArive(leadId, bad);
                    Assert.fail('Expected a refusal for ' + bad);
                } catch (AuraHandledException expected) {}
            }
            Assert.areEqual('11112222', ExternalLoPortalController.linkToArive(
                leadId, ' https://reach.arive.com/app/loans/11112222/loan-info '));
            try {
                ExternalLoPortalController.linkToArive(leadId, '12345678');
                Assert.fail('Expected a refusal once linked');
            } catch (AuraHandledException expected) {}
        }
        Assert.areEqual('11112222', [SELECT AriveId__c FROM Lead WHERE Id = :leadId].AriveId__c);
    }

    @IsTest
    static void loanOfficerLinksLoanToArive() {
        Id loanId = [SELECT Id FROM Transaction__c WHERE Name = :(NAME + ' Loan')].Id;
        Transaction__c notMine = new Transaction__c(Name = NAME + ' Not Mine');
        Transaction__c mine2 = new Transaction__c(Name = NAME + ' Mine2', Loan_Officer__c = lo().Id);
        insert new List<Transaction__c>{ notMine, mine2 };
        // The lead the loan came from shares its Arive ID: that is the conversion carry-forward, not a clash.
        insert new Lead(FirstName = 'Src', LastName = NAME + 'Src', Company = 'n/a', Status = 'New', LeadSource = 'Test');
        update new Lead(Id = [SELECT Id FROM Lead WHERE LastName = :(NAME + 'Src')].Id, AriveId__c = '33334444');
        System.runAs(lo()) {
            try {
                ExternalLoPortalController.linkToArive(notMine.Id, '55556666');
                Assert.fail('Expected a refusal on a loan that is not mine');
            } catch (AuraHandledException expected) {}
            Assert.areEqual('33334444', ExternalLoPortalController.linkToArive(loanId, '33334444'));
            try {
                ExternalLoPortalController.linkToArive(mine2.Id, '33334444');
                Assert.fail('Expected a refusal: ID already on another loan');
            } catch (AuraHandledException expected) {}
        }
        Assert.areEqual('33334444', [SELECT AriveId__c FROM Transaction__c WHERE Id = :loanId].AriveId__c);
    }

    static void assertRefused(Id recordId, String expected) {
        try {
            ExternalLoPortalController.updateContactInfo(recordId, null, null, '(407) 555-9999', 'x@example.com', null, null, null, null, null);
            System.assert(false, 'must be refused');
        } catch (AuraHandledException e) {
            System.assertEquals(expected, e.getMessage());
        }
    }
}