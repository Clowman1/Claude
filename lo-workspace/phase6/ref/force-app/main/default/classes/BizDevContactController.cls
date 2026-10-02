/**
 * Backs the Biz Dev Contact List tab on Brandon's Command Center and Adam's CEO Hub.
 *
 * Contacts are BizDev Expansion Person Accounts. That container is deliberate: RingCentral's
 * Task_Stamp_Last_RC_Call_SMS_on_Account flow matches Account.PersonContactId to Task.WhoId and
 * stamps Last_RC_Call__c / Last_RC_SMS__c with no record type scoping, so call and text history
 * arrives here for free. A Contact would not receive it.
 */
public with sharing class BizDevContactController {
    private static final String RECORD_TYPE_DEVELOPER_NAME = 'BizDev_Expansion';
    private static final String NOTE_TYPE = 'Note';
    private static final Integer NOTES_PER_CONTACT = 20;

    @AuraEnabled(cacheable=true)
    public static List<BizDevContact> getContacts() {
        Id recordTypeId = bizDevRecordTypeId();
        if (recordTypeId == null) {
            return new List<BizDevContact>();
        }

        List<Account> accounts = [
            SELECT Id, Name, FirstName, LastName, PersonContactId, Business_Type__c,
                   Phone, PersonMobilePhone, PersonEmail,
                   Last_RC_Call__c, Last_RC_SMS__c, CreatedDate, CreatedBy.Name
            FROM Account
            WHERE RecordTypeId = :recordTypeId
            ORDER BY Name
            LIMIT 2000
        ];
        if (accounts.isEmpty()) {
            return new List<BizDevContact>();
        }

        Set<Id> accountIds = new Set<Id>();
        Set<Id> personContactIds = new Set<Id>();
        for (Account contactAccount : accounts) {
            accountIds.add(contactAccount.Id);
            if (contactAccount.PersonContactId != null) {
                personContactIds.add(contactAccount.PersonContactId);
            }
        }

        Map<Id, Event> nextEventByAccountId = nextEvents(accountIds, personContactIds);
        Map<Id, List<BizDevNote>> notesByAccountId = notesByAccount(accountIds);

        List<BizDevContact> contacts = new List<BizDevContact>();
        for (Account contactAccount : accounts) {
            contacts.add(new BizDevContact(
                contactAccount,
                nextEventByAccountId.get(contactAccount.Id),
                notesByAccountId.get(contactAccount.Id)
            ));
        }
        return contacts;
    }

    /**
     * Every field is optional by design - these are contacts captured in seconds from a phone.
     * Person Accounts still require a LastName, so when none is given we fall back to whatever
     * else identifies the person rather than refusing the save.
     */
    @AuraEnabled
    public static Id createContact(
        String firstName,
        String lastName,
        String phone,
        String email,
        String businessType,
        String notes
    ) {
        Id recordTypeId = bizDevRecordTypeId();
        if (recordTypeId == null) {
            throw new AuraHandledException(
                'The BizDev Expansion record type is missing. Ask an admin to restore it.'
            );
        }

        String cleanedFirstName = trimToNull(firstName);
        String cleanedLastName = trimToNull(lastName);
        String cleanedPhone = trimToNull(phone);
        String cleanedEmail = trimToNull(email);
        String cleanedBusinessType = trimToNull(businessType);
        String cleanedNotes = trimToNull(notes);

        if (cleanedFirstName == null
            && cleanedLastName == null
            && cleanedPhone == null
            && cleanedEmail == null
            && cleanedBusinessType == null
            && cleanedNotes == null) {
            throw new AuraHandledException('Enter at least one detail before saving.');
        }

        Account contactAccount = new Account(
            RecordTypeId = recordTypeId,
            FirstName = cleanedFirstName,
            LastName = resolveLastName(cleanedLastName, cleanedEmail, cleanedPhone),
            PersonMobilePhone = cleanedPhone,
            PersonEmail = cleanedEmail,
            Business_Type__c = cleanedBusinessType
        );
        insert contactAccount;

        if (cleanedNotes != null) {
            insert buildNote(contactAccount.Id, cleanedNotes);
        }
        return contactAccount.Id;
    }

    /**
     * Inline edit from the list. Only the columns the list actually shows can be written, and the
     * whitelist is the guard: `fields` arrives from the browser, so an un-whitelisted key is
     * rejected rather than passed to an sObject field assignment.
     *
     * Phone always writes to PersonMobilePhone - that is the field the quick-add form populates
     * and the one the list reads first, so editing cannot leave two competing numbers behind.
     */
    @AuraEnabled
    public static void updateContact(Id accountId, Map<String, String> fields) {
        if (accountId == null) {
            throw new AuraHandledException('A contact is required.');
        }
        if (fields == null || fields.isEmpty()) {
            return;
        }

        Account contactAccount = new Account(Id = accountId);
        Boolean touchedAnything = false;

        for (String fieldKey : fields.keySet()) {
            String value = trimToNull(fields.get(fieldKey));
            if (fieldKey == 'firstName') {
                contactAccount.FirstName = value;
            } else if (fieldKey == 'lastName') {
                // A Person Account cannot lose its last name, so a cleared one falls back the same
                // way the quick-add form does rather than failing the save.
                contactAccount.LastName = value == null
                    ? resolveLastName(null, trimToNull(fields.get('email')), trimToNull(fields.get('phone')))
                    : value;
            } else if (fieldKey == 'businessType') {
                contactAccount.Business_Type__c = value;
            } else if (fieldKey == 'phone') {
                contactAccount.PersonMobilePhone = value;
            } else if (fieldKey == 'email') {
                contactAccount.PersonEmail = value;
            } else {
                throw new AuraHandledException('That field cannot be edited from the list.');
            }
            touchedAnything = true;
        }

        if (touchedAnything) {
            update contactAccount;
        }
    }

    @AuraEnabled
    public static void saveNote(Id accountId, String body) {
        if (accountId == null) {
            throw new AuraHandledException('A contact is required.');
        }
        String cleanedBody = trimToNull(body);
        if (cleanedBody == null) {
            throw new AuraHandledException('Enter a note before saving.');
        }

        insert buildNote(accountId, cleanedBody);
    }

    private static Enhanced_Note__c buildNote(Id accountId, String body) {
        return new Enhanced_Note__c(
            Account__c = accountId,
            Body__c = body,
            Type__c = NOTE_TYPE,
            Subject__c = 'Biz Dev Note',
            IsDeleted__c = false
        );
    }

    private static String resolveLastName(String lastName, String email, String phone) {
        if (lastName != null) {
            return lastName;
        }
        if (email != null) {
            return email;
        }
        if (phone != null) {
            return phone;
        }
        return 'Biz Dev Contact';
    }

    private static Map<Id, Event> nextEvents(Set<Id> accountIds, Set<Id> personContactIds) {
        Map<Id, Event> nextEventByAccountId = new Map<Id, Event>();
        if (accountIds.isEmpty()) {
            return nextEventByAccountId;
        }

        Map<Id, Id> accountIdByPersonContactId = new Map<Id, Id>();
        for (Account contactAccount : [
            SELECT Id, PersonContactId FROM Account WHERE Id IN :accountIds AND PersonContactId != null
        ]) {
            accountIdByPersonContactId.put(contactAccount.PersonContactId, contactAccount.Id);
        }

        Date today = Date.today();
        Datetime nowValue = System.now();
        // Events reach a Person Account either way round: WhatId when logged against the account,
        // WhoId when logged against the person. Both are checked so a meeting cannot go missing.
        for (Event eventRecord : [
            SELECT Id, WhatId, WhoId, Subject, ActivityDate, ActivityDateTime, StartDateTime
            FROM Event
            WHERE (WhatId IN :accountIds OR WhoId IN :personContactIds)
            AND (
                ActivityDate >= :today
                OR ActivityDateTime >= :nowValue
                OR StartDateTime >= :nowValue
            )
            ORDER BY ActivityDate ASC NULLS LAST, ActivityDateTime ASC NULLS LAST, StartDateTime ASC NULLS LAST
            LIMIT 2000
        ]) {
            Id ownerAccountId = eventRecord.WhatId;
            if (ownerAccountId == null || !accountIds.contains(ownerAccountId)) {
                ownerAccountId = accountIdByPersonContactId.get(eventRecord.WhoId);
            }
            if (ownerAccountId != null && !nextEventByAccountId.containsKey(ownerAccountId)) {
                nextEventByAccountId.put(ownerAccountId, eventRecord);
            }
        }
        return nextEventByAccountId;
    }

    private static Map<Id, List<BizDevNote>> notesByAccount(Set<Id> accountIds) {
        Map<Id, List<BizDevNote>> notesByAccountId = new Map<Id, List<BizDevNote>>();
        if (accountIds.isEmpty()) {
            return notesByAccountId;
        }
        for (Enhanced_Note__c note : [
            SELECT Id, Account__c, Body__c, CreatedDate, CreatedBy.Name
            FROM Enhanced_Note__c
            WHERE Account__c IN :accountIds
            AND IsDeleted__c = false
            AND (Type__c = :NOTE_TYPE OR Type__c = null)
            ORDER BY CreatedDate DESC
            LIMIT 2000
        ]) {
            List<BizDevNote> notes = notesByAccountId.get(note.Account__c);
            if (notes == null) {
                notes = new List<BizDevNote>();
                notesByAccountId.put(note.Account__c, notes);
            }
            if (notes.size() < NOTES_PER_CONTACT) {
                notes.add(new BizDevNote(note));
            }
        }
        return notesByAccountId;
    }

    private static Id bizDevRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_DEVELOPER_NAME);
        return info == null ? null : info.getRecordTypeId();
    }

    private static String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() == 0 ? null : trimmed;
    }

    public class BizDevContact {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String recordUrl { get; set; }
        @AuraEnabled public String businessType { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public Datetime lastCall { get; set; }
        @AuraEnabled public Datetime lastSms { get; set; }
        @AuraEnabled public String nextEventSubject { get; set; }
        @AuraEnabled public Datetime nextEventDate { get; set; }
        @AuraEnabled public String createdByName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public List<BizDevNote> notes { get; set; }
        @AuraEnabled public Integer noteCount { get; set; }

        public BizDevContact(Account contactAccount, Event nextEvent, List<BizDevNote> notes) {
            this.id = contactAccount.Id;
            this.name = contactAccount.Name;
            this.firstName = contactAccount.FirstName;
            this.lastName = contactAccount.LastName;
            this.recordUrl = '/lightning/r/Account/' + contactAccount.Id + '/view';
            this.businessType = contactAccount.Business_Type__c;
            this.phone = String.isNotBlank(contactAccount.PersonMobilePhone)
                ? contactAccount.PersonMobilePhone
                : contactAccount.Phone;
            this.email = contactAccount.PersonEmail;
            this.lastCall = contactAccount.Last_RC_Call__c;
            this.lastSms = contactAccount.Last_RC_SMS__c;
            this.createdByName = contactAccount.CreatedBy == null ? '' : contactAccount.CreatedBy.Name;
            this.createdDate = contactAccount.CreatedDate;
            if (nextEvent != null) {
                this.nextEventSubject = String.isBlank(nextEvent.Subject)
                    ? 'Scheduled Event'
                    : nextEvent.Subject;
                this.nextEventDate = nextEvent.ActivityDateTime != null
                    ? nextEvent.ActivityDateTime
                    : nextEvent.StartDateTime;
                if (this.nextEventDate == null && nextEvent.ActivityDate != null) {
                    this.nextEventDate = Datetime.newInstance(nextEvent.ActivityDate, Time.newInstance(0, 0, 0, 0));
                }
            }
            this.notes = notes == null ? new List<BizDevNote>() : notes;
            this.noteCount = this.notes.size();
        }
    }

    public class BizDevNote {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String body { get; set; }
        @AuraEnabled public String authorName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }

        public BizDevNote(Enhanced_Note__c note) {
            this.id = note.Id;
            this.body = note.Body__c;
            this.authorName = note.CreatedBy == null ? '' : note.CreatedBy.Name;
            this.createdDate = note.CreatedDate;
        }
    }
}