/**
 * LO Recruiting tab: Loan Officer record-type Leads worked by Fred and Adam.
 *
 * A lead is "in recruiting" when Recruit_Stage__c is set; the recruiter is the Lead Owner.
 * Recruits are owned by Fred or Adam and each must work the other's, so reads and writes run
 * without sharing behind the LO_Recruiting custom permission.
 *
 * Auto-moves (computed on every getHome, like the BD command center):
 *   New -> Contacted     any call/text/email/touch after the lead entered New
 *   -> Meeting Set       an upcoming Event with the recruit
 * Met, Offer Out and Hired are manual. Next_Touch_Date__c is set by Log touch from CADENCE_DAYS.
 */
public without sharing class LoRecruitingController {

    static final Id RT_ID = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
        .get('Loan_Officer_Lead_Record_Type').getRecordTypeId();
    static final String NOTE_PREFIX = 'Recruit Note';
    @TestVisible static final List<String> STAGE_ORDER = new List<String>{
        'New', 'Contacted', 'Conversation', 'Meeting Set', 'Met', 'Offer Out', 'Hired', 'Not Now', 'Not Interested'
    };
    static final Set<String> CLOSED = new Set<String>{ 'Hired', 'Not Interested' };
    // Days until the next touch after a touch is logged at a stage. Contacted: +3, then +7 once touched twice.
    static final Map<String, Integer> CADENCE_DAYS = new Map<String, Integer>{
        'New' => 0, 'Contacted' => 3, 'Conversation' => 3, 'Meeting Set' => 3, 'Met' => 3, 'Offer Out' => 3, 'Not Now' => 90
    };

    // ---------------------------------------------------------------- DTOs

    public class Recruit {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String initials;
        @AuraEnabled public String company;
        @AuraEnabled public String nmls;
        @AuraEnabled public String stage;
        @AuraEnabled public String phone;
        @AuraEnabled public String mobile;
        @AuraEnabled public String email;
        @AuraEnabled public String county;
        @AuraEnabled public String city;
        @AuraEnabled public Decimal volume;
        @AuraEnabled public String volumePeriod;
        @AuraEnabled public Boolean branchManager;
        @AuraEnabled public Boolean inHouse;
        @AuraEnabled public Boolean companySwitch;
        @AuraEnabled public Boolean remote;
        @AuraEnabled public Boolean followsBrandon;   // follows Brandon Brotsky on Instagram
        @AuraEnabled public Date nextTouch;
        @AuraEnabled public Date lastActivity;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        Option(String label, String value) { this.label = label; this.value = value; }
    }

    public class MeetingRow {
        @AuraEnabled public Id eventId;
        @AuraEnabled public Id leadId;
        @AuraEnabled public String name;
        @AuraEnabled public String subject;
        @AuraEnabled public Datetime startAt;
    }

    public class Stats {
        @AuraEnabled public Integer recruits = 0;
        @AuraEnabled public Integer touchedThisWeek = 0;
        @AuraEnabled public Integer callsThisWeek = 0;
        @AuraEnabled public Integer due = 0;
        @AuraEnabled public Map<String, Integer> byStage = new Map<String, Integer>();
    }

    public class Home {
        @AuraEnabled public Id userId;
        @AuraEnabled public String firstName;
        @AuraEnabled public List<Option> recruiters = new List<Option>();
        @AuraEnabled public List<String> stages = STAGE_ORDER;
        @AuraEnabled public List<Recruit> recruits = new List<Recruit>();
        @AuraEnabled public List<MeetingRow> meetings = new List<MeetingRow>();
        @AuraEnabled public Stats stats = new Stats();
    }

    public class TimelineItem {
        @AuraEnabled public String id;
        @AuraEnabled public String kind;   // call | text | email | meeting | touch | note
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
        @AuraEnabled public Datetime whenAt;
    }

    public class Detail {
        @AuraEnabled public Recruit recruit;
        @AuraEnabled public String street;
        @AuraEnabled public String state;
        @AuraEnabled public String zip;
        @AuraEnabled public String personalEmail;
        @AuraEnabled public String linkedIn;
        @AuraEnabled public String instagram;
        @AuraEnabled public String website;
        @AuraEnabled public String retr;
        @AuraEnabled public String flag;
        @AuraEnabled public String agentPartner;
        @AuraEnabled public String agentCompany;
        @AuraEnabled public String recruitList;
        @AuraEnabled public Id candidateAccountId;
        @AuraEnabled public Integer calls30 = 0;
        @AuraEnabled public List<TimelineItem> timeline = new List<TimelineItem>();
        @AuraEnabled public List<NoteRow> notes = new List<NoteRow>();
    }

    public class NoteRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String author;
        @AuraEnabled public Datetime whenAt;
    }

    // ---------------------------------------------------------------- access

    static void requireAccess() {
        if (!FeatureManagement.checkPermission('LO_Recruiting')) {
            throw new AuraHandledException('You do not have access to LO Recruiting.');
        }
    }

    static Lead requireRecruit(Id leadId) {
        requireAccess();
        List<Lead> rows = [
            SELECT Id, FirstName, LastName, Name, Company, NMLS__c, Email, Phone, MobilePhone, Recruit_Stage__c,
                   Candidate_Account__c, OwnerId
            FROM Lead WHERE Id = :leadId AND RecordTypeId = :RT_ID AND Recruit_Stage__c != null
        ];
        if (rows.isEmpty()) throw new AuraHandledException('That lead is not in LO Recruiting.');
        return rows[0];
    }

    // ---------------------------------------------------------------- home

    static final String LEAD_FIELDS = 'Id, Name, FirstName, LastName, Company, NMLS__c, Recruit_Stage__c, Phone, MobilePhone, Email, '
        + 'County_of_Operation__c, City, Loan_Volume__c, Volume_Period__c, Branch_Manager__c, Possible_In_House__c, '
        + 'Possible_Company_Switch__c, Remote_LO__c, Follows_Brandon_IG__c, Next_Touch_Date__c, LastActivityDate, OwnerId, Owner.Name, CreatedDate';

    @AuraEnabled
    public static Home getHome() {
        requireAccess();
        Home h = new Home();
        h.userId = UserInfo.getUserId();
        h.firstName = UserInfo.getFirstName();

        List<Lead> leads = Database.query('SELECT ' + LEAD_FIELDS
            + ' FROM Lead WHERE RecordTypeId = :RT_ID AND Recruit_Stage__c != null AND IsConverted = false'
            + ' ORDER BY Loan_Volume__c DESC NULLS LAST LIMIT 5000');
        advanceStages(leads);

        Map<Id, String> owners = new Map<Id, String>();
        for (Lead l : leads) {
            h.recruits.add(toRecruit(l));
            owners.put(l.OwnerId, l.Owner.Name);
        }
        for (User u : [
            SELECT Id, Name FROM User WHERE IsActive = true AND Id IN (
                SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSet.Name = 'LO_Recruiting')
        ]) owners.put(u.Id, u.Name);
        for (Id ownerId : owners.keySet()) h.recruiters.add(new Option(owners.get(ownerId), ownerId));

        Set<Id> ids = new Map<Id, Lead>(leads).keySet();
        for (Event e : [
            SELECT Id, WhoId, Who.Name, Subject, StartDateTime FROM Event
            WHERE WhoId IN :ids AND StartDateTime >= TODAY AND StartDateTime < NEXT_N_DAYS:8
            ORDER BY StartDateTime LIMIT 50
        ]) {
            MeetingRow m = new MeetingRow();
            m.eventId = e.Id; m.leadId = e.WhoId; m.name = e.Who.Name; m.subject = e.Subject; m.startAt = e.StartDateTime;
            h.meetings.add(m);
        }
        for (CampaignMember cm : [
            SELECT Id, LeadId, Name, Status, Campaign.Name, Campaign.StartDate, Campaign.Event_Time__c FROM CampaignMember
            WHERE LeadId IN :ids AND Campaign.Type = 'Event' AND Campaign.StartDate >= TODAY AND Campaign.StartDate < NEXT_N_DAYS:8
              AND Status != 'No - Unable to Attend'
            ORDER BY Campaign.StartDate LIMIT 50
        ]) {
            MeetingRow m = new MeetingRow();
            m.eventId = cm.Id; m.leadId = cm.LeadId; m.name = cm.Name; m.subject = cm.Campaign.Name + ' · ' + cm.Status;
            m.startAt = Datetime.newInstance(cm.Campaign.StartDate, cm.Campaign.Event_Time__c == null ? Time.newInstance(12, 0, 0, 0) : cm.Campaign.Event_Time__c);
            h.meetings.add(m);
        }
        return h;
    }

    /** Week stats for one recruiter (null = everyone); the stage counts are computed client-side. */
    @AuraEnabled
    public static Stats getWeekStats(Id ownerId) {
        requireAccess();
        Stats s = new Stats();
        Set<Id> touched = new Set<Id>();
        for (Task t : [
            SELECT WhoId, InteractionType__c FROM Task
            WHERE CreatedDate = THIS_WEEK AND WhoId IN (
                SELECT Id FROM Lead WHERE RecordTypeId = :RT_ID AND Recruit_Stage__c != null)
            LIMIT 10000
        ]) {
            touched.add(t.WhoId);
            if (t.InteractionType__c == 'Call') s.callsThisWeek++;
        }
        if (ownerId != null) {
            touched.retainAll(new Map<Id, Lead>([SELECT Id FROM Lead WHERE Id IN :touched AND OwnerId = :ownerId]).keySet());
        }
        s.touchedThisWeek = touched.size();
        return s;
    }

    static Recruit toRecruit(Lead l) {
        Recruit r = new Recruit();
        r.id = l.Id; r.name = l.Name; r.company = l.Company; r.nmls = l.NMLS__c; r.stage = l.Recruit_Stage__c;
        r.initials = (String.isBlank(l.FirstName) ? '' : l.FirstName.left(1)) + (String.isBlank(l.LastName) ? '' : l.LastName.left(1));
        r.phone = l.Phone; r.mobile = l.MobilePhone; r.email = l.Email;
        r.county = l.County_of_Operation__c; r.city = l.City;
        r.volume = l.Loan_Volume__c; r.volumePeriod = l.Volume_Period__c;
        r.branchManager = l.Branch_Manager__c; r.inHouse = l.Possible_In_House__c;
        r.companySwitch = l.Possible_Company_Switch__c; r.remote = l.Remote_LO__c; r.followsBrandon = l.Follows_Brandon_IG__c;
        r.nextTouch = l.Next_Touch_Date__c; r.lastActivity = l.LastActivityDate;
        r.ownerId = l.OwnerId; r.ownerName = l.Owner.Name;
        return r;
    }

    /** New -> Contacted after any activity since the lead entered New; open stages -> Meeting Set on an upcoming Event. */
    @TestVisible
    static void advanceStages(List<Lead> leads) {
        Map<Id, Lead> byId = new Map<Id, Lead>();
        Map<Id, Datetime> enteredNew = new Map<Id, Datetime>();
        for (Lead l : leads) {
            byId.put(l.Id, l);
            if (l.Recruit_Stage__c == 'New') enteredNew.put(l.Id, l.CreatedDate);
        }
        if (!enteredNew.isEmpty()) {
            for (LeadHistory lh : [
                SELECT LeadId, CreatedDate FROM LeadHistory
                WHERE LeadId IN :enteredNew.keySet() AND Field = 'Recruit_Stage__c' ORDER BY CreatedDate
            ]) enteredNew.put(lh.LeadId, lh.CreatedDate);   // ascending: the last write wins
        }

        Map<Id, Lead> updates = new Map<Id, Lead>();
        if (!enteredNew.isEmpty()) {
            Datetime oldest = Datetime.now();
            for (Datetime d : enteredNew.values()) if (d < oldest) oldest = d;
            String notePattern = NOTE_PREFIX + '%';
            for (Task t : [
                SELECT WhoId, CreatedDate, rcsfl__call_start_time__c FROM Task
                WHERE WhoId IN :enteredNew.keySet() AND CreatedDate >= :oldest AND (NOT Subject LIKE :notePattern)
            ]) {
                Datetime at = t.rcsfl__call_start_time__c != null ? t.rcsfl__call_start_time__c : t.CreatedDate;
                if (at > enteredNew.get(t.WhoId) && !updates.containsKey(t.WhoId)) {
                    updates.put(t.WhoId, new Lead(Id = t.WhoId, Recruit_Stage__c = 'Contacted',
                        Next_Touch_Date__c = Date.today().addDays(CADENCE_DAYS.get('Contacted'))));
                }
            }
        }
        // Upcoming meetings: a calendar Event with the recruit (Zoom) or an in-person invite they haven't declined.
        Set<Id> meetingLeadIds = new Set<Id>();
        for (Event e : [SELECT WhoId FROM Event WHERE WhoId IN :byId.keySet() AND StartDateTime >= :Datetime.now()]) meetingLeadIds.add(e.WhoId);
        for (CampaignMember m : [
            SELECT LeadId FROM CampaignMember
            WHERE LeadId IN :byId.keySet() AND Campaign.Type = 'Event' AND Campaign.StartDate >= TODAY AND Status != 'No - Unable to Attend'
        ]) meetingLeadIds.add(m.LeadId);
        Integer meetingRank = STAGE_ORDER.indexOf('Meeting Set');
        for (Id leadId : meetingLeadIds) {
            String stage = updates.containsKey(leadId) ? 'Contacted' : byId.get(leadId).Recruit_Stage__c;
            if (STAGE_ORDER.indexOf(stage) < meetingRank) {
                updates.put(leadId, new Lead(Id = leadId, Recruit_Stage__c = 'Meeting Set'));
            }
        }
        if (updates.isEmpty()) return;
        update updates.values();
        for (Lead u : updates.values()) {
            byId.get(u.Id).Recruit_Stage__c = u.Recruit_Stage__c;
            if (u.Next_Touch_Date__c != null) byId.get(u.Id).Next_Touch_Date__c = u.Next_Touch_Date__c;
        }
    }

    // ---------------------------------------------------------------- recruit workspace

    @AuraEnabled
    public static Detail getRecruit(Id leadId) {
        requireRecruit(leadId);
        Lead l = Database.query('SELECT ' + LEAD_FIELDS + ', Street, State, PostalCode, Personal_Email__c, LinkedIn__c, Instagram__c, '
            + 'Website, RETR_Link__c, Recruit_Flag__c, Recent_Agent_Partner__c, Recent_Agent_Company__c, Recruit_List__c, '
            + 'Candidate_Account__c FROM Lead WHERE Id = :leadId');
        Detail d = new Detail();
        advanceStages(new List<Lead>{ l });   // e.g. an invite just sent: show Meeting Set right away
        d.recruit = toRecruit(l);
        d.street = l.Street; d.state = l.State; d.zip = l.PostalCode; d.personalEmail = l.Personal_Email__c;
        d.linkedIn = l.LinkedIn__c; d.instagram = l.Instagram__c; d.website = l.Website; d.retr = l.RETR_Link__c;
        d.flag = l.Recruit_Flag__c; d.agentPartner = l.Recent_Agent_Partner__c; d.agentCompany = l.Recent_Agent_Company__c;
        d.recruitList = l.Recruit_List__c; d.candidateAccountId = l.Candidate_Account__c;

        // ALL ROWS: the merged Ben/Alex history is mostly archived (older than a year).
        Datetime since30 = Datetime.now().addDays(-30);
        for (Task t : [
            SELECT Id, Subject, Description, InteractionType__c, CallType, CallDurationInSeconds, CreatedDate, Owner.Name,
                   rcsfl__call_start_time__c, IsDeleted
            FROM Task WHERE WhoId = :leadId ORDER BY CreatedDate DESC LIMIT 200 ALL ROWS
        ]) {
            if (t.IsDeleted) continue;
            d.timeline.add(taskItem(t));
            if (t.InteractionType__c == 'Call' && whenOf(t) >= since30) d.calls30++;
        }
        for (Event e : [
            SELECT Id, Subject, Location, StartDateTime, Owner.Name, IsDeleted FROM Event
            WHERE WhoId = :leadId ORDER BY StartDateTime DESC LIMIT 50 ALL ROWS
        ]) {
            if (e.IsDeleted) continue;
            d.timeline.add(item(e.Id, 'meeting', e.Subject, (String.isBlank(e.Location) ? '' : e.Location + ' · ') + e.Owner.Name, e.StartDateTime));
        }
        for (EmailMessageRelation r : [
            SELECT EmailMessage.Id, EmailMessage.Subject, EmailMessage.FromName, EmailMessage.Incoming, EmailMessage.MessageDate
            FROM EmailMessageRelation WHERE RelationId = :leadId ORDER BY EmailMessage.MessageDate DESC LIMIT 50
        ]) {
            EmailMessage m = r.EmailMessage;
            d.timeline.add(item(m.Id, 'email', (m.Incoming ? 'Email received: ' : 'Email sent: ') + m.Subject, m.FromName, m.MessageDate));
        }
        for (CampaignMember cm : [
            SELECT Id, Status, Campaign.Name, Campaign.StartDate, Campaign.Event_Time__c, Campaign.Owner.Name FROM CampaignMember
            WHERE LeadId = :leadId AND Campaign.Type = 'Event' ORDER BY Campaign.StartDate DESC LIMIT 20
        ]) {
            Datetime at = cm.Campaign.StartDate == null ? null
                : Datetime.newInstance(cm.Campaign.StartDate, cm.Campaign.Event_Time__c == null ? Time.newInstance(12, 0, 0, 0) : cm.Campaign.Event_Time__c);
            d.timeline.add(item(cm.Id, 'meeting', 'In person: ' + cm.Campaign.Name, 'RSVP: ' + cm.Status + ' · host ' + cm.Campaign.Owner.Name, at));
        }
        sortTimeline(d.timeline);
        d.notes = notesFor(leadId);
        return d;
    }

    // ---------------------------------------------------------------- recruiting notes (standard Notes on the lead)

    static List<NoteRow> notesFor(Id leadId) {
        List<NoteRow> out = new List<NoteRow>();
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink c : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :leadId]) docIds.add(c.ContentDocumentId);
        if (docIds.isEmpty()) return out;
        for (ContentNote n : [
            SELECT Id, Title, Content, CreatedDate, CreatedBy.Name FROM ContentNote
            WHERE Id IN :docIds ORDER BY CreatedDate DESC LIMIT 100
        ]) {
            NoteRow r = new NoteRow();
            r.id = n.Id; r.title = n.Title; r.author = n.CreatedBy.Name; r.whenAt = n.CreatedDate;
            r.body = n.Content == null ? '' : plainText(n.Content.toString());
            out.add(r);
        }
        return out;
    }

    @TestVisible
    static String plainText(String html) {
        String t = html.replaceAll('(?i)<br\\s*/?>', '\n').replaceAll('(?i)</p>', '\n').replaceAll('<[^>]+>', '');
        return t.unescapeHtml4().trim();
    }

    static void insertNote(Id leadId, String title, String body) {
        ContentNote n = new ContentNote(Title = title, Content = Blob.valueOf(body.escapeHtml4().replace('\n', '<br>')));
        insert n;
        insert new ContentDocumentLink(ContentDocumentId = n.Id, LinkedEntityId = leadId, ShareType = 'I', Visibility = 'AllUsers');
    }

    @AuraEnabled
    public static void addNote(Id leadId, String body) {
        requireRecruit(leadId);
        if (String.isBlank(body)) throw new AuraHandledException('Type a note first.');
        insertNote(leadId, 'Recruiting note', body.trim());
    }

    static TimelineItem item(String id, String kind, String title, String detail, Datetime whenAt) {
        TimelineItem i = new TimelineItem();
        i.id = id; i.kind = kind; i.title = title; i.detail = detail; i.whenAt = whenAt;
        return i;
    }

    static TimelineItem taskItem(Task t) {
        String kind = 'touch', title = t.Subject;
        if (t.InteractionType__c == 'Call') {
            kind = 'call';
            title = (t.CallType == null ? '' : t.CallType + ' ') + 'call'
                + (t.CallDurationInSeconds == null || t.CallDurationInSeconds == 0 ? '' : ' · ' + (t.CallDurationInSeconds / 60) + 'm ' + Math.mod(t.CallDurationInSeconds, 60) + 's');
        } else if (t.InteractionType__c == 'Sms') {
            kind = 'text';
            title = t.CallType == 'Inbound' ? 'Text received' : 'Text sent';
        } else if (t.Subject != null && t.Subject.startsWith(NOTE_PREFIX)) {
            kind = 'note';
            title = 'Note';
        }
        return item(t.Id, kind, title, String.isBlank(t.Description) ? t.Owner.Name : t.Owner.Name + ': ' + t.Description.abbreviate(280), whenOf(t));
    }

    static Datetime whenOf(Task t) {
        return t.rcsfl__call_start_time__c != null ? t.rcsfl__call_start_time__c : t.CreatedDate;
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

    // ---------------------------------------------------------------- edits

    /** Default next touch after logging one now at this stage (the modal shows it and lets the recruiter change it). */
    @AuraEnabled
    public static Date suggestNextTouch(Id leadId, Boolean conversation) {
        Lead l = requireRecruit(leadId);
        String stage = stageAfterTouch(l.Recruit_Stage__c, conversation == true);
        if (CLOSED.contains(stage)) return null;
        Integer days = CADENCE_DAYS.get(stage);
        if (stage == 'Contacted' && l.Recruit_Stage__c == 'Contacted') days = 7;   // second touch at Contacted
        return Date.today().addDays(days);
    }

    @TestVisible
    static String stageAfterTouch(String stage, Boolean conversation) {
        if (conversation && STAGE_ORDER.indexOf(stage) < STAGE_ORDER.indexOf('Conversation')) return 'Conversation';
        if (stage == 'New') return 'Contacted';
        return stage;
    }

    /**
     * kind: Call | Text | Email | In person | Note. Typed notes also post to Recruiting Notes.
     * A Note is only a Recruiting Note: no Task, no stage move, no next-touch change.
     */
    @AuraEnabled
    public static void logTouch(Id leadId, String kind, String notes, Boolean conversation, Date nextTouch) {
        Lead l = requireRecruit(leadId);
        Boolean isNote = kind == 'Note';
        if (!String.isBlank(notes)) insertNote(leadId, isNote ? 'Recruiting note' : 'Recruiting note · ' + kind + ' touch', notes.trim());
        if (isNote) return;
        insert new Task(
            OwnerId = UserInfo.getUserId(), WhoId = leadId,
            Subject = 'Recruit Touch: ' + kind, Description = notes,
            Status = 'Completed', ActivityDate = Date.today()
        );
        update new Lead(Id = leadId, Recruit_Stage__c = stageAfterTouch(l.Recruit_Stage__c, conversation == true), Next_Touch_Date__c = nextTouch);
    }

    @AuraEnabled
    public static void setStage(Id leadId, String stage) {
        requireRecruit(leadId);
        if (!STAGE_ORDER.contains(stage)) throw new AuraHandledException('Unknown stage.');
        if (stage == 'Hired') throw new AuraHandledException('Use Mark Hired so the Candidate onboarding starts.');
        Lead u = new Lead(Id = leadId, Recruit_Stage__c = stage);
        if (stage == 'Not Interested') {
            u.Next_Touch_Date__c = null; u.DoNotCall = true; u.HasOptedOutOfEmail = true;
        } else if (stage == 'Not Now') {
            u.Next_Touch_Date__c = Date.today().addDays(CADENCE_DAYS.get('Not Now'));
        }
        update u;
    }

    @AuraEnabled
    public static void setNextTouch(Id leadId, Date nextTouch) {
        requireRecruit(leadId);
        update new Lead(Id = leadId, Next_Touch_Date__c = nextTouch);
    }

    /** Hand a recruit to another recruiter (any LO_Recruiting user). */
    @AuraEnabled
    public static void setRecruiter(Id leadId, Id userId) {
        requireRecruit(leadId);
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSet.Name = 'LO_Recruiting'] == 0) {
            throw new AuraHandledException('That user is not set up for LO Recruiting.');
        }
        update new Lead(Id = leadId, OwnerId = userId);
    }

    /** Hired: creates the Candidate Person Account (its flow builds the onboarding checklist) and links it. */
    @AuraEnabled
    public static Id markHired(Id leadId) {
        Lead l = requireRecruit(leadId);
        if (l.Candidate_Account__c != null) {
            update new Lead(Id = leadId, Recruit_Stage__c = 'Hired', Next_Touch_Date__c = null);
            return l.Candidate_Account__c;
        }
        Account a = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidate').getRecordTypeId(),
            FirstName = l.FirstName, LastName = l.LastName, PersonEmail = l.Email,
            PersonMobilePhone = l.MobilePhone, Phone = l.Phone, Type__c = 'Other',
            Current_Mortgage_Company__pc = l.Company,
            NMLS__pc = String.isBlank(l.NMLS__c) || !l.NMLS__c.isNumeric() ? null : Decimal.valueOf(l.NMLS__c)
        );
        insert a;
        update new Lead(Id = leadId, Recruit_Stage__c = 'Hired', Next_Touch_Date__c = null, Candidate_Account__c = a.Id);
        return a.Id;
    }
}
