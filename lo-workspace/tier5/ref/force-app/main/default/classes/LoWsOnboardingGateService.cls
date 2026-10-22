/**
 * LO Workspace first-login gate (phase O2). Decisions: lo-workspace/onboarding/ONBOARDING-GRILL.md
 * Q4, Q5, Q13-Q19, Q30, Q34-Q38.
 *
 * Rows: Zoom (required; live GET /users/me through the per-user named credential Zoom_User_OAuth),
 * Outlook (required; the LO says "I've connected" - EAC status is not queryable), RingCentral
 * (required only when User.LoWs_RingCentral_Required__c), Salesforce mobile app (recommended only).
 * The gate is one-time: once LoWs_Gate_Passed_At__c is stamped it never locks again; later breakage
 * is only a banner (getConnectionIssues).
 *
 * without sharing + SYSTEM_MODE DML on purpose: LOs get no FLS on the LoWs_ fields (only the admin
 * permission set has it), so they cannot edit the waiver / gate fields themselves.
 * LO calls arrive through ExternalLoWorkspaceController (already granted to the PSG, so no permset
 * change). Roster / waive / reset are called by the Oversight tab directly.
 */
public without sharing class LoWsOnboardingGateService {

    public static final String ADMIN_PERMISSION = 'LO_Workspace_Onboarding_Admin';
    static final String OVERSIGHT_PERMISSION = 'LO_Workspace_Oversight';
    static final String LO_PERMISSION = 'External_LO';
    static final String LO_ROLE = 'External_Loan_Officer';
    static final String NOTIFICATION_TYPE = 'LO_Workspace_Lead';
    static final String ZOOM = 'Zoom';
    static final String OUTLOOK = 'Outlook';
    static final String RINGCENTRAL = 'RingCentral';
    static final String MOBILE = 'Mobile';
    static final Set<String> WAIVABLE = new Set<String>{ ZOOM, OUTLOOK, RINGCENTRAL };
    // Exact LoginHistory.Application values in this org (checked 2026-10-09).
    static final List<String> MOBILE_APPS = new List<String>{ 'Salesforce for iOS', 'Salesforce for Android' };
    static final String LANDING_ENDPOINT = 'https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/lo-landing-page';

    static final String ZOOM_HELP = 'This lets LO Workspace book your Zoom meetings and bring your recordings in for you. '
        + 'Click your photo (top right) > Settings. Type External Credentials in the Quick Find box, open it, find Zoom and click Allow Access. '
        + 'Sign in with your Reach email, then come back here and click Check again.';
    static final String OUTLOOK_HELP = 'This syncs your Reach emails and calendar so every conversation shows up in one place. '
        + 'Click your photo (top right) > Settings. Type Connected Accounts in the Quick Find box, open it and connect your Reach Microsoft 365 account. '
        + 'When it shows as connected, come back here and click I\'ve connected.';
    static final String RINGCENTRAL_HELP = 'This logs your RingCentral calls for you, so you never type a call note from scratch. '
        + 'Click Connect RingCentral, sign in with your Reach RingCentral login and approve access. '
        + 'When you see "You\'re connected!", close that tab and click Check again.';
    // Short reconnect paths for the post-gate banner on Perfect Day.
    static final String ZOOM_FIX = 'Click your photo (top right) > Settings > External Credentials > Zoom > Allow Access, and sign in with your Reach email.';
    static final String OUTLOOK_FIX = 'Click your photo (top right) > Settings > Connected Accounts and reconnect your Reach Microsoft 365 account.';
    static final String RINGCENTRAL_FIX = 'Click Reconnect and sign in with your Reach RingCentral login.';
    static final String MOBILE_HELP = 'Optional, but you will love it: install the Salesforce app from the App Store or Google Play '
        + 'and log in once with your LO Workspace username. This turns green after your first phone login.';

    // ------------------------------------------------------------------ LO side

    /** The running LO's gate. Stamps Zoom (live check) and the gate itself when everything required is ready. */
    public static GateState getGateState() {
        return evaluate(false);
    }

    /** "I've connected" on the Outlook row. */
    public static GateState attestOutlook() {
        return evaluate(true);
    }

    static GateState evaluate(Boolean attestOutlook) {
        User u = loadUsers(new Set<Id>{ UserInfo.getUserId() })[0];
        GateState state = new GateState();
        state.firstName = u.FirstName;
        state.applies = isLoWorkspaceLo()
            && u.External_LO_Onboarding_Complete__c != true
            && u.LoWs_Gate_Passed_At__c == null;
        state.passed = false;
        if (!state.applies) {
            return state;
        }
        User changes = new User(Id = u.Id);
        Boolean dirty = false;
        // The Zoom callout must run before any DML in this transaction.
        if (u.LoWs_Zoom_Verified_At__c == null && !isWaived(u, ZOOM) && zoomConnected()) {
            u.LoWs_Zoom_Verified_At__c = Datetime.now();
            changes.LoWs_Zoom_Verified_At__c = u.LoWs_Zoom_Verified_At__c;
            dirty = true;
        }
        if (attestOutlook && u.LoWs_Outlook_Attested_At__c == null) {
            u.LoWs_Outlook_Attested_At__c = Datetime.now();
            changes.LoWs_Outlook_Attested_At__c = u.LoWs_Outlook_Attested_At__c;
            dirty = true;
        }
        state.rows = rowsFor(u, u.LoWs_Zoom_Verified_At__c != null, mobileUsers(new Set<Id>{ u.Id }).contains(u.Id));
        state.missing = missing(state.rows);
        if (state.missing.isEmpty()) {
            changes.LoWs_Gate_Passed_At__c = Datetime.now();
            dirty = true;
            state.passed = true;
        }
        if (dirty) {
            Database.update(new List<User>{ changes }, AccessLevel.SYSTEM_MODE);
        }
        if (state.passed) {
            notifyLive(u);
        }
        return state;
    }

    /**
     * After the gate: required connections that are broken now (Q14 - banner, never a lockout).
     * Zoom is re-checked live at most once per ZOOM_RECHECK_HOURS (a success restamps LoWs_Zoom_Verified_At__c;
     * a failure leaves it stale, so the next load checks again). Outlook cannot be checked, so its attestation stands.
     */
    @TestVisible static final Integer ZOOM_RECHECK_HOURS = 24;

    public static List<Row> getConnectionIssues() {
        List<Row> issues = new List<Row>();
        User u = loadUsers(new Set<Id>{ UserInfo.getUserId() })[0];
        if (!isLoWorkspaceLo() || u.LoWs_Gate_Passed_At__c == null) {
            return issues;
        }
        Boolean zoomOk = isWaived(u, ZOOM)
            || (u.LoWs_Zoom_Verified_At__c != null && u.LoWs_Zoom_Verified_At__c > Datetime.now().addHours(-ZOOM_RECHECK_HOURS));
        if (!zoomOk && zoomConnected()) { // callout first, then the DML
            zoomOk = true;
            Database.update(new List<User>{ new User(Id = u.Id, LoWs_Zoom_Verified_At__c = Datetime.now()) }, AccessLevel.SYSTEM_MODE);
        }
        for (Row r : rowsFor(u, zoomOk, true)) {
            if (r.required && r.status == 'red') {
                issues.add(r);
            }
        }
        return issues;
    }

    // ------------------------------------------------------------------ Guided tour (O4b, O4c)

    // Chapter ids from c/loWsTourSteps: PD (full run) and A-M. Stop ids: PD-01, PD-RC, ...
    static final Pattern TOUR_CHAPTER = Pattern.compile('[A-Z]{1,3}');
    static final Pattern TOUR_STOP = Pattern.compile('PD-[A-Z0-9]{1,3}');
    // O4c tokens kept in LoWs_Tour_Chapters_Seen__c next to the chapter ids (no new field, no FLS change):
    // PD-SKIPPED = the full run was skipped (Q67); PD@<stopId> = where the first-login run was left (Q68).
    @TestVisible static final String TOUR_SKIPPED = 'PD-SKIPPED';
    @TestVisible static final String TOUR_RESUME = 'PD@';

    /**
     * Tour progress (decision 15) + auto-launch (decisions 4, 17): only an LO who cleared the O2 gate and the
     * setup Q&A and has neither finished nor skipped the full run. Existing users never passed the gate, so never auto-launch.
     */
    public static TourState getTourState() {
        User u = tourUser();
        List<String> tokens = tourTokens(u);
        TourState s = new TourState();
        s.completed = u.LoWs_Tour_Completed_At__c != null;
        s.skipped = tokens.contains(TOUR_SKIPPED);
        s.chaptersSeen = new List<String>();
        for (String t : tokens) {
            if (t.startsWith(TOUR_RESUME)) {
                s.resumeStopId = t.removeStart(TOUR_RESUME);
            } else if (t != TOUR_SKIPPED) {
                s.chaptersSeen.add(t);
            }
        }
        s.ringCentral = u.LoWs_RingCentral_Required__c == true;
        s.autoLaunch = !s.completed
            && !s.skipped
            && u.LoWs_Gate_Passed_At__c != null
            && u.External_LO_Onboarding_Complete__c == true
            && isLoWorkspaceLo();
        return s;
    }

    /** chapterId = a chapter just finished (ticked in the menu); finished = the full run reached Finish. */
    public static TourState saveTourProgress(String chapterId, Boolean finished) {
        if (chapterId != null && !TOUR_CHAPTER.matcher(chapterId).matches()) {
            throw fail('That tour chapter does not exist.');
        }
        User u = tourUser();
        List<String> tokens = tourTokens(u);
        if (chapterId != null && !tokens.contains(chapterId)) {
            tokens.add(chapterId);
        }
        Boolean stampFinish = finished == true && u.LoWs_Tour_Completed_At__c == null;
        if (finished == true) {
            dropResume(tokens);
        }
        return saveTokens(u, tokens, stampFinish);
    }

    /** Skip on the full run (Q67): ends auto-launch but is not "tour done". */
    public static TourState skipTour() {
        User u = tourUser();
        List<String> tokens = tourTokens(u);
        dropResume(tokens);
        if (!tokens.contains(TOUR_SKIPPED)) {
            tokens.add(TOUR_SKIPPED);
        }
        return saveTokens(u, tokens, false);
    }

    /** The stop the LO just moved to in the first-login run (Q68), so a reload resumes there. */
    public static TourState saveTourResume(String stopId) {
        if (stopId == null || !TOUR_STOP.matcher(stopId).matches()) {
            throw fail('That tour stop does not exist.');
        }
        User u = tourUser();
        List<String> tokens = tourTokens(u);
        dropResume(tokens);
        tokens.add(TOUR_RESUME + stopId);
        return saveTokens(u, tokens, false);
    }

    static List<String> tourTokens(User u) {
        return String.isBlank(u.LoWs_Tour_Chapters_Seen__c)
            ? new List<String>()
            : u.LoWs_Tour_Chapters_Seen__c.split(';');
    }

    static void dropResume(List<String> tokens) {
        for (Integer i = tokens.size() - 1; i >= 0; i--) {
            if (tokens[i].startsWith(TOUR_RESUME)) {
                tokens.remove(i);
            }
        }
    }

    static TourState saveTokens(User u, List<String> tokens, Boolean stampFinish) {
        User changes = new User(Id = u.Id, LoWs_Tour_Chapters_Seen__c = String.join(tokens, ';'));
        if (stampFinish) {
            changes.LoWs_Tour_Completed_At__c = Datetime.now();
        }
        // LOs have no FLS on the LoWs_ fields (see class comment).
        Database.update(new List<User>{ changes }, AccessLevel.SYSTEM_MODE);
        return getTourState();
    }

    static User tourUser() {
        return [
            SELECT Id, External_LO_Onboarding_Complete__c, LoWs_Gate_Passed_At__c, LoWs_RingCentral_Required__c,
                   LoWs_Tour_Completed_At__c, LoWs_Tour_Chapters_Seen__c
            FROM User WHERE Id = :UserInfo.getUserId()
        ];
    }

    // ------------------------------------------------------------------ Oversight tab

    @AuraEnabled
    public static Roster getOnboardingRoster() {
        Boolean admin = FeatureManagement.checkPermission(ADMIN_PERMISSION);
        if (!admin && !FeatureManagement.checkPermission(OVERSIGHT_PERMISSION)) {
            throw fail('You do not have access to LO Workspace onboarding status.');
        }
        Roster roster = new Roster();
        roster.isAdmin = admin;
        roster.rows = new List<RosterRow>();
        Map<Id, User> byId = new Map<Id, User>([
            SELECT Id FROM User WHERE IsActive = true AND UserRole.DeveloperName = :LO_ROLE LIMIT 50
        ]);
        List<User> users = loadUsers(byId.keySet());
        Set<Id> onPhone = mobileUsers(byId.keySet());
        for (User u : users) {
            RosterRow r = new RosterRow();
            r.userId = u.Id;
            r.name = u.Name;
            r.setupDone = u.External_LO_Onboarding_Complete__c == true;
            r.gatePassed = u.LoWs_Gate_Passed_At__c != null;
            r.tourDone = u.LoWs_Tour_Completed_At__c != null;
            r.tourSkipped = !r.tourDone && tourTokens(u).contains(TOUR_SKIPPED);
            r.ringCentral = 'n/a';
            for (Row c : rowsFor(u, u.LoWs_Zoom_Verified_At__c != null, onPhone.contains(u.Id))) {
                if (c.key == ZOOM) r.zoom = c.status;
                else if (c.key == OUTLOOK) r.outlook = c.status;
                else if (c.key == RINGCENTRAL) r.ringCentral = c.status;
                else if (c.key == MOBILE) r.mobile = c.status;
            }
            roster.rows.add(r);
        }
        return roster;
    }

    /** Admin only (Q13, Q36): reason required, logged. */
    @AuraEnabled
    public static Roster waiveConnection(Id userId, String connection, String reason) {
        requireAdmin();
        if (!WAIVABLE.contains(connection)) {
            throw fail('Choose Zoom, Outlook or RingCentral to waive.');
        }
        if (String.isBlank(reason)) {
            throw fail('Enter a reason to waive this connection.');
        }
        User u = requireUser(userId);
        Set<String> waived = waivedSet(u);
        waived.add(connection);
        Database.update(new List<User>{
            new User(Id = u.Id, LoWs_Waived_Connections__c = String.join(new List<String>(waived), ';'))
        }, AccessLevel.SYSTEM_MODE);
        log('LO Workspace Onboarding Waiver',
            UserInfo.getName() + ' waived ' + connection + ' for ' + u.Name + ' (' + u.Id + ').\nReason: ' + reason.trim());
        return getOnboardingRoster();
    }

    /** Admin only (Q35): back to a brand-new first login. Goals, plan and data are kept. */
    @AuraEnabled
    public static Roster resetOnboarding(Id userId) {
        requireAdmin();
        User u = requireUser(userId);
        Database.update(new List<User>{ new User(
            Id = u.Id,
            External_LO_Onboarding_Complete__c = false,
            LoWs_Outlook_Attested_At__c = null,
            LoWs_Zoom_Verified_At__c = null,
            LoWs_Gate_Passed_At__c = null,
            LoWs_Waived_Connections__c = null,
            LoWs_Tour_Completed_At__c = null,
            LoWs_Tour_Chapters_Seen__c = null
        ) }, AccessLevel.SYSTEM_MODE);
        log('LO Workspace Onboarding Reset',
            UserInfo.getName() + ' reset LO Workspace onboarding for ' + u.Name + ' (' + u.Id + ').\nBefore: setup complete '
            + u.External_LO_Onboarding_Complete__c + ', gate passed ' + u.LoWs_Gate_Passed_At__c
            + ', waived ' + u.LoWs_Waived_Connections__c + ', tour completed ' + u.LoWs_Tour_Completed_At__c);
        return getOnboardingRoster();
    }

    // ------------------------------------------------------------------ User trigger (Q30)

    /**
     * A user just became an active LO in the External_Loan_Officer role (insert, activation or role
     * change): email + bell to the onboarding admins to set up the landing page. No DML here, so the
     * setup-object (User) trigger stays mixed-DML safe.
     */
    public static void alertNewLos(List<User> users, Map<Id, User> oldById) {
        Id roleId;
        List<User> fresh = new List<User>();
        for (User u : users) {
            if (u.IsActive != true || u.UserRoleId == null) {
                continue;
            }
            if (roleId == null) {
                List<UserRole> roles = [SELECT Id FROM UserRole WHERE DeveloperName = :LO_ROLE LIMIT 1];
                if (roles.isEmpty()) {
                    return;
                }
                roleId = roles[0].Id;
            }
            User old = oldById == null ? null : oldById.get(u.Id);
            if (u.UserRoleId == roleId && (old == null || old.IsActive != true || old.UserRoleId != roleId)) {
                fresh.add(u);
            }
        }
        if (fresh.isEmpty()) {
            return;
        }
        Set<String> admins = holders(new List<String>{ ADMIN_PERMISSION });
        for (User u : fresh) { // ponytail: one bell + email per new LO; fine for hires one at a time
            String name = (String.isBlank(u.FirstName) ? '' : u.FirstName + ' ') + u.LastName;
            send(admins, 'Set up ' + name + '\'s landing page',
                name + ' is now an active LO Workspace loan officer. Send marketing the endpoint ' + LANDING_ENDPOINT
                + ', the secret (Setup > Custom Metadata Types > LO Landing Page Config > Default) and their username '
                + u.Username + '.', u.Id);
        }
    }

    // ------------------------------------------------------------------ helpers

    static Boolean isLoWorkspaceLo() {
        // LO Workspace only: the Partner Workspace portal (a Network) never gets the gate.
        return FeatureManagement.checkPermission(LO_PERMISSION) && Network.getNetworkId() == null;
    }

    static List<Row> rowsFor(User u, Boolean zoomOk, Boolean mobileSeen) {
        List<Row> rows = new List<Row>();
        rows.add(newRow(ZOOM, 'Zoom', true, zoomOk, isWaived(u, ZOOM), ZOOM_HELP, ZOOM_FIX, null));
        rows.add(newRow(OUTLOOK, 'Outlook email and calendar', true, u.LoWs_Outlook_Attested_At__c != null,
            isWaived(u, OUTLOOK), OUTLOOK_HELP, OUTLOOK_FIX, null));
        if (u.LoWs_RingCentral_Required__c == true) {
            rows.add(newRow(RINGCENTRAL, 'RingCentral calls', true, ringCentralConnected(u), isWaived(u, RINGCENTRAL),
                RINGCENTRAL_HELP, RINGCENTRAL_FIX, ringCentralAuthUrl(u.Id)));
        }
        rows.add(newRow(MOBILE, 'Salesforce mobile app', false, mobileSeen, false, MOBILE_HELP, null, null));
        return rows;
    }

    static Row newRow(String key, String label, Boolean required, Boolean ok, Boolean waived, String help, String fix, String actionUrl) {
        Row r = new Row();
        r.key = key;
        r.label = label;
        r.required = required;
        r.status = waived ? 'waived' : (ok ? 'green' : 'red');
        r.help = help;
        r.fix = fix;
        r.actionUrl = actionUrl;
        return r;
    }

    static List<String> missing(List<Row> rows) {
        List<String> labels = new List<String>();
        for (Row r : rows) {
            if (r.required && r.status == 'red') {
                labels.add(r.label);
            }
        }
        return labels;
    }

    @TestVisible static String lastZoomError;

    static Boolean zoomConnected() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Zoom_User_OAuth/v2/users/me');
            req.setMethod('GET');
            req.setTimeout(3000); // the workspace shows nothing until the gate answers; a slow Zoom counts as not connected
            return new Http().send(req).getStatusCode() == 200;
        } catch (Exception e) {
            // No per-user authorization yet throws a CalloutException: that simply means "not connected".
            lastZoomError = e.getMessage();
            return false;
        }
    }

    // Same signal as the call-log pull: extension linked and a live refresh token.
    static Boolean ringCentralConnected(User u) {
        return String.isNotBlank(u.Rc_Extension_Id__c)
            && u.RingCentral_Refresh_Token_DateTime__c != null
            && u.RingCentral_Refresh_Token_Expired__c != true;
    }

    // Same authorize URL as RingCentralUserAuthController (that method lists every user for admins).
    static String ringCentralAuthUrl(Id userId) {
        RingCentral_Credentials__c c = RingCentral_Credentials__c.getOrgDefaults();
        return 'https://platform.ringcentral.com/restapi/oauth/authorize'
            + '?client_id=' + EncodingUtil.urlEncode(c.Client_Id__c == null ? '' : c.Client_Id__c, 'UTF-8')
            + '&redirect_uri=' + EncodingUtil.urlEncode(c.Redirect_URI__c == null ? '' : c.Redirect_URI__c, 'UTF-8')
            + '&response_type=code'
            + '&state=' + userId;
    }

    static Set<Id> mobileUsers(Set<Id> userIds) {
        Set<Id> seen = new Set<Id>();
        try {
            // Application cannot be filtered in SOQL; the apps log in as Remote Access 2.0 (as does EAC, ~12 rows/user/day).
            // ponytail: 30-day window keeps a 25-LO roster well under the row limit; a phone login older than that shows red.
            for (AggregateResult ar : [
                SELECT UserId uid, Application app FROM LoginHistory
                WHERE UserId IN :userIds AND LoginType = 'Remote Access 2.0' AND LoginTime = LAST_N_DAYS:30
                GROUP BY UserId, Application
            ]) {
                if (MOBILE_APPS.contains((String) ar.get('app'))) {
                    seen.add((Id) ar.get('uid'));
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoWsOnboardingGateService.mobileUsers: ' + e.getMessage());
        }
        return seen;
    }

    static Boolean isWaived(User u, String key) {
        return waivedSet(u).contains(key);
    }

    static Set<String> waivedSet(User u) {
        return String.isBlank(u.LoWs_Waived_Connections__c)
            ? new Set<String>()
            : new Set<String>(u.LoWs_Waived_Connections__c.split(';'));
    }

    static List<User> loadUsers(Set<Id> ids) {
        return [
            SELECT Id, Name, FirstName, Username, External_LO_Onboarding_Complete__c,
                   LoWs_Outlook_Attested_At__c, LoWs_Zoom_Verified_At__c, LoWs_RingCentral_Required__c,
                   LoWs_Waived_Connections__c, LoWs_Gate_Passed_At__c, LoWs_Tour_Completed_At__c, LoWs_Tour_Chapters_Seen__c,
                   Rc_Extension_Id__c, RingCentral_Refresh_Token_DateTime__c, RingCentral_Refresh_Token_Expired__c
            FROM User
            WHERE Id IN :ids
            ORDER BY Name
        ];
    }

    static User requireUser(Id userId) {
        List<User> users = userId == null ? new List<User>() : loadUsers(new Set<Id>{ userId });
        if (users.isEmpty()) {
            throw fail('That loan officer could not be found.');
        }
        return users[0];
    }

    static void requireAdmin() {
        if (!FeatureManagement.checkPermission(ADMIN_PERMISSION)) {
            throw fail('Only the LO Workspace onboarding admin can waive or reset onboarding.');
        }
    }

    static void notifyLive(User u) {
        Set<String> recipients = holders(new List<String>{ OVERSIGHT_PERMISSION, ADMIN_PERMISSION });
        recipients.remove(u.Id);
        send(recipients, u.Name + ' is live in LO Workspace',
            u.Name + ' connected their accounts and is moving on to setup. Time for the Week-1 checks: '
            + 'a test landing-page lead, a logged call, a pre-approval letter and a Perfect Week review.', u.Id);
    }

    /** Active holders of any of the custom permissions (SetupEntityAccess -> PermissionSetAssignment, as in LoWsLeadIntakeService). */
    @TestVisible
    static Set<String> holders(List<String> permissionNames) {
        Set<Id> permSetIds = new Set<Id>();
        for (SetupEntityAccess sea : [
            SELECT ParentId FROM SetupEntityAccess
            WHERE SetupEntityId IN (SELECT Id FROM CustomPermission WHERE DeveloperName IN :permissionNames)
        ]) {
            permSetIds.add(sea.ParentId);
        }
        Set<String> ids = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSetId IN :permSetIds AND Assignee.IsActive = true
        ]) {
            ids.add(psa.AssigneeId);
        }
        return ids;
    }

    @TestVisible static Integer sentCount = 0;

    /** Bell + email. Never throws: an alert must not block the gate or a user save. */
    static void send(Set<String> recipients, String title, String body, Id targetId) {
        if (recipients == null || recipients.isEmpty()) {
            return;
        }
        sentCount++;
        try {
            List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE LIMIT 1];
            if (!types.isEmpty()) {
                Messaging.CustomNotification n = new Messaging.CustomNotification();
                n.setNotificationTypeId(types[0].Id);
                n.setTitle(title.left(250));
                n.setBody(body.left(750));
                n.setTargetId(targetId);
                n.send(recipients);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoWsOnboardingGateService bell: ' + e.getMessage());
        }
        try {
            List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
            for (String recipient : recipients) {
                Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
                m.setTargetObjectId(recipient);
                m.setSaveAsActivity(false);
                m.setSubject(title);
                m.setPlainTextBody(body + '\n\n' + Url.getOrgDomainUrl().toExternalForm() + '/' + targetId);
                mails.add(m);
            }
            Messaging.sendEmail(mails, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoWsOnboardingGateService email: ' + e.getMessage());
        }
    }

    static void log(String source, String data) {
        Database.insert(new Custom_Log__c(Source__c = source, Data__c = data.left(32000), Processed__c = true), AccessLevel.SYSTEM_MODE);
    }

    static AuraHandledException fail(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    // ------------------------------------------------------------------ DTOs

    public class GateState {
        @AuraEnabled public Boolean applies;
        @AuraEnabled public Boolean passed;
        @AuraEnabled public String firstName;
        @AuraEnabled public List<Row> rows;
        @AuraEnabled public List<String> missing;
    }

    public class Row {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean required;
        @AuraEnabled public String status; // green | red | waived
        @AuraEnabled public String help;
        @AuraEnabled public String fix; // short reconnect path for the Perfect Day banner
        @AuraEnabled public String actionUrl;
    }

    public class TourState {
        @AuraEnabled public Boolean autoLaunch;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Boolean skipped;
        @AuraEnabled public String resumeStopId;
        @AuraEnabled public Boolean ringCentral;
        @AuraEnabled public List<String> chaptersSeen;
    }

    public class Roster {
        @AuraEnabled public Boolean isAdmin;
        @AuraEnabled public List<RosterRow> rows;
    }

    public class RosterRow {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean setupDone;
        @AuraEnabled public Boolean gatePassed;
        @AuraEnabled public Boolean tourDone;
        @AuraEnabled public Boolean tourSkipped;
        @AuraEnabled public String zoom;
        @AuraEnabled public String outlook;
        @AuraEnabled public String ringCentral; // n/a when not required for this LO
        @AuraEnabled public String mobile;
    }
}