public with sharing class LeadDocumentRequestService {
    private static final String DEFAULT_STATUS = 'New';
    private static final String REQUESTED_STATUS = 'Requested';
    private static final String REVIEW_STATUS = 'Review';
    private static final String APPROVED_STATUS = 'Approved';
    private static final String CLEARED_STATUS = 'Cleared';
    private static final String REVIEW_STATUS_FIELD = 'Condition_Document_Review_Status__c';
    private static final String REVIEW_PENDING = 'Pending Review';
    private static final String REVIEW_ACCEPTED = 'Accepted';
    private static final String REVIEW_REJECTED = 'Rejected';
    private static final String REVIEW_NOT_NEEDED = 'Not Needed';
    private static final String FALLBACK_FOLDER = 'Conditions';
    private static final String NOT_NEEDED_FOLDER = 'Not Needed';
    private static final String REJECTION_TEMPLATE_DEVELOPER_NAME = 'Lead_Document_Rejection';
    private static final String EMAIL_TEMPLATE_DEVELOPER_NAME = 'Lead_Initial_Documents_Needed';
    private static final String FOLLOW_UP_TEMPLATE_DEVELOPER_NAME = 'Lead_Documents_Follow_Up';
    private static final String UPDATED_DOCS_TEMPLATE_DEVELOPER_NAME = 'Lead_Updated_Docs_Needed';
    private static final String REFINANCE_TEMPLATE_DEVELOPER_NAME = 'Lead_Refinance_Items_Needed';
    private static final String REQUESTED_DOCUMENT_LIST_PLACEHOLDER = '{{REQUESTED_DOCUMENT_LIST}}';
    private static final String OWNER_SIGNATURE_PLACEHOLDER = '{{OWNER_SIGNATURE}}';
    private static final String SENDER_SIGNATURE_PLACEHOLDER = '{{SENDER_SIGNATURE}}';
    private static final String LEAD_PORTAL_LINK_PLACEHOLDER = '{{LEAD_PORTAL_LINK}}';
    // Use this in a template greeting instead of {!recipient.FirstName}. These are Visualforce
    // templates declared recipientType="Lead", so {!recipient.*} only binds when the whoId is a
    // Lead - it renders empty for a co-borrower, whose merge target is a Person Contact.
    private static final String BORROWER_FIRST_NAME_PLACEHOLDER = '{{BORROWER_FIRST_NAME}}';
    @TestVisible private static String testLeadHomeUrlOverride;
    @TestVisible private static Map<Id, String> testLeadPortalHashesByLeadId = new Map<Id, String>();

// Category doubles as the destination folder in the Lead Documents tab: the four categories a
    // Loan Officer can choose are named after the folders themselves. Anything unrecognised, or a
    // request created before the categories were reduced, files under Conditions.
    private static final Map<String, String> FOLDER_BY_CATEGORY = new Map<String, String>{
        'Income' => 'Income',
        'Asset' => 'Asset',
        'Credit' => 'Credit',
        'Other' => 'Credit'
    };

    // The Name field is the grouping label shown above the document detail. A hand-added condition
    // only supplies a type and a description, so the label is the type the Loan Officer picked --
    // verbatim. Renaming Credit to Identification here made the table disagree with the choice they
    // had just made. Catalog-derived conditions keep their own friendlier labels in
    // resolveReferenceConditionName.
    public static String resolveGroupingName(String category) {
        return String.isBlank(category) ? 'Other' : category;
    }

    public static String resolveFolderName(String category) {
        if (String.isBlank(category)) {
            return FALLBACK_FOLDER;
        }
        String folder = FOLDER_BY_CATEGORY.get(category);
        return folder == null ? FALLBACK_FOLDER : folder;
    }

    public class LeadDocumentRequestException extends Exception {}

    public class RequestInput {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public Boolean includeInEmail { get; set; }
        @AuraEnabled public Boolean canBorrowerSee { get; set; }
        @AuraEnabled public Id referenceId { get; set; }
        // 'ALL' (or blank) = the whole file, 'PRIMARY' = the primary borrower alone, otherwise a
        // Borrower__c Id. Blank on an update means "leave the existing assignment alone".
        @AuraEnabled public String assignment { get; set; }
    }

    public class RequestItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String description;
        @AuraEnabled public String rejectionNotes;
        @AuraEnabled public String subject;
        @AuraEnabled public String category;
        @AuraEnabled public String type;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Date requestedDate;
        @AuraEnabled public String assignedToName;
        @AuraEnabled public Boolean includeInEmail;
        @AuraEnabled public Boolean canBorrowerSee;
        @AuraEnabled public Id convertedConditionId;
        @AuraEnabled public Id referenceId;
        @AuraEnabled public Decimal fileCount;
        @AuraEnabled public String assignment;
        @AuraEnabled public String borrowerName;
        // True when this condition is assigned to a borrower who has no email address, so the
        // table can flag that it cannot actually be requested from anyone.
        @AuraEnabled public Boolean borrowerMissingEmail;

        public RequestItem(Lead_Document_Request__c requestRecord, Decimal linkedFileCount) {
            id = requestRecord.Id;
            name = requestRecord.Name;
            status = requestRecord.Status__c;
            description = requestRecord.Description__c;
            rejectionNotes = requestRecord.Rejection_Notes__c;
            subject = requestRecord.Subject__c;
            category = requestRecord.Category__c;
            type = requestRecord.Type__c;
            createdDate = requestRecord.CreatedDate;
            requestedDate = requestRecord.Requested_Date__c;
            assignedToName = requestRecord.Owner == null ? null : requestRecord.Owner.Name;
            includeInEmail = requestRecord.Include_In_Email__c;
            canBorrowerSee = requestRecord.Can_Borrower_See__c;
            convertedConditionId = requestRecord.Converted_Condition__c;
            referenceId = requestRecord.Lead_Document_Request_Reference__c;
            fileCount = linkedFileCount == null ? 0 : linkedFileCount;
            // Several queries in this package select narrower field sets, so read the assignment
            // only when it was actually queried rather than forcing every caller to widen its SOQL.
            Map<String, Object> populated = requestRecord.getPopulatedFieldsAsMap();
            if (!populated.containsKey('Borrower__c') && !populated.containsKey('Assigned_To_Primary__c')) {
                assignment = null;
                borrowerName = null;
                borrowerMissingEmail = false;
            } else if (requestRecord.Borrower__c != null) {
                assignment = String.valueOf(requestRecord.Borrower__c);
                borrowerName = requestRecord.Borrower__r == null ? null : requestRecord.Borrower__r.Name;
                borrowerMissingEmail =
                    requestRecord.Borrower__r != null && String.isBlank(requestRecord.Borrower__r.Email__c);
            } else if (requestRecord.Assigned_To_Primary__c == true) {
                assignment = ASSIGNMENT_PRIMARY;
                borrowerName = null;
                borrowerMissingEmail = false;
            } else {
                assignment = ASSIGNMENT_ALL;
                borrowerName = null;
                borrowerMissingEmail = false;
            }
        }
    }

    public class LeadDocumentRequestData {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String borrowerLastName;
        @AuraEnabled public String borrowerEmail;
        @AuraEnabled public String portalLink;
        @AuraEnabled public Boolean isConverted;
        @AuraEnabled public Id convertedTransactionId;
        @AuraEnabled public List<RequestItem> requests;
    }

    public class EmailInformation {
        @AuraEnabled public String subject;
        @AuraEnabled public String htmlBody;
        @AuraEnabled public String toAddresses;
        @AuraEnabled public String ccAddresses;
    }

    public class EmailTemplateOption {
        @AuraEnabled public String label;
        @AuraEnabled public String developerName;

        public EmailTemplateOption(String label, String developerName) {
            this.label = label;
            this.developerName = developerName;
        }
    }

    public class DocumentItem {
        @AuraEnabled public Id id;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String filename;
        @AuraEnabled public String folderName;
        @AuraEnabled public String reviewStatus;
        @AuraEnabled public String createdByName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Decimal contentSize;

        public DocumentItem(ContentDocument documentRecord) {
            id = documentRecord.Id;
            contentVersionId = documentRecord.LatestPublishedVersionId;
            filename = String.isBlank(documentRecord.FileExtension)
                ? documentRecord.Title
                : documentRecord.Title + '.' + documentRecord.FileExtension;
            folderName = documentRecord.LatestPublishedVersion == null
                ? null
                : String.valueOf(documentRecord.LatestPublishedVersion.get('Folder__c'));
            reviewStatus = documentRecord.LatestPublishedVersion == null
                ? null
                : (Schema.SObjectType.ContentVersion.fields.getMap().containsKey(REVIEW_STATUS_FIELD)
                    ? String.valueOf(documentRecord.LatestPublishedVersion.get(REVIEW_STATUS_FIELD))
                    : null);
            createdByName = documentRecord.CreatedBy == null ? null : documentRecord.CreatedBy.Name;
            createdDate = documentRecord.CreatedDate;
            contentSize = documentRecord.LatestPublishedVersion == null
                ? null
                : documentRecord.LatestPublishedVersion.ContentSize;
        }
    }

    public static LeadDocumentRequestData initializeInternalData(Id leadId) {
        Lead leadRecord = getLeadOrThrow(leadId);
        ensurePortalHash(leadId);

        leadRecord = getLeadOrThrow(leadId);
        List<Lead_Document_Request__c> requestRecords =
            LeadDocumentRequestRepository.getInstance().selectByLeadIds(new Set<Id>{ leadId });
        Map<Id, Decimal> fileCountsByRequestId = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Map<Id, Lead_Document_Request__c>(requestRecords).keySet());

        LeadDocumentRequestData data = new LeadDocumentRequestData();
        data.leadId = leadRecord.Id;
        data.leadName = leadRecord.Name;
        // Drives the "Testiana Portal Link" label when a Loan Officer copies the link to paste
        // into an email of their own.
        data.borrowerLastName = leadRecord.LastName;
        data.borrowerEmail = leadRecord.Email;
        data.portalLink = buildLeadPortalLink(leadRecord);
        data.isConverted = leadRecord.IsConverted;
        data.convertedTransactionId = leadRecord.Converted_Transaction_ID__c;
        data.requests = new List<RequestItem>();
        for (Lead_Document_Request__c requestRecord : requestRecords) {
            data.requests.add(new RequestItem(requestRecord, fileCountsByRequestId.get(requestRecord.Id)));
        }
        return data;
    }

    public static List<RequestItem> saveRequests(Id leadId, List<RequestInput> inputs) {
        Lead leadRecord = getLeadOrThrow(leadId);
        ensureLeadIsOpenForDocumentRequests(leadRecord);

        if (inputs == null) {
            inputs = new List<RequestInput>();
        }

        List<Lead_Document_Request__c> recordsToInsert = new List<Lead_Document_Request__c>();
        List<Lead_Document_Request__c> recordsToUpdate = new List<Lead_Document_Request__c>();
        for (RequestInput input : inputs) {
            if (input == null || (input.id == null
                && String.isBlank(input.name)
                && String.isBlank(input.subject)
                && String.isBlank(input.description)
                && String.isBlank(input.category))) {
                continue;
            }

            String resolvedName = String.isNotBlank(input.name)
                ? input.name
                : (String.isNotBlank(input.subject) ? input.subject : 'Document Request');

            Lead_Document_Request__c requestRecord = new Lead_Document_Request__c(
                Id = input.id,
                Lead__c = leadId,
                Name = resolvedName,
                Status__c = String.isBlank(input.status) ? DEFAULT_STATUS : input.status,
                Description__c = input.description,
                Subject__c = input.subject,
                Category__c = input.category,
                Type__c = String.isBlank(input.type) ? 'Loan Officer' : input.type,
                Include_In_Email__c = input.includeInEmail == true,
                Can_Borrower_See__c = input.canBorrowerSee == true,
                Lead_Document_Request_Reference__c = input.referenceId
            );
            // On an update a blank token means the caller is not touching assignment, so the
            // existing Borrower__c is left as it is rather than being silently reset to shared.
            if (input.id == null || String.isNotBlank(input.assignment)) {
                applyAssignment(requestRecord, input.assignment);
            }
            if (requestRecord.Id == null) {
                recordsToInsert.add(requestRecord);
            } else {
                recordsToUpdate.add(requestRecord);
            }
        }

        if (!recordsToInsert.isEmpty()) {
            assertSaveSucceeded(
                Database.insert(recordsToInsert, false, AccessLevel.SYSTEM_MODE),
                'save Lead document requests'
            );
        }
        if (!recordsToUpdate.isEmpty()) {
            assertSaveSucceeded(
                Database.update(recordsToUpdate, false, AccessLevel.SYSTEM_MODE),
                'update Lead document requests'
            );
        }
        if (recordsToInsert.isEmpty() && recordsToUpdate.isEmpty()) {
            throw new LeadDocumentRequestException('Enter request details before saving.');
        }

        return initializeInternalData(leadId).requests;
    }

    /**
     * One assignable party on the file. The primary is not a Borrower__c row - it is the Lead
     * itself - so it is synthesised here with a null id, which is also the "whole file" value.
     */
    // The three assignment states, carried as one token so the flow, the invocable and the preset
    // selector all pass a single value instead of an Id plus a flag.
    public static final String ASSIGNMENT_ALL = 'ALL';
    public static final String ASSIGNMENT_PRIMARY = 'PRIMARY';

    public class BorrowerOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String email;
        @AuraEnabled public Boolean isPrimary;
        // Without an email there is no portal and nothing can be requested, so the picker
        // lists them as ineligible rather than silently dropping them.
        @AuraEnabled public Boolean assignable;

        public BorrowerOption(String value, String label, String email, Boolean isPrimary) {
            this.value = value;
            this.label = label;
            this.email = email;
            this.isPrimary = isPrimary;
            this.assignable = String.isNotBlank(email);
        }
    }

    /** Resolves an assignment token onto a record. ALL leaves both fields empty. */
    private static void applyAssignment(Lead_Document_Request__c requestRecord, String assignment) {
        Boolean isPrimary = ASSIGNMENT_PRIMARY.equalsIgnoreCase(assignment);
        requestRecord.Assigned_To_Primary__c = isPrimary;
        requestRecord.Borrower__c = (isPrimary || String.isBlank(assignment) || ASSIGNMENT_ALL.equalsIgnoreCase(assignment))
            ? null
            : (Id) assignment;
    }

    /**
     * Every party who can own a condition on this Lead: the primary first, then additional
     * borrowers in the order they were added. Callers decide what to do with the ineligible ones.
     */
    @AuraEnabled(cacheable=true)
    public static List<BorrowerOption> getBorrowerOptions(Id leadId) {
        List<BorrowerOption> options = new List<BorrowerOption>();
        if (leadId == null) {
            return options;
        }

        Lead leadRecord = getLeadOrThrow(leadId);
        String primaryName = String.join(
            new List<String>{
                String.isBlank(leadRecord.FirstName) ? '' : leadRecord.FirstName,
                String.isBlank(leadRecord.LastName) ? '' : leadRecord.LastName
            },
            ' '
        ).trim();
        options.add(new BorrowerOption(ASSIGNMENT_ALL, 'All borrowers', null, false));
        options.get(0).assignable = true;
        options.add(
            new BorrowerOption(
                ASSIGNMENT_PRIMARY,
                String.isBlank(primaryName) ? 'Primary Borrower' : primaryName,
                leadRecord.Email,
                true
            )
        );

        for (Borrower__c row : [
            SELECT Id, Name, First_Name__c, Last_Name__c, Email__c
            FROM Borrower__c
            WHERE Lead__c = :leadId AND Removed__c = FALSE
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ]) {
            String rowName = String.isNotBlank(row.Name)
                ? row.Name
                : String.join(
                      new List<String>{
                          String.isBlank(row.First_Name__c) ? '' : row.First_Name__c,
                          String.isBlank(row.Last_Name__c) ? '' : row.Last_Name__c
                      },
                      ' '
                  ).trim();
            options.add(new BorrowerOption(String.valueOf(row.Id), rowName, row.Email__c, false));
        }
        return options;
    }

    public static List<RequestItem> createRequestsFromReferences(Id leadId, List<Id> referenceIds) {
        return createRequestsFromReferences(leadId, referenceIds, 'Loan Officer', null);
    }

    public static List<RequestItem> createRequestsFromReferences(Id leadId, List<Id> referenceIds, String requestType) {
        return createRequestsFromReferences(leadId, referenceIds, requestType, null);
    }

    public static List<RequestItem> createRequestsFromReferences(
        Id leadId,
        List<Id> referenceIds,
        String requestType,
        String assignment
    ) {
        Lead leadRecord = getLeadOrThrow(leadId);
        ensureLeadIsOpenForDocumentRequests(leadRecord);
        Set<Id> uniqueReferenceIds = referenceIds == null ? new Set<Id>() : new Set<Id>(referenceIds);
        if (uniqueReferenceIds.isEmpty()) {
            throw new LeadDocumentRequestException('Select at least one document package item before saving.');
        }

        Map<Id, Lead_Document_Request_Reference__c> referencesById =
            LeadDocumentRequestReferenceRepository.getInstance().selectByIds(uniqueReferenceIds);
        List<Lead_Document_Request__c> recordsToInsert = new List<Lead_Document_Request__c>();
        for (Id referenceId : uniqueReferenceIds) {
            Lead_Document_Request_Reference__c referenceRecord = referencesById.get(referenceId);
            if (referenceRecord == null || referenceRecord.Active__c != true) {
                continue;
            }
            recordsToInsert.add(buildRequestFromReference(leadId, referenceRecord, requestType, assignment));
        }
        if (recordsToInsert.isEmpty()) {
            throw new LeadDocumentRequestException('No active document package items were found to create.');
        }

        assertSaveSucceeded(
            Database.insert(recordsToInsert, false, AccessLevel.SYSTEM_MODE),
            'save Lead document requests from references'
        );

        return initializeInternalData(leadId).requests;
    }

    public static void deleteRequest(Id requestId) {
        if (requestId == null) {
            return;
        }
        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            return;
        }
        ensureLeadIsOpenForDocumentRequests(getLeadOrThrow(requestRecord.Lead__c));
        Database.delete(new Lead_Document_Request__c(Id = requestId), false, AccessLevel.SYSTEM_MODE);
    }

    // General notes live on the Lead itself, so a request carries only the borrower-facing
    // description. The rejection reason is written by rejectRequestDocument, not here.
    public static RequestItem saveNotes(Id requestId, String description) {
        Lead_Document_Request__c requestRecord = getEditableRequestOrThrow(requestId);
        Database.update(
            new Lead_Document_Request__c(Id = requestId, Description__c = description),
            true,
            AccessLevel.SYSTEM_MODE
        );
        requestRecord.Description__c = description;
        Decimal fileCount = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Set<Id>{ requestId }).get(requestId);
        return new RequestItem(requestRecord, fileCount);
    }

    public static RequestItem handleInternalFileUpload(Id requestId, List<Id> contentVersionIds) {
        if (requestId == null) {
            throw new LeadDocumentRequestException('A document request is required for file upload.');
        }
        Set<Id> versionIds = contentVersionIds == null ? new Set<Id>() : new Set<Id>(contentVersionIds);
        if (versionIds.isEmpty()) {
            throw new LeadDocumentRequestException('At least one uploaded document is required.');
        }

        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            throw new LeadDocumentRequestException('Unable to locate the document request for upload.');
        }
        ensureLeadIsOpenForDocumentRequests(getLeadOrThrow(requestRecord.Lead__c));

        associateContentVersions(versionIds, requestId, requestRecord.Lead__c);
        // Left unfiled on purpose. The document lands in the folder matching its condition only
        // once someone accepts it, and in Not Needed if it is sent back.
        updateContentVersions(versionIds, null, requestId);
        Database.update(
            new Lead_Document_Request__c(Id = requestId, Status__c = 'Review'),
            true,
            AccessLevel.SYSTEM_MODE
        );

        requestRecord.Status__c = 'Review';
        Decimal fileCount = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Set<Id>{ requestId }).get(requestId);
        return new RequestItem(requestRecord, fileCount);
    }

    public static List<DocumentItem> getRequestDocuments(Id requestId) {
        if (requestId == null) {
            return new List<DocumentItem>();
        }

        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            return new List<DocumentItem>();
        }

        List<DocumentItem> documents = new List<DocumentItem>();
        for (ContentDocument documentRecord : LeadDocumentRequestRepository.getInstance()
            .selectDocumentsByLinkedEntityId(requestId)) {
            documents.add(new DocumentItem(documentRecord));
        }
        return documents;
    }

    // Accepting a document says the file is legitimate, not that the request is satisfied. When the
    // last outstanding document is accepted the caller passes closeWhenNoneRemaining, which the UI
    // collects from the Loan Officer, so a misfiled upload can be kept without closing the request.
    public static RequestItem approveRequestDocument(Id requestId, Id contentDocumentId, Boolean closeWhenNoneRemaining) {
        if (requestId == null || contentDocumentId == null) {
            throw new LeadDocumentRequestException('A document request and document are required.');
        }

        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            throw new LeadDocumentRequestException('Unable to locate the Lead document request.');
        }
        Lead leadRecord = getLeadOrThrow(requestRecord.Lead__c);
        ensureLeadIsOpenForDocumentRequests(leadRecord);
        ensureCanActOnRequest(leadRecord);

        // Filing happens on the decision, not the upload: until someone has looked at it, the
        // document belongs in no folder rather than in a folder that implies it was accepted.
        updateLatestContentVersionReviewStatus(
            contentDocumentId,
            REVIEW_ACCEPTED,
            resolveFolderName(requestRecord.Category__c),
            requestId
        );
        String nextStatus;
        if (countPendingDocuments(requestId) > 0) {
            nextStatus = REVIEW_STATUS;
        } else {
            nextStatus = closeWhenNoneRemaining == true ? CLEARED_STATUS : REQUESTED_STATUS;
        }
        Database.update(
            new Lead_Document_Request__c(Id = requestId, Status__c = nextStatus),
            true,
            AccessLevel.SYSTEM_MODE
        );
        requestRecord.Status__c = nextStatus;
        Decimal fileCount = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Set<Id>{ requestId }).get(requestId);
        return new RequestItem(requestRecord, fileCount);
    }

    public static RequestItem rejectRequestDocument(
        Id requestId,
        Id contentDocumentId,
        String rejectionReason,
        String updatedRequestDescription
    ) {
        if (requestId == null || contentDocumentId == null) {
            throw new LeadDocumentRequestException('A document request and document are required.');
        }
        if (String.isBlank(rejectionReason)) {
            throw new LeadDocumentRequestException('Please enter a rejection comment.');
        }

        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            throw new LeadDocumentRequestException('Unable to locate the Lead document request.');
        }
        Lead leadRecord = getLeadOrThrow(requestRecord.Lead__c);
        ensureLeadIsOpenForDocumentRequests(leadRecord);
        ensureCanActOnRequest(leadRecord);

        // A returned document is filed under Not Needed so it stays on the Lead for the record
        // without cluttering the folder the borrower's good copy will eventually land in.
        updateLatestContentVersionReviewStatus(contentDocumentId, REVIEW_REJECTED, NOT_NEEDED_FOLDER, null);
        removeDocumentLink(requestId, contentDocumentId);

        Lead_Document_Request__c requestUpdate = new Lead_Document_Request__c(Id = requestId);
        requestUpdate.Status__c = countPendingDocuments(requestId) > 0 ? REVIEW_STATUS : REQUESTED_STATUS;
        requestUpdate.Can_Borrower_See__c = true;
        requestUpdate.Include_In_Email__c = true;
        requestUpdate.Rejection_Notes__c = rejectionReason.trim();
        requestRecord.Rejection_Notes__c = requestUpdate.Rejection_Notes__c;
        if (String.isNotBlank(updatedRequestDescription)) {
            requestUpdate.Description__c = updatedRequestDescription.trim();
            requestRecord.Description__c = requestUpdate.Description__c;
        }
        Database.update(requestUpdate, true, AccessLevel.SYSTEM_MODE);

        requestRecord.Status__c = requestUpdate.Status__c;
        requestRecord.Can_Borrower_See__c = true;
        requestRecord.Include_In_Email__c = true;

        sendBorrowerRejectionEmail(leadRecord, requestId);

        Decimal fileCount = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Set<Id>{ requestId }).get(requestId);
        return new RequestItem(requestRecord, fileCount);
    }

    /**
     * Files a document under Not Needed and takes it off the condition.
     *
     * Unlike a rejection this asks nothing of the borrower - no reason, no email. It is for the
     * upload that is simply not wanted: a duplicate, a page sent twice, something the Loan
     * Officer asked for and no longer needs. The document stays on the Lead so the record of
     * what arrived is intact.
     */
    public static RequestItem markRequestDocumentNotNeeded(
        Id requestId,
        Id contentDocumentId,
        Boolean closeWhenNoneRemaining
    ) {
        if (requestId == null || contentDocumentId == null) {
            throw new LeadDocumentRequestException('A document request and document are required.');
        }

        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            throw new LeadDocumentRequestException('Unable to locate the Lead document request.');
        }
        Lead leadRecord = getLeadOrThrow(requestRecord.Lead__c);
        ensureLeadIsOpenForDocumentRequests(leadRecord);
        ensureCanActOnRequest(leadRecord);

        updateLatestContentVersionReviewStatus(
            contentDocumentId,
            REVIEW_NOT_NEEDED,
            NOT_NEEDED_FOLDER,
            null
        );
        removeDocumentLink(requestId, contentDocumentId);

        String nextStatus;
        if (countPendingDocuments(requestId) > 0) {
            nextStatus = REVIEW_STATUS;
        } else {
            // Same question accepting the last document asks: the upload is dealt with, but only
            // the Loan Officer knows whether the borrower still owes what was originally asked for.
            nextStatus = closeWhenNoneRemaining == true ? CLEARED_STATUS : REQUESTED_STATUS;
        }
        Database.update(
            new Lead_Document_Request__c(Id = requestId, Status__c = nextStatus),
            true,
            AccessLevel.SYSTEM_MODE
        );

        requestRecord.Status__c = nextStatus;
        Decimal fileCount = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Set<Id>{ requestId }).get(requestId);
        return new RequestItem(requestRecord, fileCount);
    }

    private static Lead_Document_Request__c getEditableRequestOrThrow(Id requestId) {
        if (requestId == null) {
            throw new LeadDocumentRequestException('A Lead document request is required.');
        }
        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            throw new LeadDocumentRequestException('Unable to locate the Lead document request.');
        }
        ensureLeadIsOpenForDocumentRequests(getLeadOrThrow(requestRecord.Lead__c));
        return requestRecord;
    }

    public static EmailInformation getEmailPreview(Id leadId) {
        return getEmailTemplatePreview(leadId, EMAIL_TEMPLATE_DEVELOPER_NAME);
    }

    public static List<EmailTemplateOption> getEmailTemplateOptions() {
        // Explicit list, not a folder query: the PULSE folder also holds the Transaction-side
        // templates, which must never be offered here. A new Lead template needs a line added.
        return new List<EmailTemplateOption>{
            new EmailTemplateOption('Pre-Approval Docs Needed', EMAIL_TEMPLATE_DEVELOPER_NAME),
            new EmailTemplateOption('Pre-Approval - Updated Docs Needed', UPDATED_DOCS_TEMPLATE_DEVELOPER_NAME),
            new EmailTemplateOption('Refinance Items Needed', REFINANCE_TEMPLATE_DEVELOPER_NAME),
            new EmailTemplateOption('Follow Up - Resend Link', FOLLOW_UP_TEMPLATE_DEVELOPER_NAME)
        };
    }

    public static EmailInformation getEmailTemplatePreview(Id leadId, String templateDeveloperName) {
        Lead leadRecord = getLeadOrThrow(leadId);
        ensureLeadIsOpenForDocumentRequests(leadRecord);
        ensurePortalHash(leadId);
        leadRecord = getLeadOrThrow(leadId);

        List<Lead_Document_Request__c> requestRecords =
            LeadDocumentRequestRepository.getInstance().selectIncludedForEmail(leadId);
        Messaging.SingleEmailMessage rendered = renderTemplate(leadRecord, requestRecords, templateDeveloperName);

        EmailInformation preview = new EmailInformation();
        preview.subject = rendered.getSubject();
        preview.htmlBody = rendered.getHtmlBody();
        preview.toAddresses = String.isBlank(leadRecord.Email) ? '' : leadRecord.Email;
        preview.ccAddresses = String.join(buildDefaultCcAddresses(leadRecord), ', ');
        return preview;
    }

    public static String sendRequestEmail(Id leadId) {
        EmailInformation rendered = getEmailTemplatePreview(leadId, EMAIL_TEMPLATE_DEVELOPER_NAME);
        return sendEditedRequestEmail(
            leadId, rendered.subject, rendered.htmlBody, null, null, EMAIL_TEMPLATE_DEVELOPER_NAME
        );
    }

    public static String sendEditedRequestEmail(Id leadId, String subject, String htmlBody) {
        // Null To/CC means "use the defaults" (borrower email, Loan Partner on the Lead).
        return sendEditedRequestEmail(leadId, subject, htmlBody, null, null, null);
    }

    public static String sendEditedRequestEmail(
        Id leadId,
        String subject,
        String htmlBody,
        String toAddresses,
        String ccAddresses
    ) {
        return sendEditedRequestEmail(leadId, subject, htmlBody, toAddresses, ccAddresses, null);
    }

    /**
     * Sends the request email and returns null when everything committed cleanly, or a warning
     * for the sender when the email left but Salesforce could not finish the record updates.
     */
    /** One borrower's send: who it goes to, what they can be shown, and how it is deduped. */
    public class BorrowerSendTarget {
        public Id borrowerId;
        public String name;
        public String email;
        public String portalLink;
        // Contact/Lead/User the message is logged against. Messaging only accepts those three, so a
        // co-borrower needs their Person Account creating first - which is why Person Accounts are
        // minted on first email rather than at conversion.
        public Id targetObjectId;
    }

    /**
     * Sends one email per borrower, each listing only that borrower's conditions plus anything
     * shared with the whole file. Returns a per-recipient summary for the UI.
     *
     * The double-send guard is keyed on the logged activity's WhoId, which is now the recipient
     * rather than always the Lead - so a second borrower is no longer silently swallowed for having
     * a near-identical subject, while a genuine double-click on one person is still refused.
     */
    public static List<String> sendPerBorrowerRequestEmails(
        Id leadId,
        String subject,
        String templateDeveloperName
    ) {
        Lead leadRecord = getLeadOrThrow(leadId);
        ensureLeadIsOpenForDocumentRequests(leadRecord);
        List<Lead_Document_Request__c> allRequests =
            LeadDocumentRequestRepository.getInstance().selectIncludedForEmail(leadId);
        if (allRequests.isEmpty()) {
            throw new LeadDocumentRequestException('At least one document request must be included in the email.');
        }

        List<BorrowerSendTarget> targets = buildSendTargets(leadRecord);
        if (targets.isEmpty()) {
            throw new LeadDocumentRequestException(
                'No borrower on this lead has an email address, so there is nobody to send to.'
            );
        }

        List<String> outcomes = new List<String>();
        for (BorrowerSendTarget target : targets) {
            List<Lead_Document_Request__c> theirs = new List<Lead_Document_Request__c>();
            for (Lead_Document_Request__c request : allRequests) {
                if (isRequestForBorrower(request, target)) {
                    theirs.add(request);
                }
            }
            if (theirs.isEmpty()) {
                outcomes.add(target.name + ': nothing outstanding, not emailed');
                continue;
            }
            if (findRecentSend(target.targetObjectId, subject) != null) {
                outcomes.add(target.name + ': skipped, the same email went out in the last few minutes');
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(target.targetObjectId);
            mail.setTreatTargetObjectAsRecipient(false);
            mail.setToAddresses(new List<String>{ target.email });
            List<String> ccAddresses = buildDefaultCcAddresses(leadRecord);
            if (!ccAddresses.isEmpty()) {
                mail.setCcAddresses(ccAddresses);
            }
            mail.setSubject(subject);
            mail.setHtmlBody(buildTemplatedBorrowerBody(target, theirs, templateDeveloperName));
            mail.setSaveAsActivity(true);

            if (!Test.isRunningTest()) {
                try {
                    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
                } catch (Exception sendException) {
                    if (!isRowLockFailure(sendException)) {
                        throw sendException;
                    }
                }
            }
            outcomes.add(target.name + ': sent to ' + target.email + ' (' + theirs.size() + ' items)');
        }
        return outcomes;
    }

    private static Boolean isRequestForBorrower(Lead_Document_Request__c request, BorrowerSendTarget target) {
        if (request.Borrower__c != null) {
            return request.Borrower__c == target.borrowerId;
        }
        if (request.Assigned_To_Primary__c == true) {
            return target.borrowerId == null;
        }
        return true;
    }

    private static List<BorrowerSendTarget> buildSendTargets(Lead leadRecord) {
        List<BorrowerSendTarget> targets = new List<BorrowerSendTarget>();

        if (String.isNotBlank(leadRecord.Email)) {
            ensurePortalHash(leadRecord.Id);
            Lead refreshed = getLeadOrThrow(leadRecord.Id);
            BorrowerSendTarget primary = new BorrowerSendTarget();
            primary.borrowerId = null;
            primary.name = buildBorrowerDisplayName(refreshed);
            primary.email = refreshed.Email;
            primary.portalLink = buildLeadPortalLink(refreshed);
            primary.targetObjectId = refreshed.Id;
            targets.add(primary);
        }

        List<Borrower__c> rows = [
            SELECT Id, Name, Email__c, Account__c, Portal_Hash_Parameter__c
            FROM Borrower__c
            WHERE Lead__c = :leadRecord.Id AND Removed__c = FALSE AND Email__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ];
        if (rows.isEmpty()) {
            return targets;
        }

        Set<Id> needAccount = new Set<Id>();
        for (Borrower__c row : rows) {
            if (row.Account__c == null) {
                needAccount.add(row.Id);
            }
        }
        if (!needAccount.isEmpty()) {
            BorrowerPersonAccountService.findOrCreate(needAccount);
            rows = [
                SELECT Id, Name, Email__c, Account__c, Portal_Hash_Parameter__c
                FROM Borrower__c
                WHERE Id IN :rows
                WITH SYSTEM_MODE
                ORDER BY CreatedDate
            ];
        }

        Map<Id, Account> accountsById = new Map<Id, Account>();
        Set<Id> accountIds = new Set<Id>();
        for (Borrower__c row : rows) {
            if (row.Account__c != null) {
                accountIds.add(row.Account__c);
            }
        }
        if (!accountIds.isEmpty()) {
            accountsById = new Map<Id, Account>(
                [SELECT Id, PersonContactId FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE]
            );
        }

        String configuredUrl = resolveLeadPortalPageUrl();
        for (Borrower__c row : rows) {
            Account personAccount = row.Account__c == null ? null : accountsById.get(row.Account__c);
            if (personAccount == null || personAccount.PersonContactId == null) {
                // Without a Person Contact there is no legal target for the message, so skip rather
                // than send something that cannot be logged against anyone.
                continue;
            }
            BorrowerSendTarget target = new BorrowerSendTarget();
            target.borrowerId = row.Id;
            target.name = row.Name;
            target.email = row.Email__c;
            target.targetObjectId = personAccount.PersonContactId;
            if (String.isNotBlank(row.Portal_Hash_Parameter__c) && String.isNotBlank(configuredUrl)) {
                String separator = configuredUrl.contains('?') ? '&' : '?';
                target.portalLink = configuredUrl + separator +
                    'id=' + EncodingUtil.urlEncode(row.Portal_Hash_Parameter__c, 'UTF-8');
            }
            targets.add(target);
        }
        return targets;
    }

    private static String buildBorrowerDisplayName(Lead leadRecord) {
        String built = (String.isBlank(leadRecord.FirstName) ? '' : leadRecord.FirstName + ' ') +
            (String.isBlank(leadRecord.LastName) ? '' : leadRecord.LastName);
        return String.isBlank(built.trim()) ? 'Borrower' : built.trim();
    }

    /**
     * The wording every borrower will read, with the per-borrower item list left out, so the sender
     * can review the verbiage before sending several personalised copies. Rendered against the Lead,
     * so {!recipient.*} shows the primary's name as a representative example.
     */
    @AuraEnabled
    public static String getSharedTemplatePreview(Id leadId, String templateDeveloperName) {
        Lead leadRecord = getLeadOrThrow(leadId);
        String resolvedName = String.isBlank(templateDeveloperName)
            ? EMAIL_TEMPLATE_DEVELOPER_NAME
            : templateDeveloperName;
        EmailTemplate template = LeadDocumentRequestRepository.getInstance()
            .selectEmailTemplateByDeveloperName(resolvedName);
        if (template == null) {
            return '';
        }
        try {
            Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
                template.Id,
                leadRecord.Id,
                null
            );
            String body = rendered.getHtmlBody();
            if (String.isBlank(body)) {
                return '';
            }
            // Drop the item-list token rather than filling it: the list differs per borrower and
            // showing one borrower's items here would misrepresent what the others receive.
            body = body.replace(REQUESTED_DOCUMENT_LIST_PLACEHOLDER, '');
            if (body.contains(LEAD_PORTAL_LINK_PLACEHOLDER)) {
                body = body.replace(LEAD_PORTAL_LINK_PLACEHOLDER, '#');
            }
            // Shows the primary's name as a representative example; each borrower's own send
            // resolves to theirs.
            body = applyBorrowerFirstName(body, leadRecord.FirstName);
            return addSenderSignature(body);
        } catch (Exception renderException) {
            return '';
        }
    }

    /**
     * The same stored template the single-borrower path uses, rendered once per borrower.
     *
     * {!recipient.*} resolves off the whoId passed to renderStoredEmailTemplate, and every borrower
     * now has one - the Lead for the primary, their Person Contact for a co-borrower - so the
     * template greets each person correctly without any hand-built body. Only the item list and the
     * portal link are swapped for that borrower's own.
     */
    private static String buildTemplatedBorrowerBody(
        BorrowerSendTarget target,
        List<Lead_Document_Request__c> requests,
        String templateDeveloperName
    ) {
        String resolvedName = String.isBlank(templateDeveloperName)
            ? EMAIL_TEMPLATE_DEVELOPER_NAME
            : templateDeveloperName;
        EmailTemplate template = LeadDocumentRequestRepository.getInstance()
            .selectEmailTemplateByDeveloperName(resolvedName);
        if (template != null) {
            try {
                Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
                    template.Id,
                    target.targetObjectId,
                    null
                );
                String renderedHtmlBody = rendered.getHtmlBody();
                if (String.isNotBlank(renderedHtmlBody)) {
                    return prepareRenderedHtmlBodyFor(renderedHtmlBody, target.portalLink, requests, target);
                }
            } catch (Exception renderException) {
                // Fall through to the plain body rather than failing the send outright.
            }
        }
        return buildBorrowerEmailBody(target, requests);
    }

    /** Fallback only, for when the chosen template is missing or will not render. */
    private static String buildBorrowerEmailBody(
        BorrowerSendTarget target,
        List<Lead_Document_Request__c> requests
    ) {
        List<String> parts = new List<String>();
        parts.add('<p>Hi ' + String.escapeSingleQuotes(target.name) + ',</p>');
        parts.add('<p>We need the following from you to complete your pre-approval:</p><ul>');
        for (Lead_Document_Request__c request : requests) {
            String label = String.isNotBlank(request.Subject__c) ? request.Subject__c : request.Name;
            parts.add(
                '<li><strong>' + (request.Category__c == null ? 'Item' : request.Category__c) +
                '</strong> - ' + label + '</li>'
            );
        }
        parts.add('</ul>');
        if (String.isNotBlank(target.portalLink)) {
            // Styles are inline, not a <style> block: this body is assembled here rather than
            // rendered from a template, and most mail clients strip document-level CSS. Matches
            // the .myButton rule in the Lead_Initial_Documents_Needed template.
            parts.add(
                '<p style="margin:22px 0;"><a href="' + target.portalLink + '"' +
                ' style="display:inline-block;vertical-align:middle;padding:12px 24px;' +
                'border-radius:8px;background:#0082cb;font:normal normal bold 20px arial;' +
                'color:#ffffff;text-decoration:none;">Upload Your Documents</a></p>' +
                '<p>This link is yours: it shows only the items we need from you.</p>'
            );
        }
        parts.add('<p>Thank you!</p>');
        // Every outbound email carries the sending user's signature card, same as the composed path.
        return addSenderSignature(String.join(parts, ''));
    }

    public static String sendEditedRequestEmail(
        Id leadId,
        String subject,
        String htmlBody,
        String toAddresses,
        String ccAddresses,
        String templateDeveloperName
    ) {
        Lead leadRecord = getLeadOrThrow(leadId);
        ensureLeadIsOpenForDocumentRequests(leadRecord);
        if (String.isBlank(leadRecord.Email)) {
            throw new LeadDocumentRequestException('Lead primary borrower email is required before sending document requests.');
        }
        ensurePortalHash(leadId);
        leadRecord = getLeadOrThrow(leadId);

        List<Lead_Document_Request__c> requestRecords =
            LeadDocumentRequestRepository.getInstance().selectIncludedForEmail(leadId);
        if (requestRecords.isEmpty()) {
            throw new LeadDocumentRequestException('At least one document request must be included in the email.');
        }
        if (String.isBlank(subject)) {
            throw new LeadDocumentRequestException('Email subject is required before sending.');
        }
        if (String.isBlank(htmlBody)) {
            throw new LeadDocumentRequestException('Email body is required before sending.');
        }

        // A blank To falls back to the borrower email. A non-null but empty CC means the sender
        // deliberately cleared the Loan Partner, so it is respected rather than re-defaulted.
        List<String> resolvedToAddresses = parseEmailAddressList(toAddresses, 'To');
        if (resolvedToAddresses.isEmpty()) {
            resolvedToAddresses.add(leadRecord.Email);
        }
        List<String> resolvedCcAddresses = ccAddresses == null
            ? buildDefaultCcAddresses(leadRecord)
            : parseEmailAddressList(ccAddresses, 'CC');

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(leadRecord.Id);
        mail.setToAddresses(resolvedToAddresses);
        mail.setTreatTargetObjectAsRecipient(false);
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(true);

        // Intentionally no org-wide From address: the email must send from the user clicking send,
        // not a shared inbox, so borrower replies land with the person they spoke with.
        if (!resolvedCcAddresses.isEmpty()) {
            mail.setCcAddresses(resolvedCcAddresses);
        }

        ensureNotAlreadyJustSent(leadId, subject);

        String warning = null;
        if (!Test.isRunningTest()) {
            try {
                Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
            } catch (Exception sendException) {
                if (!isRowLockFailure(sendException)) {
                    throw sendException;
                }
                // The email is already with the mail server. Rethrowing would roll back the
                // request and status updates and show a red failure, which is what led a Loan
                // Officer to click Send a second time and double-email a borrower. Keep the
                // updates, and hand back a warning instead of an error.
                warning = POST_DISPATCH_WARNING;
            }
        }

        markIncludedRequestsAsRequested(requestRecords);
        stampInitialDocsRequested(leadRecord, templateDeveloperName);
        return warning;
    }

    // Salesforce hands the email to the mail server before the activity logging that can hit
    // UNABLE_TO_LOCK_ROW, so a failure here does not mean the borrower was spared the email. The
    // logged activity is created outside this transaction and survives the rollback, which makes
    // it the only reliable evidence of what actually went out.
    private static final Integer RECENT_SEND_MINUTES = 5;
    private static final String POST_DISPATCH_WARNING =
        'The email was handed off to the mail server, but Salesforce hit a record lock before it '
        + 'finished updating the Lead. The requests and status have been updated. Check the '
        + 'activity timeline on this Lead before sending again - a second send would deliver a '
        + 'duplicate.';

    private static void ensureNotAlreadyJustSent(Id leadId, String subject) {
        Datetime lastSend = findRecentSend(leadId, subject);
        if (lastSend == null) {
            return;
        }
        throw new LeadDocumentRequestException(
            'This exact email already went to the borrower at ' + lastSend.format('h:mm a')
            + '. Use the Follow Up - Resend Link template if you meant to send it again.'
        );
    }

    // Judged from the error itself rather than by looking for the logged activity: that activity
    // is committed outside this transaction and is not reliably visible to a query made from
    // inside it.
    @TestVisible
    private static Boolean isRowLockFailure(Exception sendException) {
        String message = sendException == null ? null : sendException.getMessage();
        return message != null && message.contains('UNABLE_TO_LOCK_ROW');
    }

    /**
     * whoId is whoever the activity is logged against - the Lead for the primary, a co-borrower's
     * Person Contact for them - so the guard scopes per recipient rather than per file.
     */
    private static Datetime findRecentSend(Id whoId, String subject) {
        Id leadId = whoId;
        if (leadId == null || String.isBlank(subject)) {
            return null;
        }
        // Matches the activity Salesforce logs for a sent email: "Email: <subject> on <date>".
        String subjectPattern = 'Email: ' + subject + '%';
        Datetime cutoff = Datetime.now().addMinutes(-RECENT_SEND_MINUTES);
        List<Task> recentSends = Database.query(
            'SELECT Id, CreatedDate FROM Task' +
            ' WHERE WhoId = :leadId AND Subject LIKE :subjectPattern AND CreatedDate >= :cutoff' +
            ' WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1'
        );
        return recentSends.isEmpty() ? null : recentSends[0].CreatedDate;
    }

    // The first Pre-Approval Docs Needed email moves the Lead to Documents Requested. Only the
    // first: a Lead that has since reached Pre-Approval must not be dragged back a stage because
    // someone resent the request, and the follow-up template never touches status at all.
    // Initial_Docs_Requested_Date__c exists purely to make "first" detectable, rather than
    // inferring it from a status the Lead may have already moved past.
    private static final String DOCS_REQUESTED_STATUS = 'Documents Requested';

    @TestVisible
    private static void stampInitialDocsRequested(Lead leadRecord, String templateDeveloperName) {
        if (leadRecord == null || templateDeveloperName != EMAIL_TEMPLATE_DEVELOPER_NAME) {
            return;
        }
        if (!hasLeadField('Initial_Docs_Requested_Date__c')) {
            return;
        }

        Lead currentLead = getLeadWithInitialDocsStamp(leadRecord.Id);
        if (currentLead == null || currentLead.get('Initial_Docs_Requested_Date__c') != null) {
            return;
        }

        Lead leadUpdate = new Lead(Id = leadRecord.Id);
        leadUpdate.put('Initial_Docs_Requested_Date__c', Datetime.now());
        leadUpdate.Status = DOCS_REQUESTED_STATUS;

        try {
            Database.update(leadUpdate, true, AccessLevel.SYSTEM_MODE);
        } catch (Exception statusException) {
            // The borrower already has the email; a status or validation-rule problem on the Lead
            // must not present itself as a failed send. Retry happens on the next first-send only,
            // which is why the stamp and the status move together in one update.
            System.debug(
                LoggingLevel.ERROR,
                'Could not move Lead ' + leadRecord.Id + ' to ' + DOCS_REQUESTED_STATUS + ': ' +
                    statusException.getMessage()
            );
        }
    }

    private static Lead getLeadWithInitialDocsStamp(Id leadId) {
        List<Lead> leads = Database.query(
            'SELECT Id, Status, Initial_Docs_Requested_Date__c FROM Lead WHERE Id = :leadId WITH SYSTEM_MODE LIMIT 1'
        );
        return leads.isEmpty() ? null : leads[0];
    }

    private static Boolean hasLeadField(String fieldApiName) {
        return Schema.SObjectType.Lead.fields.getMap().containsKey(fieldApiName);
    }

    public static void populateMissingPortalHashes(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        List<Lead> leadsToUpdate = new List<Lead>();
        for (Lead leadRecord : LeadDocumentRequestRepository.getInstance().selectLeadsForPortalHash(leadIds).values()) {
            if (String.isBlank(getLeadPortalHash(leadRecord))) {
                String encryptedLeadId = encryptLeadId(leadRecord.Id);
                if (LeadDocumentRequestRepository.getInstance().hasLeadPortalHashField()) {
                    Lead updateRecord = new Lead(Id = leadRecord.Id);
                    updateRecord.put('Portal_Hash_Parameter__c', encryptedLeadId);
                    leadsToUpdate.add(updateRecord);
                }
                if (Test.isRunningTest()) {
                    testLeadPortalHashesByLeadId.put(leadRecord.Id, encryptedLeadId);
                }
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            Database.update(leadsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
    }

    public static Id decryptLeadId(String hashFromURL) {
        return Id.valueOf(BorrowerPortalEncryptionService.decryptString(hashFromURL));
    }

    public static String encryptLeadId(Id leadId) {
        return BorrowerPortalEncryptionService.encryptString(String.valueOf(leadId));
    }

    private static Lead getLeadOrThrow(Id leadId) {
        Map<Id, Lead> leads = LeadDocumentRequestRepository.getInstance().selectLeadsByIds(new Set<Id>{ leadId });
        Lead leadRecord = leads.get(leadId);
        if (leadRecord == null) {
            throw new LeadDocumentRequestException('Unable to locate a lead for document collection.');
        }
        return leadRecord;
    }

    // Accept, reject and clear are limited to the two people who own the relationship. The object
    // is Public Read/Write, so without this any user could reject a document on someone else's
    // Lead -- and rejecting emails the borrower. Visibility is untouched; everyone still sees all.
    private static void ensureCanActOnRequest(Lead leadRecord) {
        if (leadRecord == null) {
            return;
        }
        Id runningUserId = UserInfo.getUserId();
        if (leadRecord.OwnerId == runningUserId) {
            return;
        }
        Id loanPartnerId = resolveLoanPartnerId(leadRecord);
        if (loanPartnerId == runningUserId) {
            return;
        }
        if (isSystemAdministrator()) {
            return;
        }
        throw new LeadDocumentRequestException(
            'Only the Loan Officer or Loan Partner on this Lead can review documents.'
        );
    }

    private static Boolean isSystemAdministrator() {
        List<Profile> profiles = [SELECT Id, PermissionsModifyAllData FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        return !profiles.isEmpty() && profiles[0].PermissionsModifyAllData == true;
    }

    private static void ensureLeadIsOpenForDocumentRequests(Lead leadRecord) {
        if (leadRecord != null && leadRecord.IsConverted) {
            throw new LeadDocumentRequestException('Lead document requests can no longer be edited after conversion.');
        }
    }

    private static void ensurePortalHash(Id leadId) {
        populateMissingPortalHashes(new Set<Id>{ leadId });
    }

    // Sent when a Loan Officer or Loan Partner sends an item back. Deliberately not called a
    // rejection to the borrower: the copy says we looked and need a bit more. The other half of the
    // lead team is CC'd, so whoever did not do the reviewing still sees what was asked for.
    // Sends from the reviewing user rather than an org-wide address so the borrower's reply lands
    // with the person who looked at their document.
    private static void sendBorrowerRejectionEmail(Lead leadRecord, Id requestId) {
        if (leadRecord == null || String.isBlank(leadRecord.Email)) {
            throw new LeadDocumentRequestException(
                'This lead has no email address, so the borrower could not be told what is still needed.'
            );
        }
        EmailTemplate template = LeadDocumentRequestRepository.getInstance()
            .selectEmailTemplateByDeveloperName(REJECTION_TEMPLATE_DEVELOPER_NAME);
        if (template == null) {
            throw new LeadDocumentRequestException(
                'The borrower follow-up email template is missing, so no email was sent.'
            );
        }

        try {
            ensurePortalHash(leadRecord.Id);
        } catch (Exception portalHashException) {
            // A missing portal encryption key should not stop the borrower being told what is
            // still needed. The link falls back to whatever hash the Lead already carries.
            System.debug(LoggingLevel.WARN, 'Lead portal hash unavailable: ' + portalHashException.getMessage());
        }
        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
            template.Id,
            leadRecord.Id,
            requestId
        );

        String htmlBody = rendered.getHtmlBody();
        htmlBody = addLeadPortalLink(htmlBody, leadRecord);
        htmlBody = addSenderSignature(htmlBody);
        htmlBody = repairLeadPortalLinks(htmlBody, leadRecord);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ leadRecord.Email });
        List<String> ccAddresses = buildDefaultCcAddresses(leadRecord);
        if (!ccAddresses.isEmpty()) {
            email.setCcAddresses(ccAddresses);
        }
        email.setSubject(
            String.isBlank(rendered.getSubject())
                ? 'Need additional item(s) for your Pre-Approval'
                : rendered.getSubject()
        );
        email.setHtmlBody(htmlBody);
        // Same shape as the document request email, which sends and logs cleanly in this org:
        // the Lead is the target so the activity has something to attach to, and the recipient
        // list stays explicit. setWhatId is gone - it is only valid alongside a Contact target,
        // and the template rendering above already takes the request as its whatId.
        email.setTargetObjectId(leadRecord.Id);
        email.setTreatTargetObjectAsRecipient(false);
        email.setSaveAsActivity(true);
        String senderEmail = currentUserEmail();
        if (String.isNotBlank(senderEmail)) {
            email.setReplyTo(senderEmail);
        }

        if (!Test.isRunningTest()) {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        }
    }

    private static String currentUserEmail() {
        User sender = LeadDocumentRequestRepository.getInstance()
            .selectUsersByIds(new Set<Id>{ UserInfo.getUserId() })
            .get(UserInfo.getUserId());
        return sender == null ? null : sender.Email;
    }

    // The portal button is authored with an empty href and the real link is injected at send time,
    // matching how the Transaction rejection template works.
    @TestVisible
    private static String repairLeadPortalLinks(String htmlBody, Lead leadRecord) {
        if (String.isBlank(htmlBody) || leadRecord == null) {
            return htmlBody;
        }
        String portalUrl = buildLeadPortalLink(leadRecord);
        if (String.isBlank(portalUrl)) {
            return htmlBody;
        }

        String encodedUrl = portalUrl.escapeHtml4();
        String repaired = htmlBody;
        repaired = repaired.replace('href=""', 'href="' + encodedUrl + '"');
        repaired = repaired.replace('href=" "', 'href="' + encodedUrl + '"');
        repaired = repaired.replace('href="null"', 'href="' + encodedUrl + '"');
        repaired = repaired.replace(LEAD_PORTAL_LINK_PLACEHOLDER, encodedUrl);
        return repaired;
    }

    private static Messaging.SingleEmailMessage renderTemplate(
        Lead leadRecord,
        List<Lead_Document_Request__c> requestRecords,
        String templateDeveloperName
    ) {
        String resolvedTemplateDeveloperName = String.isBlank(templateDeveloperName)
            ? EMAIL_TEMPLATE_DEVELOPER_NAME
            : templateDeveloperName;
        EmailTemplate template = LeadDocumentRequestRepository.getInstance()
            .selectEmailTemplateByDeveloperName(resolvedTemplateDeveloperName);
        if (template == null) {
            return buildFallbackMessage(null, leadRecord, requestRecords);
        }

        try {
            Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
                template.Id,
                leadRecord.Id,
                null
            );
            String renderedHtmlBody = rendered.getHtmlBody();
            if (String.isBlank(renderedHtmlBody)) {
                return buildFallbackMessage(template.Subject, leadRecord, requestRecords);
            }
            rendered.setHtmlBody(prepareRenderedHtmlBody(renderedHtmlBody, leadRecord, requestRecords));
            return rendered;
        } catch (Exception renderException) {
            return buildFallbackMessage(template.Subject, leadRecord, requestRecords);
        }
    }

    private static Messaging.SingleEmailMessage buildFallbackMessage(
        String templateSubject,
        Lead leadRecord,
        List<Lead_Document_Request__c> requestRecords
    ) {
        Messaging.SingleEmailMessage fallback = new Messaging.SingleEmailMessage();
        fallback.setSubject(String.isBlank(templateSubject) ? 'Documents Needed' : templateSubject);
        fallback.setHtmlBody(buildFallbackHtmlBody(leadRecord, requestRecords));
        return fallback;
    }

    private static Lead_Document_Request__c buildRequestFromReference(
        Id leadId,
        Lead_Document_Request_Reference__c referenceRecord,
        String requestType,
        String assignment
    ) {
        String resolvedItemDescription = resolveReferenceItemDescription(referenceRecord);
        String resolvedCategoryName = resolveReferenceConditionName(referenceRecord, resolvedItemDescription);
        Lead_Document_Request__c requestRecord = new Lead_Document_Request__c(
            Lead__c = leadId,
            Name = resolvedCategoryName,
            Subject__c = resolvedItemDescription,
            Status__c = DEFAULT_STATUS,
            Description__c = resolvedItemDescription,
            Category__c = resolveRuntimePicklistValue(
                Lead_Document_Request__c.Category__c,
                referenceRecord.Category__c
            ),
            Type__c = resolveRuntimePicklistValue(
                Lead_Document_Request__c.Type__c,
                String.isBlank(requestType) ? 'Loan Officer' : requestType
            ),
            Include_In_Email__c = referenceRecord.Include_In_Email__c,
            Can_Borrower_See__c = referenceRecord.Can_Borrower_See__c,
            Lead_Document_Request_Reference__c = referenceRecord.Id
        );
        applyAssignment(requestRecord, assignment);
        return requestRecord;
    }

    private static String resolveReferenceRequestName(Lead_Document_Request_Reference__c referenceRecord) {
        if (referenceRecord == null) {
            return 'Document Request';
        }
        String label = referenceRecord.Borrower_Label__c;
        if (new Set<String>{ 'ID', 'Income', 'Assets', 'Gift Letter', 'WVOE' }.contains(label)
            && String.isNotBlank(referenceRecord.Borrower_Description__c)) {
            return referenceRecord.Borrower_Description__c;
        }
        return String.isNotBlank(label) ? label : 'Document Request';
    }

    private static String resolveReferenceItemDescription(Lead_Document_Request_Reference__c referenceRecord) {
        String resolvedName = resolveReferenceRequestName(referenceRecord);
        if (referenceRecord == null || referenceRecord.Package__c != 'Special Income Types') {
            return resolvedName;
        }
        if (String.isBlank(referenceRecord.Borrower_Label__c) || String.isBlank(referenceRecord.Borrower_Description__c)) {
            return resolvedName;
        }
        return referenceRecord.Borrower_Label__c + ' - ' + formatChecklistText(referenceRecord.Borrower_Description__c);
    }

    private static String formatChecklistText(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.replace('\r\n', '\n')
            .replace('\r', '\n')
            .replace('\n- ', ', ')
            .replace('\n', ', ')
            .replace('- ', '')
            .trim();
    }

    private static String resolveReferenceConditionName(
        Lead_Document_Request_Reference__c referenceRecord,
        String resolvedItemDescription
    ) {
        if (referenceRecord == null) {
            return 'Condition';
        }
        String category = referenceRecord.Category__c;
        String label = referenceRecord.Borrower_Label__c;
        if (category == 'Credit' || category == 'ID' || label == 'ID' || isIdentificationItem(resolvedItemDescription)) {
            return 'Identification';
        }
        if (category == 'Asset' || category == 'Assets' || category == 'Gift Letter' || label == 'Assets' || label == 'Gift Letter') {
            return 'Asset';
        }
        if (category == 'Other' || category == 'REO') {
            return 'Other Items';
        }
        if (String.isNotBlank(category)) {
            return resolveGroupingName(category);
        }
        return String.isNotBlank(label) ? label : 'Condition';
    }

    private static Boolean isIdentificationItem(String value) {
        String normalizedValue = String.isBlank(value) ? '' : value.toLowerCase();
        return normalizedValue.contains('photo id')
            || normalizedValue.contains('driver')
            || normalizedValue.contains('state id')
            || normalizedValue.contains('passport')
            || normalizedValue.contains('visa')
            || normalizedValue.contains('itin')
            || normalizedValue.contains('resident card')
            || normalizedValue.contains('employment authorization');
    }

    private static String resolveRuntimePicklistValue(Schema.SObjectField fieldToken, String requestedValue) {
        if (String.isBlank(requestedValue)) {
            return null;
        }
        Schema.DescribeFieldResult describeResult = fieldToken.getDescribe();
        if (!describeResult.isRestrictedPicklist()) {
            return requestedValue;
        }
        for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == requestedValue) {
                return requestedValue;
            }
        }
        return null;
    }

    private static void assertSaveSucceeded(Database.SaveResult[] saveResults, String operation) {
        List<String> errorMessages = new List<String>();
        for (Database.SaveResult saveResult : saveResults) {
            if (saveResult.isSuccess()) {
                continue;
            }
            for (Database.Error error : saveResult.getErrors()) {
                errorMessages.add(error.getMessage());
            }
        }

        if (!errorMessages.isEmpty()) {
            throw new LeadDocumentRequestException(
                'Unable to ' + operation + ': ' + String.join(errorMessages, '; ')
            );
        }
    }

    private static String buildFallbackHtmlBody(Lead leadRecord, List<Lead_Document_Request__c> requestRecords) {
        String borrowerName = String.isBlank(leadRecord.FirstName) ? 'there' : leadRecord.FirstName.escapeHtml4();
        String body = '<p>Hi ' + borrowerName + ',</p>' +
            '<p>To keep your loan moving, we would like to begin collecting a few documents while your file is still in the lead stage.</p>' +
            '<p>Please upload any requested documentation to this secure portal.</p>' +
            buildRequestedDocumentListHtml(requestRecords);
        body += '<p><a href="' + buildLeadPortalLink(leadRecord).escapeHtml4() +
            '">Upload Files</a></p>' +
            '<p>Please remember that I am here to assist you every step of the way. If you need help gathering any documents or have questions, please reply to this email.</p>' +
            '<p>All the best,</p>';
        return body;
    }

    // Linked to BOTH the request and the Lead. The request link ties the file to the condition and
    // is removed when an item is sent back; the Lead link is what the Documents tab actually reads,
    // since it queries links on the Lead itself. Without it an uploaded file never appeared there,
    // and a rejected one lost its only link and was orphaned outright.
    private static void associateContentVersions(Set<Id> contentVersionIds, Id requestId, Id leadId) {
        List<ContentVersion> versions = LeadDocumentRequestRepository.getInstance()
            .selectContentVersionsByLatestIds(contentVersionIds);
        Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>(versions);

        Set<Id> targetEntityIds = new Set<Id>{ requestId };
        if (leadId != null) {
            targetEntityIds.add(leadId);
        }

        Set<String> existingLinkKeys = new Set<String>();
        for (ContentDocumentLink existingLink : LeadDocumentRequestRepository.getInstance()
            .selectDocumentLinksByEntityIds(targetEntityIds)) {
            existingLinkKeys.add(existingLink.LinkedEntityId + ':' + existingLink.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (Id contentVersionId : contentVersionIds) {
            ContentVersion version = versionsById.get(contentVersionId);
            if (version == null) {
                continue;
            }
            for (Id targetEntityId : targetEntityIds) {
                if (existingLinkKeys.contains(targetEntityId + ':' + version.ContentDocumentId)) {
                    continue;
                }
                linksToInsert.add(new ContentDocumentLink(
                    ContentDocumentId = version.ContentDocumentId,
                    LinkedEntityId = targetEntityId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }
        }

        if (!linksToInsert.isEmpty()) {
            Database.insert(linksToInsert, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void updateContentVersions(Set<Id> contentVersionIds, String folderName, Id requestId) {
        List<ContentVersion> versionsToUpdate = new List<ContentVersion>();
        for (Id contentVersionId : contentVersionIds) {
            ContentVersion versionRecord = new ContentVersion(
                Id = contentVersionId,
                // A blank folder is meaningful here: the document is waiting on a decision.
                Folder__c = folderName,
                Lead_Document_Request__c = requestId
            );
            if (Schema.SObjectType.ContentVersion.fields.getMap().containsKey(REVIEW_STATUS_FIELD)) {
                versionRecord.put(REVIEW_STATUS_FIELD, REVIEW_PENDING);
            }
            versionsToUpdate.add(versionRecord);
        }

        if (!versionsToUpdate.isEmpty()) {
            new BorrowerFileWriter().updateVersions(versionsToUpdate, false);
        }
    }

    private static void updateLatestContentVersionReviewStatus(
        Id contentDocumentId,
        String reviewStatus,
        String folder,
        Id requestId
    ) {
        if (contentDocumentId == null) {
            return;
        }

        List<ContentVersion> latestVersions = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = TRUE
            WITH SYSTEM_MODE
        ];
        if (latestVersions.isEmpty()) {
            return;
        }

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.ContentVersion.fields.getMap();
        List<ContentVersion> versionsToUpdate = new List<ContentVersion>();
        for (ContentVersion latestVersion : latestVersions) {
            ContentVersion versionUpdate = new ContentVersion(Id = latestVersion.Id);
            if (fields.containsKey(REVIEW_STATUS_FIELD)) {
                versionUpdate.put(REVIEW_STATUS_FIELD, reviewStatus);
            }
            if (String.isNotBlank(folder) && fields.containsKey('Folder__c')) {
                versionUpdate.Folder__c = folder;
            }
            if (fields.containsKey('Lead_Document_Request__c')) {
                versionUpdate.Lead_Document_Request__c = requestId;
            }
            versionsToUpdate.add(versionUpdate);
        }
        new BorrowerFileWriter().updateVersions(versionsToUpdate, true);
    }

    /**
     * Writes to borrower-uploaded files.
     *
     * Files arriving through the borrower portal are created by the site guest user and owned by
     * the integration user, so no Loan Officer or Loan Partner has edit access to them. Reviewing
     * one is the job this component exists for, and callers have already checked the running user
     * is the Owner or Loan Partner on the Lead, so these writes run without sharing.
     * AccessLevel.SYSTEM_MODE alone is not enough: it waives field and object permissions but
     * leaves record-level sharing in place, and sharing is what refuses the update.
     */
    private without sharing class BorrowerFileWriter {
        private void updateVersions(List<ContentVersion> versionsToUpdate, Boolean allOrNone) {
            if (versionsToUpdate == null || versionsToUpdate.isEmpty()) {
                return;
            }
            Database.update(versionsToUpdate, allOrNone, AccessLevel.SYSTEM_MODE);
        }

        private void removeLink(Id requestId, Id contentDocumentId) {
            List<ContentDocumentLink> linksToDelete = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :requestId
                AND ContentDocumentId = :contentDocumentId
                WITH SYSTEM_MODE
            ];
            if (!linksToDelete.isEmpty()) {
                Database.delete(linksToDelete, true, AccessLevel.SYSTEM_MODE);
            }
        }
    }

    private static Integer countPendingDocuments(Id requestId) {
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : LeadDocumentRequestRepository.getInstance()
            .selectDocumentLinksByEntityIds(new Set<Id>{ requestId })) {
            contentDocumentIds.add(link.ContentDocumentId);
        }
        if (contentDocumentIds.isEmpty()) {
            return 0;
        }

        if (!Schema.SObjectType.ContentVersion.fields.getMap().containsKey(REVIEW_STATUS_FIELD)) {
            return 0;
        }

        String query =
            'SELECT Id, ' +
            REVIEW_STATUS_FIELD +
            ' FROM ContentVersion WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = TRUE WITH SYSTEM_MODE';
        Integer pendingCount = 0;
        for (SObject latestVersion : Database.query(query)) {
            String status = (String) latestVersion.get(REVIEW_STATUS_FIELD);
            if (String.isBlank(status) || status == REVIEW_PENDING) {
                pendingCount++;
            }
        }
        return pendingCount;
    }

    private static void removeDocumentLink(Id requestId, Id contentDocumentId) {
        new BorrowerFileWriter().removeLink(requestId, contentDocumentId);
    }

    private static String prepareRenderedHtmlBody(
        String htmlBody,
        Lead leadRecord,
        List<Lead_Document_Request__c> requestRecords
    ) {
        String bodyWithPortalLink = addLeadPortalLink(htmlBody, leadRecord);
        // The same token the per-borrower path fills, so a template works on either path.
        String bodyWithName = applyBorrowerFirstName(bodyWithPortalLink, leadRecord.FirstName);
        String bodyWithDocuments = addRequestedDocumentList(bodyWithName, requestRecords);
        return addSenderSignature(bodyWithDocuments);
    }

    /**
     * Same as prepareRenderedHtmlBody but with an explicit portal link, so a co-borrower's template
     * carries their own link and their own item list rather than the primary's.
     */
    private static String prepareRenderedHtmlBodyFor(
        String htmlBody,
        String portalLink,
        List<Lead_Document_Request__c> requestRecords,
        BorrowerSendTarget target
    ) {
        String body = htmlBody;
        if (body.contains(LEAD_PORTAL_LINK_PLACEHOLDER) && String.isNotBlank(portalLink)) {
            body = body.replace(LEAD_PORTAL_LINK_PLACEHOLDER, portalLink.escapeHtml4());
        }
        body = applyBorrowerFirstName(body, firstNameOf(target));
        return addSenderSignature(addRequestedDocumentList(body, requestRecords));
    }

    /** First word of the borrower's name, which is what a greeting wants. */
    private static String firstNameOf(BorrowerSendTarget target) {
        if (target == null || String.isBlank(target.name)) {
            return '';
        }
        return target.name.trim().split(' ')[0];
    }

    private static String applyBorrowerFirstName(String htmlBody, String firstName) {
        if (!htmlBody.contains(BORROWER_FIRST_NAME_PLACEHOLDER)) {
            return htmlBody;
        }
        return htmlBody.replace(BORROWER_FIRST_NAME_PLACEHOLDER, String.isBlank(firstName) ? 'there' : firstName);
    }

    private static String addLeadPortalLink(String htmlBody, Lead leadRecord) {
        if (!htmlBody.contains(LEAD_PORTAL_LINK_PLACEHOLDER)) {
            return htmlBody;
        }
        return htmlBody.replace(
            LEAD_PORTAL_LINK_PLACEHOLDER,
            buildLeadPortalLink(leadRecord).escapeHtml4()
        );
    }

    private static String addRequestedDocumentList(
        String htmlBody,
        List<Lead_Document_Request__c> requestRecords
    ) {
        String requestedDocumentsHtml = buildRequestedDocumentListHtml(requestRecords);
        if (htmlBody.contains(REQUESTED_DOCUMENT_LIST_PLACEHOLDER)) {
            return htmlBody.replace(REQUESTED_DOCUMENT_LIST_PLACEHOLDER, requestedDocumentsHtml);
        }
        Integer closingBodyIndex = htmlBody.toLowerCase().lastIndexOf('</body>');
        if (closingBodyIndex < 0) {
            return htmlBody + requestedDocumentsHtml;
        }
        return htmlBody.substring(0, closingBodyIndex) +
            requestedDocumentsHtml +
            htmlBody.substring(closingBodyIndex);
    }

    private static String addSenderSignature(String htmlBody) {
        String signature = buildSenderSignature();
        String updatedBody = htmlBody;
        Boolean replaced = false;
        // Both tokens are honored so existing templates keep working after the rename.
        if (updatedBody.contains(SENDER_SIGNATURE_PLACEHOLDER)) {
            updatedBody = updatedBody.replace(SENDER_SIGNATURE_PLACEHOLDER, signature);
            replaced = true;
        }
        if (updatedBody.contains(OWNER_SIGNATURE_PLACEHOLDER)) {
            updatedBody = updatedBody.replace(OWNER_SIGNATURE_PLACEHOLDER, signature);
            replaced = true;
        }
        // A double-brace placeholder is only literal text in a Visualforce template. In an HTML
        // template Salesforce parses it as a merge field and refuses to render, so those templates
        // carry no token and the signature is appended instead.
        if (!replaced && String.isNotBlank(signature)) {
            updatedBody += '<br/>' + signature;
        }
        return updatedBody;
    }

    // Accepts comma, semicolon, or whitespace separated addresses so senders can paste or type
    // extra recipients. Duplicates are collapsed and malformed entries are rejected up front.
    private static List<String> parseEmailAddressList(String rawValue, String fieldLabel) {
        List<String> parsedAddresses = new List<String>();
        if (String.isBlank(rawValue)) {
            return parsedAddresses;
        }
        Set<String> seenLowerCase = new Set<String>();
        for (String candidate : rawValue.split('[,;\\s]+')) {
            String trimmed = candidate == null ? '' : candidate.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            if (!Pattern.matches('^[^@\\s,;]+@[^@\\s,;]+\\.[^@\\s,;.]+$', trimmed)) {
                throw new LeadDocumentRequestException(
                    fieldLabel + ' contains an invalid email address: ' + trimmed
                );
            }
            if (seenLowerCase.add(trimmed.toLowerCase())) {
                parsedAddresses.add(trimmed);
            }
        }
        return parsedAddresses;
    }

    // Default CC is the Lead Owner plus the Loan Partner, minus whoever is sending. So the Owner
    // sending CCs the Loan Partner, the Loan Partner sending CCs the Owner, and anyone else
    // sending CCs both. Owner is listed first.
    private static List<String> buildDefaultCcAddresses(Lead leadRecord) {
        List<String> ccAddresses = new List<String>();
        if (leadRecord == null) {
            return ccAddresses;
        }
        Id senderId = UserInfo.getUserId();

        List<Id> orderedCandidateIds = new List<Id>();
        // A Lead can be owned by a queue, so only consider User owners.
        if (leadRecord.OwnerId != null
            && leadRecord.OwnerId.getSObjectType() == Schema.User.SObjectType
            && leadRecord.OwnerId != senderId) {
            orderedCandidateIds.add(leadRecord.OwnerId);
        }
        Id loanPartnerId = (Id) safeLeadValue(leadRecord, 'Loan_Partner__c');
        if (loanPartnerId != null && loanPartnerId != senderId && !orderedCandidateIds.contains(loanPartnerId)) {
            orderedCandidateIds.add(loanPartnerId);
        }
        if (orderedCandidateIds.isEmpty()) {
            return ccAddresses;
        }

        Map<Id, User> usersById = LeadDocumentRequestRepository.getInstance()
            .selectUsersByIds(new Set<Id>(orderedCandidateIds));
        Set<String> seenLowerCase = new Set<String>();
        for (Id candidateId : orderedCandidateIds) {
            User candidate = usersById.get(candidateId);
            if (candidate == null || String.isBlank(candidate.Email)) {
                continue;
            }
            if (seenLowerCase.add(candidate.Email.toLowerCase())) {
                ccAddresses.add(candidate.Email);
            }
        }
        return ccAddresses;
    }

    private static Object safeLeadValue(Lead leadRecord, String fieldApiName) {
        if (leadRecord == null) {
            return null;
        }
        try {
            return leadRecord.get(fieldApiName);
        } catch (SObjectException fieldNotQueried) {
            return null;
        }
    }

    // Signature follows the user sending the email (matching the From address), not the lead owner.
    // Card layout mirrors the Transaction Conditions component signature in LoanConditionController.
    private static String buildSenderSignature() {
        Id senderId = UserInfo.getUserId();
        User sender = LeadDocumentRequestRepository.getInstance()
            .selectUsersByIds(new Set<Id>{ senderId })
            .get(senderId);
        if (sender == null) {
            return '';
        }

        String displayName = sender.Name;
        if (String.isBlank(displayName)) {
            List<String> nameParts = new List<String>();
            if (String.isNotBlank(sender.FirstName)) {
                nameParts.add(sender.FirstName);
            }
            if (String.isNotBlank(sender.LastName)) {
                nameParts.add(sender.LastName);
            }
            displayName = String.join(nameParts, ' ');
        }
        if (String.isBlank(displayName)) {
            return '';
        }

        String photoUrl = htmlEncode(sender.Headshot_URL__c);
        String title = htmlEncode(sender.Title);
        String phone = htmlEncode(FormattingUtility.formatPhone(sender.Phone));
        String mobilePhone = htmlEncode(FormattingUtility.formatPhone(sender.MobilePhone));
        String fax = htmlEncode(FormattingUtility.formatPhone(sender.Fax));
        String email = htmlEncode(sender.Email);
        String nmls = htmlEncode(sender.NMLS__c);

        List<String> detailLines = new List<String>();
        if (String.isNotBlank(title)) {
            detailLines.add('<div style="font-size:13px;line-height:18px;color:#4b5563;">' + title + '</div>');
        }
        if (String.isNotBlank(phone)) {
            detailLines.add('<div style="font-size:13px;line-height:18px;color:#4b5563;">Direct: ' + phone + '</div>');
        } else if (String.isNotBlank(mobilePhone)) {
            detailLines.add('<div style="font-size:13px;line-height:18px;color:#4b5563;">Mobile: ' + mobilePhone + '</div>');
        }
        if (String.isNotBlank(email)) {
            detailLines.add('<div style="font-size:13px;line-height:18px;color:#4b5563;"><a href="mailto:' + email + '" style="color:#1a2541;text-decoration:none;">' + email + '</a></div>');
        }
        if (String.isNotBlank(fax)) {
            detailLines.add('<div style="font-size:13px;line-height:18px;color:#4b5563;">Fax: ' + fax + '</div>');
        }
        detailLines.add('<div style="font-size:13px;line-height:18px;color:#4b5563;">327 Plaza Real #215, Boca Raton, FL, 33432</div>');
        if (String.isNotBlank(nmls)) {
            detailLines.add('<div style="font-size:13px;line-height:18px;color:#4b5563;">NMLS #' + nmls + '</div>');
        }
        detailLines.add('<div style="font-size:13px;line-height:18px;color:#4b5563;">Company NMLS #2266637</div>');

        // Headshot_URL__c holds a public file.force.com delivery link, so it renders for external
        // borrowers. Senders without a headshot simply get the text-only card.
        String imageMarkup = String.isBlank(photoUrl)
            ? ''
            : '<td style="padding-right:14px;vertical-align:top;width:82px;">'
                + '<img src="' + photoUrl + '" alt="' + htmlEncode(displayName) + '" width="72" height="72" '
                + 'style="display:block;border-radius:50%;width:72px;height:72px;object-fit:cover;">'
                + '</td>';

        return '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="font-family:Arial,sans-serif;color:#1f2937;">'
            + '<tr>'
            + imageMarkup
            + '<td style="vertical-align:top;">'
            + '<div style="font-size:15px;line-height:20px;font-weight:bold;color:#1a2541;">' + htmlEncode(displayName) + '</div>'
            + String.join(detailLines, '')
            + '</td>'
            + '</tr>'
            + '</table>';
    }

    private static String htmlEncode(String value) {
        return String.isBlank(value) ? '' : value.escapeHtml4();
    }

    private static String buildRequestedDocumentListHtml(List<Lead_Document_Request__c> requestRecords) {
        String body = '<ul>';
        for (Lead_Document_Request__c requestRecord : requestRecords) {
            body += '<li><strong>' + requestRecord.Name.escapeHtml4() + '</strong>';
            if (String.isNotBlank(requestRecord.Description__c)) {
                body += ' - ' + requestRecord.Description__c.escapeHtml4();
            }
            body += '</li>';
        }
        body += '</ul>';
        return body;
    }

    public static String getLeadPortalHash(Lead leadRecord) {
        if (leadRecord == null) {
            return null;
        }
        if (LeadDocumentRequestRepository.getInstance().hasLeadPortalHashField()) {
            return (String) leadRecord.get('Portal_Hash_Parameter__c');
        }
        return Test.isRunningTest() ? testLeadPortalHashesByLeadId.get(leadRecord.Id) : null;
    }

    /** A borrower and the portal link they can be sent, for the pills in the conditions modal. */
    public class BorrowerPortalLink {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String link;
        @AuraEnabled public Boolean isPrimary;

        public BorrowerPortalLink(String value, String label, String link, Boolean isPrimary) {
            this.value = value;
            this.label = label;
            this.link = link;
            this.isPrimary = isPrimary;
        }
    }

    /**
     * Links for everyone on the file who can have a portal. Minting and revoking happen here rather
     * than in a trigger: the panel writes Borrower__c through the UI API, so this is the first Apex
     * that sees the change, and it mirrors populateMissingPortalHashes for Leads.
     *
     * An email is what makes someone a portal participant, so a borrower who gains one gets a token
     * and a borrower who loses one has theirs cleared, which kills their existing link.
     */
    @AuraEnabled
    public static List<BorrowerPortalLink> getBorrowerPortalLinks(Id leadId) {
        List<BorrowerPortalLink> links = new List<BorrowerPortalLink>();
        if (leadId == null) {
            return links;
        }

        Lead leadRecord = getLeadOrThrow(leadId);
        if (String.isNotBlank(leadRecord.Email)) {
            ensurePortalHash(leadId);
            leadRecord = getLeadOrThrow(leadId);
            String primaryName = (String.isBlank(leadRecord.FirstName) ? '' : leadRecord.FirstName + ' ') +
                (String.isBlank(leadRecord.LastName) ? '' : leadRecord.LastName);
            links.add(
                new BorrowerPortalLink(
                    ASSIGNMENT_PRIMARY,
                    String.isBlank(primaryName.trim()) ? 'Primary Borrower' : primaryName.trim(),
                    buildLeadPortalLink(leadRecord),
                    true
                )
            );
        }

        List<Borrower__c> rows = [
            SELECT Id, Name, Email__c, Portal_Hash_Parameter__c
            FROM Borrower__c
            WHERE Lead__c = :leadId AND Removed__c = FALSE
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ];
        List<Borrower__c> toUpdate = new List<Borrower__c>();
        for (Borrower__c row : rows) {
            Boolean hasEmail = String.isNotBlank(row.Email__c);
            if (hasEmail && String.isBlank(row.Portal_Hash_Parameter__c)) {
                row.Portal_Hash_Parameter__c = BorrowerPortalEncryptionService.encryptString(String.valueOf(row.Id));
                toUpdate.add(row);
            } else if (!hasEmail && String.isNotBlank(row.Portal_Hash_Parameter__c)) {
                // Revoked: removing the email address takes the portal away with it.
                row.Portal_Hash_Parameter__c = null;
                toUpdate.add(row);
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
        }

        String configuredUrl = resolveLeadPortalPageUrl();
        for (Borrower__c row : rows) {
            if (String.isBlank(row.Portal_Hash_Parameter__c) || String.isBlank(configuredUrl)) {
                continue;
            }
            String separator = configuredUrl.contains('?') ? '&' : '?';
            links.add(
                new BorrowerPortalLink(
                    String.valueOf(row.Id),
                    row.Name,
                    configuredUrl + separator + 'id=' + EncodingUtil.urlEncode(row.Portal_Hash_Parameter__c, 'UTF-8'),
                    false
                )
            );
        }
        return links;
    }

    /**
     * The site setting stores the Experience Cloud root ending in /s, but the portal is a
     * Visualforce page, not an Experience Builder page. Lead_Portal_Link_As_URL__c does this
     * substitution declaratively for the primary; co-borrower links have to do the same or they
     * land on a path that is not the portal.
     */
    private static String resolveLeadPortalPageUrl() {
        String configuredUrl = getConfiguredLeadHomeUrl();
        if (String.isBlank(configuredUrl)) {
            return null;
        }
        String trimmed = configuredUrl.endsWith('/') ? configuredUrl.removeEnd('/') : configuredUrl;
        return trimmed.endsWith('/s')
            ? trimmed.removeEnd('/s') + '/apex/LeadBorrowerDocumentPortal'
            : trimmed;
    }

    public static String buildLeadPortalLink(Lead leadRecord) {
        if (leadRecord == null) {
            return '';
        }

        if (LeadDocumentRequestRepository.getInstance().hasLeadPortalLinkField()) {
            String formulaLink = (String) leadRecord.get('Lead_Portal_Link_As_URL__c');
            if (String.isNotBlank(formulaLink)) {
                return formulaLink;
            }
        }

        String portalHash = getLeadPortalHash(leadRecord);
        if (String.isBlank(portalHash)) {
            return '';
        }

        String configuredUrl = getConfiguredLeadHomeUrl();
        if (String.isBlank(configuredUrl)) {
            return '';
        }

        String separator = configuredUrl.contains('?') ? '&' : '?';
        return configuredUrl + separator + 'id=' + EncodingUtil.urlEncode(portalHash, 'UTF-8');
    }

    public static Id getTestLeadIdForPortalHash(String portalHash) {
        if (!Test.isRunningTest() || String.isBlank(portalHash)) {
            return null;
        }
        for (Id leadId : testLeadPortalHashesByLeadId.keySet()) {
            if (testLeadPortalHashesByLeadId.get(leadId) == portalHash) {
                return leadId;
            }
        }
        return null;
    }

    private static String getConfiguredLeadHomeUrl() {
        if (Test.isRunningTest() && testLeadHomeUrlOverride != null) {
            return testLeadHomeUrlOverride;
        }
        if (!BorrowerPortalSettings__c.SObjectType.getDescribe().fields.getMap().containsKey('Lead_Borrower_Home_Url__c')) {
            return null;
        }
        BorrowerPortalSettings__c defaults = BorrowerPortalSettings__c.getOrgDefaults();
        return defaults == null ? null : (String) defaults.get('Lead_Borrower_Home_Url__c');
    }

    private static void markIncludedRequestsAsRequested(List<Lead_Document_Request__c> requestRecords) {
        List<Lead_Document_Request__c> requestsToUpdate = new List<Lead_Document_Request__c>();
        for (Lead_Document_Request__c requestRecord : requestRecords) {
            if (requestRecord.Status__c == DEFAULT_STATUS) {
                requestsToUpdate.add(new Lead_Document_Request__c(
                    Id = requestRecord.Id,
                    Status__c = REQUESTED_STATUS,
                    Requested_Date__c = Date.today(),
                    Can_Borrower_See__c = true
                ));
            }
        }

        if (!requestsToUpdate.isEmpty()) {
            Database.update(requestsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
    }

    // Loan_Partner__c is queried conditionally (the repository omits it when the field is absent,
    // and always omits it under test), so reading it blindly throws on an unqueried field.
    private static Id resolveLoanPartnerId(Lead leadRecord) {
        if (leadRecord == null || !leadRecord.getPopulatedFieldsAsMap().containsKey('Loan_Partner__c')) {
            return null;
        }
        return (Id) leadRecord.get('Loan_Partner__c');
    }
}
