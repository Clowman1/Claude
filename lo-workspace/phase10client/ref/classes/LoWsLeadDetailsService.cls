/**
 * LO Workspace leads: the Pre-Approval Details card (loWsLeadDetails), the referring-realtor picker
 * and the Add lead form's required fields (loWsAddLeadForm, via ExternalLoLeadService).
 *
 * Read: the lead must be visible to the running user (with-sharing query).
 * Edit: only a lead the running user OWNS (not converted), only the fields set in saveDetails.
 * LeadSource, OwnerId and Status are never touched. SYSTEM_MODE DML behind that check, as in
 * LoWsContactService. Lead validation rules still run and their messages reach the LO.
 * Referring realtor = one of MY partners (my tags + partner-type Person Accounts I own); keeping a
 * lead's current realtor is always allowed.
 */
public with sharing class LoWsLeadDetailsService {

    public static final String FOREIGN_REALTOR = 'Pick a realtor from your own partners.';
    public static final String NOT_FOUND = 'Lead could not be found.';

    public class Option {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        Option(Id id, String label) {
            this.id = id;
            this.label = label;
        }
    }

    public class FormOptions {
        @AuraEnabled public List<Option> realtors = new List<Option>();
        @AuraEnabled public List<String> purposes = new List<String>();
        // The form reads the Consumer record type's Lead Source values (UI API, org order) with this.
        @AuraEnabled public Id consumerRecordTypeId;
    }

    public static final String SOURCE_NEEDS_REALTOR = 'Pick the referring realtor to use Realtor Referral.';

    /** Add lead without a realtor: blank, or an active Lead Source other than Realtor Referral. */
    public static String checkLeadSource(String value) {
        value = LoWsContactService.clean(value);
        if (value == null) return null;
        if (value == 'Realtor Referral') throw new DomainException(SOURCE_NEEDS_REALTOR);
        if (!activeValues(Lead.LeadSource).contains(value)) throw new DomainException('Pick a Lead Source from the list.');
        return value;
    }

    /** Values in, values out. Picklist options are filled only when the LO can edit. */
    public class Details {
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public String note;
        @AuraEnabled public String purpose;
        @AuraEnabled public String program;
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public Decimal downPaymentAmount;
        @AuraEnabled public Decimal downPaymentPercent;
        @AuraEnabled public Decimal estimatedPayment;
        @AuraEnabled public String propertyType;
        @AuraEnabled public String buyingTimeline;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public Decimal purchasePrice;
        @AuraEnabled public Id realtorId;
        @AuraEnabled public String realtorName;
        @AuraEnabled public Boolean realtorLinkable = false;
        @AuraEnabled public List<String> purposes = new List<String>();
        // Lead.Loan_Program__c is text; the org's list is the Transaction picklist Loan_Program_1st__c.
        @AuraEnabled public List<String> programs = new List<String>();
        @AuraEnabled public List<String> propertyTypes = new List<String>();
        @AuraEnabled public List<String> timelines = new List<String>();
        @AuraEnabled public List<Option> realtors = new List<Option>();
    }

    public static Details getDetails(Id leadId) {
        LoWsContactService.requireInternal();
        List<Lead> leads = [
            SELECT Id, OwnerId, IsConverted, Loan_Purpose__c, Loan_Program__c, Loan_Amount__c,
                   Down_Payment_Amount__c, Down_Payment_Percentage__c, Estimated_Monthly_Payment__c,
                   Property_Type__c, Buying_Timeline__c, City, State, Purchase_Price__c, Realtor_Buying_Agent__c
            FROM Lead WHERE Id = :leadId
        ];
        if (leads.isEmpty()) throw new DomainException(NOT_FOUND);
        Lead l = leads[0];
        Details d = new Details();
        d.purpose = l.Loan_Purpose__c;
        d.program = l.Loan_Program__c;
        d.loanAmount = l.Loan_Amount__c;
        d.downPaymentAmount = l.Down_Payment_Amount__c;
        d.downPaymentPercent = l.Down_Payment_Percentage__c;
        d.estimatedPayment = l.Estimated_Monthly_Payment__c;
        d.propertyType = l.Property_Type__c;
        d.buyingTimeline = l.Buying_Timeline__c;
        d.city = l.City;
        d.state = l.State;
        d.purchasePrice = l.Purchase_Price__c;
        d.realtorId = l.Realtor_Buying_Agent__c;
        if (d.realtorId != null) {
            // The name always shows (it is on a lead I can read); the link only when I can open the partner.
            List<Account> visible = [SELECT Id, Name FROM Account WHERE Id = :d.realtorId];
            d.realtorLinkable = !visible.isEmpty();
            List<Account> named = visible.isEmpty()
                ? LoWsContactService.readAccountsWithoutSharing(new Set<Id>{ d.realtorId })
                : visible;
            d.realtorName = named.isEmpty() ? null : named[0].Name;
        }
        d.note = LoWsContactService.leadEditBlocker(l);
        d.canEdit = d.note == null;
        if (d.canEdit) {
            d.purposes = activeValues(Lead.Loan_Purpose__c);
            d.programs = activeValues(Transaction__c.Loan_Program_1st__c);
            d.propertyTypes = activeValues(Lead.Property_Type__c);
            d.timelines = activeValues(Lead.Buying_Timeline__c);
            d.realtors = formOptions().realtors;
        }
        return d;
    }

    /** One save for the whole card. detailsJson = a Details (only the value fields are read). */
    public static Details saveDetails(Id leadId, String detailsJson) {
        Details current = getDetails(leadId);
        if (current.canEdit != true) throw new DomainException(current.note ?? LoWsContactService.NOT_OWNER_NOTE);
        Details input = String.isBlank(detailsJson) ? new Details() : (Details) JSON.deserialize(detailsJson, Details.class);
        Lead l = new Lead(Id = leadId);
        l.Loan_Purpose__c = checkPicklist(input.purpose, current.purposes, current.purpose, 'loan purpose');
        // Only an active Transaction program, or the lead's current (legacy free-text) value.
        l.Loan_Program__c = checkProgram(input.program, current.programs, current.program);
        l.Loan_Amount__c = checkAmount(input.loanAmount, 'Loan amount');
        l.Down_Payment_Amount__c = checkAmount(input.downPaymentAmount, 'Down payment');
        if (input.downPaymentPercent != null && (input.downPaymentPercent < 0 || input.downPaymentPercent > 100)) {
            throw new DomainException('Down payment % must be between 0 and 100.');
        }
        l.Down_Payment_Percentage__c = input.downPaymentPercent;
        l.Estimated_Monthly_Payment__c = checkAmount(input.estimatedPayment, 'Estimated payment');
        l.Property_Type__c = checkPicklist(input.propertyType, current.propertyTypes, current.propertyType, 'property type');
        l.Buying_Timeline__c = checkPicklist(input.buyingTimeline, current.timelines, current.buyingTimeline, 'buying timeline');
        l.City = LoWsContactService.clean(input.city);
        l.State = LoWsContactService.clean(input.state);
        l.Purchase_Price__c = checkAmount(input.purchasePrice, 'Purchase price');
        if (input.realtorId != current.realtorId) {
            applyRealtor(l, input.realtorId);
        }
        Database.update(l, AccessLevel.SYSTEM_MODE);
        return getDetails(leadId);
    }

    // ------------------------------------------------------------------ realtor picker + Add lead

    /**
     * My partners: my tags plus partner-type Person Accounts I own. Same scope as the In Person
     * Invite picker (BdCommandCenterController.loPartnerAccounts, private there, so repeated here).
     * Empty outside tag mode.
     */
    public static Map<Id, Account> myPartners(Set<Id> onlyIds) {
        Map<Id, Account> out = new Map<Id, Account>();
        if (!LoWsPartnerTagService.isTagMode()) return out;
        Id me = UserInfo.getUserId();
        Set<Id> tagged = LoWsPartnerTagService.myTags(onlyIds).keySet();
        String q = 'SELECT Id, Name, PersonContactId, PersonTitle, Company__c, BD_Industry__c, Is_Realtor__c, '
            + 'Type, Type__c, Group__pc FROM Account '
            + 'WHERE IsPersonAccount = true AND PersonContactId != null AND (Id IN :tagged OR OwnerId = :me)';
        if (onlyIds != null) q += ' AND Id IN :onlyIds';
        // ponytail: one capped list feeds a plain select; add a type-ahead search if an LO passes ~200 partners.
        for (Account a : (List<Account>) Database.query(q + ' ORDER BY Name LIMIT 2000')) {
            if (tagged.contains(a.Id) || LoWsPartnerTagService.isPartner(a)) out.put(a.Id, a);
        }
        return out;
    }

    /** The Add lead form: my partners and the active Loan Purpose values. */
    public static FormOptions formOptions() {
        FormOptions o = new FormOptions();
        for (Account a : myPartners(null).values()) {
            String company = a.Company__c ?? a.PersonTitle;
            o.realtors.add(new Option(a.Id, String.isBlank(company) ? a.Name : a.Name + ' · ' + company));
        }
        o.purposes = activeValues(Lead.Loan_Purpose__c);
        o.consumerRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
            .get('Consumer_Lead_record_type').getRecordTypeId();
        return o;
    }

    /**
     * The referring realtor, set the way BD's createReferralLead and the internal flows do it:
     * Realtor_Buying_Agent__c (Account: agent texts, countSharedBuyers) plus Referral_Source__c (the
     * realtor's PersonContactId: attribution; Stamp_Referred_By_When_Buying_Agent_is_Filled_In would
     * copy it anyway for Realtor Referral leads). null clears both. Must be one of my partners.
     */
    public static void applyRealtor(Lead l, Id realtorId) {
        if (realtorId == null) {
            l.Realtor_Buying_Agent__c = null;
            l.Referral_Source__c = null;
            return;
        }
        Account realtor = myPartners(new Set<Id>{ realtorId }).get(realtorId);
        if (realtor == null) throw new DomainException(FOREIGN_REALTOR);
        l.Realtor_Buying_Agent__c = realtor.Id;
        l.Referral_Source__c = realtor.PersonContactId;
    }

    /**
     * Add lead, optionally with "+ New realtor" (newRealtorName set) in ONE transaction:
     * (a) LoWsPartnerTagService.addPartner as a Realtor (Fred's duplicate check: a partner match returns
     * realtorMatches and creates nothing; a non-partner match throws the admin message),
     * (b) the lead with that realtor (ExternalLoLeadService, which also bumps my tag to Active Partner).
     * Any failure rolls both back.
     */
    public static ExternalLoLeadService.CreateLeadResult createLead(
        ExternalLoLeadService.CreateLeadRequest request,
        String newRealtorName, String newRealtorPhone, String newRealtorEmail, String newRealtorCompany, String newRealtorMarket
    ) {
        Savepoint sp = Database.setSavepoint();
        try {
            if (String.isNotBlank(newRealtorName)) {
                // Validate the lead first, so a bad lead never leaves a new realtor behind.
                validateNewLead(request.firstName, request.lastName, request.phone, request.email, request.purpose);
                LoWsPartnerTagService.AddResult added = LoWsPartnerTagService.addPartner(
                    newRealtorName, newRealtorPhone, newRealtorEmail, newRealtorCompany, newRealtorMarket, 'Realtor');
                if (added.status == 'match') {
                    ExternalLoLeadService.CreateLeadResult matched = new ExternalLoLeadService.CreateLeadResult();
                    matched.realtorMatches = added.matches;
                    return matched;
                }
                request.realtorId = added.accountId;
            }
            return ExternalLoLeadService.createLead(request);
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
    }

    /** My tag on this realtor goes to Active Partner from any other stage, Dormant included (owner, 2026-10-02). */
    public static void activateRealtor(Id realtorId) {
        External_User_Assignment__c tag = LoWsPartnerTagService.myTags(new Set<Id>{ realtorId }).get(realtorId);
        if (tag != null && tag.Stage__c != 'Active Partner') {
            LoWsPartnerTagService.setStage(realtorId, 'Active Partner');
        }
    }

    /** LO Workspace Add lead: all required; phone/email checked lightly; na@na.com refused. */
    public static void validateNewLead(String firstName, String lastName, String phone, String email, String purpose) {
        if (String.isBlank(firstName) || String.isBlank(lastName)) {
            throw new DomainException('Enter the borrower\'s first and last name.');
        }
        if (String.isBlank(phone)) throw new DomainException('Enter a phone number.');
        LoWsContactService.checkPhone(phone, 'Phone');
        String e = LoWsContactService.clean(email);
        if (e == null) throw new DomainException('Enter an email address.');
        if (e.equalsIgnoreCase(LoWsContactService.PLACEHOLDER_EMAIL) || !LoWsContactService.isEmail(e)) {
            throw new DomainException('Enter the borrower\'s real email address, like name@example.com.');
        }
        if (String.isBlank(purpose) || !activeValues(Lead.Loan_Purpose__c).contains(purpose)) {
            throw new DomainException('Pick a loan purpose.');
        }
    }

    // ------------------------------------------------------------------ private

    private static List<String> activeValues(Schema.SObjectField field) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
            if (e.isActive()) values.add(e.getValue());
        }
        return values;
    }

    /** Blank -> null; the current value (even an inactive legacy one) is kept; else every part must be active. */
    private static String checkPicklist(String value, List<String> allowed, String currentValue, String label) {
        value = LoWsContactService.clean(value);
        if (value == null || value == currentValue) return value;
        for (String part : value.split(';')) {
            if (!allowed.contains(part)) throw new DomainException('Pick a valid ' + label + '.');
        }
        return value;
    }

    private static String checkProgram(String value, List<String> allowed, String currentValue) {
        value = LoWsContactService.clean(value);
        if (value == null || value == currentValue || allowed.contains(value)) return value;
        throw new DomainException('Pick a loan program from the list.');
    }

    private static Decimal checkAmount(Decimal value, String label) {
        if (value != null && value < 0) throw new DomainException(label + ' cannot be negative.');
        return value;
    }
}