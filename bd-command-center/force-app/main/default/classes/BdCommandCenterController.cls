/**
 * Business development command center: partner book, touches, stages, invites and the
 * read-only BD Overview for managers.
 *
 * Partners are Person Accounts tagged with BD_Rep__c. Tagging never changes ownership, and
 * Frank must work realtors owned by other LOs, so reads run without sharing and every entry
 * point checks a custom permission instead:
 *   BD_Command_Center - the rep's own book (read + write)
 *   BD_Manager        - read any rep's book (BD Overview)
 *
 * A "touch" is any activity or communication with the partner by anyone: Tasks (RingCentral
 * calls/texts, logged emails, manual touches), Events, EmailMessages, and events the partner
 * attended. RingCentral association is unreliable, so the rep's own call Tasks are also
 * matched to partners by phone number.
 */
public without sharing class BdCommandCenterController {

    public static final Integer NEEDS_TOUCH_DAYS = 14;
    // The realtor Lead Intake Form; ?email= pre-identifies the sender, and LeadBdAttribution
    // files them as Buying Agent (realtors) or Referral Source (everyone else).
    static final String INTAKE_FORM_URL = 'https://reachhomeloans.my.site.com/LeadIntakeForm/s/?email=';
    static final String NOTE_PREFIX = 'BD Note';
    static final List<String> STAGE_ORDER = new List<String>{
        'Prospect', 'Contacted', 'Meeting Set', 'Met', 'Active Partner', 'Dormant'
    };
    static final Map<String, String> TYPE_FOR_INDUSTRY = new Map<String, String>{
        'Realtor' => 'Realtor Account', 'Title Agent' => 'Title Agent Account'
    };

    // ---------------------------------------------------------------- DTOs

    public class Partner {
        @AuraEnabled public Id id;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String initials;
        @AuraEnabled public String company;
        @AuraEnabled public String industry;
        @AuraEnabled public String stage;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Boolean isBorrower;
        @AuraEnabled public Datetime lastTouch;
        @AuraEnabled public Integer daysQuiet;
        @AuraEnabled public Boolean needsTouch;
        @AuraEnabled public Integer referredLeads90;
        @AuraEnabled public String intakeUrl;
    }

    public class CallRow {
        @AuraEnabled public Id taskId;
        @AuraEnabled public Id partnerId;
        @AuraEnabled public String partnerName;
        @AuraEnabled public String company;
        @AuraEnabled public String phoneNumber;
        @AuraEnabled public String kind;       // Call | Text
        @AuraEnabled public String direction;  // Inbound | Outbound
        @AuraEnabled public Integer seconds;
        @AuraEnabled public String subject;
        @AuraEnabled public Datetime whenAt;
    }

    public class EventRow {
        @AuraEnabled public Id campaignId;
        @AuraEnabled public String name;
        @AuraEnabled public String kind;
        @AuraEnabled public Date startDate;
        @AuraEnabled public String timeLabel;
        @AuraEnabled public String location;
        @AuraEnabled public Integer invited = 0;
        @AuraEnabled public Integer attending = 0;
        @AuraEnabled public Integer declined = 0;
        @AuraEnabled public Integer awaiting = 0;
        @AuraEnabled public String outcome;
        @AuraEnabled public List<String> partnerNames = new List<String>();
    }

    public class Stats {
        @AuraEnabled public Integer partners = 0;
        @AuraEnabled public Integer addedThisWeek = 0;
        @AuraEnabled public Integer callsThisWeek = 0;
        @AuraEnabled public Integer textsThisWeek = 0;
        @AuraEnabled public Integer meetingsThisWeek = 0;
        @AuraEnabled public Integer activePartners = 0;
        @AuraEnabled public Integer referredLeads90 = 0;
        @AuraEnabled public Integer referringPartners90 = 0;
        @AuraEnabled public Integer needsTouch = 0;
        @AuraEnabled public Map<String, Integer> byIndustry = new Map<String, Integer>();
    }

    public class RepOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
    }

    public class Home {
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public String repFirstName;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public List<RepOption> reps = new List<RepOption>();
        @AuraEnabled public Stats stats = new Stats();
        @AuraEnabled public List<Partner> partners = new List<Partner>();
        @AuraEnabled public List<CallRow> calls = new List<CallRow>();
        @AuraEnabled public List<CallRow> unmatchedCalls = new List<CallRow>();
        @AuraEnabled public List<EventRow> upcoming = new List<EventRow>();
        @AuraEnabled public List<EventRow> toConfirm = new List<EventRow>();
        @AuraEnabled public List<String> industries = new List<String>();
        @AuraEnabled public List<String> stages = STAGE_ORDER;
        @AuraEnabled public Boolean rcConnected = true;
        @AuraEnabled public String rcAuthUrl;
    }

    public class TimelineItem {
        @AuraEnabled public String id;
        @AuraEnabled public String kind;   // call | text | email | meeting | touch | note | event
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
        @AuraEnabled public Datetime whenAt;
    }

    public class LeadRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Date createdDate;
    }

    public class PartnerDetail {
        @AuraEnabled public Partner partner;
        @AuraEnabled public Integer calls30 = 0;
        @AuraEnabled public Integer meetingsHeld = 0;
        @AuraEnabled public EventRow nextEvent;
        @AuraEnabled public List<TimelineItem> timeline = new List<TimelineItem>();
        @AuraEnabled public List<LeadRow> referredLeads = new List<LeadRow>();
    }

    public class AccountHit {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String typeLabel;
        @AuraEnabled public String bdRepName;
        @AuraEnabled public Boolean inMyBook;
        @AuraEnabled public String matchedOn;
    }

    public class InviteRequest {
        @AuraEnabled public String kind { get; set; }          // Coffee | Lunch | Happy Hour
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Date eventDate { get; set; }
        @AuraEnabled public String eventTime { get; set; }     // HH:mm
        @AuraEnabled public Integer minutes { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String note { get; set; }
        @AuraEnabled public List<Id> partnerIds { get; set; }
        @AuraEnabled public List<Id> coHostIds { get; set; }
        @AuraEnabled public String scope { get; set; }         // null = BD rep's book; 'lo' = LO Workspace (outside LO)
    }

    /** LO Workspace "In Person Invite": the outside LO's invitable partners and their own upcoming events. */
    public class LoInviteHome {
        @AuraEnabled public String repFirstName;
        @AuraEnabled public List<Partner> partners = new List<Partner>();
        @AuraEnabled public List<EventRow> upcoming = new List<EventRow>();
    }

    public class InviteeRow {
        @AuraEnabled public Id memberId;
        @AuraEnabled public Id partnerId;
        @AuraEnabled public String name;
        @AuraEnabled public String industry;
        @AuraEnabled public String status;
        @AuraEnabled public String sentText;
    }

    public class EventDetail {
        @AuraEnabled public EventRow event;
        @AuraEnabled public List<String> hosts = new List<String>();
        @AuraEnabled public List<InviteeRow> invitees = new List<InviteeRow>();
    }

    public class ImportRow {
        @AuraEnabled public Integer rowNumber { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String company { get; set; }
        @AuraEnabled public String industry { get; set; }
        @AuraEnabled public String action { get; set; }        // link | create | skip | error
        @AuraEnabled public Id matchId { get; set; }
        @AuraEnabled public String matchName { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    // ---------------------------------------------------------------- access

    static Boolean isRep() { return FeatureManagement.checkPermission('BD_Command_Center'); }
    static Boolean isManager() { return FeatureManagement.checkPermission('BD_Manager'); }

    static Id resolveRep(Id repId) {
        if (repId == null || repId == UserInfo.getUserId()) {
            if (isRep()) return UserInfo.getUserId();
            if (isManager()) return defaultRepId();
            throw new AuraHandledException('You do not have access to the BD command center.');
        }
        if (!isManager()) throw new AuraHandledException('You can only view your own partners.');
        return repId;
    }

    static void requireRep() {
        if (!isRep()) throw new AuraHandledException('Only the business development rep can make changes here.');
    }

    static Id defaultRepId() {
        List<RepOption> reps = repOptions();
        return reps.isEmpty() ? null : reps[0].id;
    }

    static List<RepOption> repOptions() {
        List<RepOption> out = new List<RepOption>();
        for (User u : [
            SELECT Id, Name FROM User
            WHERE IsActive = true AND Id IN (
                SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSet.Name = 'Business_Development'
            )
            ORDER BY Name
        ]) {
            RepOption o = new RepOption();
            o.id = u.Id;
            o.name = u.Name;
            out.add(o);
        }
        return out;
    }

    static void requireMyPartner(Id accountId) {
        requireRep();
        List<Account> rows = [SELECT Id FROM Account WHERE Id = :accountId AND BD_Rep__c = :UserInfo.getUserId()];
        if (rows.isEmpty()) throw new AuraHandledException('That partner is not in your book.');
    }

    // ---------------------------------------------------------------- home

    @AuraEnabled
    public static Home getHome(Id repId) {
        Id rep = resolveRep(repId);
        Home h = new Home();
        h.isManager = isManager();
        h.canEdit = rep == UserInfo.getUserId() && isRep();
        h.reps = h.isManager ? repOptions() : new List<RepOption>();
        for (Schema.PicklistEntry e : Account.BD_Industry__c.getDescribe().getPicklistValues()) h.industries.add(e.getValue());
        if (rep == null) return h;

        User u = [SELECT Name, FirstName FROM User WHERE Id = :rep];
        h.repId = rep;
        h.repName = u.Name;
        h.repFirstName = u.FirstName;

        Map<Id, Account> accounts = partnerAccounts(rep, null);
        Map<Id, Partner> partners = buildPartners(accounts, rep);
        advanceStages(accounts, partners);
        h.partners = sortedByQuiet(partners.values());

        Stats s = h.stats;
        s.partners = partners.size();
        Date weekStart = Date.today().toStartOfWeek();
        for (Account a : accounts.values()) if (a.CreatedDate >= weekStart) s.addedThisWeek++;
        Set<Id> referring = new Set<Id>();
        for (Partner p : partners.values()) {
            if (p.stage == 'Active Partner') s.activePartners++;
            if (p.needsTouch) s.needsTouch++;
            if (p.referredLeads90 > 0) { s.referredLeads90 += p.referredLeads90; referring.add(p.id); }
            String ind = p.industry == null ? 'Other' : p.industry;
            s.byIndustry.put(ind, (s.byIndustry.containsKey(ind) ? s.byIndustry.get(ind) : 0) + 1);
        }
        s.referringPartners90 = referring.size();
        for (AggregateResult r : [
            SELECT InteractionType__c kind, COUNT(Id) c FROM Task
            WHERE OwnerId = :rep AND rcsfl__call_start_time__c = THIS_WEEK AND InteractionType__c IN ('Call', 'Sms')
            GROUP BY InteractionType__c
        ]) {
            if ((String) r.get('kind') == 'Call') s.callsThisWeek = (Integer) r.get('c');
            else s.textsThisWeek = (Integer) r.get('c');
        }

        buildCalls(h, rep, accounts);
        if (h.canEdit) applyRingCentralStatus(h);

        List<EventRow> events = eventRows(hostedCampaignIds(rep), null);
        for (EventRow e : events) {
            if (e.startDate >= weekStart && e.startDate < weekStart.addDays(7)) s.meetingsThisWeek++;
            if (e.startDate >= Date.today()) h.upcoming.add(e);
            else if (e.outcome == null && e.startDate >= Date.today().addDays(-60)) h.toConfirm.add(e);
        }
        return h;
    }

    static Map<Id, Account> partnerAccounts(Id rep, Set<Id> onlyIds) {
        String q = 'SELECT Id, Name, FirstName, LastName, PersonContactId, PersonTitle, BD_Industry__c, BD_Stage__c, '
            + 'Phone, PersonMobilePhone, PersonHomePhone, Phone_2__c, PersonEmail, Owner.Name, Type__c, CreatedDate '
            + 'FROM Account WHERE BD_Rep__c = :rep AND IsPersonAccount = true';
        if (onlyIds != null) q += ' AND Id IN :onlyIds';
        return new Map<Id, Account>((List<Account>) Database.query(q + ' ORDER BY Name LIMIT 2000'));
    }

    static Map<Id, Partner> buildPartners(Map<Id, Account> accounts, Id rep) {
        Map<Id, Datetime> lastTouch = lastTouchByAccount(accounts, rep);
        Map<Id, Integer> referred = referredCounts(accounts);
        Map<Id, Partner> out = new Map<Id, Partner>();
        for (Account a : accounts.values()) {
            Partner p = new Partner();
            p.id = a.Id;
            p.contactId = a.PersonContactId;
            p.name = a.Name;
            p.initials = (String.isBlank(a.FirstName) ? '' : a.FirstName.left(1)) + (String.isBlank(a.LastName) ? '' : a.LastName.left(1));
            p.company = a.PersonTitle;
            p.industry = a.BD_Industry__c;
            p.stage = String.isBlank(a.BD_Stage__c) ? 'Prospect' : a.BD_Stage__c;
            p.phone = String.isNotBlank(a.PersonMobilePhone) ? a.PersonMobilePhone : a.Phone;
            p.email = a.PersonEmail;
            p.ownerName = a.Owner.Name;
            p.isBorrower = a.Type__c == 'Borrower Account';
            p.lastTouch = lastTouch.get(a.Id);
            // A partner with no touch yet is measured from when it was added, so a brand-new
            // prospect is not instantly overdue.
            Datetime since = p.lastTouch == null ? a.CreatedDate : p.lastTouch;
            p.daysQuiet = since.date().daysBetween(Date.today());
            p.needsTouch = p.stage != 'Dormant' && p.daysQuiet >= NEEDS_TOUCH_DAYS;
            p.referredLeads90 = referred.containsKey(a.Id) ? referred.get(a.Id) : 0;
            applyIntakeUrl(p);
            out.put(a.Id, p);
        }
        return out;
    }

    static List<Partner> sortedByQuiet(List<Partner> ps) {
        List<PartnerSort> wrapped = new List<PartnerSort>();
        for (Partner p : ps) wrapped.add(new PartnerSort(p));
        wrapped.sort();
        List<Partner> out = new List<Partner>();
        for (PartnerSort w : wrapped) out.add(w.p);
        return out;
    }

    class PartnerSort implements Comparable {
        Partner p;
        PartnerSort(Partner p) { this.p = p; }
        public Integer compareTo(Object o) {
            Partner other = ((PartnerSort) o).p;
            return other.daysQuiet - p.daysQuiet;
        }
    }

    // ---------------------------------------------------------------- touches

    @TestVisible
    static String digits(String value) {
        if (String.isBlank(value)) return null;
        String d = value.replaceAll('[^0-9]', '');
        if (d.length() == 11 && d.startsWith('1')) d = d.substring(1);
        return d.length() == 10 ? d : null;
    }

    static Map<String, Id> accountIdsByPhone(Map<Id, Account> accounts) {
        Map<String, Id> out = new Map<String, Id>();
        for (Account a : accounts.values()) {
            for (String raw : new List<String>{ a.PersonMobilePhone, a.Phone, a.PersonHomePhone, a.Phone_2__c }) {
                String d = digits(raw);
                if (d != null) out.put(d, a.Id);
            }
        }
        return out;
    }

    static void bump(Map<Id, Datetime> m, Id key, Datetime value) {
        if (key == null || value == null) return;
        if (!m.containsKey(key) || m.get(key) < value) m.put(key, value);
    }

    static Map<Id, Datetime> lastTouchByAccount(Map<Id, Account> accounts, Id rep) {
        Map<Id, Datetime> out = new Map<Id, Datetime>();
        if (accounts.isEmpty()) return out;
        Set<Id> ids = accounts.keySet();
        Map<Id, Id> accountByContact = new Map<Id, Id>();
        for (Account a : accounts.values()) if (a.PersonContactId != null) accountByContact.put(a.PersonContactId, a.Id);
        Set<Id> contactIds = accountByContact.keySet();
        String notePattern = NOTE_PREFIX + '%';

        for (AggregateResult r : [
            SELECT AccountId acc, MAX(CreatedDate) lastAt FROM Task
            WHERE AccountId IN :ids AND (NOT Subject LIKE :notePattern) AND rcsfl__call_start_time__c = null
              // Email tasks are stamped when logged, not sent; EmailMessage below has the real date.
              AND TaskSubtype != 'Email'
            GROUP BY AccountId
        ]) bump(out, (Id) r.get('acc'), (Datetime) r.get('lastAt'));

        // RingCentral syncs in batches, so its record is created after the call: use the call time.
        for (AggregateResult r : [
            SELECT AccountId acc, MAX(rcsfl__call_start_time__c) lastAt FROM Task
            WHERE AccountId IN :ids AND rcsfl__call_start_time__c != null
            GROUP BY AccountId
        ]) bump(out, (Id) r.get('acc'), (Datetime) r.get('lastAt'));

        for (AggregateResult r : [
            SELECT AccountId acc, MAX(StartDateTime) lastAt FROM Event
            WHERE AccountId IN :ids AND StartDateTime <= :Datetime.now()
            GROUP BY AccountId
        ]) bump(out, (Id) r.get('acc'), (Datetime) r.get('lastAt'));

        for (AggregateResult r : [
            SELECT RelatedToId acc, MAX(MessageDate) lastAt FROM EmailMessage
            WHERE RelatedToId IN :ids GROUP BY RelatedToId
        ]) bump(out, (Id) r.get('acc'), (Datetime) r.get('lastAt'));

        for (EmailMessageRelation r : [
            SELECT RelationId, EmailMessage.MessageDate FROM EmailMessageRelation
            WHERE RelationId IN :contactIds AND EmailMessage.MessageDate = LAST_N_DAYS:180
            ORDER BY EmailMessage.MessageDate DESC LIMIT 5000
        ]) bump(out, accountByContact.get(r.RelationId), r.EmailMessage.MessageDate);

        for (CampaignMember m : [
            SELECT ContactId, Campaign.StartDate FROM CampaignMember
            WHERE ContactId IN :contactIds AND Status = 'Yes - Attending' AND Campaign.StartDate <= TODAY
        ]) bump(out, accountByContact.get(m.ContactId), Datetime.newInstance(m.Campaign.StartDate, Time.newInstance(12, 0, 0, 0)));

        // RingCentral often logs the rep's calls with no WhoId/WhatId: match by number.
        Map<String, Id> byPhone = accountIdsByPhone(accounts);
        for (Task t : [
            SELECT rcsfl__from_number__c, rcsfl__to_number__c, rcsfl__call_start_time__c, CreatedDate FROM Task
            WHERE OwnerId = :rep AND InteractionType__c IN ('Call', 'Sms') AND CreatedDate = LAST_N_DAYS:180
            ORDER BY CreatedDate DESC LIMIT 5000
        ]) {
            Id hit = byPhone.get(digits(t.rcsfl__to_number__c));
            if (hit == null) hit = byPhone.get(digits(t.rcsfl__from_number__c));
            bump(out, hit, whenOf(t));
        }
        return out;
    }

    static Map<Id, Integer> referredCounts(Map<Id, Account> accounts) {
        Map<Id, Id> accountByContact = new Map<Id, Id>();
        for (Account a : accounts.values()) if (a.PersonContactId != null) accountByContact.put(a.PersonContactId, a.Id);
        Map<Id, Integer> out = new Map<Id, Integer>();
        if (accountByContact.isEmpty()) return out;
        for (AggregateResult r : [
            SELECT Referral_Source__c c, COUNT(Id) n FROM Lead
            WHERE Referral_Source__c IN :accountByContact.keySet() AND CreatedDate = LAST_N_DAYS:90
            GROUP BY Referral_Source__c
        ]) out.put(accountByContact.get((Id) r.get('c')), (Integer) r.get('n'));
        return out;
    }

    /**
     * Forward-only automatic stage moves. Met is never automatic (the rep confirms the
     * meeting happened) and Dormant is manual only.
     * ponytail: evaluated when the command center loads rather than by triggers, so a stage
     * lags until the rep or a manager opens the tab. Move to a nightly batch if reports need
     * it to be exact.
     */
    static void advanceStages(Map<Id, Account> accounts, Map<Id, Partner> partners) {
        Map<Id, Id> accountByContact = new Map<Id, Id>();
        for (Account a : accounts.values()) if (a.PersonContactId != null) accountByContact.put(a.PersonContactId, a.Id);
        Set<Id> upcomingMeeting = new Set<Id>();
        for (CampaignMember m : [
            SELECT ContactId FROM CampaignMember
            WHERE ContactId IN :accountByContact.keySet() AND Campaign.Type = 'Event'
              AND Campaign.StartDate >= TODAY AND Status != 'No - Unable to Attend'
        ]) upcomingMeeting.add(accountByContact.get(m.ContactId));

        List<Account> updates = new List<Account>();
        for (Partner p : partners.values()) {
            String next = p.stage;
            if (p.referredLeads90 > 0) next = 'Active Partner';
            else if (p.stage == 'Dormant') continue;
            else if (upcomingMeeting.contains(p.id) && rank(p.stage) < rank('Meeting Set')) next = 'Meeting Set';
            else if (p.lastTouch != null && p.stage == 'Prospect') next = 'Contacted';
            if (next != p.stage || accounts.get(p.id).BD_Stage__c == null) {
                p.stage = next;
                applyIntakeUrl(p);
                updates.add(new Account(Id = p.id, BD_Stage__c = next));
            }
        }
        if (!updates.isEmpty()) Database.update(updates, false);
    }

    static Integer rank(String stage) { return STAGE_ORDER.indexOf(stage); }

    /** Active Partners with an email get their personal intake-form link for Fred to copy. */
    static void applyIntakeUrl(Partner p) {
        p.intakeUrl = p.stage == 'Active Partner' && String.isNotBlank(p.email)
            ? INTAKE_FORM_URL + EncodingUtil.urlEncode(p.email.trim(), 'UTF-8')
            : null;
    }

    /** The account-page strip: the partner's intake link, or null when not shareable yet. */
    @AuraEnabled
    public static String getIntakeLink(Id accountId) {
        if (accountId == null || !isRep()) return null;
        List<Account> rows = [
            SELECT BD_Stage__c, PersonEmail FROM Account WHERE Id = :accountId AND BD_Rep__c = :UserInfo.getUserId()
        ];
        if (rows.isEmpty()) return null;
        Partner p = new Partner();
        p.stage = rows[0].BD_Stage__c;
        p.email = rows[0].PersonEmail;
        applyIntakeUrl(p);
        return p.intakeUrl;
    }

    /**
     * The rep's own RingCentral sign-in, via the org's existing OAuth flow. Connected means the
     * token was refreshed in the last 4 days - the same rule RingCentralUserAuthController uses.
     */
    static void applyRingCentralStatus(Home h) {
        Datetime refreshed = [SELECT RingCentral_Refresh_Token_DateTime__c FROM User WHERE Id = :UserInfo.getUserId()].RingCentral_Refresh_Token_DateTime__c;
        h.rcConnected = refreshed != null && refreshed >= Datetime.now().addDays(-4);
        RingCentral_Credentials__c creds = RingCentral_Credentials__c.getOrgDefaults();
        if (h.rcConnected || creds == null || String.isBlank(creds.Client_Id__c) || String.isBlank(creds.Redirect_URI__c)) return;
        h.rcAuthUrl = 'https://platform.ringcentral.com/restapi/oauth/authorize'
            + '?client_id=' + creds.Client_Id__c
            + '&redirect_uri=' + EncodingUtil.urlEncode(creds.Redirect_URI__c, 'UTF-8')
            + '&response_type=code'
            + '&state=' + EncodingUtil.urlEncode(UserInfo.getUserId(), 'UTF-8');
    }

    // ---------------------------------------------------------------- calls

    static void buildCalls(Home h, Id rep, Map<Id, Account> accounts) {
        Map<String, Id> byPhone = accountIdsByPhone(accounts);
        for (Task t : [
            SELECT Id, Subject, InteractionType__c, CallType, CallDurationInSeconds, CreatedDate, rcsfl__call_start_time__c,
                   rcsfl__from_number__c, rcsfl__to_number__c, AccountId, WhoId, WhatId
            FROM Task
            WHERE OwnerId = :rep AND InteractionType__c IN ('Call', 'Sms') AND CreatedDate = LAST_N_DAYS:14
            ORDER BY rcsfl__call_start_time__c DESC NULLS LAST LIMIT 200
        ]) {
            CallRow c = new CallRow();
            c.taskId = t.Id;
            c.kind = t.InteractionType__c == 'Sms' ? 'Text' : 'Call';
            c.direction = t.CallType;
            c.seconds = t.CallDurationInSeconds;
            c.subject = t.Subject;
            c.whenAt = whenOf(t);
            String to = digits(t.rcsfl__to_number__c), fr = digits(t.rcsfl__from_number__c);
            c.phoneNumber = t.CallType == 'Inbound' ? (fr != null ? fr : to) : (to != null ? to : fr);
            Id pid = accounts.containsKey(t.AccountId) ? t.AccountId : null;
            if (pid == null) pid = byPhone.get(to);
            if (pid == null) pid = byPhone.get(fr);
            if (pid != null) {
                c.partnerId = pid;
                c.partnerName = accounts.get(pid).Name;
                c.company = accounts.get(pid).PersonTitle;
                if (h.calls.size() < 25) h.calls.add(c);
            } else if (t.WhoId == null && t.WhatId == null && c.kind == 'Call' && h.unmatchedCalls.size() < 25) {
                h.unmatchedCalls.add(c);
            }
        }
    }

    @AuraEnabled
    public static void linkCall(Id taskId, Id accountId) {
        requireMyPartner(accountId);
        Account a = [SELECT PersonContactId FROM Account WHERE Id = :accountId];
        update new Task(Id = taskId, WhatId = accountId, WhoId = a.PersonContactId);
    }

    // ---------------------------------------------------------------- partner workspace

    @AuraEnabled
    public static PartnerDetail getPartner(Id accountId, Id repId) {
        Id rep = resolveRep(repId);
        Map<Id, Account> accounts = partnerAccounts(rep, new Set<Id>{ accountId });
        if (accounts.isEmpty()) throw new AuraHandledException('That partner is not in this book.');
        Account a = accounts.get(accountId);
        PartnerDetail d = new PartnerDetail();
        d.partner = buildPartners(accounts, rep).get(accountId);

        String notePattern = NOTE_PREFIX + '%';
        Set<Id> taskIds = new Set<Id>();
        for (Task t : [
            SELECT Id, Subject, Description, InteractionType__c, CallType, CallDurationInSeconds, CreatedDate, Owner.Name, rcsfl__call_start_time__c
            FROM Task WHERE AccountId = :accountId AND TaskSubtype != 'Email' ORDER BY CreatedDate DESC LIMIT 100
        ]) {
            taskIds.add(t.Id);
            d.timeline.add(taskItem(t));
            if (t.InteractionType__c == 'Call' && whenOf(t) >= Datetime.now().addDays(-30)) d.calls30++;
        }
        // The rep's unassociated RingCentral activity with this partner's numbers.
        Map<String, Id> byPhone = accountIdsByPhone(accounts);
        for (Task t : [
            SELECT Id, Subject, Description, InteractionType__c, CallType, CallDurationInSeconds, CreatedDate, Owner.Name,
                   rcsfl__call_start_time__c, rcsfl__from_number__c, rcsfl__to_number__c
            FROM Task WHERE OwnerId = :rep AND InteractionType__c IN ('Call', 'Sms') AND AccountId = null
              AND CreatedDate = LAST_N_DAYS:180 ORDER BY CreatedDate DESC LIMIT 2000
        ]) {
            if (taskIds.contains(t.Id)) continue;
            if (byPhone.containsKey(digits(t.rcsfl__to_number__c)) || byPhone.containsKey(digits(t.rcsfl__from_number__c))) {
                d.timeline.add(taskItem(t));
                if (t.InteractionType__c == 'Call' && whenOf(t) >= Datetime.now().addDays(-30)) d.calls30++;
            }
        }
        for (Event e : [
            SELECT Id, Subject, Location, StartDateTime, Owner.Name FROM Event
            WHERE AccountId = :accountId ORDER BY StartDateTime DESC LIMIT 50
        ]) {
            TimelineItem i = new TimelineItem();
            i.id = e.Id; i.kind = 'meeting'; i.title = e.Subject;
            i.detail = (String.isBlank(e.Location) ? '' : e.Location + ' · ') + e.Owner.Name;
            i.whenAt = e.StartDateTime;
            d.timeline.add(i);
        }
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessageRelation r : [SELECT EmailMessageId FROM EmailMessageRelation WHERE RelationId = :a.PersonContactId LIMIT 50]) emailIds.add(r.EmailMessageId);
        for (EmailMessage m : [SELECT Id FROM EmailMessage WHERE RelatedToId = :accountId LIMIT 50]) emailIds.add(m.Id);
        for (EmailMessage m : [
            SELECT Id, Subject, FromName, Incoming, MessageDate FROM EmailMessage
            WHERE Id IN :emailIds ORDER BY MessageDate DESC LIMIT 50
        ]) {
            TimelineItem i = new TimelineItem();
            i.id = m.Id; i.kind = 'email'; i.title = (m.Incoming ? 'Email received: ' : 'Email sent: ') + m.Subject;
            i.detail = m.FromName; i.whenAt = m.MessageDate;
            d.timeline.add(i);
        }
        Set<Id> campaignIds = new Set<Id>();
        for (CampaignMember m : [
            SELECT CampaignId, Status, Campaign.Name, Campaign.StartDate, Campaign.BD_Outcome__c FROM CampaignMember
            WHERE ContactId = :a.PersonContactId AND Campaign.Type = 'Event' ORDER BY Campaign.StartDate DESC LIMIT 50
        ]) {
            campaignIds.add(m.CampaignId);
            TimelineItem i = new TimelineItem();
            i.id = m.CampaignId; i.kind = 'event'; i.title = m.Campaign.Name;
            i.detail = 'RSVP: ' + m.Status + (m.Campaign.BD_Outcome__c == null ? '' : ' · ' + m.Campaign.BD_Outcome__c);
            i.whenAt = m.Campaign.StartDate == null ? null : Datetime.newInstance(m.Campaign.StartDate, Time.newInstance(12, 0, 0, 0));
            d.timeline.add(i);
            if (m.Campaign.BD_Outcome__c == 'Held' && m.Status != 'No - Unable to Attend') d.meetingsHeld++;
        }
        for (EventRow e : eventRows(campaignIds, null)) {
            if (e.startDate >= Date.today() && (d.nextEvent == null || e.startDate < d.nextEvent.startDate)) d.nextEvent = e;
        }
        sortTimeline(d.timeline);

        for (Lead l : [
            SELECT Id, Name, Status, Owner.Name, CreatedDate FROM Lead
            WHERE Referral_Source__c = :a.PersonContactId ORDER BY CreatedDate DESC LIMIT 50
        ]) {
            LeadRow r = new LeadRow();
            r.id = l.Id; r.name = l.Name; r.status = l.Status; r.ownerName = l.Owner.Name; r.createdDate = l.CreatedDate.date();
            d.referredLeads.add(r);
        }
        return d;
    }

    static TimelineItem taskItem(Task t) {
        TimelineItem i = new TimelineItem();
        i.id = t.Id;
        i.whenAt = whenOf(t);
        if (t.InteractionType__c == 'Call') {
            i.kind = 'call';
            i.title = (t.CallType == null ? '' : t.CallType + ' ') + 'call'
                + (t.CallDurationInSeconds == null || t.CallDurationInSeconds == 0 ? '' : ' · ' + duration(t.CallDurationInSeconds));
        } else if (t.InteractionType__c == 'Sms') {
            i.kind = 'text';
            i.title = (t.CallType == 'Inbound' ? 'Text received' : 'Text sent');
        } else if (t.Subject != null && t.Subject.startsWith(NOTE_PREFIX)) {
            i.kind = 'note';
            i.title = 'Note';
        } else {
            i.kind = 'touch';
            i.title = t.Subject;
        }
        i.detail = String.isBlank(t.Description) ? t.Owner.Name : t.Description.abbreviate(280);
        return i;
    }

    static Datetime whenOf(Task t) {
        return t.rcsfl__call_start_time__c != null ? t.rcsfl__call_start_time__c : t.CreatedDate;
    }

    static String duration(Integer secs) {
        return (secs / 60) + 'm ' + Math.mod(secs, 60) + 's';
    }

    static void sortTimeline(List<TimelineItem> items) {
        List<TimelineSort> w = new List<TimelineSort>();
        for (TimelineItem i : items) w.add(new TimelineSort(i));
        w.sort();
        items.clear();
        for (TimelineSort s : w) items.add(s.i);
    }

    class TimelineSort implements Comparable {
        TimelineItem i;
        TimelineSort(TimelineItem i) { this.i = i; }
        public Integer compareTo(Object o) {
            Datetime a = i.whenAt, b = ((TimelineSort) o).i.whenAt;
            if (a == b) return 0;
            if (a == null) return 1;
            if (b == null) return -1;
            return a > b ? -1 : 1;
        }
    }

    @AuraEnabled
    public static void setStage(Id accountId, String stage) {
        requireMyPartner(accountId);
        if (!STAGE_ORDER.contains(stage)) throw new AuraHandledException('Unknown stage.');
        update new Account(Id = accountId, BD_Stage__c = stage);
    }

    @AuraEnabled
    public static void setIndustry(Id accountId, String industry) {
        requireMyPartner(accountId);
        update new Account(Id = accountId, BD_Industry__c = industry);
    }

    /** Lets the account-page Log touch card show only on the rep's own partners. */
    @AuraEnabled
    public static Boolean isMyPartner(Id accountId) {
        if (accountId == null || !isRep()) return false;
        return [SELECT COUNT() FROM Account WHERE Id = :accountId AND BD_Rep__c = :UserInfo.getUserId()] > 0;
    }

    /** kind: In person | Call | Text | Email | Note. Notes do not count as a touch. */
    @AuraEnabled
    public static void logTouch(Id accountId, String kind, String notes) {
        requireMyPartner(accountId);
        Account a = [SELECT PersonContactId FROM Account WHERE Id = :accountId];
        String subject = kind == 'Note' ? NOTE_PREFIX : 'BD Touch: ' + kind;
        insert new Task(
            OwnerId = UserInfo.getUserId(), WhatId = accountId, WhoId = a.PersonContactId,
            Subject = subject, Description = notes, Status = 'Completed', ActivityDate = Date.today()
        );
    }

    @AuraEnabled
    public static Id createReferralLead(Id accountId, String firstName, String lastName, String phone, String email, String notes) {
        requireMyPartner(accountId);
        if (String.isBlank(firstName) || String.isBlank(lastName)) throw new AuraHandledException('First and last name are required.');
        if (String.isBlank(phone) && String.isBlank(email)) throw new AuraHandledException('Enter a phone or an email.');
        Account a = [SELECT Name, PersonContactId, BD_Industry__c FROM Account WHERE Id = :accountId];
        Lead l = new Lead(
            // Matches how realtor referrals arrive today; other partner types use the existing
            // referral value rather than a new picklist entry.
            LeadSource = a.BD_Industry__c == 'Realtor' ? 'Realtor Referral' : 'Personal Referral',
            FirstName = firstName.trim(), LastName = lastName.trim(),
            Company = firstName.trim() + ' ' + lastName.trim(),
            Phone = String.isBlank(phone) ? null : phone.trim(),
            Email = String.isBlank(email) ? null : email.trim(),
            Referral_Source__c = a.PersonContactId,
            Comments__c = 'Referred by ' + a.Name + ' via BD command center' + (String.isBlank(notes) ? '' : '. ' + notes.trim())
        );
        // Normal lead assignment decides the owner, exactly as for any other new lead.
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.assignmentRuleHeader.useDefaultRule = true;
        l.setOptions(opts);
        insert l;
        return l.Id;
    }

    // ---------------------------------------------------------------- adding partners

    @AuraEnabled
    public static List<AccountHit> searchAccounts(String term) {
        requireRep();
        if (String.isBlank(term) || term.trim().length() < 2) return new List<AccountHit>();
        String likeTerm = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        String d = term.replaceAll('[^0-9]', '');
        String phoneLike = d.length() >= 4 ? '%' + d.right(4) : '__none__';
        List<AccountHit> out = new List<AccountHit>();
        for (Account a : [
            SELECT Id, Name, PersonTitle, Phone, PersonMobilePhone, PersonEmail, Type__c, BD_Rep__c, BD_Rep__r.Name
            FROM Account
            WHERE IsPersonAccount = true AND (Name LIKE :likeTerm OR PersonEmail LIKE :likeTerm OR PersonTitle LIKE :likeTerm
                  OR PersonMobilePhone LIKE :phoneLike OR Phone LIKE :phoneLike)
            ORDER BY Name LIMIT 25
        ]) out.add(hit(a, null));
        return out;
    }

    static AccountHit hit(Account a, String matchedOn) {
        AccountHit h = new AccountHit();
        h.id = a.Id;
        h.name = a.Name;
        h.company = a.PersonTitle;
        h.phone = String.isNotBlank(a.PersonMobilePhone) ? a.PersonMobilePhone : a.Phone;
        h.email = a.PersonEmail;
        h.typeLabel = a.Type__c == null ? null : a.Type__c.removeEnd(' Account');
        h.bdRepName = a.BD_Rep__r == null ? null : a.BD_Rep__r.Name;
        h.inMyBook = a.BD_Rep__c == UserInfo.getUserId();
        h.matchedOn = matchedOn;
        return h;
    }

    /** Existing people who already hold this email or phone: the "already exists" alert. */
    @AuraEnabled
    public static List<AccountHit> findDuplicates(String email, String phone) {
        requireRep();
        Map<Id, String> matched = new Map<Id, String>();
        for (PersonAccountDuplicateService.Match m : PersonAccountDuplicateService.findMatches(email, phone, null)) {
            matched.put(m.accountId, m.matchedOn);
        }
        List<AccountHit> out = new List<AccountHit>();
        if (matched.isEmpty()) return out;
        for (Account a : [
            SELECT Id, Name, PersonTitle, Phone, PersonMobilePhone, PersonEmail, Type__c, BD_Rep__c, BD_Rep__r.Name
            FROM Account WHERE Id IN :matched.keySet()
        ]) out.add(hit(a, matched.get(a.Id)));
        return out;
    }

    @AuraEnabled
    public static void addExisting(Id accountId, String industry) {
        requireRep();
        Account a = [SELECT Id, BD_Rep__c, BD_Stage__c, Biz_Dev_Designation__c FROM Account WHERE Id = :accountId AND IsPersonAccount = true];
        a.BD_Rep__c = UserInfo.getUserId();
        a.Biz_Dev_Designation__c = LeadBdAttribution.designationForNewPartner(a.Biz_Dev_Designation__c, UserInfo.getUserId());
        if (String.isNotBlank(industry)) a.BD_Industry__c = industry;
        if (a.BD_Stage__c == null) a.BD_Stage__c = 'Prospect';
        update a;
    }

    @AuraEnabled
    public static Id createPartner(String firstName, String lastName, String phone, String email, String company, String industry) {
        requireRep();
        if (String.isBlank(firstName) || String.isBlank(lastName)) throw new AuraHandledException('First and last name are required.');
        if (String.isBlank(phone) && String.isBlank(email)) throw new AuraHandledException('Enter a phone or an email.');
        if (String.isBlank(industry)) throw new AuraHandledException('Pick an industry.');
        try {
            PersonAccountDuplicateService.blockIfDuplicate(email, phone);
        } catch (PersonAccountDuplicateService.DuplicateFoundException e) {
            throw new AuraHandledException(e.getMessage());
        }
        return insertPartner(firstName, lastName, phone, email, company, industry);
    }

    static Id insertPartner(String firstName, String lastName, String phone, String email, String company, String industry) {
        Account a = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = firstName.trim(), LastName = lastName.trim(),
            PersonMobilePhone = String.isBlank(phone) ? null : phone.trim(),
            PersonEmail = String.isBlank(email) ? null : email.trim(),
            PersonTitle = String.isBlank(company) ? null : company.trim(),
            BD_Rep__c = UserInfo.getUserId(), BD_Industry__c = industry, BD_Stage__c = 'Prospect',
            Biz_Dev_Designation__c = LeadBdAttribution.designationForNewPartner(null, UserInfo.getUserId()),
            Type__c = TYPE_FOR_INDUSTRY.containsKey(industry) ? TYPE_FOR_INDUSTRY.get(industry) : 'Other'
        );
        if (industry == 'Realtor') a.Is_Realtor__c = true;
        insert a;
        return a.Id;
    }

    // ---------------------------------------------------------------- import

    /** Dry run: decides link / create / error per row without writing anything. */
    @AuraEnabled
    public static List<ImportRow> previewImport(List<ImportRow> rows) {
        requireRep();
        Set<String> industries = new Set<String>();
        for (Schema.PicklistEntry e : Account.BD_Industry__c.getDescribe().getPicklistValues()) industries.add(e.getValue());
        Map<String, Integer> seenInFile = new Map<String, Integer>();
        for (ImportRow r : rows) {
            r.action = null; r.matchId = null; r.matchName = null; r.message = null;
            if (String.isBlank(r.lastName) || (String.isBlank(r.phone) && String.isBlank(r.email))) {
                r.action = 'error'; r.message = 'Needs a last name and a phone or email.';
                continue;
            }
            if (String.isNotBlank(r.industry) && !industries.contains(r.industry)) {
                r.action = 'error'; r.message = 'Unknown industry "' + r.industry + '".';
                continue;
            }
            String key = (digits(r.phone) == null ? '' : digits(r.phone)) + '|' + (r.email == null ? '' : r.email.trim().toLowerCase());
            if (seenInFile.containsKey(key)) {
                r.action = 'skip'; r.message = 'Same person as row ' + seenInFile.get(key) + '.';
                continue;
            }
            seenInFile.put(key, r.rowNumber);
            // One lookup per row keeps the rule identical to the Add partner modal.
            // ponytail: ~2 queries per row, fine to ~40 rows per call; the UI sends chunks.
            List<PersonAccountDuplicateService.Match> matches = PersonAccountDuplicateService.findMatches(r.email, r.phone, null);
            if (!matches.isEmpty()) {
                r.action = 'link'; r.matchId = matches[0].accountId; r.matchName = matches[0].name;
                r.message = 'Already in Salesforce (matched on ' + matches[0].matchedOn.toLowerCase() + ').';
            } else {
                r.action = 'create';
            }
        }
        return rows;
    }

    @AuraEnabled
    public static List<ImportRow> commitImport(List<ImportRow> rows, String defaultIndustry) {
        requireRep();
        List<ImportRow> checked = previewImport(rows);
        for (ImportRow r : checked) {
            String industry = String.isNotBlank(r.industry) ? r.industry : defaultIndustry;
            try {
                if (r.action == 'link') {
                    addExisting(r.matchId, industry);
                    r.message = 'Linked to ' + r.matchName + '.';
                } else if (r.action == 'create') {
                    if (String.isBlank(industry)) throw new AuraHandledException('Pick an industry.');
                    r.matchId = insertPartner(String.isBlank(r.firstName) ? '' : r.firstName, r.lastName, r.phone, r.email, r.company, industry);
                    r.message = 'Created.';
                }
            } catch (Exception e) {
                r.action = 'error';
                r.message = e.getMessage();
            }
        }
        return checked;
    }

    // ---------------------------------------------------------------- events

    static Set<Id> hostedCampaignIds(Id rep) {
        Set<Id> ids = new Set<Id>();
        for (Campaign c : [SELECT Id FROM Campaign WHERE OwnerId = :rep AND Type = 'Event' AND StartDate >= LAST_N_DAYS:90]) ids.add(c.Id);
        for (Campaign_Co_Host__c h : [
            SELECT Campaign__c FROM Campaign_Co_Host__c
            WHERE Co_Host__c = :rep AND Campaign__r.Type = 'Event' AND Campaign__r.StartDate >= LAST_N_DAYS:90
        ]) ids.add(h.Campaign__c);
        return ids;
    }

    static List<EventRow> eventRows(Set<Id> campaignIds, Map<Id, Account> unused) {
        List<EventRow> out = new List<EventRow>();
        if (campaignIds.isEmpty()) return out;
        Map<Id, EventRow> byId = new Map<Id, EventRow>();
        for (Campaign c : [
            SELECT Id, Name, StartDate, Event_Time__c, Description, BD_Outcome__c,
                   (SELECT Location FROM Events ORDER BY CreatedDate LIMIT 1)
            FROM Campaign WHERE Id IN :campaignIds AND StartDate != null ORDER BY StartDate
        ]) {
            EventRow e = new EventRow();
            e.campaignId = c.Id;
            e.name = c.Name;
            e.kind = kindOf(c.Name);
            e.startDate = c.StartDate;
            e.timeLabel = c.Event_Time__c == null ? null : RealtorEventWorkspaceController.formatEventTime(c.Event_Time__c);
            e.location = c.Events.isEmpty() ? null : c.Events[0].Location;
            e.outcome = c.BD_Outcome__c;
            byId.put(c.Id, e);
            out.add(e);
        }
        for (CampaignMember m : [
            SELECT CampaignId, Status, Contact.Name FROM CampaignMember WHERE CampaignId IN :byId.keySet()
        ]) {
            EventRow e = byId.get(m.CampaignId);
            e.invited++;
            if (m.Status == 'Yes - Attending') e.attending++;
            else if (m.Status == 'No - Unable to Attend') e.declined++;
            else e.awaiting++;
            if (e.partnerNames.size() < 3) e.partnerNames.add(m.Contact.Name);
        }
        return out;
    }

    @TestVisible
    static String kindOf(String campaignName) {
        String n = campaignName == null ? '' : campaignName.toLowerCase();
        if (n.contains('happy hour')) return 'Happy Hour';
        if (n.contains('lunch')) return 'Lunch';
        if (n.contains('coffee')) return 'Coffee';
        return 'Event';
    }

    // ---------------------------------------------------------------- LO Workspace (outside LOs)
    // Same invite engine for LO Workspace users (External_LO, or LO_Workspace_Demo for Brandon).
    // They have no BD book: they may invite only their own tagged partners (Phase 5 tags) and
    // partner-type Person Accounts they own, and they see only events they host or co-host.

    static void requireLo() {
        if (!LoWsPartnerTagService.isTagMode()) throw new AuraHandledException('In-person invites are for LO Workspace loan officers.');
    }

    @TestVisible
    static Map<Id, Account> loPartnerAccounts(Set<Id> onlyIds) {
        Id me = UserInfo.getUserId();
        Set<Id> tagged = LoWsPartnerTagService.myTags(onlyIds).keySet();
        String q = 'SELECT Id, Name, FirstName, PersonContactId, PersonTitle, Company__c, BD_Industry__c, Is_Realtor__c, '
            + 'Type, Type__c, Group__pc FROM Account '
            + 'WHERE IsPersonAccount = true AND PersonContactId != null AND (Id IN :tagged OR OwnerId = :me)';
        if (onlyIds != null) q += ' AND Id IN :onlyIds';
        Map<Id, Account> out = new Map<Id, Account>();
        for (Account a : (List<Account>) Database.query(q + ' ORDER BY Name LIMIT 2000')) {
            if (tagged.contains(a.Id) || LoWsPartnerTagService.isPartner(a)) out.put(a.Id, a);
        }
        return out;
    }

    static void requireHostedByMe(Id campaignId) {
        Id me = UserInfo.getUserId();
        Boolean host = [SELECT COUNT() FROM Campaign WHERE Id = :campaignId AND OwnerId = :me] > 0
            || [SELECT COUNT() FROM Campaign_Co_Host__c WHERE Campaign__c = :campaignId AND Co_Host__c = :me] > 0;
        if (!host) throw new AuraHandledException('You can only open events you host.');
    }

    @AuraEnabled
    public static LoInviteHome getLoInviteHome() {
        requireLo();
        LoInviteHome h = new LoInviteHome();
        h.repFirstName = UserInfo.getFirstName();
        for (Account a : loPartnerAccounts(null).values()) {
            Partner p = new Partner();
            p.id = a.Id;
            p.name = a.Name;
            p.company = String.isNotBlank(a.Company__c) ? a.Company__c : a.PersonTitle;
            h.partners.add(p);
        }
        for (EventRow e : eventRows(hostedCampaignIds(UserInfo.getUserId()), null)) {
            if (e.startDate >= Date.today()) h.upcoming.add(e);
        }
        return h;
    }

    @AuraEnabled
    public static List<RealtorEventWorkspaceController.CoHostOption> searchCoHosts(String term) {
        if (isRep()) return RealtorEventWorkspaceController.searchReachEmployees(term);
        requireLo();
        List<RealtorEventWorkspaceController.CoHostOption> out = new List<RealtorEventWorkspaceController.CoHostOption>();
        String t = String.isBlank(term) ? '' : term.trim();
        if (t.length() < 2) return out;
        String pattern = '%' + t + '%';
        for (User u : [
            SELECT Id, Name, Email, Title FROM User
            WHERE Id IN :internalStaffIds(null) AND (Name LIKE :pattern OR Email LIKE :pattern)
            ORDER BY Name LIMIT 20
        ]) {
            RealtorEventWorkspaceController.CoHostOption o = new RealtorEventWorkspaceController.CoHostOption();
            o.userId = u.Id;
            o.name = u.Name;
            o.email = u.Email;
            o.title = u.Title;
            out.add(o);
        }
        return out;
    }

    /** Outside LOs may co-host only with internal Reach staff: active Standard users outside the External LO role. */
    static Set<Id> internalStaffIds(Set<Id> onlyIds) {
        String q = 'SELECT Id FROM User WHERE IsActive = true AND UserType = \'Standard\' '
            + 'AND (UserRoleId = null OR UserRole.DeveloperName != \'External_Loan_Officer\')';
        if (onlyIds != null) q += ' AND Id IN :onlyIds';
        return new Map<Id, User>((List<User>) Database.query(q)).keySet();
    }

    /**
     * Creates the event exactly the way the realtor event tool does (Campaign Type=Event plus
     * a calendar Event), then hands invitees, co-hosts and sending to that same engine so BD
     * invites get the identical RSVP emails, texts and reminders.
     */
    @AuraEnabled
    public static Id createInvite(InviteRequest req) {
        Boolean lo = req != null && req.scope == 'lo';
        if (lo) requireLo(); else requireRep();
        if (req == null || req.eventDate == null || String.isBlank(req.eventTime)) throw new AuraHandledException('Pick a date and time.');
        if (req.partnerIds == null || req.partnerIds.isEmpty()) throw new AuraHandledException('Invite at least one partner.');
        String kind = String.isBlank(req.kind) ? 'Coffee' : req.kind;
        List<String> hm = req.eventTime.split(':');
        Time t = Time.newInstance(Integer.valueOf(hm[0]), Integer.valueOf(hm[1]), 0, 0);
        Integer minutes = req.minutes == null || req.minutes <= 0 ? 60 : req.minutes;

        List<Account> partners;
        if (lo) {
            // Every requested partner must be one this LO may invite; nothing is silently dropped.
            Set<Id> requested = new Set<Id>(req.partnerIds);
            partners = loPartnerAccounts(requested).values();
            if (partners.size() != requested.size()) throw new AuraHandledException('You can only invite your own partners.');
            if (req.coHostIds != null && !req.coHostIds.isEmpty()) {
                Set<Id> coHosts = new Set<Id>(req.coHostIds);
                if (!internalStaffIds(coHosts).containsAll(coHosts)) throw new AuraHandledException('Co-hosts must be Reach team members.');
            }
        } else {
            partners = [
                SELECT Id, Name, FirstName, PersonContactId FROM Account
                WHERE Id IN :req.partnerIds AND BD_Rep__c = :UserInfo.getUserId() AND PersonContactId != null
            ];
        }
        if (partners.isEmpty()) throw new AuraHandledException('Those partners are not in your book.');

        String name = String.isBlank(req.name) ? defaultEventName(kind, partners) : req.name.trim();
        // The invite artwork is chosen from the name, so make sure the kind is in it.
        if (kindOf(name) != kind) name = kind + ': ' + name;

        String description = (String.isBlank(req.location) ? '' : 'Location: ' + req.location.trim())
            + (String.isBlank(req.note) ? '' : (String.isBlank(req.location) ? '' : '\n') + req.note.trim());
        Campaign c = new Campaign(
            Name = name.left(80), Type = 'Event', Status = 'Planned', IsActive = true,
            StartDate = req.eventDate, EndDate = req.eventDate, Event_Time__c = t,
            Description = String.isBlank(description) ? null : description
        );
        insert c;
        Datetime startAt = Datetime.newInstance(req.eventDate, t);
        insert new Event(
            WhatId = c.Id, Subject = name.left(255), StartDateTime = startAt, EndDateTime = startAt.addMinutes(minutes),
            Location = String.isBlank(req.location) ? null : req.location.trim(), Description = c.Description,
            OwnerId = UserInfo.getUserId()
        );

        if (req.coHostIds != null && !req.coHostIds.isEmpty()) RealtorEventWorkspaceController.addCoHosts(c.Id, req.coHostIds);
        List<Id> contactIds = new List<Id>();
        for (Account a : partners) contactIds.add(a.PersonContactId);
        RealtorEventWorkspaceController.addInvitees(c.Id, contactIds);

        RealtorEventWorkspaceController.InvitationDraft draft = RealtorEventWorkspaceController.getInvitationDraft(c.Id);
        RealtorEventWorkspaceController.sendInvitations(c.Id, draft.emailSubject, draft.emailBody, draft.smsBody);
        return c.Id;
    }

    static String defaultEventName(String kind, List<Account> partners) {
        String who = partners.size() == 1 ? partners[0].Name : partners.size() + ' partners';
        return kind + ' with ' + UserInfo.getFirstName() + ' · ' + who;
    }

    @AuraEnabled
    public static EventDetail getEvent(Id campaignId) {
        if (!isRep() && !isManager()) {
            if (!LoWsPartnerTagService.isTagMode()) throw new AuraHandledException('You do not have access to the BD command center.');
            requireHostedByMe(campaignId);
        }
        EventDetail d = new EventDetail();
        List<EventRow> rows = eventRows(new Set<Id>{ campaignId }, null);
        if (rows.isEmpty()) throw new AuraHandledException('Event not found.');
        d.event = rows[0];
        Campaign c = [SELECT Owner.Name FROM Campaign WHERE Id = :campaignId];
        d.hosts.add(c.Owner.Name);
        for (Campaign_Co_Host__c h : [SELECT Co_Host__r.Name FROM Campaign_Co_Host__c WHERE Campaign__c = :campaignId ORDER BY CreatedDate]) d.hosts.add(h.Co_Host__r.Name);
        for (CampaignMember m : [
            SELECT Id, Status, Contact.Name, Contact.AccountId, Contact.Account.BD_Industry__c,
                   Invite_Email_Sent_At__c, Invite_SMS_Sent_At__c, RSVP_Reminder_Sent_At__c, Event_Reminder_Sent_At__c
            FROM CampaignMember WHERE CampaignId = :campaignId ORDER BY Contact.Name
        ]) {
            InviteeRow r = new InviteeRow();
            r.memberId = m.Id;
            r.partnerId = m.Contact.AccountId;
            r.name = m.Contact.Name;
            r.industry = m.Contact.Account.BD_Industry__c;
            r.status = m.Status;
            List<String> sent = new List<String>();
            if (m.Invite_Email_Sent_At__c != null) sent.add('Email ' + m.Invite_Email_Sent_At__c.format('M/d'));
            if (m.Invite_SMS_Sent_At__c != null) sent.add('text ' + m.Invite_SMS_Sent_At__c.format('M/d'));
            if (m.RSVP_Reminder_Sent_At__c != null) sent.add('reminder ' + m.RSVP_Reminder_Sent_At__c.format('M/d'));
            if (m.Event_Reminder_Sent_At__c != null) sent.add('day-before ' + m.Event_Reminder_Sent_At__c.format('M/d'));
            r.sentText = sent.isEmpty() ? null : String.join(sent, ' · ');
            d.invitees.add(r);
        }
        return d;
    }

    @AuraEnabled
    public static String resendInvite(Id campaignMemberId) {
        if (!isRep()) {
            requireLo();
            List<CampaignMember> m = [SELECT CampaignId FROM CampaignMember WHERE Id = :campaignMemberId];
            if (m.isEmpty()) throw new AuraHandledException('Invitee not found.');
            requireHostedByMe(m[0].CampaignId);
        }
        return RealtorEventWorkspaceController.resendInvitation(campaignMemberId).message;
    }

    /** The rep confirms whether a past meeting happened. Held moves the attendees to Met. */
    @AuraEnabled
    public static void confirmMeeting(Id campaignId, Boolean held) {
        requireRep();
        update new Campaign(Id = campaignId, BD_Outcome__c = held ? 'Held' : 'Did Not Happen');
        if (!held) return;
        Set<Id> accountIds = new Set<Id>();
        for (CampaignMember m : [
            SELECT Contact.AccountId FROM CampaignMember
            WHERE CampaignId = :campaignId AND Status != 'No - Unable to Attend'
        ]) accountIds.add(m.Contact.AccountId);
        List<Account> updates = new List<Account>();
        for (Account a : [
            SELECT Id, BD_Stage__c FROM Account
            WHERE Id IN :accountIds AND BD_Rep__c = :UserInfo.getUserId()
        ]) {
            if (a.BD_Stage__c == null || rank(a.BD_Stage__c) < rank('Met')) updates.add(new Account(Id = a.Id, BD_Stage__c = 'Met'));
        }
        if (!updates.isEmpty()) update updates;
    }
}