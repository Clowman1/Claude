/**
 * LO Workspace: the Contact card on the Overview of a lead, partner or past client (loWsContactCard).
 *
 * Read: the record must be visible to the running user (with-sharing query). A loan Id shows its
 * borrower, read without sharing because an LO reads their loan but not always the borrower.
 * Edit: only a Lead or Person Account the running user OWNS, and only the fields written in
 * updateContact. LeadSource, OwnerId and everything else are never touched.
 * The DML runs in SYSTEM_MODE (no CRUD/FLS check) behind the ownership check; the class is
 * with sharing, so record sharing still applies.
 * Partner Workspace (portal) users are refused: the portal keeps its own contact list.
 */
public with sharing class LoWsContactService {

    public static final String SHARED_PARTNER_NOTE = 'Shared Reach partner — contact an admin to update.';
    public static final String BORROWER_NOTE = 'Borrower on your loan — contact an admin to update.';
    public static final String NOT_OWNER_NOTE = 'You don\'t own this record — contact an admin to update.';
    public static final String CONVERTED_NOTE = 'This lead is converted — update the client record instead.';
    public static final String NOT_FOUND = 'Contact details could not be found.';
    // Realtor_Lead_Placeholder_Email: a stand-in, never a real address. Shown blank, never written.
    public static final String PLACEHOLDER_EMAIL = 'na@na.com';
    private static final Pattern EMAIL_FORMAT = Pattern.compile('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$');

    public class ContactInfo {
        @AuraEnabled public Id recordId;      // the record the card edits (the borrower Account for a loan)
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String company;
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public String note;      // why it is read-only
        // Leads: "Next appointment: <when> — <subject>" from my earliest future Event on the lead. Indicator only.
        @AuraEnabled public String nextAppointment;
        // Co-borrowers (Borrower__c on the lead): name is shown and edited; there is no address.
        @AuraEnabled public Boolean isBorrower = false;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String relationship;
        @AuraEnabled public List<String> relationships = new List<String>(); // active Borrower__c.Relationship__c values
        // Set when a co-borrower has no email: nothing can be requested from them.
        @AuraEnabled public String noEmailWarning;
    }

    public static final String NO_EMAIL_WARNING =
        'No email — document requests and condition lists can\'t be sent to this borrower. Add an email to include them.';

    public static ContactInfo getContact(Id recordId) {
        requireInternal();
        SObjectType type = recordId?.getSObjectType();
        if (type == Lead.SObjectType) {
            List<Lead> leads = [
                SELECT Id, OwnerId, IsConverted, Phone, MobilePhone, Email, Street, City, State, PostalCode
                FROM Lead WHERE Id = :recordId
            ];
            if (leads.isEmpty()) throw new DomainException(NOT_FOUND);
            Lead l = leads[0];
            ContactInfo c = info(l.Id, l.Phone, l.MobilePhone, l.Email);
            c.street = l.Street;
            c.city = l.City;
            c.state = l.State;
            c.postalCode = l.PostalCode;
            c.note = leadEditBlocker(l);
            c.canEdit = c.note == null;
            c.nextAppointment = nextAppointments(new Set<Id>{ l.Id }).get(l.Id);
            return c;
        }
        if (type == Account.SObjectType) {
            List<Account> accounts = Database.query(ACCOUNT_SELECT + ' WHERE Id = :recordId');
            if (accounts.isEmpty()) throw new DomainException(NOT_FOUND);
            return fromAccount(accounts[0], null);
        }
        if (type == Borrower__c.SObjectType) {
            // with sharing + the External_LO restriction rule: an outside LO sees rows stamped for them.
            List<Borrower__c> rows = [
                SELECT Id, First_Name__c, Last_Name__c, Phone__c, Email__c, Relationship__c, Lead__c, Lead__r.OwnerId, Lead__r.IsConverted
                FROM Borrower__c WHERE Id = :recordId AND Removed__c = false AND Lead__c != null
            ];
            if (rows.isEmpty()) throw new DomainException(NOT_FOUND);
            Borrower__c b = rows[0];
            ContactInfo c = info(b.Id, b.Phone__c, null, b.Email__c);
            c.isBorrower = true;
            c.firstName = b.First_Name__c;
            c.lastName = b.Last_Name__c;
            c.relationship = b.Relationship__c;
            c.relationships = relationshipValues();
            c.noEmailWarning = String.isBlank(c.email) ? NO_EMAIL_WARNING : null;
            c.note = leadEditBlocker(b.Lead__r.OwnerId, b.Lead__r.IsConverted);
            c.canEdit = c.note == null;
            return c;
        }
        if (type == Transaction__c.SObjectType) {
            List<Transaction__c> loans = [SELECT Borrower_Name__c FROM Transaction__c WHERE Id = :recordId];
            if (loans.isEmpty() || loans[0].Borrower_Name__c == null) throw new DomainException(NOT_FOUND);
            List<Account> borrowers = readAccountsWithoutSharing(new Set<Id>{ loans[0].Borrower_Name__c });
            if (borrowers.isEmpty()) throw new DomainException(NOT_FOUND);
            return fromAccount(borrowers[0], BORROWER_NOTE);
        }
        throw new DomainException(NOT_FOUND);
    }

    /**
     * Saves the contact fields of a record the running user owns; returns the re-read card.
     * One phone: it is written to BOTH phone fields (Phone + MobilePhone / PersonMobilePhone) so duplicate
     * matching, Twilio and Zapier keep working. firstName/lastName are used for co-borrowers only.
     */
    public static ContactInfo updateContact(
        Id recordId, String firstName, String lastName, String phone, String email,
        String street, String city, String state, String postalCode, String relationship
    ) {
        ContactInfo current = getContact(recordId);
        if (current.canEdit != true) {
            throw new DomainException(current.note ?? NOT_OWNER_NOTE);
        }
        if (current.isBorrower) {
            Borrower__c b = borrowerFields(firstName, lastName, phone, email, relationship);
            b.Id = current.recordId;
            Database.update(b, AccessLevel.SYSTEM_MODE);
            return getContact(b.Id);
        }
        phone = checkPhone(phone, 'Phone');
        email = clean(email);
        if (email != null && email.equalsIgnoreCase(PLACEHOLDER_EMAIL)) {
            email = null;
        }
        if (email != null && !isEmail(email)) {
            throw new DomainException('Enter a valid email address, like name@example.com.');
        }
        Id targetId = current.recordId;
        SObject record;
        if (targetId.getSObjectType() == Lead.SObjectType) {
            Lead l = new Lead(Id = targetId, Phone = phone, MobilePhone = phone,
                Street = clean(street), City = clean(city), State = clean(state), PostalCode = clean(postalCode));
            if (email != null || !isPlaceholderOnFile(targetId)) l.Email = email;
            record = l;
        } else {
            Account a = new Account(Id = targetId, Phone = phone, PersonMobilePhone = phone,
                PersonMailingStreet = clean(street), PersonMailingCity = clean(city),
                PersonMailingState = clean(state), PersonMailingPostalCode = clean(postalCode));
            if (email != null || !isPlaceholderOnFile(targetId)) a.PersonEmail = email;
            record = a;
        }
        Database.update(record, AccessLevel.SYSTEM_MODE);
        return getContact(targetId);
    }

    // ------------------------------------------------------------------ shared helpers

    /**
     * Co-borrower fields: first + last name required. Phone, email and relationship are optional;
     * phone and email are format-checked when filled in (na@na.com is not an email). Blank = cleared.
     */
    public static Borrower__c borrowerFields(String firstName, String lastName, String phone, String email, String relationship) {
        firstName = clean(firstName);
        lastName = clean(lastName);
        if (firstName == null || lastName == null) throw new DomainException('Enter the borrower\'s first and last name.');
        phone = checkPhone(phone, 'Phone');
        email = clean(email);
        if (email != null && (email.equalsIgnoreCase(PLACEHOLDER_EMAIL) || !isEmail(email))) {
            throw new DomainException('Enter the borrower\'s real email address, like name@example.com, or leave it blank.');
        }
        relationship = clean(relationship);
        if (relationship != null && !relationshipValues().contains(relationship)) {
            throw new DomainException('Pick a relationship from the list.');
        }
        return new Borrower__c(First_Name__c = firstName, Last_Name__c = lastName, Phone__c = phone, Email__c = email,
            Relationship__c = relationship, Name = (firstName + ' ' + lastName).left(80));
    }

    /** The values live on the Borrower__c.Relationship__c picklist only (change them there). */
    public static List<String> relationshipValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry e : Borrower__c.Relationship__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) values.add(e.getValue());
        }
        return values;
    }

    /**
     * "Next appointment: <when> — <subject>" per lead: the earliest future Event I own with WhoId =
     * the lead. SYSTEM_MODE, owner = me. Indicator only: nothing here changes the lead.
     */
    public static Map<Id, String> nextAppointments(Set<Id> leadIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (leadIds == null || leadIds.isEmpty() || UserInfo.getUserType() != 'Standard') return out;
        Id me = UserInfo.getUserId();
        Datetime now = Datetime.now();
        for (Event e : [
            SELECT WhoId, StartDateTime, Subject FROM Event
            WHERE OwnerId = :me AND WhoId IN :leadIds AND StartDateTime > :now
            WITH SYSTEM_MODE
            ORDER BY StartDateTime ASC
            LIMIT 2000
        ]) {
            if (!out.containsKey(e.WhoId)) {
                String label = 'Next appointment: ' + e.StartDateTime.format('EEE, MMM d, h:mm a');
                out.put(e.WhoId, String.isBlank(e.Subject) ? label : label + ' — ' + e.Subject);
            }
        }
        return out;
    }

    /** null when the running user may edit this lead (owns it, not converted), else the reason. */
    public static String leadEditBlocker(Lead l) {
        return leadEditBlocker(l.OwnerId, l.IsConverted);
    }

    public static String leadEditBlocker(Id ownerId, Boolean converted) {
        if (converted == true) return CONVERTED_NOTE;
        return ownerId == UserInfo.getUserId() ? null : NOT_OWNER_NOTE;
    }

    public static Boolean isEmail(String value) {
        return value != null && EMAIL_FORMAT.matcher(value).matches();
    }

    /** Light check: 10 digits (a leading 1 is allowed) and only phone punctuation. Returns the trimmed value. */
    public static String checkPhone(String value, String label) {
        value = clean(value);
        if (value == null) return null;
        String digits = value.replaceAll('[^0-9]', '');
        if (digits.length() == 11 && digits.startsWith('1')) digits = digits.substring(1);
        if (digits.length() != 10 || value.replaceAll('[0-9()+.\\-\\s]', '').length() > 0) {
            throw new DomainException(label + ' must be a 10-digit number, like (407) 555-0101.');
        }
        return value;
    }

    public static String clean(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    /**
     * The statuses LO Workspace uses (owner decision 2026-10-03), in org order. No meeting statuses,
     * Application / Application Link Out, Active, or converted-stage statuses (Submitted For Disclosures,
     * Under Contract): converting is Convert to transaction.
     */
    @TestVisible
    private static final Set<String> WORKSPACE_STATUSES = new Set<String>{
        'New', 'Contacted/Call Back', 'Contact Attempt 1', 'Contact Attempt 2', 'Contact Attempt 3',
        'Contact Attempt 4', 'Contact Attempt 5', 'Contact Attempt 6', 'Working', '30 Day + Follow Up',
        'Documents Requested', 'Documents Received for Review', 'Pre-Approval', 'Nurture - Preapproval', 'Nurturing'
    };

    public static List<String> leadStatusOptions() {
        Set<String> converted = new Set<String>();
        for (LeadStatus s : [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true]) {
            converted.add(s.MasterLabel);
        }
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive() && WORKSPACE_STATUSES.contains(entry.getValue()) && !converted.contains(entry.getValue())) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    /**
     * LO Workspace status dropdown / Board drag: the owner sets any non-converted status, forward or back.
     * Outside LOs are exempt from Calls_Required_for_Status_Change; any other rule's message is returned.
     */
    public static String updateLeadStatus(Id leadId, String status) {
        requireInternal();
        if (leadId == null || leadId.getSObjectType() != Lead.SObjectType) {
            throw new DomainException('Pick a lead.');
        }
        if (String.isBlank(status) || !leadStatusOptions().contains(status)) {
            throw new DomainException('Pick a valid status. Use Convert to transaction to convert a lead.');
        }
        List<Lead> leads = [SELECT OwnerId, IsConverted, Status FROM Lead WHERE Id = :leadId WITH SYSTEM_MODE];
        if (leads.isEmpty()) {
            throw new DomainException(NOT_FOUND);
        }
        String blocker = leadEditBlocker(leads[0]);
        if (blocker != null) {
            throw new DomainException(blocker);
        }
        if (leads[0].Status == status) {
            return status;
        }
        Database.SaveResult saved = Database.update(new Lead(Id = leadId, Status = status), false, AccessLevel.SYSTEM_MODE);
        if (!saved.isSuccess()) {
            List<String> messages = new List<String>();
            for (Database.Error error : saved.getErrors()) {
                messages.add(error.getMessage());
            }
            throw new DomainException(String.join(messages, ' '));
        }
        return status;
    }

    public static void requireInternal() {
        if (UserInfo.getUserType() != 'Standard') {
            throw new DomainException('This is available in LO Workspace only.');
        }
    }

    /** Borrower / realtor-name reads the LO may not have sharing for (callers check the parent record first). */
    public static List<Account> readAccountsWithoutSharing(Set<Id> accountIds) {
        return new SystemAccountReader().read(accountIds);
    }

    // ------------------------------------------------------------------ private

    private static final String ACCOUNT_SELECT =
        'SELECT Id, Name, OwnerId, IsPersonAccount, Phone, PersonMobilePhone, PersonEmail, '
        + 'PersonMailingStreet, PersonMailingCity, PersonMailingState, PersonMailingPostalCode, '
        + 'BillingStreet, BillingCity, BillingState, BillingPostalCode, Company__c, PersonTitle, '
        + 'BD_Industry__c, Is_Realtor__c, Type, Type__c, Group__pc FROM Account';

    private static ContactInfo fromAccount(Account a, String notOwnerNote) {
        ContactInfo c = info(a.Id, a.Phone, a.PersonMobilePhone, a.PersonEmail);
        // Person Accounts use PersonMailing* (13k populated vs 2.9k Billing*). Billing is only a
        // fallback for display; imports and Add partner put the market in BillingCity.
        Boolean hasMailing = a.PersonMailingStreet != null || a.PersonMailingCity != null
            || a.PersonMailingState != null || a.PersonMailingPostalCode != null;
        c.street = hasMailing ? a.PersonMailingStreet : a.BillingStreet;
        c.city = hasMailing ? a.PersonMailingCity : a.BillingCity;
        c.state = hasMailing ? a.PersonMailingState : a.BillingState;
        c.postalCode = hasMailing ? a.PersonMailingPostalCode : a.BillingPostalCode;
        Boolean partner = LoWsPartnerTagService.isPartner(a);
        if (partner) {
            c.company = a.Company__c ?? a.PersonTitle;
        }
        if (a.OwnerId == UserInfo.getUserId() && a.IsPersonAccount) {
            c.canEdit = true;
        } else {
            c.note = notOwnerNote ?? (partner ? SHARED_PARTNER_NOTE : NOT_OWNER_NOTE);
        }
        return c;
    }

    /** One "Phone": the mobile number, falling back to the main phone. */
    private static ContactInfo info(Id recordId, String phone, String mobile, String email) {
        ContactInfo c = new ContactInfo();
        c.recordId = recordId;
        c.phone = String.isBlank(mobile) ? phone : mobile;
        c.email = email != null && email.equalsIgnoreCase(PLACEHOLDER_EMAIL) ? null : email;
        return c;
    }

    /** True when the record's email is the placeholder: a blank save then leaves it alone. */
    private static Boolean isPlaceholderOnFile(Id recordId) {
        String onFile = recordId.getSObjectType() == Lead.SObjectType
            ? [SELECT Email FROM Lead WHERE Id = :recordId].Email
            : [SELECT PersonEmail FROM Account WHERE Id = :recordId].PersonEmail;
        return onFile != null && onFile.equalsIgnoreCase(PLACEHOLDER_EMAIL);
    }

    /** SYSTEM_MODE alone keeps the caller's sharing, so these reads need a without-sharing hop. */
    private without sharing class SystemAccountReader {
        List<Account> read(Set<Id> accountIds) {
            return Database.query(ACCOUNT_SELECT + ' WHERE Id IN :accountIds', AccessLevel.SYSTEM_MODE);
        }
    }
}