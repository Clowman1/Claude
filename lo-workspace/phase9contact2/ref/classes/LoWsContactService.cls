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
        @AuraEnabled public String mobile;
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
    }

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
        if (type == Transaction__c.SObjectType) {
            List<Transaction__c> loans = [SELECT Borrower_Name__c FROM Transaction__c WHERE Id = :recordId];
            if (loans.isEmpty() || loans[0].Borrower_Name__c == null) throw new DomainException(NOT_FOUND);
            List<Account> borrowers = readAccountsWithoutSharing(new Set<Id>{ loans[0].Borrower_Name__c });
            if (borrowers.isEmpty()) throw new DomainException(NOT_FOUND);
            return fromAccount(borrowers[0], BORROWER_NOTE);
        }
        throw new DomainException(NOT_FOUND);
    }

    /** Saves the contact fields of a record the running user owns; returns the re-read card. */
    public static ContactInfo updateContact(
        Id recordId, String phone, String mobile, String email,
        String street, String city, String state, String postalCode
    ) {
        ContactInfo current = getContact(recordId);
        if (current.canEdit != true) {
            throw new DomainException(current.note ?? NOT_OWNER_NOTE);
        }
        phone = checkPhone(phone, 'Phone');
        mobile = checkPhone(mobile, 'Mobile');
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
            Lead l = new Lead(Id = targetId, Phone = phone, MobilePhone = mobile,
                Street = clean(street), City = clean(city), State = clean(state), PostalCode = clean(postalCode));
            if (email != null || !isPlaceholderOnFile(targetId)) l.Email = email;
            record = l;
        } else {
            Account a = new Account(Id = targetId, Phone = phone, PersonMobilePhone = mobile,
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
        if (l.IsConverted) return CONVERTED_NOTE;
        return l.OwnerId == UserInfo.getUserId() ? null : NOT_OWNER_NOTE;
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

    private static ContactInfo info(Id recordId, String phone, String mobile, String email) {
        ContactInfo c = new ContactInfo();
        c.recordId = recordId;
        c.phone = phone;
        c.mobile = mobile;
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