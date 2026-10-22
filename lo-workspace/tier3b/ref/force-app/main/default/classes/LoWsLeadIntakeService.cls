/**
 * LO Workspace, Phase 6: lead intake, duplicate rules and the Nurturing takeover.
 *
 * Every LO Workspace intake path (landing-page webhook, Add lead, consumer CSV import) asks decide()
 * what to do with a person (email or phone; placeholders such as na@na.com never match):
 *   - someone else's Nurturing lead          -> taken over through takeOver() (the ONLY path allowed
 *                                               to replace Lead Source, see Lead_Source_Change_Restricted)
 *   - someone else's open, non-Nurturing lead -> BLOCKED_MESSAGE (no name) + admin alert
 *   - someone else's client / converted lead  -> no block (owner rule 2026-10-12); otherClient is set
 *                                               so a CSV past-client row never duplicates their account
 *   - my own lead or client                   -> "already in your list"
 *   - nobody                                  -> the caller creates the record
 *
 * without sharing on purpose: matching must see every Lead and Person Account (Lead OWD is Private),
 * and a takeover updates a lead the new LO cannot see yet. Nothing here takes a user Id from a client:
 * Add lead / CSV pass UserInfo.getUserId(), the webhook resolves the LO from the authenticated payload.
 */
public without sharing class LoWsLeadIntakeService {

    public static final String BLOCKED_MESSAGE = 'This person is already being worked by another Reach loan officer. Contact an admin.';
    public static final String LANDING_PAGE_SOURCE = 'LO Landing Page';
    /** Custom_Log__c.Source__c of every landing-page submission (Perfect Day reads it too). */
    public static final String LOG_SOURCE = 'LO Landing Page';
    public static final String ALERT_LOG_SOURCE = 'LO Workspace Duplicate Blocked';
    static final String NOTIFICATION_TYPE = 'LO_Workspace_Lead';

    // ------------------------------------------------------------------ duplicate rules

    public class Verdict {
        /** Null when the caller may go ahead (create, or take over takeoverLeadId). */
        public String message;
        /** Someone else's Nurturing lead the caller should take over. */
        public Id takeoverLeadId;
        /** Admin-facing description of what blocked the row (record Ids, never shown to the LO). */
        public String alert;
        /** Someone else's client (Person Account or converted lead): never blocks a lead. */
        public Boolean otherClient = false;
    }

    /** Takeable statuses. '30 Day + Follow Up' is actively worked (My Leads shows it under Working), so it blocks. */
    public static Boolean isNurture(String status) {
        return status != null && status.startsWithIgnoreCase('Nurtur');
    }

    /** One Verdict per (emails[i], phones[i]) for ownerId; a fixed number of queries for the whole list. */
    public static List<Verdict> decide(Id ownerId, List<String> emails, List<String> phones) {
        Integer size = emails.size();
        Set<String> emailKeys = new Set<String>();
        Set<String> phoneKeys = new Set<String>();
        for (Integer i = 0; i < size; i++) {
            String e = PersonAccountDuplicateService.normalizeEmail(emails[i]);
            String p = PersonAccountDuplicateService.normalizePhone(phones[i]);
            if (e != null) emailKeys.add(e);
            if (p != null) phoneKeys.add(p);
        }

        // Leads anywhere in the org, converted ones included. Most recently touched first, so a
        // takeover picks the freshest of several Nurturing duplicates.
        Set<String> variants = phoneKeys.isEmpty() ? new Set<String>() : ExternalLoPhoneNormalizer.soqlVariants(phoneKeys);
        Map<String, List<Lead>> leadsByKey = new Map<String, List<Lead>>();
        Set<Id> convertedAccountIds = new Set<Id>();
        if (!emailKeys.isEmpty() || !variants.isEmpty()) {
            for (Lead l : [
                SELECT Id, OwnerId, Status, IsConverted, ConvertedAccountId, Email, Phone, MobilePhone FROM Lead
                WHERE Email IN :emailKeys OR Phone IN :variants OR MobilePhone IN :variants
                ORDER BY LastModifiedDate DESC
                LIMIT 2000
            ]) {
                if (l.ConvertedAccountId != null) convertedAccountIds.add(l.ConvertedAccountId);
                Set<String> keys = new Set<String>{
                    PersonAccountDuplicateService.normalizeEmail(l.Email),
                    PersonAccountDuplicateService.normalizePhone(l.Phone),
                    PersonAccountDuplicateService.normalizePhone(l.MobilePhone)
                };
                for (String k : keys) {
                    if (k == null) continue;
                    if (!leadsByKey.containsKey(k)) leadsByKey.put(k, new List<Lead>());
                    leadsByKey.get(k).add(l);
                }
            }
        }

        // Person Accounts (borrowers, past clients, partners). Mine = I own it or I am the LO on a loan for it.
        List<List<PersonAccountDuplicateService.Match>> paMatches =
            PersonAccountDuplicateService.findMatchesAcrossOrg(emails, phones);
        Set<Id> accountIds = new Set<Id>(convertedAccountIds);
        for (List<PersonAccountDuplicateService.Match> ms : paMatches) {
            for (PersonAccountDuplicateService.Match m : ms) accountIds.add(m.accountId);
        }
        Set<Id> mine = new Set<Id>();
        for (Account a : [SELECT Id FROM Account WHERE Id IN :accountIds AND OwnerId = :ownerId]) mine.add(a.Id);
        for (Transaction__c t : [SELECT Borrower_Name__c FROM Transaction__c WHERE Borrower_Name__c IN :accountIds AND Loan_Officer__c = :ownerId]) {
            mine.add(t.Borrower_Name__c);
        }

        List<Verdict> out = new List<Verdict>();
        for (Integer i = 0; i < size; i++) {
            Verdict v = new Verdict();
            List<String> blockedBy = new List<String>();
            String own = null;
            Id nurture = null;
            for (PersonAccountDuplicateService.Match m : paMatches[i]) {
                if (mine.contains(m.accountId)) own = LoWsPartnerTagService.CONFLICT_OWN_CLIENT;
                else v.otherClient = true;
            }
            Set<Id> seen = new Set<Id>();
            for (String k : new List<String>{
                PersonAccountDuplicateService.normalizeEmail(emails[i]),
                PersonAccountDuplicateService.normalizePhone(phones[i])
            }) {
                if (k == null || !leadsByKey.containsKey(k)) continue;
                for (Lead l : leadsByKey.get(k)) {
                    if (!seen.add(l.Id)) continue;
                    if (l.IsConverted) {
                        if (l.OwnerId == ownerId || mine.contains(l.ConvertedAccountId)) own = own ?? LoWsPartnerTagService.CONFLICT_OWN_CLIENT;
                        else v.otherClient = true;
                    } else if (l.OwnerId == ownerId) {
                        own = own ?? LoWsPartnerTagService.CONFLICT_OWN_LEAD;
                    } else if (isNurture(l.Status)) {
                        nurture = nurture ?? l.Id;
                    } else {
                        blockedBy.add(l.Status + ' Lead ' + l.Id);
                    }
                }
            }
            if (!blockedBy.isEmpty()) {
                v.message = BLOCKED_MESSAGE;
                v.alert = String.join(blockedBy, ', ');
            } else if (own != null) {
                v.message = own;
            } else {
                v.takeoverLeadId = nurture;
            }
            out.add(v);
        }
        return out;
    }

    /**
     * The one takeover path. Owner -> newOwnerId, Status New, Loan Partner cleared, Lead Source replaced
     * when a new one is given (blank keeps the old one). Activity and field history stay on the lead,
     * and the previous owner is not notified. Stamping LO_Takeover_At__c is what lets this save past
     * Lead_Source_Change_Restricted; the field has no FLS, so only system-mode Apex can set it.
     * Only leads still unconverted and Nurturing are touched. Returns the Ids taken over.
     */
    public static Set<Id> takeOver(Map<Id, String> sourceByLeadId, Id newOwnerId) {
        Set<Id> taken = new Set<Id>();
        if (sourceByLeadId == null || sourceByLeadId.isEmpty()) return taken;
        Set<Id> ids = sourceByLeadId.keySet();
        List<Lead> rows = new List<Lead>();
        for (Lead l : [SELECT Id, Status FROM Lead WHERE Id IN :ids AND IsConverted = false FOR UPDATE]) {
            if (!isNurture(l.Status)) continue;
            // The old lead team goes too: Biz Dev (stops the BDR "LeadQualified" Zap on New), Scenario
            // Manager and Other (whose Manual share the owner change removes; the share handler sees null and re-creates nothing).
            Lead u = new Lead(Id = l.Id, OwnerId = newOwnerId, Status = 'New', Loan_Partner__c = null,
                Biz_Dev__c = null, Scenario_Manager__c = null, Other_Lead_Team_Member__c = null,
                LO_Takeover_At__c = System.now());
            String source = sourceByLeadId.get(l.Id);
            if (String.isNotBlank(source)) u.LeadSource = source;
            rows.add(u);
            taken.add(l.Id);
        }
        update rows;
        return taken;
    }

    // ------------------------------------------------------------------ alerts

    /**
     * Raises one admin alert per call (so a CSV with many blocked rows raises one). Published as an
     * immediate event because Add lead refuses by throwing, which rolls back anything written here.
     * Never throws: a refused add must still return its message to the LO.
     */
    public static void alertAdmins(String channel, List<String> details) {
        if (details == null || details.isEmpty()) return;
        try {
            EventBus.publish(new LO_Workspace_Intake__e(Payload__c = JSON.serialize(new Map<String, Object>{
                'kind' => 'alert', 'channel' => channel, 'actorId' => UserInfo.getUserId(),
                'actorName' => UserInfo.getName(), 'details' => details
            }).left(32000)));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoWsLeadIntakeService.alertAdmins: ' + e.getMessage());
        }
    }

    /**
     * Active holders of the LO_Workspace_Oversight custom permission (direct or via a permission set
     * group). Works as Automated Process; FeatureManagement.checkPermission only covers the running user.
     */
    @TestVisible
    static Set<String> oversightUserIds() {
        Set<Id> permSetIds = new Set<Id>();
        for (SetupEntityAccess sea : [
            SELECT ParentId FROM SetupEntityAccess
            WHERE SetupEntityId IN (SELECT Id FROM CustomPermission WHERE DeveloperName = 'LO_Workspace_Oversight')
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

    /** One log row, plus a push to the oversight managers (none assigned = log only). */
    private static void writeAlert(String channel, String actorId, String actorName, List<Object> details) {
        try {
            Custom_Log__c log = new Custom_Log__c(
                Source__c = ALERT_LOG_SOURCE,
                Data__c = (channel + ' by ' + actorName + ' (' + actorId + ') was refused because the person already exists:\n'
                    + String.join(details, '\n')).left(32000),
                Processed__c = false
            );
            insert log;
            send(oversightUserIds(),'LO Workspace duplicate blocked',
                actorName + ' tried to add ' + details.size() + (details.size() == 1 ? ' person' : ' people')
                + ' already worked by another loan officer. Open the log for the matched records.', log.Id);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoWsLeadIntakeService.writeAlert: ' + e.getMessage());
        }
    }

    /** Targets the record, or the LO Workspace tab when there is no record the recipient can open. */
    private static void send(Set<String> recipients, String title, String body, Id targetId) {
        if (recipients.isEmpty()) return;
        try {
            List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE LIMIT 1];
            if (types.isEmpty()) return;
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setNotificationTypeId(types[0].Id);
            n.setTitle(title.left(250));
            n.setBody(body.left(750));
            if (targetId != null) n.setTargetId(targetId);
            else n.setTargetPageRef(workspacePage());
            n.send(recipients);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoWsLeadIntakeService.send: ' + e.getMessage());
        }
    }

    // ------------------------------------------------------------------ landing-page webhook

    /** Events per trigger run: one lead save fires the whole Lead automation stack (40 flows, 9 triggers). */
    @TestVisible static Integer eventsPerRun = 1;

    /** LO_Workspace_Intake__e subscriber (runs as Automated Process). The rest resume after the checkpoint. */
    public static void handleEvents(List<LO_Workspace_Intake__e> events) {
        Integer done = 0;
        for (LO_Workspace_Intake__e e : events) {
            if (done++ == eventsPerRun) break;
            Map<String, Object> alert = alertPayload(e.Payload__c);
            if (alert != null) {
                writeAlert((String) alert.get('channel'), (String) alert.get('actorId'),
                    (String) alert.get('actorName'), (List<Object>) alert.get('details'));
            } else {
                processLandingPage(e.Payload__c);
            }
            EventBus.TriggerContext.currentContext().setResumeCheckpoint(e.ReplayId);
        }
    }

    /** The webhook refuses bodies carrying "kind", so only alertAdmins() can produce an alert. */
    private static Map<String, Object> alertPayload(String payload) {
        try {
            Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(payload);
            return p.get('kind') == 'alert' ? p : null;
        } catch (Exception e) {
            return null;
        }
    }

    /** Payload keys: loEmail (required), firstName, lastName or name, email and/or phone, leadSource, loanPurpose, city, state, notes or message. */
    @TestVisible
    static void processLandingPage(String payload) {
        Custom_Log__c log = new Custom_Log__c(Source__c = LOG_SOURCE, Data__c = payload == null ? '' : payload.left(30000), Processed__c = true);
        Savepoint sp = Database.setSavepoint();
        try {
            Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(payload);
            User lo = resolveLo(str(p, 'loEmail'));
            if (lo == null) {
                log.Errors__c = 'No single active user matches loEmail "' + str(p, 'loEmail') + '". Nothing was created.';
                insert log;
                return;
            }
            String first = str(p, 'firstName');
            String last = str(p, 'lastName');
            if (String.isBlank(last) && String.isNotBlank(str(p, 'name'))) {
                List<String> parts = str(p, 'name').split('\\s+', 2);
                first = parts.size() > 1 ? parts[0] : first;
                last = parts.size() > 1 ? parts[1] : parts[0];
            }
            String email = str(p, 'email');
            String phone = str(p, 'phone');
            String fullName = String.join(new List<String>{ first ?? '', last ?? '' }, ' ').trim();
            String source = validLeadSource(str(p, 'leadSource'));

            Verdict v = decide(lo.Id, new List<String>{ email }, new List<String>{ phone })[0];
            if (v.message == BLOCKED_MESSAGE) {
                log.Data__c = outcome(log, 'Blocked: ' + v.alert); // payload kept: the admin must resolve it
                insert log;
                writeAlert('Landing page lead', lo.Id, lo.Name, new List<Object>{ fullName + ' -> ' + v.alert });
                send(new Set<String>{ lo.Id }, 'Landing page lead not added', BLOCKED_MESSAGE, null);
                return;
            }
            Id leadId;
            String title;
            if (v.message != null) {
                // Mine already: point the log at it so Perfect Day lifts it if it is still New.
                leadId = ownMatch(lo.Id, email, phone);
                title = 'Landing page: ' + fullName + ' (already one of yours)';
                log.Data__c = summary(v.message, lo, source);
            } else if (v.takeoverLeadId != null) {
                takeOver(new Map<Id, String>{ v.takeoverLeadId => source }, lo.Id);
                leadId = v.takeoverLeadId;
                title = 'New landing page lead: ' + fullName;
                log.Data__c = summary('Took over Nurturing lead ' + leadId, lo, source);
            } else {
                if (String.isBlank(last) || (PersonAccountDuplicateService.normalizeEmail(email) == null && String.isBlank(phone))) {
                    log.Errors__c = 'A last name or name, and an email or phone, are required. Nothing was created.';
                    insert log;
                    return;
                }
                Lead l = new Lead(
                    RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId(),
                    FirstName = first, LastName = last, Company = last + ' Household', Status = 'New',
                    OwnerId = lo.Id, Email = email, Phone = phone, LeadSource = source,
                    City = str(p, 'city'), State = str(p, 'state'),
                    Loan_Purpose__c = validPurpose(str(p, 'loanPurpose')),
                    Description = str(p, 'notes') ?? str(p, 'message')
                );
                insert l;
                leadId = l.Id;
                title = 'New landing page lead: ' + fullName;
                log.Data__c = summary('Created lead ' + leadId, lo, source);
            }
            log.Lead__c = leadId;
            insert log;
            send(new Set<String>{ lo.Id }, title, 'Contact them now. They are at the top of your Perfect Day.', leadId);
        } catch (Exception e) {
            Database.rollback(sp);
            log.Id = null;
            log.Lead__c = null;
            log.Errors__c = (e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString()).left(32000);
            insert log;
        }
    }

    /**
     * Success rows keep no contact details: Custom_Log__c is Public Read/Write and loan officers
     * (outside LOs included) can read Data__c. The lead itself holds the data.
     */
    private static String summary(String text, User lo, String source) {
        return 'Outcome: ' + text + '\nLO: ' + lo.Name + ' (' + lo.Id + ')\nLead Source: ' + source;
    }

    private static String outcome(Custom_Log__c log, String text) {
        return ('Outcome: ' + text + '\n\n' + log.Data__c).left(32000);
    }

    private static Id ownMatch(Id ownerId, String email, String phone) {
        String e = PersonAccountDuplicateService.normalizeEmail(email) ?? '#none'; // never Email = null
        String p = PersonAccountDuplicateService.normalizePhone(phone);
        Set<String> variants = p == null ? new Set<String>() : ExternalLoPhoneNormalizer.soqlVariants(new Set<String>{ p });
        for (Lead l : [
            SELECT Id FROM Lead
            WHERE OwnerId = :ownerId AND IsConverted = false AND (Email = :e OR Phone IN :variants OR MobilePhone IN :variants)
            ORDER BY LastModifiedDate DESC LIMIT 1
        ]) {
            return l.Id;
        }
        return null;
    }

    /** Username wins; otherwise the single active internal user with that email. */
    @TestVisible
    static User resolveLo(String loEmail) {
        if (String.isBlank(loEmail)) return null;
        String key = loEmail.trim();
        List<User> users = [
            SELECT Id, Name, Username FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND (Username = :key OR Email = :key)
        ];
        for (User u : users) {
            if (u.Username.equalsIgnoreCase(key)) return u;
        }
        return users.size() == 1 ? users[0] : null;
    }

    private static String validLeadSource(String raw) {
        if (String.isNotBlank(raw)) {
            for (Schema.PicklistEntry e : Lead.LeadSource.getDescribe().getPicklistValues()) {
                if (e.isActive() && e.getValue().equalsIgnoreCase(raw.trim())) return e.getValue();
            }
        }
        return LANDING_PAGE_SOURCE;
    }

    private static String validPurpose(String raw) {
        if (String.isBlank(raw)) return null;
        for (Schema.PicklistEntry e : Lead.Loan_Purpose__c.getDescribe().getPicklistValues()) {
            if (e.isActive() && e.getValue().equalsIgnoreCase(raw.trim())) return e.getValue();
        }
        return null;
    }

    private static String str(Map<String, Object> p, String key) {
        Object v = p.get(key);
        return v == null || String.isBlank(String.valueOf(v)) ? null : String.valueOf(v).trim();
    }

    private static String workspacePage() {
        return JSON.serialize(new Map<String, Object>{
            'type' => 'standard__navItemPage', 'attributes' => new Map<String, Object>{ 'apiName' => 'LO_Workspace' }
        });
    }

    // ------------------------------------------------------------------ Perfect Day

    /** My New leads that arrived from a landing page in the last 30 days, newest submission first. */
    public static List<Id> recentLandingPageLeadIds(Id ownerId) {
        List<Id> ids = new List<Id>();
        for (Custom_Log__c c : [
            SELECT Lead__c FROM Custom_Log__c
            WHERE Source__c = :LOG_SOURCE AND Lead__c != null AND CreatedDate = LAST_N_DAYS:30
              AND Lead__r.OwnerId = :ownerId AND Lead__r.Status = 'New' AND Lead__r.IsConverted = false
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            if (!ids.contains(c.Lead__c)) ids.add(c.Lead__c);
        }
        return ids;
    }

    /**
     * Landing-page leads first (newest first), then the queue as it was. Landing-page leads are loaded
     * here too, so a taken-over lead created years ago (outside the queue's CreatedDate window) still
     * shows. A lead deferred from Perfect Day stays out until its return time.
     */
    public static List<Lead> landingPageFirst(List<Id> landingIds, List<Lead> queue) {
        if (landingIds.isEmpty()) return queue;
        Datetime nowValue = System.now();
        Map<Id, Lead> byId = new Map<Id, Lead>([
            SELECT Id, Name, CreatedDate, Status, Phone, Email, LeadSource FROM Lead
            WHERE Id IN :landingIds AND (Appointment_Date_Time__c = null OR Appointment_Date_Time__c <= :nowValue)
        ]);
        List<Lead> out = new List<Lead>();
        for (Id leadId : landingIds) {
            if (byId.containsKey(leadId)) out.add(byId.get(leadId));
        }
        for (Lead l : queue) {
            if (!byId.containsKey(l.Id)) out.add(l);
        }
        return out;
    }
}