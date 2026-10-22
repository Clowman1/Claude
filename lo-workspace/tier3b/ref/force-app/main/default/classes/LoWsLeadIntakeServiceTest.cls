/**
 * Phase 6 (LO Workspace lead intake), run as real outside loan officers (External Loan Officer
 * Profile + role, External_LO_Access + External_LO_Perfect_Day_Access).
 *
 * Proves: someone else's Nurturing lead is taken over (owner, status New, Loan Partner and its share
 * cleared, Lead Source replaced past the lock, also as the Automated Process webhook subscriber); an
 * actively worked lead or someone else's client is refused with no name and an admin alert; my own
 * lead says "already in your list"; na@na.com never matches; the webhook authenticates, logs and
 * notifies; landing-page leads lead the Perfect Day queue; the Lead Source lock still blocks others.
 */
@IsTest
private class LoWsLeadIntakeServiceTest {

    static final String SECRET = 'p6-secret';

    @TestSetup
    static void setup() {
        User loA = newExternalLo('p6.loa');
        User loB = newExternalLo('p6.lob');
        // B's default Loan Partner is the admin running the test, so B's leads carry a Loan Partner + share.
        loB.Loan_Partner__c = UserInfo.getUserId();
        // A User insert with a Loan Partner enqueues a self-chaining share sync; chaining fails in tests.
        LoanPartnerLeadShareService.bypassQueueableEnqueueInTests = true;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ loA, loB };
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('External_LO_Access', 'External_LO_Perfect_Day_Access')]) {
                psas.add(new PermissionSetAssignment(AssigneeId = loA.Id, PermissionSetId = ps.Id));
                psas.add(new PermissionSetAssignment(AssigneeId = loB.Id, PermissionSetId = ps.Id));
            }
            // B is an oversight manager for the alert-recipient test.
            psas.add(new PermissionSetAssignment(AssigneeId = loB.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'LO_Workspace_Oversight'].Id));
            insert psas;
        }
        Lead nora = lead('Nora', 'Nurture', 'Nurturing', 'p6.nurture@example.com', '(407) 555-0611', loB.Id);
        // An old lead team the takeover must clear.
        nora.Biz_Dev__c = 'Biz Dev - Reach'; // Nurturing, so ReachNewLeadWebhook does not qualify it
        nora.Scenario_Manager__c = UserInfo.getUserId();
        nora.Other_Lead_Team_Member__c = UserInfo.getUserId();
        insert new List<Lead>{
            nora,
            lead('Walt', 'Working', 'Working', 'p6.working@example.com', '(407) 555-0622', loB.Id),
            lead('Olive', 'Own', 'New', 'p6.own@example.com', null, loA.Id),
            lead('Pat', 'Placeholder', 'Working', 'na@na.com', null, loB.Id)
        };
        insert new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = 'Cora', LastName = 'Client', PersonEmail = 'p6.client@example.com', Type__c = 'Borrower Account'
        );
    }

    // ------------------------------------------------------------------ Add lead (manual)

    @IsTest
    static void addLeadTakesOverSomeoneElsesNurturingLead() {
        Lead before = byEmail('p6.nurture@example.com');
        System.assertEquals(UserInfo.getUserId(), before.Loan_Partner__c, 'setup: B default Loan Partner stamped');
        System.assertEquals(1, manualShares(before.Id, UserInfo.getUserId()), 'setup: Loan Partner share exists');

        ExternalLoLeadService.CreateLeadResult r;
        Test.startTest();
        System.runAs(lo('p6.loa')) {
            // LO Workspace Add lead (phase9contact): first/last, phone, email and purpose are required.
            r = addLead('Nora', 'Nurture', '(407) 555-0681', 'P6.Nurture@example.com', 'Personal Referral');
        }
        Test.stopTest();

        System.assertEquals(before.Id, r.leadId, 'no new lead: the existing one is taken');
        Lead after = byEmail('p6.nurture@example.com');
        System.assertEquals(lo('p6.loa').Id, after.OwnerId);
        System.assertEquals('New', after.Status);
        System.assertEquals('Personal Referral', after.LeadSource, 'Lead Source replaced');
        System.assertEquals(null, after.Loan_Partner__c, 'Loan Partner cleared');
        System.assertNotEquals(null, after.LO_Takeover_At__c);
        assertTeamCleared(after);
        System.assertEquals(0, manualShares(before.Id, UserInfo.getUserId()), 'old Loan Partner keeps no access');
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = 'p6.nurture@example.com']);
    }

    @IsTest
    static void addLeadRefusesWorkedLeadsButNotClientsAndAlertsAdmins() {
        System.runAs(lo('p6.loa')) {
            expectError('Walt Working', '(407) 555-0682', 'p6.working@example.com', LoWsLeadIntakeService.BLOCKED_MESSAGE);
            expectError('Walt Again', '407.555.0622', 'p6.waltagain@example.com', LoWsLeadIntakeService.BLOCKED_MESSAGE);
            expectError('Olive Own', '(407) 555-0684', 'p6.own@example.com', LoWsPartnerTagService.CONFLICT_OWN_LEAD);
            // Someone else's client (Person Account) never blocks a new lead.
            addLead('Cora', 'Client', '(407) 555-0683', 'p6.client@example.com', 'Website');
        }
        System.assertEquals(lo('p6.loa').Id, [SELECT OwnerId FROM Lead WHERE Email = 'p6.client@example.com'].OwnerId);
        LoWsLeadIntakeService.eventsPerRun = 10;
        Test.getEventBus().deliver();
        List<Custom_Log__c> alerts = [SELECT Data__c FROM Custom_Log__c WHERE Source__c = :LoWsLeadIntakeService.ALERT_LOG_SOURCE];
        System.assertEquals(2, alerts.size(), 'one admin alert per refused add');
        System.assert(alerts[0].Data__c.contains('Add lead'), alerts[0].Data__c);
        System.assertEquals('Working', byEmail('p6.working@example.com').Status, 'untouched');
        System.assertEquals(lo('p6.lob').Id, byEmail('p6.working@example.com').OwnerId);
    }

    @IsTest
    static void placeholderEmailNeverMatches() {
        // Add lead now refuses na@na.com outright (phase9contact); the duplicate decision still ignores it
        // for the webhook and CSV, which keep their own rules.
        LoWsLeadIntakeService.Verdict v = LoWsLeadIntakeService.decide(
            lo('p6.loa').Id, new List<String>{ 'na@na.com' }, new List<String>{ '(352) 555-0699' })[0];
        System.assertEquals(null, v.message, 'na@na.com does not match the Working placeholder lead');
        System.assertEquals(null, v.takeoverLeadId);
        System.runAs(lo('p6.loa')) {
            try {
                addLead('Pam', 'Fresh', '(352) 555-0699', 'na@na.com', null);
                System.assert(false, 'Add lead must refuse the placeholder');
            } catch (DomainException e) {
                System.assert(e.getMessage().contains('real email'), e.getMessage());
            }
        }
    }

    @IsTest
    static void thirtyDayFollowUpBlocksInsteadOfTakeover() {
        System.assertEquals(true, LoWsLeadIntakeService.isNurture('Nurturing'));
        System.assertEquals(false, LoWsLeadIntakeService.isNurture('30 Day + Follow Up'), 'actively worked');
        Lead t = lead('Thea', 'Thirty', '30 Day + Follow Up', 'p6.thirty@example.com', '(407) 555-0633', lo('p6.lob').Id);
        insert t;
        LoWsLeadIntakeService.Verdict v = LoWsLeadIntakeService.decide(
            lo('p6.loa').Id, new List<String>{ 'p6.thirty@example.com' }, new List<String>{ null })[0];
        System.assertEquals(null, v.takeoverLeadId, 'never taken over');
        System.assertEquals(LoWsLeadIntakeService.BLOCKED_MESSAGE, v.message);
    }

    @IsTest
    static void leadSourceLockStillBlocksEveryoneElse() {
        Lead l = byEmail('p6.working@example.com');
        insert new LeadShare(LeadId = l.Id, UserOrGroupId = lo('p6.loa').Id, LeadAccessLevel = 'Edit', RowCause = 'Manual');
        System.runAs(lo('p6.loa')) {
            try {
                update new Lead(Id = l.Id, LeadSource = 'Zillow');
                System.assert(false, 'expected the lock');
            } catch (DmlException e) {
                System.assert(e.getMessage().contains('Lead Source is locked'), e.getMessage());
            }
        }
    }

    // ------------------------------------------------------------------ CSV

    @IsTest
    static void csvTakesOverAndRefusesInOnePass() {
        String csv = 'First Name,Last Name,Email,Phone\n'
            + 'Nora,Nurture,,407-555-0611\n'
            + 'Nora,Twice,p6.nurture@example.com,\n'
            + 'Walt,Working,p6.working@example.com,\n'
            + 'Fresh,Prospect,p6.fresh@example.com,\n';
        ExternalLoCsvImportService.ImportResult result;
        Test.startTest();
        System.runAs(lo('p6.loa')) {
            result = ExternalLoWorkspaceController.importCsv('consumer', csv);
        }
        Test.stopTest();
        System.assertEquals(2, result.successCount, String.valueOf(result.errors));
        System.assertEquals(2, result.errorCount, String.valueOf(result.errors));
        System.assert(result.errors[0].message.startsWith('Same person'), result.errors[0].message);
        System.assertEquals(LoWsLeadIntakeService.BLOCKED_MESSAGE, result.errors[1].message);
        Lead taken = byEmail('p6.nurture@example.com');
        System.assertEquals(lo('p6.loa').Id, taken.OwnerId);
        System.assertEquals('Website', taken.LeadSource, 'no new source in the file: the old one stays');
        System.assertEquals(lo('p6.loa').Id, byEmail('p6.fresh@example.com').OwnerId);
    }

    // ------------------------------------------------------------------ webhook

    @IsTest
    static void webhookCreatesLeadNotifiesAndLeadsPerfectDay() {
        User loA = lo('p6.loa');
        Integer status = post(SECRET, new Map<String, Object>{
            'loEmail' => [SELECT Username FROM User WHERE Id = :loA.Id].Username,
            'name' => 'Lana Landing', 'email' => 'p6.landing@example.com', 'phone' => '(352) 555-0677',
            'loanPurpose' => 'purchase', 'leadSource' => 'Not A Real Source', 'notes' => 'Wants to buy in spring'
        });
        System.assertEquals(202, status);
        Test.getEventBus().deliver();

        Lead l = byEmail('p6.landing@example.com');
        System.assertEquals(loA.Id, l.OwnerId);
        System.assertEquals('New', l.Status);
        System.assertEquals(LoWsLeadIntakeService.LANDING_PAGE_SOURCE, l.LeadSource, 'unknown source falls back');
        System.assertEquals(null, l.Loan_Partner__c, 'outside LOs get no default Loan Partner');
        Custom_Log__c log = [SELECT Lead__c, Data__c, Errors__c FROM Custom_Log__c WHERE Source__c = :LoWsLeadIntakeService.LOG_SOURCE];
        System.assertEquals(l.Id, log.Lead__c);
        System.assertEquals(null, log.Errors__c);
        System.assert(!log.Data__c.contains('p6.landing@example.com'), 'no contact details in a success log');

        System.runAs(loA) {
            // Olive (New, created earlier) would normally be first; the landing-page lead jumps the queue.
            List<Lead> queue = LoWsLeadIntakeService.landingPageFirst(
                LoWsLeadIntakeService.recentLandingPageLeadIds(loA.Id),
                new List<Lead>{ byEmail('p6.own@example.com') });
            System.assertEquals(l.Id, queue[0].Id);
            System.assertEquals(2, queue.size());
            PerfectDayHomeModels.PerfectDayHomeData home = PerfectDayHomeService.getHomeData();
            System.assertEquals(l.Id, home.upNext.recordId);
            System.assertEquals('New lead from your landing page', home.upNext.detail);
        }
    }

    @IsTest
    static void webhookTakeoverRunsPastTheLockAsAutomatedProcess() {
        post(SECRET, new Map<String, Object>{
            'loEmail' => [SELECT Username FROM User WHERE Id = :lo('p6.loa').Id].Username,
            'firstName' => 'Nora', 'lastName' => 'Nurture', 'phone' => '407 555 0611'
        });
        Test.getEventBus().deliver();
        Lead l = byEmail('p6.nurture@example.com');
        System.assertEquals(lo('p6.loa').Id, l.OwnerId);
        System.assertEquals(LoWsLeadIntakeService.LANDING_PAGE_SOURCE, l.LeadSource, 'replaced although the subscriber is not the owner');
        System.assertEquals('New', l.Status);
        assertTeamCleared(l);
        System.assertEquals(l.Id, [SELECT Lead__c FROM Custom_Log__c WHERE Source__c = :LoWsLeadIntakeService.LOG_SOURCE].Lead__c);
    }

    @IsTest
    static void webhookBlocksWorkedLeadAndUnknownLo() {
        String loUsername = [SELECT Username FROM User WHERE Id = :lo('p6.loa').Id].Username;
        post(SECRET, new Map<String, Object>{ 'loEmail' => loUsername, 'name' => 'Walt Working', 'email' => 'p6.working@example.com' });
        Test.getEventBus().deliver();
        post(SECRET, new Map<String, Object>{ 'loEmail' => 'nobody@reach-p6.test', 'name' => 'Ghost', 'email' => 'p6.ghost@example.com' });
        Test.getEventBus().deliver();
        post(SECRET, new Map<String, Object>{ 'loEmail' => loUsername, 'name' => 'Olive Own', 'email' => 'p6.own@example.com' });
        Test.getEventBus().deliver();

        System.assertEquals(lo('p6.lob').Id, byEmail('p6.working@example.com').OwnerId);
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'p6.ghost@example.com']);
        System.assertEquals(1, [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = :LoWsLeadIntakeService.ALERT_LOG_SOURCE]);
        Map<String, Custom_Log__c> logs = new Map<String, Custom_Log__c>();
        for (Custom_Log__c c : [SELECT Data__c, Errors__c, Lead__c FROM Custom_Log__c WHERE Source__c = :LoWsLeadIntakeService.LOG_SOURCE]) {
            logs.put(c.Data__c.contains('Blocked') ? 'blocked' : c.Errors__c != null ? 'unknown' : 'own', c);
        }
        System.assertEquals(3, logs.size(), String.valueOf(logs));
        System.assert(logs.get('unknown').Errors__c.contains('No single active user'));
        System.assertEquals(byEmail('p6.own@example.com').Id, logs.get('own').Lead__c, 'own lead re-submitted: linked for Perfect Day');
    }

    @IsTest
    static void webhookRejectsBadCalls() {
        LoLandingPageWebhook.testSecret = ''; // simulate "no Default record" regardless of the org's real config
        System.assertEquals(503, post(null, new Map<String, Object>{ 'loEmail' => 'x@y.z' }), 'not configured');
        LoLandingPageWebhook.testSecret = SECRET;
        System.assertEquals(401, post('wrong', new Map<String, Object>{ 'loEmail' => 'x@y.z' }));
        System.assertEquals(401, post(SECRET.toUpperCase(), new Map<String, Object>{ 'loEmail' => 'x@y.z' }), 'key is case-sensitive');
        System.assertEquals(400, post(SECRET, new Map<String, Object>{ 'name' => 'No LO' }));
        System.assertEquals(400, post(SECRET, new Map<String, Object>{ 'loEmail' => 'x@y.z', 'kind' => 'alert' }));
        System.assertEquals(400, rawPost(SECRET, '[1,2]'));
        System.assertEquals(6, [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'LO Landing Page Rejected']);
        System.assertEquals(null, LoWsLeadIntakeService.resolveLo(null));
    }

    @IsTest
    static void alertsGoOnlyToOversightHolders() {
        Set<String> ids = LoWsLeadIntakeService.oversightUserIds();
        System.assert(ids.contains(lo('p6.lob').Id), 'holder of LO_Workspace_Oversight');
        System.assert(!ids.contains(lo('p6.loa').Id), 'non-holder');
    }

    // ------------------------------------------------------------------ helpers

    private static void assertTeamCleared(Lead l) {
        System.assertEquals(null, l.Biz_Dev__c);
        System.assertEquals(null, l.Scenario_Manager__c);
        System.assertEquals(null, l.Other_Lead_Team_Member__c);
    }

    private static Integer post(String key, Map<String, Object> body) {
        if (key != null) LoLandingPageWebhook.testSecret = SECRET;
        return rawPost(key, JSON.serialize(body));
    }

    private static Integer rawPost(String key, String body) {
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/lo-landing-page';
        req.requestBody = Blob.valueOf(body);
        if (key != null) req.headers.put('x-reach-webhook-key', key);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        LoLandingPageWebhook.receive();
        return RestContext.response.statusCode;
    }

    private static void expectError(String name, String phone, String email, String message) {
        try {
            addLead(name.substringBefore(' '), name.substringAfter(' '), phone, email, 'Website');
            System.assert(false, 'expected an error for ' + name);
        } catch (DomainException e) {
            System.assert(e.getMessage().contains(message), e.getMessage());
        }
    }

    private static ExternalLoLeadService.CreateLeadResult addLead(String first, String last, String phone, String email, String source) {
        ExternalLoLeadService.CreateLeadRequest r = new ExternalLoLeadService.CreateLeadRequest();
        r.firstName = first;
        r.lastName = last;
        r.phone = phone;
        r.email = email;
        r.purpose = 'Purchase';
        r.leadSource = source;
        r.forceCreate = false;
        return ExternalLoLeadService.createLead(r);
    }

    private static Lead lead(String first, String last, String status, String email, String phone, Id ownerId) {
        return new Lead(
            RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId(),
            FirstName = first, LastName = last, Company = last + ' Household', Status = status,
            Email = email, Phone = phone, OwnerId = ownerId, LeadSource = 'Website'
        );
    }

    private static Lead byEmail(String email) {
        return [SELECT Id, OwnerId, Status, LeadSource, Loan_Partner__c, LO_Takeover_At__c, Biz_Dev__c, Scenario_Manager__c, Other_Lead_Team_Member__c FROM Lead WHERE Email = :email LIMIT 1];
    }

    private static Integer manualShares(Id leadId, Id userId) {
        return [SELECT COUNT() FROM LeadShare WHERE LeadId = :leadId AND UserOrGroupId = :userId AND RowCause = 'Manual'];
    }

    private static User lo(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias.right(8)];
    }

    private static User newExternalLo(String alias) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = alias + suffix + '@reach-p6.test',
            Email = alias + '@reach-p6.test',
            LastName = alias,
            Alias = alias.right(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}