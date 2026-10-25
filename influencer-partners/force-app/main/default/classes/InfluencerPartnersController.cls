/**
 * Influencer Partners pipeline (Ernesto's working tab, also its own CustomTab). Design: influencer-partners/GRILL.md.
 * Partners are Person Accounts with Influencer_Stage__c set; that field, never Type__c, says "is a partner".
 * Program leads = LeadSource 'Influencer Partners'; partner = Lead/Transaction Referral_Source__c (the PersonContact).
 * Without sharing because Lead OWD is Private and the lead/loan views are read-only for the team;
 * every entry point is gated by the Influencer_Partners custom permission.
 */
public without sharing class InfluencerPartnersController {
    public static final List<String> STAGE_ORDER = new List<String>{
        'Target', 'Contacted', 'Meeting Booked', 'Follow Up', 'Marketing Agreement Signed',
        'Landing Page Launched & Tested', 'Active', 'Lost'
    };
    public static final Integer NEEDS_TOUCH_DAYS = 14;
    public static final String INTAKE_BASE = 'https://reachhomeloans.my.site.com/LeadIntakeForm/s/?partner=';
    static final String TOUCH_PREFIX = 'Influencer Touch: ';
    static final String NOTE_SUBJECT = 'Influencer Note';
    static final String SOURCE = LeadInfluencerAttribution.LEAD_SOURCE;
    static final Set<String> CLOSED = new Set<String>{ 'Post-Closed' };
    static final Set<String> CANCELLED = new Set<String>{ 'Cancelled', 'Lost' };

    // ---------------------------------------------------------------- DTOs

    public class Home {
        @AuraEnabled public List<String> stages = STAGE_ORDER;
        @AuraEnabled public List<String> channels = values(Account.Biggest_Channel__c.getDescribe());
        @AuraEnabled public List<String> lostReasons = values(Account.Influencer_Lost_Reason__c.getDescribe());
        @AuraEnabled public List<Option> loanOfficers = new List<Option>();
        @AuraEnabled public List<Partner> partners = new List<Partner>();
        @AuraEnabled public Integer needsTouch = 0;
        @AuraEnabled public Integer active = 0;
    }

    public class Option {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        Option(String value, String label) { this.value = value; this.label = label; }
    }

    public class Partner {
        @AuraEnabled public Id id;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String stage;
        @AuraEnabled public String channel;
        @AuraEnabled public String channelUrl;
        @AuraEnabled public Decimal audience;
        @AuraEnabled public String offerWebsite;
        @AuraEnabled public Id loId;
        @AuraEnabled public String loName;
        @AuraEnabled public String code;
        @AuraEnabled public Boolean codeLocked = false;
        @AuraEnabled public String intakeLink;
        @AuraEnabled public Date agreementDate;
        @AuraEnabled public Decimal monthlyFee;
        @AuraEnabled public String notes;
        @AuraEnabled public String lostReason;
        @AuraEnabled public String lostFrom;
        @AuraEnabled public Date lostDate;
        @AuraEnabled public Datetime lastTouch;
        @AuraEnabled public Integer daysQuiet;
        @AuraEnabled public Boolean needsTouch = false;
        @AuraEnabled public Integer leads = 0;
        @AuraEnabled public Integer closed = 0;
        @AuraEnabled public Decimal volume = 0;
    }

    public class Detail {
        @AuraEnabled public Partner partner;
        @AuraEnabled public List<TimelineItem> timeline = new List<TimelineItem>();
        @AuraEnabled public List<LeadRow> leads = new List<LeadRow>();
        @AuraEnabled public List<LoanRow> loans = new List<LoanRow>();
        @AuraEnabled public ResultRow results;
    }

    public class TimelineItem implements Comparable {
        @AuraEnabled public Id id;
        @AuraEnabled public String kind;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public Datetime whenAt;
        @AuraEnabled public String who;
        public Integer compareTo(Object o) {
            Datetime b = ((TimelineItem) o).whenAt;
            if (whenAt == b) return 0;
            if (whenAt == null) return 1;
            if (b == null) return -1;
            return whenAt > b ? -1 : 1;
        }
    }

    public class LeadRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Id partnerId;
        @AuraEnabled public String partnerName;
        @AuraEnabled public Datetime created;
        @AuraEnabled public Date preApprovalDate;
        @AuraEnabled public Boolean converted;
    }

    public class LoanRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String loName;
        @AuraEnabled public Id partnerId;
        @AuraEnabled public String partnerName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closedDate;
        @AuraEnabled public Datetime created;
    }

    public class ResultRow {
        @AuraEnabled public Id partnerId;
        @AuraEnabled public String partnerName;
        @AuraEnabled public String stage;
        @AuraEnabled public Integer leads = 0;
        @AuraEnabled public Integer preApproved = 0;
        @AuraEnabled public Integer loans = 0;
        @AuraEnabled public Integer closed = 0;
        @AuraEnabled public Integer cancelled = 0;
        @AuraEnabled public Decimal volume = 0;
        @AuraEnabled public Decimal cost = 0;
        @AuraEnabled public Decimal costPerClosed;
        @AuraEnabled public Decimal conversion;
    }

    public class Results {
        @AuraEnabled public ResultRow total;
        @AuraEnabled public List<ResultRow> partners = new List<ResultRow>();
        @AuraEnabled public Date rangeStart;
    }

    public class PartnerInput {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String channel { get; set; }
        @AuraEnabled public String channelUrl { get; set; }
        @AuraEnabled public Decimal audience { get; set; }
        @AuraEnabled public String offerWebsite { get; set; }
        @AuraEnabled public Id loId { get; set; }
        @AuraEnabled public String code { get; set; }
        @AuraEnabled public Date agreementDate { get; set; }
        @AuraEnabled public Decimal monthlyFee { get; set; }
        @AuraEnabled public String notes { get; set; }
    }

    public class Duplicate {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String typeLabel;
        @AuraEnabled public String matchedOn;
        @AuraEnabled public Boolean alreadyPartner;
    }

    // ---------------------------------------------------------------- access

    static void requireAccess() {
        if (!FeatureManagement.checkPermission('Influencer_Partners')) {
            throw new AuraHandledException('You do not have access to Influencer Partners.');
        }
    }

    static List<String> values(Schema.DescribeFieldResult f) {
        List<String> out = new List<String>();
        for (Schema.PicklistEntry e : f.getPicklistValues()) if (e.isActive()) out.add(e.getValue());
        return out;
    }

    // ---------------------------------------------------------------- pipeline

    @AuraEnabled
    public static Home getHome() {
        requireAccess();
        Home h = new Home();
        // Assignable LOs = active people who own a lead created in the last 90 days.
        Set<Id> owners = new Set<Id>();
        for (AggregateResult r : [SELECT OwnerId o FROM Lead WHERE CreatedDate = LAST_N_DAYS:90 GROUP BY OwnerId]) owners.add((Id) r.get('o'));
        for (User u : [SELECT Id, Name FROM User WHERE IsActive = true AND UserType = 'Standard' AND Id IN :owners ORDER BY Name]) {
            h.loanOfficers.add(new Option(u.Id, u.Name));
        }

        Map<Id, Account> accounts = partnerAccounts(null);
        Map<Id, Partner> partners = buildPartners(accounts);
        advanceStages(accounts, partners);
        for (Partner p : partners.values()) {
            if (p.needsTouch) h.needsTouch++;
            if (p.stage == 'Active') h.active++;
        }
        h.partners = partners.values();
        return h;
    }

    static Map<Id, Account> partnerAccounts(Set<Id> onlyIds) {
        String q = 'SELECT Id, Name, FirstName, LastName, PersonContactId, PersonEmail, PersonMobilePhone, Phone, CreatedDate, '
            + 'Influencer_Stage__c, Influencer_Lost_Reason__c, Influencer_Lost_From_Stage__c, Influencer_Lost_Date__c, '
            + 'Biggest_Channel__c, Channel_URL__c, Audience_Size__c, Offer_Website__c, Influencer_Assigned_LO__c, '
            + 'Influencer_Assigned_LO__r.Name, Influencer_Partner_Code__c, Influencer_Agreement_Signed__c, '
            + 'Influencer_Monthly_Fee__c, Influencer_Notes__c '
            + 'FROM Account WHERE Influencer_Stage__c != null AND IsPersonAccount = true';
        if (onlyIds != null) q += ' AND Id IN :onlyIds';
        return new Map<Id, Account>((List<Account>) Database.query(q + ' ORDER BY Name LIMIT 2000'));
    }

    static Map<Id, Partner> buildPartners(Map<Id, Account> accounts) {
        Map<Id, Datetime> lastTouch = lastTouchByAccount(accounts);
        Map<Id, Id> accountByContact = accountByContact(accounts);
        Map<Id, Partner> out = new Map<Id, Partner>();
        for (Account a : accounts.values()) out.put(a.Id, toPartner(a));

        // A new lead from an Active partner counts as contact for the touch clock.
        Map<Id, Datetime> lastLead = new Map<Id, Datetime>();
        for (AggregateResult r : [
            SELECT Referral_Source__c c, COUNT(Id) n, MAX(CreatedDate) lastAt FROM Lead
            WHERE Referral_Source__c IN :accountByContact.keySet() AND LeadSource = :SOURCE
            GROUP BY Referral_Source__c
        ]) {
            Partner p = out.get(accountByContact.get((Id) r.get('c')));
            p.leads = (Integer) r.get('n');
            p.codeLocked = true;
            lastLead.put(p.id, (Datetime) r.get('lastAt'));
        }
        for (LoanRow l : loanRows(accounts, false)) {
            Partner p = out.get(l.partnerId);
            if (p == null || !CLOSED.contains(l.status)) continue;
            p.closed++;
            p.volume += l.amount == null ? 0 : l.amount;
        }
        for (Partner p : out.values()) {
            Datetime t = lastTouch.get(p.id);
            if (p.stage == 'Active' && lastLead.containsKey(p.id) && (t == null || lastLead.get(p.id) > t)) t = lastLead.get(p.id);
            p.lastTouch = t;
            Datetime since = t == null ? accounts.get(p.id).CreatedDate : t;
            p.daysQuiet = since.date().daysBetween(Date.today());
            p.needsTouch = p.stage != 'Lost' && p.daysQuiet >= NEEDS_TOUCH_DAYS;
        }
        return out;
    }

    static Partner toPartner(Account a) {
        Partner p = new Partner();
        p.id = a.Id;
        p.contactId = a.PersonContactId;
        p.name = a.Name;
        p.firstName = a.FirstName;
        p.lastName = a.LastName;
        p.email = a.PersonEmail;
        p.phone = String.isNotBlank(a.PersonMobilePhone) ? a.PersonMobilePhone : a.Phone;
        p.stage = a.Influencer_Stage__c;
        p.channel = a.Biggest_Channel__c;
        p.channelUrl = a.Channel_URL__c;
        p.audience = a.Audience_Size__c;
        p.offerWebsite = a.Offer_Website__c;
        p.loId = a.Influencer_Assigned_LO__c;
        p.loName = a.Influencer_Assigned_LO__r == null ? null : a.Influencer_Assigned_LO__r.Name;
        p.code = a.Influencer_Partner_Code__c;
        p.intakeLink = String.isBlank(a.Influencer_Partner_Code__c) ? null : INTAKE_BASE + a.Influencer_Partner_Code__c;
        p.agreementDate = a.Influencer_Agreement_Signed__c;
        p.monthlyFee = a.Influencer_Monthly_Fee__c;
        p.notes = a.Influencer_Notes__c;
        p.lostReason = a.Influencer_Lost_Reason__c;
        p.lostFrom = a.Influencer_Lost_From_Stage__c;
        p.lostDate = a.Influencer_Lost_Date__c;
        return p;
    }

    static Map<Id, Id> accountByContact(Map<Id, Account> accounts) {
        Map<Id, Id> out = new Map<Id, Id>();
        for (Account a : accounts.values()) if (a.PersonContactId != null) out.put(a.PersonContactId, a.Id);
        return out;
    }

    // Logged touches, past meetings and synced calls/emails; notes don't count (same rule as the BD tab).
    static Map<Id, Datetime> lastTouchByAccount(Map<Id, Account> accounts) {
        Map<Id, Datetime> out = new Map<Id, Datetime>();
        if (accounts.isEmpty()) return out;
        Set<Id> ids = accounts.keySet();
        String notePattern = NOTE_SUBJECT + '%';
        for (AggregateResult r : [
            SELECT AccountId acc, MAX(CreatedDate) lastAt FROM Task
            WHERE AccountId IN :ids AND (NOT Subject LIKE :notePattern)
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
        return out;
    }

    static void bump(Map<Id, Datetime> m, Id key, Datetime value) {
        if (key == null || value == null) return;
        if (!m.containsKey(key) || m.get(key) < value) m.put(key, value);
    }

    // Auto-moves (on read): Target -> Contacted once anything is logged; Target/Contacted -> Meeting Booked
    // when a future meeting exists. Everything else is manual.
    static void advanceStages(Map<Id, Account> accounts, Map<Id, Partner> partners) {
        Set<Id> early = new Set<Id>();
        for (Partner p : partners.values()) if (p.stage == 'Target' || p.stage == 'Contacted') early.add(p.id);
        if (early.isEmpty()) return;
        Set<Id> booked = new Set<Id>();
        for (Event e : [SELECT AccountId FROM Event WHERE AccountId IN :early AND StartDateTime > :Datetime.now()]) booked.add(e.AccountId);
        List<Account> updates = new List<Account>();
        for (Id id : early) {
            Partner p = partners.get(id);
            String next = booked.contains(id) ? 'Meeting Booked' : (p.stage == 'Target' && p.lastTouch != null ? 'Contacted' : null);
            if (next == null) continue;
            p.stage = next;
            updates.add(new Account(Id = id, Influencer_Stage__c = next));
        }
        if (!updates.isEmpty()) update updates;
    }

    @AuraEnabled
    public static Detail getPartner(Id accountId) {
        requireAccess();
        Map<Id, Account> accounts = partnerAccounts(new Set<Id>{ accountId });
        if (accounts.isEmpty()) throw new AuraHandledException('That partner was not found.');
        Detail d = new Detail();
        d.partner = buildPartners(accounts).get(accountId);
        d.leads = leadRows(accounts, true);
        d.loans = loanRows(accounts, true);
        d.results = buildResults(accounts, null, d.leads, d.loans).partners[0];

        Account a = accounts.get(accountId);
        for (Task t : [
            SELECT Id, Subject, Description, CreatedDate, Owner.Name FROM Task
            WHERE AccountId = :accountId ORDER BY CreatedDate DESC LIMIT 100
        ]) {
            TimelineItem i = new TimelineItem();
            i.id = t.Id;
            i.kind = t.Subject != null && t.Subject.startsWith(NOTE_SUBJECT) ? 'Note' : 'Touch';
            i.title = t.Subject == null ? 'Activity' : t.Subject.removeStart(TOUCH_PREFIX);
            i.body = t.Description;
            i.whenAt = t.CreatedDate;
            i.who = t.Owner.Name;
            d.timeline.add(i);
        }
        for (Event e : [
            SELECT Id, Subject, Description, StartDateTime, Owner.Name FROM Event
            WHERE AccountId = :accountId ORDER BY StartDateTime DESC LIMIT 50
        ]) {
            TimelineItem i = new TimelineItem();
            i.id = e.Id;
            i.kind = e.StartDateTime > Datetime.now() ? 'Upcoming' : 'Meeting';
            i.title = e.Subject;
            i.body = e.Description;
            i.whenAt = e.StartDateTime;
            i.who = e.Owner.Name;
            d.timeline.add(i);
        }
        for (LeadRow l : d.leads) {
            TimelineItem i = new TimelineItem();
            i.id = l.id;
            i.kind = 'Lead';
            i.title = 'New lead: ' + l.name;
            i.whenAt = l.created;
            i.who = l.ownerName;
            d.timeline.add(i);
        }
        d.timeline.sort();
        return d;
    }

    @AuraEnabled
    public static void setStage(Id accountId, String stage, String lostReason) {
        requireAccess();
        if (!STAGE_ORDER.contains(stage)) throw new AuraHandledException('Unknown stage.');
        Account a = [SELECT Id, Influencer_Stage__c FROM Account WHERE Id = :accountId AND Influencer_Stage__c != null];
        if (a.Influencer_Stage__c == stage) return;
        Account u = new Account(Id = accountId, Influencer_Stage__c = stage);
        if (stage == 'Lost') {
            if (String.isBlank(lostReason)) throw new AuraHandledException('Pick a reason before marking a partner Lost.');
            u.Influencer_Lost_Reason__c = lostReason;
            u.Influencer_Lost_From_Stage__c = a.Influencer_Stage__c;
            u.Influencer_Lost_Date__c = Date.today();
        } else {
            u.Influencer_Lost_Reason__c = null;
            u.Influencer_Lost_From_Stage__c = null;
            u.Influencer_Lost_Date__c = null;
        }
        if (stage == 'Active') u.Type__c = typeForActive(accountId);
        update u;
    }

    // An existing borrower keeps Borrower Account (Type__c is single-select); everyone else is an Influencer Partner.
    static String typeForActive(Id accountId) {
        String t = [SELECT Type__c FROM Account WHERE Id = :accountId].Type__c;
        return t == 'Borrower Account' ? t : 'Influencer Partner';
    }

    /** Reopen a Lost partner to the stage they were lost from. */
    @AuraEnabled
    public static void reopen(Id accountId) {
        requireAccess();
        Account a = [SELECT Influencer_Lost_From_Stage__c FROM Account WHERE Id = :accountId AND Influencer_Stage__c = 'Lost'];
        String back = STAGE_ORDER.contains(a.Influencer_Lost_From_Stage__c) ? a.Influencer_Lost_From_Stage__c : 'Follow Up';
        setStage(accountId, back, null);
    }

    @AuraEnabled
    public static void savePartner(PartnerInput input) {
        requireAccess();
        Account a = [
            SELECT Id, Influencer_Partner_Code__c, PersonContactId FROM Account
            WHERE Id = :input.id AND Influencer_Stage__c != null
        ];
        if (String.isBlank(input.lastName)) throw new AuraHandledException('Last name is required.');
        Account u = new Account(
            Id = a.Id,
            FirstName = trimmed(input.firstName), LastName = input.lastName.trim(),
            PersonEmail = trimmed(input.email), PersonMobilePhone = trimmed(input.phone),
            Biggest_Channel__c = trimmed(input.channel), Channel_URL__c = trimmed(input.channelUrl),
            Audience_Size__c = input.audience, Offer_Website__c = trimmed(input.offerWebsite),
            Influencer_Assigned_LO__c = input.loId, Influencer_Agreement_Signed__c = input.agreementDate,
            Influencer_Monthly_Fee__c = input.monthlyFee, Influencer_Notes__c = trimmed(input.notes)
        );
        String code = normalizeCode(input.code);
        if (code != a.Influencer_Partner_Code__c) {
            if (codeLocked(a)) throw new AuraHandledException('The intake code is locked: leads have already come in on this link.');
            if (String.isBlank(code)) throw new AuraHandledException('The intake code cannot be blank.');
            if ([SELECT COUNT() FROM Account WHERE Influencer_Partner_Code__c = :code AND Id != :a.Id] > 0) {
                throw new AuraHandledException('Another partner already uses the code ' + code + '.');
            }
            u.Influencer_Partner_Code__c = code;
        }
        update u;
    }

    static Boolean codeLocked(Account a) {
        return [SELECT COUNT() FROM Lead WHERE Referral_Source__c = :a.PersonContactId AND LeadSource = :SOURCE] > 0;
    }

    static String trimmed(String s) { return String.isBlank(s) ? null : s.trim(); }

    @TestVisible
    static String normalizeCode(String raw) {
        return String.isBlank(raw) ? null : raw.trim().toUpperCase().replaceAll('[^A-Z0-9-]', '');
    }

    /** FIRST-L from the name, numbered on a collision: MARIA-G, MARIA-G2 ... */
    @TestVisible
    static String generateCode(String firstName, String lastName) {
        String first = normalizeCode(firstName) == null ? '' : normalizeCode(firstName).replace('-', '');
        String last = normalizeCode(lastName) == null ? 'X' : normalizeCode(lastName).replace('-', '');
        String root = (String.isBlank(first) ? last : first.left(12) + '-' + last.left(1));
        if (String.isBlank(root)) root = 'PARTNER';
        Set<String> taken = new Set<String>();
        String pattern = root + '%';
        for (Account a : [SELECT Influencer_Partner_Code__c FROM Account WHERE Influencer_Partner_Code__c LIKE :pattern]) {
            taken.add(a.Influencer_Partner_Code__c.toUpperCase());
        }
        String code = root;
        for (Integer n = 2; taken.contains(code); n++) code = root + n;
        return code;
    }

    // ---------------------------------------------------------------- adding partners

    @AuraEnabled
    public static List<Duplicate> findDuplicates(String email, String phone) {
        requireAccess();
        Map<Id, String> matched = new Map<Id, String>();
        for (PersonAccountDuplicateService.Match m : PersonAccountDuplicateService.findMatches(email, phone, null)) {
            matched.put(m.accountId, m.matchedOn);
        }
        List<Duplicate> out = new List<Duplicate>();
        if (matched.isEmpty()) return out;
        for (Account a : [
            SELECT Id, Name, PersonEmail, PersonMobilePhone, Phone, Type__c, Influencer_Stage__c
            FROM Account WHERE Id IN :matched.keySet()
        ]) {
            Duplicate d = new Duplicate();
            d.id = a.Id;
            d.name = a.Name;
            d.email = a.PersonEmail;
            d.phone = String.isNotBlank(a.PersonMobilePhone) ? a.PersonMobilePhone : a.Phone;
            d.typeLabel = a.Type__c == null ? null : a.Type__c.removeEnd(' Account');
            d.matchedOn = matched.get(a.Id);
            d.alreadyPartner = a.Influencer_Stage__c != null;
            out.add(d);
        }
        return out;
    }

    /** Links an existing person: keeps their Type__c, starts them at Target. */
    @AuraEnabled
    public static Id addExisting(Id accountId, PartnerInput input) {
        requireAccess();
        Account a = [SELECT Id, FirstName, LastName, Influencer_Stage__c, Influencer_Partner_Code__c FROM Account WHERE Id = :accountId AND IsPersonAccount = true];
        if (a.Influencer_Stage__c != null) return a.Id;
        a.Influencer_Stage__c = 'Target';
        if (a.Influencer_Partner_Code__c == null) a.Influencer_Partner_Code__c = generateCode(a.FirstName, a.LastName);
        if (input != null) applyChannel(a, input);
        update a;
        return a.Id;
    }

    @AuraEnabled
    public static Id createPartner(PartnerInput input) {
        requireAccess();
        if (input == null || String.isBlank(input.firstName) || String.isBlank(input.lastName)) {
            throw new AuraHandledException('First and last name are required.');
        }
        if (String.isBlank(input.phone) && String.isBlank(input.email)) throw new AuraHandledException('Enter a phone or an email.');
        try {
            PersonAccountDuplicateService.blockIfDuplicate(input.email, input.phone);
        } catch (PersonAccountDuplicateService.DuplicateFoundException e) {
            throw new AuraHandledException(e.getMessage());
        }
        Account a = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = input.firstName.trim(), LastName = input.lastName.trim(),
            PersonEmail = trimmed(input.email), PersonMobilePhone = trimmed(input.phone),
            Type__c = 'Influencer Partner', Influencer_Stage__c = 'Target',
            Influencer_Partner_Code__c = generateCode(input.firstName, input.lastName)
        );
        applyChannel(a, input);
        insert a;
        return a.Id;
    }

    static void applyChannel(Account a, PartnerInput input) {
        if (String.isNotBlank(input.channel)) a.Biggest_Channel__c = input.channel;
        if (String.isNotBlank(input.channelUrl)) a.Channel_URL__c = input.channelUrl.trim();
        if (input.audience != null) a.Audience_Size__c = input.audience;
        if (String.isNotBlank(input.offerWebsite)) a.Offer_Website__c = input.offerWebsite.trim();
        if (input.loId != null) a.Influencer_Assigned_LO__c = input.loId;
    }

    // ---------------------------------------------------------------- touches + leads

    /** kind: Call | Text | Email | Meeting | Note. Notes do not reset the 14-day clock. */
    @AuraEnabled
    public static void logTouch(Id accountId, String kind, String notes) {
        requireAccess();
        Account a = [SELECT PersonContactId FROM Account WHERE Id = :accountId AND Influencer_Stage__c != null];
        insert new Task(
            OwnerId = UserInfo.getUserId(), WhatId = accountId, WhoId = a.PersonContactId,
            Subject = kind == 'Note' ? NOTE_SUBJECT : TOUCH_PREFIX + kind,
            Description = notes, Status = 'Completed', ActivityDate = Date.today()
        );
    }

    @AuraEnabled
    public static Id createLead(Id accountId, String firstName, String lastName, String phone, String email, String notes) {
        requireAccess();
        if (String.isBlank(firstName) || String.isBlank(lastName)) throw new AuraHandledException('First and last name are required.');
        if (String.isBlank(phone) && String.isBlank(email)) throw new AuraHandledException('Enter a phone or an email.');
        Account a = [
            SELECT Name, PersonContactId, Influencer_Assigned_LO__c, Influencer_Assigned_LO__r.IsActive
            FROM Account WHERE Id = :accountId AND Influencer_Stage__c != null
        ];
        Lead l = new Lead(
            RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId(),
            LeadSource = SOURCE, Referral_Source__c = a.PersonContactId,
            FirstName = firstName.trim(), LastName = lastName.trim(), Company = firstName.trim() + ' ' + lastName.trim(),
            Phone = trimmed(phone), Email = trimmed(email),
            Comments__c = 'Referred by ' + a.Name + ' (Influencer Partner)' + (String.isBlank(notes) ? '' : '. ' + notes.trim())
        );
        if (a.Influencer_Assigned_LO__c != null && a.Influencer_Assigned_LO__r.IsActive) {
            l.OwnerId = a.Influencer_Assigned_LO__c;
        } else {
            Database.DMLOptions opts = new Database.DMLOptions();
            opts.assignmentRuleHeader.useDefaultRule = true;
            l.setOptions(opts);
        }
        insert l;
        return l.Id;
    }

    // ---------------------------------------------------------------- leads, loans, results

    @AuraEnabled
    public static List<LeadRow> getLeads() {
        requireAccess();
        return leadRows(partnerAccounts(null), false);
    }

    @AuraEnabled
    public static List<LoanRow> getLoans() {
        requireAccess();
        return loanRows(partnerAccounts(null), false);
    }

    /** range: MONTH | QUARTER | YTD | ALL */
    @AuraEnabled
    public static Results getResults(String range) {
        requireAccess();
        Date start = rangeStart(range);
        Map<Id, Account> accounts = partnerAccounts(null);
        Results r = buildResults(accounts, start, leadRows(accounts, false), loanRows(accounts, false));
        r.rangeStart = start;
        return r;
    }

    @TestVisible
    static Date rangeStart(String range) {
        Date t = Date.today();
        if (range == 'MONTH') return t.toStartOfMonth();
        if (range == 'QUARTER') return Date.newInstance(t.year(), ((t.month() - 1) / 3) * 3 + 1, 1);
        if (range == 'ALL') return null;
        return Date.newInstance(t.year(), 1, 1);
    }

    // Program leads (every Influencer Partners lead, attributed or not) plus partner-referred leads.
    static List<LeadRow> leadRows(Map<Id, Account> accounts, Boolean onePartner) {
        Map<Id, Id> byContact = accountByContact(accounts);
        Set<Id> contactIds = byContact.keySet();
        String q = 'SELECT Id, Name, Status, Owner.Name, Referral_Source__c, Referral_Source__r.Name, CreatedDate, '
            + 'Pre_Approval_Date__c, IsConverted FROM Lead WHERE LeadSource = :SOURCE';
        if (onePartner) q += ' AND Referral_Source__c IN :contactIds';
        List<LeadRow> out = new List<LeadRow>();
        for (Lead l : (List<Lead>) Database.query(q + ' ORDER BY CreatedDate DESC LIMIT 5000')) {
            LeadRow r = new LeadRow();
            r.id = l.Id;
            r.name = l.Name;
            r.status = l.Status;
            r.ownerName = l.Owner.Name;
            r.partnerId = byContact.get(l.Referral_Source__c);
            r.partnerName = l.Referral_Source__r == null ? null : l.Referral_Source__r.Name;
            r.created = l.CreatedDate;
            r.preApprovalDate = l.Pre_Approval_Date__c;
            r.converted = l.IsConverted;
            out.add(r);
        }
        return out;
    }

    // Loans tagged Influencer Partners, plus any converted from a program lead (in case the tag was edited).
    static List<LoanRow> loanRows(Map<Id, Account> accounts, Boolean onePartner) {
        Map<Id, Id> byContact = accountByContact(accounts);
        Set<Id> contactIds = byContact.keySet();
        Map<Id, Id> partnerByLoan = new Map<Id, Id>();
        String lq = 'SELECT Converted_Transaction_ID__c, Referral_Source__c FROM Lead WHERE LeadSource = :SOURCE AND Converted_Transaction_ID__c != null';
        if (onePartner) lq += ' AND Referral_Source__c IN :contactIds';
        for (Lead l : (List<Lead>) Database.query(lq + ' LIMIT 5000')) partnerByLoan.put(l.Converted_Transaction_ID__c, l.Referral_Source__c);
        Set<Id> loanIds = partnerByLoan.keySet();
        String q = 'SELECT Id, Name, Status__c, Loan_Officer__r.Name, Referral_Source__c, Referral_Source__r.Name, '
            + 'Loan_Amount_1st__c, Post_Closed_Date__c, CreatedDate FROM Transaction__c WHERE ';
        q += onePartner
            ? '(Id IN :loanIds OR (Lead_Source__c = :SOURCE AND Referral_Source__c IN :contactIds))'
            : '(Id IN :loanIds OR Lead_Source__c = :SOURCE)';
        Map<Id, String> contactNames = new Map<Id, String>();
        for (Account a : accounts.values()) contactNames.put(a.PersonContactId, a.Name);
        List<LoanRow> out = new List<LoanRow>();
        for (Transaction__c t : (List<Transaction__c>) Database.query(q + ' ORDER BY CreatedDate DESC LIMIT 5000')) {
            Id contact = t.Referral_Source__c != null ? t.Referral_Source__c : partnerByLoan.get(t.Id);
            LoanRow r = new LoanRow();
            r.id = t.Id;
            r.name = t.Name;
            r.status = t.Status__c;
            r.loName = t.Loan_Officer__r == null ? null : t.Loan_Officer__r.Name;
            r.partnerId = byContact.get(contact);
            r.partnerName = r.partnerId != null ? contactNames.get(contact) : (t.Referral_Source__r == null ? null : t.Referral_Source__r.Name);
            r.amount = t.Loan_Amount_1st__c;
            r.closedDate = t.Post_Closed_Date__c;
            r.created = t.CreatedDate;
            out.add(r);
        }
        return out;
    }

    static Results buildResults(Map<Id, Account> accounts, Date start, List<LeadRow> leads, List<LoanRow> loans) {
        Results res = new Results();
        res.total = new ResultRow();
        res.total.partnerName = 'All Influencer Partners';
        Map<Id, ResultRow> rows = new Map<Id, ResultRow>();
        for (Account a : accounts.values()) {
            ResultRow r = new ResultRow();
            r.partnerId = a.Id;
            r.partnerName = a.Name;
            r.stage = a.Influencer_Stage__c;
            r.cost = cost(a, start);
            res.total.cost += r.cost;
            rows.put(a.Id, r);
        }
        for (LeadRow l : leads) {
            if (start != null && l.created.date() < start) continue;
            for (ResultRow r : targets(res.total, rows.get(l.partnerId))) {
                r.leads++;
                if (l.preApprovalDate != null) r.preApproved++;
            }
        }
        for (LoanRow l : loans) {
            Boolean closed = CLOSED.contains(l.status) && l.closedDate != null;
            Boolean inRangeClosed = closed && (start == null || l.closedDate >= start);
            Boolean inRangeCreated = start == null || l.created.date() >= start;
            for (ResultRow r : targets(res.total, rows.get(l.partnerId))) {
                if (inRangeCreated) r.loans++;
                if (inRangeCreated && CANCELLED.contains(l.status)) r.cancelled++;
                if (inRangeClosed) {
                    r.closed++;
                    r.volume += l.amount == null ? 0 : l.amount;
                }
            }
        }
        res.partners = rows.values();
        for (ResultRow r : res.partners) finish(r);
        finish(res.total);
        return res;
    }

    static List<ResultRow> targets(ResultRow total, ResultRow partner) {
        return partner == null ? new List<ResultRow>{ total } : new List<ResultRow>{ total, partner };
    }

    static void finish(ResultRow r) {
        r.conversion = r.leads == 0 ? null : (Decimal.valueOf(r.closed) * 100 / r.leads).setScale(1);
        r.costPerClosed = r.closed == 0 || r.cost == 0 ? null : (r.cost / r.closed).setScale(2);
    }

    // Flat monthly fee for every calendar month the agreement ran inside the range, partial months included.
    // ponytail: calendar-month count, not prorated by day; switch to a payments object if fees ever vary.
    @TestVisible
    static Decimal cost(Account a, Date start) {
        if (a.Influencer_Monthly_Fee__c == null || a.Influencer_Agreement_Signed__c == null) return 0;
        Date fromDate = start == null || a.Influencer_Agreement_Signed__c > start ? a.Influencer_Agreement_Signed__c : start;
        Date to = a.Influencer_Stage__c == 'Lost' && a.Influencer_Lost_Date__c != null ? a.Influencer_Lost_Date__c : Date.today();
        if (to < fromDate) return 0;
        Integer months = (to.year() * 12 + to.month()) - (fromDate.year() * 12 + fromDate.month()) + 1;
        return a.Influencer_Monthly_Fee__c * months;
    }
}
