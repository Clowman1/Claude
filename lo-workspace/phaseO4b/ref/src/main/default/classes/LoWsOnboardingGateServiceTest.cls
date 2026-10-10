/**
 * O2 first-login gate, run as real LO Workspace LOs: profile External Loan Officer Profile, role
 * External_Loan_Officer, permission set External_LO_Access assigned directly (not the PSG, which
 * recalculates after permset deploys). Zoom is an HttpCalloutMock on callout:Zoom_User_OAuth.
 */
@IsTest
private class LoWsOnboardingGateServiceTest {

    @TestSetup
    static void setup() {
        User loNew = newUser('o2.new', 'External Loan Officer Profile', 'External_Loan_Officer');
        User loDone = newUser('o2.done', 'External Loan Officer Profile', 'External_Loan_Officer');
        loDone.External_LO_Onboarding_Complete__c = true;
        loDone.ExtLO_Monthly_Unit_Goal__c = 4;
        User loRc = newUser('o2.rc', 'External Loan Officer Profile', 'External_Loan_Officer');
        loRc.LoWs_RingCentral_Required__c = true;
        User admin = newUser('o2.admin', 'System Administrator', null);
        User manager = newUser('o2.mgr', 'System Administrator', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ loNew, loDone, loRc, admin, manager };
            Map<String, Id> ps = new Map<String, Id>();
            for (PermissionSet p : [
                SELECT Id, Name FROM PermissionSet
                WHERE Name IN ('External_LO_Access', 'LO_Workspace_Onboarding_Admin', 'LO_Workspace_Oversight', 'Zoom_OAuth_Connection_Access')
            ]) {
                ps.put(p.Name, p.Id);
            }
            // Zoom principal access, as the PSG grants it (the per-user named credential refuses without it).
            insert new PermissionSetAssignment(AssigneeId = loNew.Id, PermissionSetId = ps.get('Zoom_OAuth_Connection_Access'));
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = loNew.Id, PermissionSetId = ps.get('External_LO_Access')),
                new PermissionSetAssignment(AssigneeId = loDone.Id, PermissionSetId = ps.get('External_LO_Access')),
                new PermissionSetAssignment(AssigneeId = loRc.Id, PermissionSetId = ps.get('External_LO_Access')),
                new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = ps.get('LO_Workspace_Onboarding_Admin')),
                new PermissionSetAssignment(AssigneeId = manager.Id, PermissionSetId = ps.get('LO_Workspace_Oversight'))
            };
        }
    }

    // ------------------------------------------------------------------ gate

    @IsTest
    static void finishedUserNeverSeesTheGate() {
        Test.startTest(); // callouts from runAs need the startTest context
        Test.setMock(HttpCalloutMock.class, new ZoomMock(200));
        System.runAs(user('o2.done')) {
            LoWsOnboardingGateService.GateState s = ExternalLoWorkspaceController.getGateState();
            System.assertEquals(false, s.applies);
            System.assertEquals(null, s.rows, 'no checks run for a finished user');
        }
    }

    @IsTest
    static void newUserIsGatedUntilZoomAndOutlook() {
        Test.startTest(); // callouts from runAs need the startTest context
        Test.setMock(HttpCalloutMock.class, new ZoomMock(401));
        System.runAs(user('o2.new')) {
            LoWsOnboardingGateService.GateState s = ExternalLoWorkspaceController.getGateState();
            System.assertEquals(true, s.applies);
            System.assertEquals(false, s.passed);
            System.assertEquals(new List<String>{ 'Zoom', 'Outlook email and calendar' }, s.missing);
            Map<String, LoWsOnboardingGateService.Row> rows = byKey(s.rows);
            System.assert(!rows.containsKey('RingCentral'), 'RingCentral only when flagged');
            System.assertEquals(false, rows.get('Mobile').required, 'mobile app is recommended only');
            System.assertEquals('red', rows.get('Zoom').status);
        }
        System.assertEquals(null, user('o2.new').LoWs_Zoom_Verified_At__c);
    }

    @IsTest
    static void zoomLiveCheckThenOutlookPassesAndNotifies() {
        Test.startTest(); // callouts from runAs need the startTest context
        Test.setMock(HttpCalloutMock.class, new ZoomMock(200));
        System.runAs(user('o2.new')) {
            LoWsOnboardingGateService.GateState s = ExternalLoWorkspaceController.getGateState();
            System.assertEquals('green', byKey(s.rows).get('Zoom').status, 'zoom: ' + LoWsOnboardingGateService.lastZoomError);
            System.assertEquals(new List<String>{ 'Outlook email and calendar' }, s.missing);
            System.assertEquals(0, LoWsOnboardingGateService.sentCount);

            s = ExternalLoWorkspaceController.attestOutlook();
            System.assertEquals(true, s.passed);
            System.assertEquals(1, LoWsOnboardingGateService.sentCount, 'live alert to the managers');
        }
        User u = user('o2.new');
        System.assertNotEquals(null, u.LoWs_Zoom_Verified_At__c);
        System.assertNotEquals(null, u.LoWs_Outlook_Attested_At__c);
        System.assertNotEquals(null, u.LoWs_Gate_Passed_At__c);
        System.runAs(u) {
            System.assertEquals(false, ExternalLoWorkspaceController.getGateState().applies, 'one-time gate');
        }
        System.assert(LoWsOnboardingGateService.holders(new List<String>{ 'LO_Workspace_Oversight' }).contains(user('o2.mgr').Id));
    }

    @IsTest
    static void ringCentralRowWhenFlagged() {
        User rc = user('o2.rc');
        update new User(Id = rc.Id, LoWs_Zoom_Verified_At__c = Datetime.now(), LoWs_Outlook_Attested_At__c = Datetime.now());
        System.runAs(rc) {
            LoWsOnboardingGateService.GateState s = ExternalLoWorkspaceController.getGateState();
            LoWsOnboardingGateService.Row row = byKey(s.rows).get('RingCentral');
            System.assertEquals('red', row.status);
            System.assert(row.actionUrl.contains('state=' + rc.Id), 'authorize link carries the user');
            System.assertEquals(new List<String>{ 'RingCentral calls' }, s.missing);
        }
        update new User(Id = rc.Id, Rc_Extension_Id__c = 'o2ext' + String.valueOf(Crypto.getRandomInteger()).right(6),
            RingCentral_Refresh_Token_DateTime__c = Datetime.now(), RingCentral_Access_Token_DateTime__c = Datetime.now());
        System.runAs(rc) {
            System.assertEquals(true, ExternalLoWorkspaceController.getGateState().passed);
        }
    }

    @IsTest
    static void waivedRowsCountAsReady() {
        User lo = user('o2.new');
        System.runAs(user('o2.admin')) {
            LoWsOnboardingGateService.waiveConnection(lo.Id, 'Zoom', 'No Zoom licence until next month');
            LoWsOnboardingGateService.Roster r = LoWsOnboardingGateService.waiveConnection(lo.Id, 'Outlook', 'Mailbox pending IT');
            System.assertEquals(true, r.isAdmin);
        }
        System.runAs(lo) {
            LoWsOnboardingGateService.GateState s = ExternalLoWorkspaceController.getGateState();
            System.assertEquals('waived', byKey(s.rows).get('Zoom').status);
            System.assertEquals(true, s.passed);
        }
        System.assertEquals(2, [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'LO Workspace Onboarding Waiver']);
    }

    @IsTest
    static void onlyTheOnboardingAdminWaivesOrResets() {
        Id loId = user('o2.new').Id;
        System.runAs(user('o2.mgr')) {
            LoWsOnboardingGateService.Roster r = LoWsOnboardingGateService.getOnboardingRoster();
            System.assertEquals(false, r.isAdmin);
            System.assert(r.rows.size() >= 3);
            assertRefused(new WaiveCall(loId, 'Zoom', 'x'), 'Only the LO Workspace onboarding admin');
            assertRefused(new ResetCall(loId), 'Only the LO Workspace onboarding admin');
        }
        System.runAs(user('o2.admin')) {
            assertRefused(new WaiveCall(loId, 'Zoom', '  '), 'Enter a reason');
            assertRefused(new WaiveCall(loId, 'Twilio', 'x'), 'Choose Zoom, Outlook or RingCentral');
        }
        System.runAs(user('o2.new')) {
            try {
                LoWsOnboardingGateService.getOnboardingRoster();
                System.assert(false, 'LOs cannot see the roster');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('do not have access'));
            }
        }
    }

    @IsTest
    static void resetClearsOnboardingButKeepsGoals() {
        User lo = user('o2.done');
        update new User(Id = lo.Id, LoWs_Gate_Passed_At__c = Datetime.now(), LoWs_Waived_Connections__c = 'Zoom',
            LoWs_Tour_Completed_At__c = Datetime.now(), LoWs_Tour_Chapters_Seen__c = 'home');
        System.runAs(user('o2.admin')) {
            LoWsOnboardingGateService.resetOnboarding(lo.Id);
        }
        User u = user('o2.done');
        System.assertEquals(false, u.External_LO_Onboarding_Complete__c);
        System.assertEquals(null, u.LoWs_Gate_Passed_At__c);
        System.assertEquals(null, u.LoWs_Waived_Connections__c);
        System.assertEquals(null, u.LoWs_Tour_Completed_At__c);
        System.assertEquals(null, u.LoWs_Tour_Chapters_Seen__c);
        System.assertEquals(4, u.ExtLO_Monthly_Unit_Goal__c, 'goals kept');
        System.assertEquals(1, [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'LO Workspace Onboarding Reset']);
    }

    @IsTest
    static void bannerListsBrokenConnectionsAfterTheGate() {
        User lo = user('o2.done');
        System.runAs(lo) {
            System.assertEquals(0, ExternalLoWorkspaceController.getConnectionIssues().size(), 'no banner before the gate');
        }
        update new User(Id = lo.Id, LoWs_Gate_Passed_At__c = Datetime.now(), LoWs_Outlook_Attested_At__c = Datetime.now());
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ZoomMock(401));
        System.runAs(lo) {
            List<LoWsOnboardingGateService.Row> issues = ExternalLoWorkspaceController.getConnectionIssues();
            System.assertEquals(1, issues.size());
            System.assertEquals('Zoom', issues[0].key);
            System.assert(String.isNotBlank(issues[0].fix));
        }
        Test.stopTest();
    }

    @IsTest
    static void bannerRechecksZoomAtMostDaily() {
        User lo = user('o2.done');
        Datetime stale = Datetime.now().addHours(-25);
        update new User(Id = lo.Id, LoWs_Gate_Passed_At__c = Datetime.now(), LoWs_Outlook_Attested_At__c = Datetime.now(),
            LoWs_Zoom_Verified_At__c = stale);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ZoomMock(200));
        System.runAs(lo) {
            System.assertEquals(0, ExternalLoWorkspaceController.getConnectionIssues().size(), 'stale stamp: live check passes');
        }
        System.assert(user('o2.done').LoWs_Zoom_Verified_At__c > stale, 'successful re-check restamps');
        Test.setMock(HttpCalloutMock.class, new ZoomMock(401)); // would raise the banner if it were called
        System.runAs(lo) {
            System.assertEquals(0, ExternalLoWorkspaceController.getConnectionIssues().size(), 'verified within 24h: no callout');
        }
        Test.stopTest();
    }

    /** ExternalLoWorkspaceController is deployed with the delegates, so its other entry points are exercised here too. */
    @IsTest
    static void workspaceControllerEntryPoints() {
        System.runAs(user('o2.new')) {
            // Reads: other test classes own their results; here they only need to run without a raw exception.
            for (Integer i = 0; i < 3; i++) {
                try {
                    if (i == 0) ExternalLoWorkspaceController.getOnboardingState();
                    if (i == 1) ExternalLoWorkspaceController.getActivityPlan();
                    if (i == 2) ExternalLoWorkspaceController.getPastClients(null);
                } catch (AuraHandledException e) {
                    System.assert(String.isNotBlank(e.getMessage()));
                }
            }
            System.assertEquals(1, ExternalLoWorkspaceController.parseGoals('[{"activityKey":"calls","weeklyTarget":5}]').size());
            System.assertEquals(0, ExternalLoWorkspaceController.parseGoals('').size());
            try {
                ExternalLoWorkspaceController.saveOnboarding(null, 1, 1, 1, 1, 1, false);
                System.assert(false, 'blank focus is refused');
            } catch (AuraHandledException e) {
                System.assert(String.isNotBlank(e.getMessage()));
            }
            try {
                ExternalLoWorkspaceController.saveOnboardingV2(null, 5, false, '[]', null, null, null);
                System.assert(false, 'blank focus is refused');
            } catch (AuraHandledException e) {
                System.assert(String.isNotBlank(e.getMessage()));
            }
            try {
                ExternalLoWorkspaceController.importCsv('nope', 'a,b');
            } catch (AuraHandledException e) {
                System.assert(String.isNotBlank(e.getMessage()));
            }
        }
        System.assert(String.isNotBlank(ExternalLoWorkspaceController.toAura(new NullPointerException()).getMessage()));
    }

    // ------------------------------------------------------------------ User trigger alert (Q30)

    @IsTest
    static void newActiveLoAlertsTheAdmin() {
        User fresh = newUser('o2.hire', 'External Loan Officer Profile', 'External_Loan_Officer');
        User internal = newUser('o2.int', 'System Administrator', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert internal;
            System.assertEquals(0, LoWsOnboardingGateService.sentCount, 'non-LO user: no alert');
            insert fresh;
            System.assertEquals(1, LoWsOnboardingGateService.sentCount, 'new active LO: landing-page alert');
            update new User(Id = fresh.Id, Title = 'Loan Officer');
            System.assertEquals(1, LoWsOnboardingGateService.sentCount, 'ordinary edit: no repeat');
        }
    }

    // ------------------------------------------------------------------ helpers

    static void assertRefused(System.Callable call, String messagePart) {
        try {
            call.call(null, null);
            System.assert(false, 'expected a refusal');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains(messagePart), e.getMessage());
        }
    }

    class WaiveCall implements System.Callable {
        Id userId; String connection; String reason;
        WaiveCall(Id userId, String connection, String reason) { this.userId = userId; this.connection = connection; this.reason = reason; }
        public Object call(String action, Map<String, Object> args) {
            return LoWsOnboardingGateService.waiveConnection(userId, connection, reason);
        }
    }

    class ResetCall implements System.Callable {
        Id userId;
        ResetCall(Id userId) { this.userId = userId; }
        public Object call(String action, Map<String, Object> args) {
            return LoWsOnboardingGateService.resetOnboarding(userId);
        }
    }

    class ZoomMock implements HttpCalloutMock {
        Integer code;
        ZoomMock(Integer code) { this.code = code; }
        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().startsWith('callout:Zoom_User_OAuth/v2/users/me'), req.getEndpoint());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody(code == 200 ? '{"id":"abc","email":"lo@reachhomeloans.com"}' : '{"code":124,"message":"Invalid access token."}');
            return res;
        }
    }

    static Map<String, LoWsOnboardingGateService.Row> byKey(List<LoWsOnboardingGateService.Row> rows) {
        Map<String, LoWsOnboardingGateService.Row> m = new Map<String, LoWsOnboardingGateService.Row>();
        for (LoWsOnboardingGateService.Row r : rows) {
            m.put(r.key, r);
        }
        return m;
    }

    static User user(String alias) {
        return [
            SELECT Id, External_LO_Onboarding_Complete__c, ExtLO_Monthly_Unit_Goal__c, LoWs_Zoom_Verified_At__c,
                   LoWs_Outlook_Attested_At__c, LoWs_Gate_Passed_At__c, LoWs_Waived_Connections__c,
                   LoWs_Tour_Completed_At__c, LoWs_Tour_Chapters_Seen__c
            FROM User WHERE Alias = :alias.right(8) AND Email LIKE '%@reach-o2.test' LIMIT 1
        ];
    }

    static User newUser(String alias, String profileName, String roleName) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName].Id,
            Username = alias + suffix + '@reach-o2.test',
            Email = alias + '@reach-o2.test',
            FirstName = 'Test',
            LastName = alias,
            Alias = alias.right(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        if (roleName != null) {
            u.UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = :roleName].Id;
        }
        return u;
    }
}