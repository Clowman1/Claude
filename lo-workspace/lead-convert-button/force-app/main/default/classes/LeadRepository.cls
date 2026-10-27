// ADR-0001: portal/Perfect Day selectors use SYSTEM_MODE so Customer Community Plus can query owned Leads without Lead CRUD on the license.

public with sharing class LeadRepository {
    private static List<String> LEAD_FIELDS;
    private static LeadRepository self;
    static{
        List<String> fields = new List<String>();
        Set<String> ownerFields = new Set<String>();
        Set<String> userFields = new Set<String>{'NMLS_ID__c','Banking_Bridge_ID__c'};
        fields.addAll(Schema.getGlobalDescribe().get('Lead').getDescribe().fields.getMap().keySet());
//        Map<String, SObjectField> userFieldMap = Schema.getGlobalDescribe().get('User').getDescribe().fields.getMap();
//        for(String s: userFields){
//            ownerFields.add('Owner.'+s);
//        }
//        String ownerFieldSubQuery = String.join((Iterable<String>)userFields, ',');
//        ownerFieldSubQuery = 'TYPEOF Owner WHEN USER THEN ' + ownerFieldSubQuery + ' END';
//        fields.add(ownerFieldSubQuery);
        LEAD_FIELDS = fields;
    }
    public static LeadRepository getInstance(){
        if(self==null){

            self = new LeadRepository();
        }
        return self;
    }
    public Lead getLeadById(String recordId){
        String query = 'SELECT ' + String.join(LEAD_FIELDS, ',')
                + ' FROM Lead WHERE Id=:recordId';
        System.debug(query);
        Lead lead = (Lead)Database.query(query);
        return lead;
    }

    /**
     * Selector used by Realtor Lead Convert quick action.
     * Keep this focused to avoid dynamic SELECT * usage in conversion logic.
     */
    public Lead selectForRealtorConvert(Id leadId) {
        if (leadId == null) {
            return null;
        }

        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, Title, Company,
                   Street, City, State, PostalCode, Country, Description, Website, LeadSource,
                   OwnerId, Status, IsConverted, ConvertedAccountId, Follow_Up_Account__c,
                   Realtor_Group__c, RecordType.DeveloperName
            FROM Lead
            WHERE Id = :leadId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        return leads.isEmpty() ? null : leads[0];
    }

    /**
     * Selects Leads by IDs with SMS Opt Out field for trigger handler use.
     * Used by SchMsgLeadOptOutBlockTrigHandler to check opt-out status when creating new Scheduled Messages.
     */
    public Map<Id, Lead> selectSmsOptOutByIds(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return new Map<Id, Lead>();
        }
        return new Map<Id, Lead>([
            SELECT Id, Opt_Out_from_SMS_Automation__c
            FROM Lead
            WHERE Id IN :leadIds
            WITH SECURITY_ENFORCED
        ]);
    }

    /**
     * Selects Leads by email for borrower portal opt-out processing.
     */
    public List<Lead> selectByEmailsForEmailOptOut(Set<String> emails) {
        if (emails == null || emails.isEmpty()) {
            return new List<Lead>();
        }

        return [
            SELECT Id, Email, HasOptedOutOfEmail
            FROM Lead
            WHERE Email IN :emails
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Converted Leads for Twilio / comms relinking (ConvertedAccountId / ConvertedContactId).
     */
    public Map<Id, Lead> selectConvertedByIds(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return new Map<Id, Lead>();
        }
        return new Map<Id, Lead>([
            SELECT Id, IsConverted, ConvertedAccountId, ConvertedContactId
            FROM Lead
            WHERE Id IN :leadIds
            AND IsConverted = true
            WITH SECURITY_ENFORCED
        ]);
    }

  /**
     * New leads assigned to the user that still need an initial contact attempt.
     */
    public List<Lead> selectNewLeadsToContact(Id ownerId, Date minimumCreatedDate) {
        if (ownerId == null) {
            return new List<Lead>();
        }

        Date createdDateFilter = minimumCreatedDate == null
            ? Date.newInstance(2024, 1, 1)
            : minimumCreatedDate;

        // Leads deferred from Perfect Day carry a future appointment time and
        // stay out of the queue until it passes.
        Datetime nowValue = System.now();
        return [
            SELECT Id, Name, CreatedDate, Status, Phone, Email, LeadSource
            FROM Lead
            WHERE OwnerId = :ownerId
              AND IsConverted = false
              AND Status = 'New'
              AND CreatedDate >= :createdDateFilter
              AND (Appointment_Date_Time__c = null OR Appointment_Date_Time__c <= :nowValue)
              AND RecordType.DeveloperName IN :ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 500
        ];
    }

    /**
     * Pre-approved leads owned by the user for Perfect Day review queues.
     */
    public List<Lead> selectPreApprovalsToReview(Id ownerId) {
        if (ownerId == null) {
            return new List<Lead>();
        }

        return [
            SELECT Id, Name, Status, Pre_Approval_Date__c, Email, CreatedDate,
                   Last_Call_Attempt_RingCentral__c, Last_SMS_Attempt_RingCentral__c,
                   LastActivityDate
            FROM Lead
            WHERE OwnerId = :ownerId
              AND IsConverted = false
              AND Status = 'Pre-Approval'
              AND RecordType.DeveloperName IN :ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES
            WITH SYSTEM_MODE
            ORDER BY Pre_Approval_Date__c DESC NULLS LAST, LastModifiedDate DESC
            LIMIT 500
        ];
    }

    /**
     * Narrow selector for Perfect Day defer: only the fields the action touches,
     * owner-scoped so a user can never defer someone else's lead.
     */
    public Lead selectForPerfectDayDefer(Id leadId, Id ownerId) {
        if (leadId == null || ownerId == null) {
            return null;
        }
        List<Lead> leads = [
            SELECT Id, OwnerId, Appointment_Date_Time__c
            FROM Lead
            WHERE Id = :leadId
              AND OwnerId = :ownerId
              AND IsConverted = false
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return leads.isEmpty() ? null : leads[0];
    }

    public Set<Id> selectLeadIdsWithFutureEvents(Set<Id> leadIds) {
        Set<Id> leadIdsWithFutureEvents = new Set<Id>();
        if (leadIds == null || leadIds.isEmpty()) {
            return leadIdsWithFutureEvents;
        }

        Datetime nowValue = System.now();
        // LO Workspace exact-time follow-ups (Prompt_Key__c 'follow-up') are reminders, not booked appointments:
        // the lead stays in "New leads to contact". System mode: Prompt_Key__c FLS is only in the External LO
        // permsets, and the caller passes the user's own lead Ids.
        for (Event eventRecord : [
            SELECT WhoId
            FROM Event
            WHERE WhoId IN :leadIds
              AND (
                  ActivityDate > TODAY
                  OR ActivityDateTime >= :nowValue
                  OR StartDateTime >= :nowValue
              )
              AND Prompt_Key__c != :LoWsCalendarService.FOLLOW_UP_EVENT_KEY
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            if (eventRecord.WhoId != null) {
                leadIdsWithFutureEvents.add(eventRecord.WhoId);
            }
        }
        return leadIdsWithFutureEvents;
    }

    public Id selectConsumerLeadRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
              AND DeveloperName = 'Consumer_Lead_record_type'
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    public List<Lead> selectPortalLeadsForImportMatch(
        Id ownerId,
        Set<String> emails,
        Set<String> phoneVariants
    ) {
        if (ownerId == null) {
            return new List<Lead>();
        }
        Set<String> safeEmails = emails == null ? new Set<String>() : emails;
        Set<String> safePhones = phoneVariants == null ? new Set<String>() : phoneVariants;
        if (safeEmails.isEmpty() && safePhones.isEmpty()) {
            return new List<Lead>();
        }
        return [
            SELECT Id, Email, Phone, MobilePhone
            FROM Lead
            WHERE OwnerId = :ownerId
              AND IsConverted = false
              AND RecordType.DeveloperName IN :ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES
              AND (
                  Email IN :safeEmails
                  OR Phone IN :safePhones
                  OR MobilePhone IN :safePhones
              )
            WITH SYSTEM_MODE
            LIMIT 500
        ];
    }

    public List<Lead> selectPortalLeadsByOwner(Id ownerId) {
        if (ownerId == null) {
            return new List<Lead>();
        }
        return [
            SELECT Id, Name, Status, IsConverted, Phone, Email, MobilePhone, LeadSource, CreatedDate,
                   LastActivityDate, Loan_Purpose__c, Loan_Amount__c, Loan_Program__c,
                   City, State, AriveId__c, Realtor_Buying_Agent__c, RecordType.DeveloperName
            FROM Lead
            WHERE OwnerId = :ownerId
              // Converted leads from the last year feed the My Leads "Converted" tab.
              AND (IsConverted = false OR ConvertedDate = LAST_N_DAYS:365)
              AND RecordType.DeveloperName IN :ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];
    }

    /**
     * LO Workspace My Leads: one status scope ('active' = not Nurture, 'nurture' = Nurture + 30 Day + Follow Up,
     * which the page shows under Working) with the search done here, so a big book is never cut before
     * it is filtered. term matches name, email, a full phone number or its last 4 digits.
     */
    public List<Lead> selectPortalLeadsByOwner(Id ownerId, String scope, String term, Integer rowLimit) {
        if (ownerId == null) {
            return new List<Lead>();
        }
        Set<String> recordTypes = ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES;
        Integer lim = rowLimit == null || rowLimit < 1 ? 2000 : Math.min(rowLimit, 2000);
        String soql = 'SELECT Id, Name, Status, IsConverted, Phone, Email, MobilePhone, LeadSource, CreatedDate,'
            + ' LastActivityDate, Loan_Purpose__c, Loan_Amount__c, Loan_Program__c,'
            + ' City, State, AriveId__c, Realtor_Buying_Agent__c, RecordType.DeveloperName'
            + ' FROM Lead WHERE OwnerId = :ownerId AND IsConverted = false'
            + ' AND RecordType.DeveloperName IN :recordTypes';
        soql += scope == 'nurture'
            // LO Workspace shows 30 Day + Follow Up under Working, so it never enters the nurture page (keeps
            // "Load more" honest); the old portal's Nurture tab still lists it.
            ? (UserInfo.getUserType() == 'Standard'
                ? ' AND Status LIKE \'Nurtur%\''
                : ' AND (Status LIKE \'Nurtur%\' OR Status = \'30 Day + Follow Up\')')
            : ' AND (NOT Status LIKE \'Nurtur%\')';
        String likeTerm;
        Set<String> phones = new Set<String>();
        String last4;
        if (String.isNotBlank(term)) {
            likeTerm = '%' + term.trim() + '%'; // bound, so no escaping
            String digits = term.replaceAll('\\D', '');
            if (digits.length() >= 10) {
                phones = ExternalLoPhoneNormalizer.soqlVariants(new Set<String>{ digits.right(10) });
            }
            last4 = digits.length() >= 4 ? '%' + digits.right(4) : null;
            soql += ' AND (Name LIKE :likeTerm OR Email LIKE :likeTerm OR Phone IN :phones OR MobilePhone IN :phones'
                + (last4 == null ? '' : ' OR Phone LIKE :last4 OR MobilePhone LIKE :last4') + ')';
        }
        soql += ' WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT :lim';
        return Database.query(soql);
    }

    /**
     * The user's open leads referred by one partner — the shared pipeline on
     * the partner detail page.
     */
    public List<Lead> selectPortalLeadsByPartner(Id ownerId, Id partnerId) {
        if (ownerId == null || partnerId == null) {
            return new List<Lead>();
        }
        return [
            SELECT Id, Name, Status, Phone, Email, MobilePhone, LeadSource, CreatedDate,
                   LastActivityDate, Loan_Purpose__c, Loan_Amount__c, Loan_Program__c,
                   City, State, AriveId__c, Realtor_Buying_Agent__c, RecordType.DeveloperName
            FROM Lead
            WHERE OwnerId = :ownerId
              AND IsConverted = false
              AND Realtor_Buying_Agent__c = :partnerId
              AND RecordType.DeveloperName IN :ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    public Lead selectPortalLeadDetail(Id leadId, Id ownerId) {
        if (leadId == null || ownerId == null) {
            return null;
        }
        List<Lead> leads = [
            SELECT Id, Name, Status, Phone, Email, MobilePhone, LeadSource, CreatedDate,
                   LastActivityDate, Loan_Purpose__c, Loan_Amount__c, Loan_Program__c,
                   City, State, PostalCode, AriveId__c, Description, Realtor_Buying_Agent__c,
                   Realtor_Buying_Agent__r.Name, RecordType.DeveloperName, OwnerId, Rating,
                   Down_Payment_Amount__c, Down_Payment_Percentage__c, Estimated_Monthly_Payment__c,
                   Property_Type__c, Purchase_Price__c
            FROM Lead
            WHERE Id = :leadId
              AND OwnerId = :ownerId
              AND IsConverted = false
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return leads.isEmpty() ? null : leads[0];
    }

    private static final Set<String> CONVERT_ANY_LEAD_PROFILES = new Set<String>{ 'Manager', 'System Administrator' };

    public Lead selectPortalLeadForConversion(Id leadId, Id ownerId) {
        if (leadId == null || ownerId == null) {
            return null;
        }

        List<String> fields = new List<String>{
            'Id', 'Name', 'FirstName', 'LastName', 'OwnerId', 'IsConverted',
            'Converted_Transaction_ID__c', 'Subject_Property_Street__c', 'Subject_Property_City__c', 'Property_State__c', 'Subject_Property_Zip__c',
            'Loan_Amount__c', 'Value_of_Property__c', 'Purchase_Price__c'
        };
        Map<String, Schema.SObjectField> leadFieldMap = Schema.SObjectType.Lead.fields.getMap();
        for (String candidate : new List<String>{
            'SSN__c', 'Borrower_SSN__c', 'Social_Security_Number__c', 'Social_Security__c',
            'Household_Income__c', 'Annual_Income__c', 'Gross_Monthly_Income__c', 'Borrower_Income__c',
            'Estimated_Property_Value__c'
        }) {
            if (leadFieldMap.containsKey(candidate)) {
                fields.add(candidate);
            }
        }

        // Who may convert: the lead's Owner or Loan Partner, or any Manager or Admin.
        String profileName = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() WITH SYSTEM_MODE].Name;
        String teamFilter = CONVERT_ANY_LEAD_PROFILES.contains(profileName)
            ? ''
            : ' AND (OwnerId = :ownerId OR Loan_Partner__c = :ownerId)';
        String query =
            'SELECT ' + String.join(fields, ',') +
            ' FROM Lead WHERE Id = :leadId' + teamFilter + ' AND IsConverted = false WITH SYSTEM_MODE LIMIT 1';
        List<Lead> leads = (List<Lead>) Database.query(query);
        return leads.isEmpty() ? null : leads[0];
    }

    public Lead selectPortalLeadForDocumentRequest(Id leadId, Id ownerId) {
        if (leadId == null || ownerId == null) {
            return null;
        }

        List<String> fields = new List<String>{
            'Id', 'Name', 'FirstName', 'LastName', 'Email', 'OwnerId', 'IsConverted', 'Converted_Transaction_ID__c'
        };
        Map<String, Schema.SObjectField> leadFieldMap = Schema.SObjectType.Lead.fields.getMap();
        if (leadFieldMap.containsKey('Portal_Hash_Parameter__c')) {
            fields.add('Portal_Hash_Parameter__c');
        }
        if (leadFieldMap.containsKey('Lead_Portal_Link_As_URL__c')) {
            fields.add('Lead_Portal_Link_As_URL__c');
        }

        String query =
            'SELECT ' + String.join(fields, ',') +
            ' FROM Lead WHERE Id = :leadId AND OwnerId = :ownerId WITH SYSTEM_MODE LIMIT 1';
        List<Lead> leads = (List<Lead>) Database.query(query);
        return leads.isEmpty() ? null : leads[0];
    }

    public List<Lead> selectDuplicateLeads(Id ownerId, String nameTerm, String phoneDigits, String email) {
        if (ownerId == null) {
            return new List<Lead>();
        }
        String normalizedEmail = String.isBlank(email) ? null : email.trim().toLowerCase();
        String normalizedName = String.isBlank(nameTerm) ? null : nameTerm.trim();
        if (normalizedEmail == null && normalizedName == null && String.isBlank(phoneDigits)) {
            return new List<Lead>();
        }

        List<Lead> matches = new List<Lead>();
        for (Lead leadRecord : [
            SELECT Id, Name, Status, Phone, MobilePhone, Email, LeadSource, Loan_Purpose__c,
                   Loan_Amount__c, Loan_Program__c, City, State, CreatedDate, LastActivityDate
            FROM Lead
            WHERE OwnerId = :ownerId
              AND IsConverted = false
              AND RecordType.DeveloperName IN :ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            Boolean nameMatch = normalizedName != null
                && normalizedName.length() >= 3
                && leadRecord.Name != null
                && leadRecord.Name.toLowerCase().contains(normalizedName.toLowerCase());
            Boolean phoneMatch = !String.isBlank(phoneDigits)
                && leadRecord.Phone != null
                && leadRecord.Phone.replaceAll('[^0-9]', '') == phoneDigits;
            Boolean emailMatch = normalizedEmail != null
                && leadRecord.Email != null
                && leadRecord.Email.toLowerCase() == normalizedEmail;
            if (nameMatch || phoneMatch || emailMatch) {
                matches.add(leadRecord);
            }
            if (matches.size() >= 10) {
                break;
            }
        }
        return matches;
    }

    public List<Lead> selectPortalPreApprovalsByOwner(Id ownerId) {
        if (ownerId == null) {
            return new List<Lead>();
        }
        return [
            SELECT Id, Name, Status, Pre_Approval_Date__c, Loan_Amount__c, Loan_Program__c,
                   App_Summary_Credit__c, Realtor_Buying_Agent__c, Realtor_Buying_Agent__r.Name,
                   Last_Call_Attempt_RingCentral__c, Last_SMS_Attempt_RingCentral__c,
                   LastActivityDate, Email, CreatedDate
            FROM Lead
            WHERE OwnerId = :ownerId
              AND IsConverted = false
              AND Status = 'Pre-Approval'
              AND RecordType.DeveloperName IN :ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES
            WITH SYSTEM_MODE
            ORDER BY Pre_Approval_Date__c DESC NULLS LAST
            LIMIT 500
        ];
    }

    public List<Lead> selectPastClientLeadsByOwner(Id ownerId) {
        if (ownerId == null) {
            return new List<Lead>();
        }
        return [
            SELECT Id, Name, Status, Phone, Email, MobilePhone, LeadSource, CreatedDate,
                   LastActivityDate, Loan_Purpose__c, Loan_Amount__c, Loan_Program__c,
                   City, State, AriveId__c, Realtor_Buying_Agent__c, RecordType.DeveloperName
            FROM Lead
            WHERE OwnerId = :ownerId
              AND IsConverted = false
              AND LeadSource = 'Past Client'
              AND RecordType.DeveloperName IN :ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ];
    }
}