/**
 * Phase 5 (LO Workspace realtor / partner tagging), run as two real outside loan officers:
 * profile External Loan Officer Profile, role External_Loan_Officer, permission sets
 * External_LO_Access (custom permission External_LO) and External_LO_Perfect_Day_Access.
 *
 * Proves: LO B never sees LO A's tags or stages; a tag grants Read on the partner and untagging
 * removes it (but never access granted another way); a partner-type duplicate is tagged without a
 * new record; any other duplicate is refused with the admin message; CSV import follows the same
 * rules; Past Clients come from my closed loans.
 *
 * with sharing on purpose: the runAs assertions must see exactly what each LO can see.
 */
@IsTest
private with sharing class LoWsPartnerTagServiceTest {

    static final String REALTOR_EMAIL = 'p5.realtor@example.com';
    static final String REALTOR_PHONE = '(407) 555-0101';
    static final String BORROWER_EMAIL = 'p5.borrower@example.com';
    static final String BORROWER_PHONE = '(407) 555-0202';

    @TestSetup
    static void setup() {
        User loA = newExternalLo('p5.loa');
        User loB = newExternalLo('p5.lob');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ loA, loB };
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('External_LO_Access', 'External_LO_Perfect_Day_Access')]) {
                psas.add(new PermissionSetAssignment(AssigneeId = loA.Id, PermissionSetId = ps.Id));
                psas.add(new PermissionSetAssignment(AssigneeId = loB.Id, PermissionSetId = ps.Id));
            }
            insert psas;
        }
        Id personRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        // Owned by the admin running the test, i.e. by somebody other than either outside LO.
        insert new List<Account>{
            new Account(RecordTypeId = personRt, FirstName = 'Rita', LastName = 'Realtor', PersonEmail = REALTOR_EMAIL,
                PersonMobilePhone = REALTOR_PHONE, Is_Realtor__c = true, Company__c = 'Sunshine Realty'),
            new Account(RecordTypeId = personRt, FirstName = 'Tom', LastName = 'Title', PersonEmail = 'p5.title@example.com',
                BD_Industry__c = 'Title Agent'),
            new Account(RecordTypeId = personRt, FirstName = 'Bea', LastName = 'Borrower', PersonEmail = BORROWER_EMAIL,
                PersonMobilePhone = BORROWER_PHONE)
        };
    }

    // ------------------------------------------------------------------ add partner / tag / isolation

    @IsTest
    static void partnerMatchIsTaggedWithoutDuplicateAndIsolatedPerLo() {
        Id realtorId = account('Realtor');
        Integer accountsBefore = accountCount();

        System.runAs(lo('p5.loa')) {
            System.assertEquals(0, ExternalLoPortalController.getRealtors('all', null).size(), 'nothing tagged yet');
            System.assert(!RecordAccessGuard.readable(new Set<Id>{ realtorId }).contains(realtorId), 'no access before tagging');

            ExternalLoPartnerService.CreatePartnerResult r = ExternalLoPortalController.createPartner(
                'Rita Realtor', null, REALTOR_EMAIL.toUpperCase(), 'Sunshine Realty', 'Orlando', 'Realtor');
            System.assertEquals('match', r.status);
            System.assertEquals(1, r.matches.size());
            System.assertEquals(realtorId, r.matches[0].id);
            System.assertEquals(null, r.matches[0].phone, 'no contact details of an unseen record');

            ExternalLoPortalController.tagPartner(realtorId, REALTOR_EMAIL, null);
            ExternalLoPortalController.tagPartner(realtorId, REALTOR_EMAIL, null); // idempotent
            System.assert(RecordAccessGuard.readable(new Set<Id>{ realtorId }).contains(realtorId), 'tag grants read');

            List<ExternalLoPortalService.PartnerRow> rows = ExternalLoPortalController.getRealtors('all', null);
            System.assertEquals(1, rows.size());
            System.assertEquals('Prospect', rows[0].stage);
            System.assertEquals(true, rows[0].followUpDue, 'never touched counts as due');
            System.assertEquals(false, rows[0].houseLocked);
            System.assertEquals(1, ExternalLoPortalController.getRealtors('due', null).size());
            System.assertEquals(1, ExternalLoPortalController.getRealtorProspects(null).size());

            ExternalLoPortalController.setPartnerStage(realtorId, 'Active Partner');
            System.assertEquals('Active Partner', ExternalLoPortalController.getPartnerDetail(realtorId).summary.stage);
            System.assertEquals(0, ExternalLoPortalController.getRealtorProspects(null).size(), 'active partners are not prospects');
            System.assertEquals(1, ExternalLoPortalController.getRealtors('all', null).size());
        }
        System.assertEquals(accountsBefore, accountCount(), 'no duplicate created');

        System.runAs(lo('p5.lob')) {
            System.assertEquals(0, ExternalLoPortalController.getRealtors('all', null).size(), 'B sees none of A');
            System.assertEquals(0, [SELECT COUNT() FROM External_User_Assignment__c], 'A tags are private');
            System.assert(!RecordAccessGuard.readable(new Set<Id>{ realtorId }).contains(realtorId), 'A tag gives B nothing');
            try { ExternalLoPortalController.setPartnerStage(realtorId, 'Met'); System.assert(false, 'expected an error'); } catch (AuraHandledException e) { assertHas(e, 'not on your list'); }
            try { ExternalLoPortalController.untagPartner(realtorId); System.assert(false, 'expected an error'); } catch (AuraHandledException e) { assertHas(e, 'not on your list'); }
            try { ExternalLoPortalController.tagPartner(realtorId, null, null); System.assert(false, 'expected an error'); } catch (AuraHandledException e) { assertHas(e, 'You do not have access'); }

            // B tags the same partner by phone and keeps a separate stage.
            ExternalLoPortalController.tagPartner(realtorId, null, '407.555.0101');
            System.assertEquals('Prospect', ExternalLoPortalController.getRealtors('all', null)[0].stage);
            System.assertEquals(1, [SELECT COUNT() FROM External_User_Assignment__c], 'B sees only B tag');
        }

        System.runAs(lo('p5.loa')) {
            System.assertEquals('Active Partner', ExternalLoPortalController.getRealtors('all', null)[0].stage, 'B did not touch A stage');
            ExternalLoPortalController.untagPartner(realtorId);
            System.assertEquals(0, ExternalLoPortalController.getRealtors('all', null).size());
            System.assert(!RecordAccessGuard.readable(new Set<Id>{ realtorId }).contains(realtorId), 'untag removes read');
        }
        System.runAs(lo('p5.lob')) {
            System.assert(RecordAccessGuard.readable(new Set<Id>{ realtorId }).contains(realtorId), 'B keeps its own access');
        }
        System.assertEquals(1, [SELECT COUNT() FROM External_User_Assignment__c]);
    }

    @IsTest
    static void nonPartnerMatchIsRefusedWithAdminMessage() {
        Id borrowerId = account('Borrower');
        Integer accountsBefore = accountCount();
        System.runAs(lo('p5.loa')) {
            try { ExternalLoPortalController.createPartner('Bea Borrower', '407-555-0202', null, 'None', null, 'Realtor'); System.assert(false, 'expected an error'); } catch (AuraHandledException e) { assertHas(e, LoWsPartnerTagService.ADMIN_MESSAGE); }
            try { ExternalLoPortalController.tagPartner(borrowerId, BORROWER_EMAIL, null); System.assert(false, 'expected an error'); } catch (AuraHandledException e) { assertHas(e, LoWsPartnerTagService.ADMIN_MESSAGE); }
            try { ExternalLoPortalController.createPartner('No Contact', null, 'na@na.com', 'Co', null, 'Realtor'); System.assert(false, 'expected an error'); } catch (AuraHandledException e) { assertHas(e, 'phone number or email'); }
            System.assertEquals(0, ExternalLoPortalController.getRealtors('all', null).size());
            System.assert(!RecordAccessGuard.readable(new Set<Id>{ borrowerId }).contains(borrowerId));
        }
        System.assertEquals(accountsBefore, accountCount());
        System.assertEquals(0, [SELECT COUNT() FROM AccountShare WHERE RowCause = 'Manual' AND AccountId = :borrowerId]);
    }

    @IsTest
    static void newPartnerIsCreatedOwnedAndTagged() {
        Id newId;
        System.runAs(lo('p5.loa')) {
            ExternalLoPartnerService.CreatePartnerResult r = ExternalLoPortalController.createPartner(
                'Carla Cpa', '(321) 555-0303', 'p5.cpa@example.com', 'Numbers LLC', 'Tampa', 'CPA');
            System.assertEquals('created', r.status);
            newId = r.accountId;
            ExternalLoPortalService.PartnerRow row = ExternalLoPortalController.getRealtors('all', null)[0];
            System.assertEquals('CPA', row.partnerType);
            System.assertEquals('Numbers LLC', row.company);
            System.assertEquals('321-555-0303', row.phone);
        }
        Account created = [SELECT OwnerId, BD_Industry__c, Type__c, FirstName, LastName FROM Account WHERE Id = :newId];
        System.assertEquals(lo('p5.loa').Id, created.OwnerId);
        System.assertEquals('CPA', created.BD_Industry__c);
        System.assertEquals('Other', created.Type__c);
        System.assertEquals('Carla', created.FirstName);
        System.assertEquals(false, [SELECT Granted_Share__c FROM External_User_Assignment__c].Granted_Share__c, 'owner needs no share');

        System.runAs(lo('p5.lob')) {
            // The new partner is now a partner-type duplicate for everyone else.
            ExternalLoPartnerService.CreatePartnerResult again = ExternalLoPortalController.createPartner(
                'Carla C', '321 555 0303', null, 'Numbers', null, 'CPA');
            System.assertEquals('match', again.status);
            System.assertEquals(newId, again.matches[0].id);
        }
        System.runAs(lo('p5.loa')) {
            ExternalLoPortalController.untagPartner(newId);
            System.assert(RecordAccessGuard.readable(new Set<Id>{ newId }).contains(newId), 'owner keeps access');
        }
    }

    @IsTest
    static void untagNeverRemovesAccessGrantedAnotherWay() {
        Id titleId = account('Title');
        User loA = lo('p5.loa');
        insert new AccountShare(AccountId = titleId, UserOrGroupId = loA.Id, AccountAccessLevel = 'Read',
            OpportunityAccessLevel = 'None', CaseAccessLevel = 'None', RowCause = 'Manual');
        System.runAs(loA) {
            ExternalLoPortalController.linkPartner(titleId); // search "Link" = tag a partner I can read
            System.assertEquals('Title Agent', ExternalLoPortalController.getRealtors('all', null)[0].partnerType);
            ExternalLoPortalController.untagPartner(titleId);
            System.assert(RecordAccessGuard.readable(new Set<Id>{ titleId }).contains(titleId), 'admin share survives');
        }
        System.assertEquals(1, [SELECT COUNT() FROM AccountShare WHERE RowCause = 'Manual' AND AccountId = :titleId]);
    }

    // ------------------------------------------------------------------ CSV import

    @IsTest
    static void partnerCsvFollowsTheSameRules() {
        Id realtorId = account('Realtor');
        Integer accountsBefore = accountCount();
        String csv = 'Full Name,Phone Number,E-mail Address,Brokerage,Type\n'
            + 'Rita Realtor,,' + REALTOR_EMAIL + ',Sunshine Realty,Realtor\n'
            + 'Bea Borrower,,' + BORROWER_EMAIL + ',X,Realtor\n'
            + '"New, Agent",(352) 555-0404,,"Line one\nline two",Insurance\n'
            + 'Same Person,352-555-0404,,Other Co,Insurance\n'
            + 'No Contact,,na@na.com,Co,Realtor\n';
        ExternalLoCsvImportService.ImportResult result;
        System.runAs(lo('p5.loa')) {
            result = ExternalLoWorkspaceController.importCsv('partner', csv);
            System.assertEquals(2, ExternalLoPortalController.getRealtors('all', null).size());
        }
        System.assertEquals(2, result.successCount, result.successes + ' / ' + result.errors);
        System.assertEquals(3, result.errorCount);
        System.assertEquals(LoWsPartnerTagService.ADMIN_MESSAGE, result.errors[0].message);
        System.assert(result.errors[1].message.startsWith('Same person as row 4'), result.errors[1].message);
        System.assertEquals(accountsBefore + 1, accountCount(), 'only the new agent is created');
        Account created = [SELECT BD_Industry__c, Company__c, LastName FROM Account WHERE CreatedDate = TODAY AND PersonMobilePhone = '352-555-0404'];
        System.assertEquals('Insurance Agent', created.BD_Industry__c);
        // Company__c is single-line text, so Salesforce turns the newline into a space.
        System.assert(created.Company__c.startsWith('Line one'), 'quoted newline stayed inside the cell');
        System.assertEquals(1, [SELECT COUNT() FROM AccountShare WHERE RowCause = 'Manual' AND AccountId = :realtorId]);
    }

    @IsTest
    static void pastClientCsvKeepsLoanHistory() {
        User loA = lo('p5.loa');
        String csv = 'Name,Email,Type,Closing Date,Purchase Price,Loan Purpose,Loan Amount\n'
            + 'Hal History,p5.hist@example.com,Past Client,3/15/2024,"$425,000",Purchase,"$382,500"\n'
            + 'Bad Date,p5.baddate@example.com,Past Client,13/45/2024,,,\n';
        ExternalLoCsvImportService.ImportResult result;
        System.runAs(loA) {
            result = ExternalLoWorkspaceController.importCsv('consumer', csv);
        }
        System.assertEquals(2, result.successCount, String.valueOf(result.errors));
        Account client = [SELECT Most_Recent_Closing_Date__c, Purchase_Price__pc, Most_Recent_Loan_Purpose__c, Most_Recent_Loan_Amount__c
                          FROM Account WHERE PersonEmail = 'p5.hist@example.com'];
        System.assertEquals(Date.newInstance(2024, 3, 15), client.Most_Recent_Closing_Date__c);
        System.assertEquals(425000, client.Purchase_Price__pc);
        System.assertEquals('Purchase', client.Most_Recent_Loan_Purpose__c);
        System.assertEquals(382500, client.Most_Recent_Loan_Amount__c);
        // An unreadable date is left blank; the row still imports.
        System.assertEquals(null, [SELECT Most_Recent_Closing_Date__c FROM Account WHERE PersonEmail = 'p5.baddate@example.com'].Most_Recent_Closing_Date__c);
        System.assertEquals(Date.newInstance(2025, 1, 2), ExternalLoCsvImportService.parseDate('2025-01-02'));
        System.assertEquals(Date.newInstance(2023, 7, 4), ExternalLoCsvImportService.parseDate('7/4/23'));
    }

    @IsTest
    static void consumerCsvRefusesSomeoneElsesPeople() {
        User loA = lo('p5.loa');
        User loB = lo('p5.lob');
        insert new List<Lead>{
            new Lead(FirstName = 'Own', LastName = 'Lead', Company = 'Own', Status = 'New', Email = 'p5.own@example.com', OwnerId = loA.Id),
            new Lead(FirstName = 'Other', LastName = 'Lead', Company = 'Other', Status = 'Nurturing', Email = 'p5.other@example.com', OwnerId = loB.Id)
        };
        String csv = 'First Name,Last Name,Email,Phone,Type,City\n'
            + 'Own,Lead,p5.own@example.com,,Past Client,\n'
            + 'Other,Lead,p5.other@example.com,,Past Client,\n'
            + 'Bea,Borrower,,' + BORROWER_PHONE + ',Past Client,\n'
            + 'Fresh,Client,p5.fresh@example.com,,Past Client,Ocala\n'
            + 'Fresh,Again,P5.Fresh@example.com,,Past Client,\n'
            + 'New,Prospect,p5.prospect@example.com,,Purchase,\n';
        ExternalLoCsvImportService.ImportResult result;
        System.runAs(loA) {
            result = ExternalLoWorkspaceController.importCsv('consumer', csv);
        }
        // Phase 6: B's Nurturing lead is taken over (still a lead, Lead Source Past Client).
        System.assertEquals(3, result.successCount, String.valueOf(result.errors));
        System.assertEquals(3, result.errorCount, String.valueOf(result.errors));
        System.assertEquals(LoWsPartnerTagService.CONFLICT_OWN_LEAD, result.errors[0].message);
        System.assertEquals(LoWsLeadIntakeService.BLOCKED_MESSAGE, result.errors[1].message);
        System.assert(result.errors[2].message.startsWith('Same person'), result.errors[2].message);
        Lead taken = [SELECT OwnerId, Status, LeadSource FROM Lead WHERE Email = 'p5.other@example.com'];
        System.assertEquals(loA.Id, taken.OwnerId);
        System.assertEquals('Past Client', taken.LeadSource);

        // The past client is a borrower Person Account I own, never a New lead.
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'p5.fresh@example.com']);
        Account client = [SELECT OwnerId, Type__c, Group__pc, RecordType.DeveloperName, BillingCity
                          FROM Account WHERE PersonEmail = 'p5.fresh@example.com'];
        System.assertEquals(loA.Id, client.OwnerId);
        System.assertEquals('Borrower Account', client.Type__c);
        System.assert(client.Group__pc.split(';').contains('Client'));
        System.assertEquals('PersonAccount', client.RecordType.DeveloperName);
        System.assertEquals('Ocala', client.BillingCity);
        // Not a past client: still a lead.
        System.assertEquals('New', [SELECT Status FROM Lead WHERE Email = 'p5.prospect@example.com' AND OwnerId = :loA.Id].Status);

        String again = 'Name,Email,Type\nFresh Client,p5.fresh@example.com,Past Client\n';
        System.runAs(loA) {
            ExternalLoCsvImportService.ImportResult mine = ExternalLoWorkspaceController.importCsv('consumer', again);
            System.assertEquals(LoWsPartnerTagService.CONFLICT_OWN_CLIENT, mine.errors[0].message);
            List<ExternalLoPortalService.LeadRow> rows = ExternalLoPortalController.getPastClientRows(null);
            System.assertEquals(1, rows.size());
            System.assertEquals('pastClients', rows[0].openView);
            System.assertEquals('Fresh Client', rows[0].name);
            // The in-workspace past client page and the shell's Account routing, as the owning outside LO.
            ExternalLoPortalService.PastClientDetail page = ExternalLoPortalController.getPastClientDetail(rows[0].id);
            System.assertEquals(true, page.isPastClient);
            System.assertEquals('pastClients', ExternalLoPortalController.getAccountWorkspaceView(rows[0].id));
        }
        System.runAs(loB) {
            ExternalLoCsvImportService.ImportResult theirs = ExternalLoWorkspaceController.importCsv('consumer', again);
            System.assertEquals(LoWsLeadIntakeService.BLOCKED_MESSAGE, theirs.errors[0].message);
            System.assertEquals(0, ExternalLoPortalController.getPastClientRows(null).size());
        }
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'p5.fresh@example.com'], 'no duplicate');
    }

    @IsTest
    static void deletingATaggedPartnerIsNotBlocked() {
        Id realtorId = account('Realtor');
        Id titleId = account('Title');
        System.runAs(lo('p5.loa')) {
            ExternalLoPortalController.tagPartner(realtorId, REALTOR_EMAIL, null);
            ExternalLoPortalController.tagPartner(titleId, 'p5.title@example.com', null);
            System.assertEquals(2, ExternalLoPortalController.getRealtors('all', null).size());
        }
        delete new Account(Id = realtorId); // used to fail: Contact__c was a Restrict lookup
        External_User_Assignment__c orphan = [SELECT Contact__c FROM External_User_Assignment__c WHERE Stage__c = 'Prospect' AND Contact__c = null];
        System.assertEquals(null, orphan.Contact__c);
        System.runAs(lo('p5.loa')) {
            List<ExternalLoPortalService.PartnerRow> rows = ExternalLoPortalController.getRealtors('all', null);
            System.assertEquals(1, rows.size(), 'the orphaned tag is ignored');
            System.assertEquals(titleId, rows[0].id);
            System.assertEquals(1, ExternalLoPortalController.getRealtorProspects(null).size());
            System.assertNotEquals(null, ExternalLoPortalController.getNavBadges());
            try { ExternalLoPortalController.setPartnerStage(realtorId, 'Met'); System.assert(false, 'expected an error'); } catch (AuraHandledException e) { assertHas(e, 'not on your list'); }
            try { ExternalLoPortalController.untagPartner(realtorId); System.assert(false, 'expected an error'); } catch (AuraHandledException e) { assertHas(e, 'not on your list'); }
            ExternalLoPortalController.setPartnerStage(titleId, 'Met');
            ExternalLoPortalController.untagPartner(titleId);
            System.assertEquals(0, ExternalLoPortalController.getRealtors('all', null).size());
        }
    }

    @IsTest
    static void lineCountIgnoresQuotedNewlines() {
        System.assertEquals(3, ExternalLoCsvImportService.estimatedLineCount('h\na\nb'));
        System.assertEquals(2, ExternalLoCsvImportService.estimatedLineCount('h\n"multi\nline\ncell",x'));
        Map<String, Integer> idx = ExternalLoCsvParser.headerIndex(new List<String>{ 'phonenumber', 'phone', 'brokerage' });
        System.assertEquals(1, idx.get('phone'), 'exact column wins over alias');
        System.assertEquals(2, idx.get('company'));
        System.assertEquals('Title Agent', LoWsPartnerTagService.industryFor('title'));
        System.assertEquals('Realtor', LoWsPartnerTagService.industryFor('Realtor Prospect'));
        System.assertEquals('Attorney', LoWsPartnerTagService.industryFor('attorney'));
        System.assertEquals('Other', LoWsPartnerTagService.industryFor('Plumber'));
    }

    // ------------------------------------------------------------------ past clients

    @IsTest
    static void pastClientsAreMyClosedLoans() {
        User loA = lo('p5.loa');
        Id borrowerId = account('Borrower');
        Transaction__c closed = new Transaction__c(Name = 'P5 Closed', Status__c = 'Post-Closed',
            Loan_Officer__c = loA.Id, Borrower_Name__c = borrowerId);
        Transaction__c lost = new Transaction__c(Name = 'P5 Lost', Status__c = 'Cancelled',
            Loan_Officer__c = loA.Id, Borrower_Name__c = borrowerId);
        Account client;
        System.runAs(loA) {
            // Inserted as the LO, as the import does: Account automation runs as an outside LO.
            client = LoWsPartnerTagService.newPastClient('Cal', 'Client', null, '(407) 555-0909', null, null, null);
            insert client;
        }
        Transaction__c clientLoan = new Transaction__c(Name = 'P5 Client Loan', Status__c = 'Funding',
            Loan_Officer__c = loA.Id, Borrower_Name__c = client.Id);
        insert new List<Transaction__c>{ closed, lost, clientLoan };
        System.runAs(loA) {
            List<ExternalLoPortalService.LeadRow> rows = ExternalLoPortalController.getPastClientRows(null);
            System.assertEquals(2, rows.size(), 'Cal is a loan borrower and an imported client: shown once');
            Map<Id, ExternalLoPortalService.LeadRow> byId = new Map<Id, ExternalLoPortalService.LeadRow>();
            for (ExternalLoPortalService.LeadRow r : rows) byId.put(r.id, r);
            System.assertEquals('loans', byId.get(closed.Id).openView);
            System.assertEquals('Bea Borrower', byId.get(closed.Id).name);
            System.assertEquals('Cal Client', byId.get(clientLoan.Id).name);
        }
        System.runAs(lo('p5.lob')) {
            System.assertEquals(0, ExternalLoPortalController.getPastClientRows(null).size());
        }
    }

    // ------------------------------------------------------------------ helpers

    private static void assertHas(Exception e, String fragment) {
        System.assert(e.getMessage().contains(fragment), e.getMessage());
    }

    private static Integer accountCount() {
        return [SELECT COUNT() FROM Account WHERE IsPersonAccount = true];
    }

    private static Id account(String lastName) {
        return [SELECT Id FROM Account WHERE LastName = :lastName AND PersonEmail LIKE 'p5.%' LIMIT 1].Id;
    }

    private static User lo(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias.right(8)];
    }

    private static User newExternalLo(String alias) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = alias + suffix + '@reach-p5.test',
            Email = alias + '@reach-p5.test',
            LastName = alias,
            Alias = alias.right(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}