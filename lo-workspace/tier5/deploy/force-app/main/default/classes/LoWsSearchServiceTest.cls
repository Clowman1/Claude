/**
 * LO Workspace header search, run as two real outside loan officers (same setup as LoWsPartnerTagServiceTest).
 * Proves: each LO finds only their own leads (consumer, incl. nurtured), loans, borrowers / past clients and
 * tagged partners; the other LO's records never come back; name, email, full phone and last-4 phone all
 * match; terms under 2 characters return nothing.
 *
 * with sharing on purpose: the runAs assertions must see exactly what each LO can see.
 */
@IsTest
private with sharing class LoWsSearchServiceTest {

    @TestSetup
    static void setup() {
        User loA = newExternalLo('srch.loa');
        User loB = newExternalLo('srch.lob');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ loA, loB };
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('External_LO_Access', 'External_LO_Perfect_Day_Access')]) {
                psas.add(new PermissionSetAssignment(AssigneeId = loA.Id, PermissionSetId = ps.Id));
                psas.add(new PermissionSetAssignment(AssigneeId = loB.Id, PermissionSetId = ps.Id));
            }
            insert psas;
        }
        Map<String, Schema.RecordTypeInfo> leadTypes = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
        Id consumer = leadTypes.get('Consumer_Lead_record_type').getRecordTypeId();
        Id realtorLead = leadTypes.get('Realtor_Lead_record_type').getRecordTypeId();
        insert new List<Lead>{
            new Lead(RecordTypeId = consumer, FirstName = 'Zed', LastName = 'Searchable', Company = 'Zed', Status = 'New',
                Email = 'zed.search@example.com', Phone = '561-589-4420', OwnerId = loA.Id),
            new Lead(RecordTypeId = consumer, FirstName = 'Nina', LastName = 'Searchable', Company = 'Nina', Status = 'Nurturing',
                Email = 'nina.search@example.com', OwnerId = loA.Id),
            new Lead(RecordTypeId = realtorLead, FirstName = 'Rex', LastName = 'Searchable', Company = 'Rex', Status = 'New',
                Email = 'rex.search@example.com', OwnerId = loA.Id),
            new Lead(RecordTypeId = consumer, FirstName = 'Zara', LastName = 'Searchable', Company = 'Zara', Status = 'New',
                Email = 'zara.search@example.com', Phone = '772-555-4420', OwnerId = loB.Id)
        };
        Id personRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        // Partners owned by the admin running the test, i.e. by somebody other than either outside LO.
        insert new List<Account>{
            new Account(RecordTypeId = personRt, FirstName = 'Rita', LastName = 'Searchable', PersonEmail = 'rita.search@example.com',
                Is_Realtor__c = true, Company__c = 'Sunshine Realty'),
            new Account(RecordTypeId = personRt, FirstName = 'Tom', LastName = 'Searchable', PersonEmail = 'tom.search@example.com',
                BD_Industry__c = 'Title Agent'),
            new Account(RecordTypeId = personRt, FirstName = 'Paul', LastName = 'Searchable', PersonEmail = 'paul.search@example.com',
                Is_Realtor__c = true)
        };
    }

    @IsTest
    static void leadsAreMineConsumerOnlyAndRouteByStatus() {
        System.runAs(lo('srch.loa')) {
            Map<String, LoWsSearchService.ResultItem> leads = byTitle(itemsIn(LoWsSearchService.search('Searchable'), 'leads'));
            System.assertEquals(new Set<String>{ 'Zed Searchable', 'Nina Searchable' }, leads.keySet(),
                'own consumer leads only: no realtor lead, nothing of LO B');
            System.assertEquals('leads', leads.get('Zed Searchable').view);
            System.assertEquals('nurtured', leads.get('Nina Searchable').view);

            System.assertEquals(new Set<String>{ 'Zed Searchable' }, byTitle(itemsIn(LoWsSearchService.search('zed.search@'), 'leads')).keySet(), 'email');
            System.assertEquals(new Set<String>{ 'Zed Searchable' }, byTitle(itemsIn(LoWsSearchService.search('(561) 589-4420'), 'leads')).keySet(), 'full phone');
            System.assertEquals(new Set<String>{ 'Zed Searchable' }, byTitle(itemsIn(LoWsSearchService.search('4420'), 'leads')).keySet(),
                'last 4: LO B has a lead ending 4420 too, never returned');
        }
        System.runAs(lo('srch.lob')) {
            System.assertEquals(new Set<String>{ 'Zara Searchable' }, byTitle(itemsIn(LoWsSearchService.search('Searchable'), 'leads')).keySet());
            System.assertEquals(0, LoWsSearchService.search('Zed').size(), 'no hint of LO A records');
        }
    }

    @IsTest
    static void loansAndBorrowersAreMine() {
        User loA = lo('srch.loa');
        User loB = lo('srch.lob');
        Transaction__c loanA;
        System.runAs(loA) {
            Account bo = LoWsPartnerTagService.newPastClient('Bo', 'Searchable', null, '407-555-0303', 'bo.search@example.com', null, null);
            bo.Group__pc = null; // a plain borrower: found through the loan, not as an imported client
            Account cal = LoWsPartnerTagService.newPastClient('Cal', 'Searchable', null, '407-555-0909', null, null, null);
            insert new List<Account>{ bo, cal };
            loanA = new Transaction__c(Name = 'Searchable - 1526000001', Loan_Number__c = '1526000001', Status__c = 'Funding',
                Loan_Officer__c = loA.Id, Borrower_Name__c = bo.Id);
            insert loanA;
        }
        System.runAs(loB) {
            Account bob = LoWsPartnerTagService.newPastClient('Bob', 'Searchable', null, '407-555-1303', null, null, null);
            insert bob;
            insert new Transaction__c(Name = 'Searchable - 1526000002', Loan_Number__c = '1526000002', Status__c = 'Funding',
                Loan_Officer__c = loB.Id, Borrower_Name__c = bob.Id);
        }
        Test.startTest();
        System.runAs(loA) {
            List<LoWsSearchService.ResultGroup> groups = LoWsSearchService.search('Searchable');
            List<LoWsSearchService.ResultItem> loans = itemsIn(groups, 'loans');
            System.assertEquals(1, loans.size(), 'only my loan');
            System.assertEquals(loanA.Id, loans[0].id);
            System.assertEquals('loans', loans[0].view);
            Map<String, LoWsSearchService.ResultItem> clients = byTitle(itemsIn(groups, 'clients'));
            System.assertEquals(new Set<String>{ 'Bo Searchable', 'Cal Searchable' }, clients.keySet(), 'no Bob (LO B)');
            System.assertEquals('pastClients', clients.get('Bo Searchable').view);

            System.assertEquals(loanA.Id, itemsIn(LoWsSearchService.search('1526000001'), 'loans')[0].id, 'loan number');
            System.assertEquals(0, itemsIn(LoWsSearchService.search('1526000002'), 'loans').size(), 'LO B loan number');
            List<LoWsSearchService.ResultGroup> byLast4 = LoWsSearchService.search('0303');
            System.assertEquals(new Set<String>{ 'Bo Searchable' }, byTitle(itemsIn(byLast4, 'clients')).keySet(), 'last 4, not Bob 1303');
            System.assertEquals(loanA.Id, itemsIn(byLast4, 'loans')[0].id, 'loan by borrower phone');
            System.assertEquals(new Set<String>{ 'Bo Searchable' }, byTitle(itemsIn(LoWsSearchService.search('bo.search@example.com'), 'clients')).keySet());
        }
        Test.stopTest();
    }

    @IsTest
    static void partnersAreMyTagsRoutedByKind() {
        Id rita = account('Rita');
        Id tom = account('Tom');
        Id paul = account('Paul');
        System.runAs(lo('srch.loa')) {
            LoWsPartnerTagService.tagAccounts(new Set<Id>{ rita, tom });
        }
        System.runAs(lo('srch.lob')) {
            LoWsPartnerTagService.tagAccounts(new Set<Id>{ rita, paul });
        }
        Test.startTest();
        System.runAs(lo('srch.loa')) {
            Map<String, LoWsSearchService.ResultItem> partners = byTitle(itemsIn(LoWsSearchService.search('Searchable'), 'partners'));
            System.assertEquals(new Set<String>{ 'Rita Searchable', 'Tom Searchable' }, partners.keySet(), 'never LO B tag (Paul)');
            System.assertEquals('realtors', partners.get('Rita Searchable').view);
            System.assertEquals(rita, partners.get('Rita Searchable').id);
            System.assertEquals('otherContacts', partners.get('Tom Searchable').view);
            System.assertEquals(1, itemsIn(LoWsSearchService.search('Sunshine'), 'partners').size(), 'company');
            System.assertEquals(0, itemsIn(LoWsSearchService.search('paul.search@'), 'partners').size());
        }
        Test.stopTest();
    }

    @IsTest
    static void shortOrBlankTermsReturnNothing() {
        System.runAs(lo('srch.loa')) {
            System.assertEquals(0, LoWsSearchService.search(null).size());
            System.assertEquals(0, LoWsSearchService.search('   ').size());
            System.assertEquals(0, LoWsSearchService.search(' Z ').size(), 'one character after trim');
            System.assertEquals(0, LoWsSearchService.search('qq-no-such-record').size());
        }
    }

    // ------------------------------------------------------------------ helpers

    private static List<LoWsSearchService.ResultItem> itemsIn(List<LoWsSearchService.ResultGroup> groups, String key) {
        for (LoWsSearchService.ResultGroup g : groups) {
            if (g.key == key) return g.items;
        }
        return new List<LoWsSearchService.ResultItem>();
    }

    private static Map<String, LoWsSearchService.ResultItem> byTitle(List<LoWsSearchService.ResultItem> items) {
        Map<String, LoWsSearchService.ResultItem> m = new Map<String, LoWsSearchService.ResultItem>();
        for (LoWsSearchService.ResultItem i : items) m.put(i.title, i);
        return m;
    }

    private static Id account(String firstName) {
        return [SELECT Id FROM Account WHERE FirstName = :firstName AND LastName = 'Searchable' LIMIT 1].Id;
    }

    private static User lo(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias.right(8)];
    }

    private static User newExternalLo(String alias) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = alias + suffix + '@reach-srch.test',
            Email = alias + '@reach-srch.test',
            LastName = alias,
            Alias = alias.right(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}
