/**
 * Influencer Partners intake. The public form (?partner=<code>) stamps Lead.Influencer_Partner_Code__c;
 * this turns the code into the two attributions and routes the lead:
 *   Referral Source = the partner, Lead Source = Influencer Partners, Buyer's Agent stays blank,
 *   Owner = Spanish speaker -> Brandon (same rule as the realtor form), else the partner's Assigned LO,
 *   else the Intake Form Queue.
 * The form/Zap never sets ReferralFormSourceEmail__c, so none of the realtor intake flows fire; the LO
 * notification those flows send (email + SMS platform event) is sent from here instead, with Ernesto copied.
 * Without sharing: it runs as the site guest user.
 */
public without sharing class LeadInfluencerAttribution {
    public static final String LEAD_SOURCE = 'Influencer Partners';
    @TestVisible static final Id SPANISH_OWNER_ID = '005f2000009NwSsAAK';
    @TestVisible static final String INTAKE_QUEUE = 'Intake Form Queue';
    // Program manager: copied on every influencer lead alert, including queue-owned ones.
    @TestVisible static String PROGRAM_MANAGER_USERNAME = 'ernesto@reachhomeloans.com';
    @TestVisible static List<Messaging.SingleEmailMessage> sentForTest;

    public static void beforeInsert(List<Lead> leads) {
        Map<String, Account> partners = partnersByCode(leads);
        if (partners.isEmpty()) return;
        Id queueId = queueId();
        for (Lead l : leads) {
            Account p = String.isBlank(l.Influencer_Partner_Code__c) ? null : partners.get(l.Influencer_Partner_Code__c.trim().toUpperCase());
            if (p == null) continue;
            l.Referral_Source__c = p.PersonContactId;
            l.LeadSource = LEAD_SOURCE;
            l.Realtor_Buying_Agent__c = null;
            if (l.Spanish_Speaker_Intake_Form__c == 'Yes') l.OwnerId = SPANISH_OWNER_ID;
            else if (p.Influencer_Assigned_LO__c != null && p.Influencer_Assigned_LO__r.IsActive) l.OwnerId = p.Influencer_Assigned_LO__c;
            else if (queueId != null) l.OwnerId = queueId;
        }
    }

    public static void afterInsert(List<Lead> leads) {
        Map<String, Account> partners = partnersByCode(leads);
        if (partners.isEmpty()) return;
        Set<Id> ownerIds = new Set<Id>();
        for (Lead l : leads) if (partners.containsKey(code(l))) ownerIds.add(l.OwnerId);
        Map<Id, User> owners = new Map<Id, User>([
            SELECT Id, Name, Email, Phone, MobilePhone, Loan_Partner__r.Email FROM User WHERE Id IN :ownerIds AND IsActive = true
        ]);
        List<User> manager = [SELECT Email FROM User WHERE Username = :PROGRAM_MANAGER_USERNAME AND IsActive = true LIMIT 1];
        List<OrgWideEmailAddress> sender = [SELECT Id FROM OrgWideEmailAddress WHERE Address = 'reachus@reachhomeloans.com' LIMIT 1];
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        List<Intake_Form_New_Lead_Created__e> texts = new List<Intake_Form_New_Lead_Created__e>();
        for (Lead l : leads) {
            Account p = partners.get(code(l));
            if (p == null) continue;
            User o = owners.get(l.OwnerId); // null = queue-owned: no LO yet, the program manager still hears about it
            Set<String> to = new Set<String>();
            if (o != null) {
                String phone = String.isBlank(o.Phone) ? o.MobilePhone : o.Phone;
                if (String.isNotBlank(phone)) texts.add(new Intake_Form_New_Lead_Created__e(Lead_ID__c = l.Id, Phone__c = phone));
                to.add(o.Email);
                if (o.Loan_Partner__r != null && String.isNotBlank(o.Loan_Partner__r.Email)) to.add(o.Loan_Partner__r.Email);
            }
            if (!manager.isEmpty()) to.add(manager[0].Email);
            if (to.isEmpty()) continue;
            String name = (l.FirstName == null ? '' : l.FirstName + ' ') + l.LastName;
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            if (!sender.isEmpty()) m.setOrgWideEmailAddressId(sender[0].Id);
            m.setToAddresses(new List<String>(to));
            m.setSubject('New Influencer Partner Lead: ' + name);
            m.setHtmlBody('<p>New lead from Influencer Partner <b>' + p.Name.escapeHtml4() + '</b>: <a href="'
                + Url.getOrgDomainUrl().toExternalForm() + '/lightning/r/Lead/' + l.Id + '/view">' + name.escapeHtml4() + '</a></p>'
                + '<p>Assigned to: ' + (o == null ? INTAKE_QUEUE + ' (no LO assigned to this partner)' : o.Name.escapeHtml4()) + '</p>'
                + '<p>Phone: ' + (l.Phone == null ? '' : l.Phone.escapeHtml4()) + '<br/>Email: ' + (l.Email == null ? '' : l.Email.escapeHtml4()) + '</p>'
                + '<p>Comments: ' + (l.Comments__c == null ? '' : l.Comments__c.escapeHtml4()) + '</p>');
            m.setSaveAsActivity(false);
            mails.add(m);
        }
        sentForTest = mails;
        if (!texts.isEmpty()) EventBus.publish(texts);
        if (!mails.isEmpty()) {
            // A failed notification must never lose the lead: log it instead.
            String failure;
            try {
                for (Messaging.SendEmailResult r : Messaging.sendEmail(mails, false)) {
                    if (!r.isSuccess()) failure = String.valueOf(r.getErrors());
                }
            } catch (Exception e) {
                failure = e.getMessage();
            }
            if (failure != null) insert new Custom_Log__c(Source__c = 'Influencer Intake Email Error', Data__c = failure.left(5000));
        }
    }

    static String code(Lead l) {
        return String.isBlank(l.Influencer_Partner_Code__c) ? null : l.Influencer_Partner_Code__c.trim().toUpperCase();
    }

    static Map<String, Account> partnersByCode(List<Lead> leads) {
        Set<String> codes = new Set<String>();
        for (Lead l : leads) if (code(l) != null) codes.add(code(l));
        Map<String, Account> out = new Map<String, Account>();
        if (codes.isEmpty()) return out;
        for (Account a : [
            SELECT Id, Name, PersonContactId, Influencer_Partner_Code__c, Influencer_Assigned_LO__c, Influencer_Assigned_LO__r.IsActive
            FROM Account
            WHERE Influencer_Partner_Code__c IN :codes AND Influencer_Stage__c != null AND IsPersonAccount = true
        ]) out.put(a.Influencer_Partner_Code__c.toUpperCase(), a);
        return out;
    }

    static Id queueId() {
        List<Group> q = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = :INTAKE_QUEUE LIMIT 1];
        return q.isEmpty() ? null : q[0].Id;
    }
}
