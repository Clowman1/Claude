public without sharing class LeadDocumentPortalService {
    private static final String REVIEW_STATUS = 'Review';
    private static final String ORG_WIDE_FROM_ADDRESS = 'reachus@reachhomeloans.com';
    private static final Set<String> FINISHED_STATUSES = new Set<String>{ 'Cleared', 'Approved', 'Completed' };

    public class LeadDocumentPortalException extends Exception {}

    public class PortalRequest {
        @AuraEnabled public Id id;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String description;
        @AuraEnabled public String notes;
        @AuraEnabled public Decimal fileCount;

        public PortalRequest(Lead_Document_Request__c requestRecord, Decimal linkedFileCount) {
            id = requestRecord.Id;
            parentId = requestRecord.Lead__c;
            name = requestRecord.Name;
            status = requestRecord.Status__c;
            description = requestRecord.Description__c;
            notes = requestRecord.Subject__c;
            fileCount = linkedFileCount == null ? 0 : linkedFileCount;
        }
    }

    // Finished items stay on the portal in a collapsed list so the borrower can see progress
    // rather than watching items silently disappear.
    public class PortalClearedRequest {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Datetime clearedDate;

        public PortalClearedRequest(Lead_Document_Request__c requestRecord) {
            id = requestRecord.Id;
            name = requestRecord.Name;
            clearedDate = requestRecord.LastModifiedDate;
        }
    }

    // One shape for every person shown on the portal, so the Loan Officer and the Loan Partner
    // render through the same card instead of the Owner getting a bespoke inline block.
    public class PortalContact {
        @AuraEnabled public String role;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String nmls;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String photoUrl;
    }

    public class PortalData {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String borrowerName;
        @AuraEnabled public Decimal approvedDocuments;
        @AuraEnabled public Decimal requestedDocuments;
        @AuraEnabled public Decimal outstandingDocuments;
        @AuraEnabled public Decimal pendingReviewDocuments;
        @AuraEnabled public String redirectUrl;
        @AuraEnabled public List<PortalRequest> requests;
        @AuraEnabled public List<PortalClearedRequest> clearedRequests;
        @AuraEnabled public List<PortalContact> contacts;
    }

    public static PortalData initializeData(String hashFromURL, Boolean isInSitePreview) {
        Lead leadRecord = isInSitePreview
            ? getPreviewLead()
            : LeadDocumentRequestRepository.getInstance().selectLeadByPortalHash(hashFromURL);
        if (leadRecord == null && Test.isRunningTest()) {
            Id testLeadId = LeadDocumentRequestService.getTestLeadIdForPortalHash(hashFromURL);
            if (testLeadId != null) {
                leadRecord = LeadDocumentRequestRepository.getInstance()
                    .selectLeadsByIds(new Set<Id>{ testLeadId }).get(testLeadId);
            }
        }

        if (leadRecord == null) {
            throw new LeadDocumentPortalException('Unable to locate a lead document portal record.');
        }

        PortalData response = new PortalData();
        response.recordId = leadRecord.Id;
        response.borrowerName = buildBorrowerName(leadRecord);
        response.requests = new List<PortalRequest>();
        response.clearedRequests = new List<PortalClearedRequest>();
        response.contacts = new List<PortalContact>();
        applyRequestCounts(response, new List<Lead_Document_Request__c>());

        if (leadRecord.Converted_Transaction_ID__c != null) {
            response.redirectUrl = buildConvertedTransactionRedirectUrl(leadRecord.Converted_Transaction_ID__c);
            return response;
        }

        List<Lead_Document_Request__c> visibleRequests =
            LeadDocumentRequestRepository.getInstance().selectVisibleByLeadId(leadRecord.Id);
        Map<Id, Decimal> fileCountsByRequestId = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Map<Id, Lead_Document_Request__c>(visibleRequests).keySet());

        applyRequestCounts(response, visibleRequests);
        for (Lead_Document_Request__c requestRecord : visibleRequests) {
            response.requests.add(new PortalRequest(requestRecord, fileCountsByRequestId.get(requestRecord.Id)));
        }

        for (Lead_Document_Request__c clearedRecord :
            LeadDocumentRequestRepository.getInstance().selectClearedByLeadId(leadRecord.Id)) {
            response.clearedRequests.add(new PortalClearedRequest(clearedRecord));
        }
        response.approvedDocuments = response.clearedRequests.size();

        response.contacts = buildContacts(leadRecord);

        return response;
    }

    // The Loan Officer is the Lead Owner and the Loan Partner comes from Loan_Partner__c.
    // Loan_Partner__c is stamped on every Lead insert and defaults to an integration user, so a
    // populated lookup is not proof of a real person: only show someone carrying an NMLS number
    // or a headshot, which every licensed member of staff has and no service account does.
    private static List<PortalContact> buildContacts(Lead leadRecord) {
        List<PortalContact> contacts = new List<PortalContact>();

        Id loanPartnerId = resolveLoanPartnerId(leadRecord);
        Set<Id> userIds = new Set<Id>();
        if (leadRecord.OwnerId != null && String.valueOf(leadRecord.OwnerId).startsWith('005')) {
            userIds.add(leadRecord.OwnerId);
        }
        if (loanPartnerId != null) {
            userIds.add(loanPartnerId);
        }
        if (userIds.isEmpty()) {
            return contacts;
        }

        Map<Id, User> usersById = LeadDocumentRequestRepository.getInstance().selectUsersByIds(userIds);

        PortalContact loanOfficer = buildContact(usersById.get(leadRecord.OwnerId), 'Loan Officer');
        if (loanOfficer != null) {
            contacts.add(loanOfficer);
        }
        if (loanPartnerId != null && loanPartnerId != leadRecord.OwnerId) {
            PortalContact loanPartner = buildContact(usersById.get(loanPartnerId), 'Loan Partner');
            if (loanPartner != null) {
                contacts.add(loanPartner);
            }
        }
        return contacts;
    }

    private static PortalContact buildContact(User userRecord, String role) {
        if (!isDisplayableContact(userRecord)) {
            return null;
        }

        PortalContact contact = new PortalContact();
        contact.role = role;
        contact.name = buildUserName(userRecord);
        contact.title = userRecord.Title;
        contact.nmls = userRecord.NMLS__c;
        contact.phone = String.isNotBlank(userRecord.MobilePhone) ? userRecord.MobilePhone : userRecord.Phone;
        contact.email = userRecord.Email;
        contact.photoUrl = userRecord.Headshot_URL__c;
        return contact;
    }

    @TestVisible
    private static Boolean isDisplayableContact(User userRecord) {
        if (userRecord == null || userRecord.IsActive != true) {
            return false;
        }
        if (String.isBlank(buildUserName(userRecord))) {
            return false;
        }
        return String.isNotBlank(userRecord.NMLS__c) || String.isNotBlank(userRecord.Headshot_URL__c);
    }

    // lightning-file-upload does not work for site guest users, which is why no borrower has ever
    // managed to upload a document through either portal. The borrower's browser sends the file as
    // base64 instead and it is written here, in system mode, so the upload never depends on the
    // guest user having record access to the Lead.
    // ponytail: single request per file, so heap caps the file size at MAX_UPLOAD_BYTES. Chunked
    // upload is the upgrade if borrowers start hitting the limit on bank statements.
    private static final Integer MAX_UPLOAD_BYTES = 3500000;

    public static PortalRequest uploadBorrowerDocument(
        String hashFromURL,
        Id requestId,
        String fileName,
        String base64Data
    ) {
        if (requestId == null) {
            throw new LeadDocumentPortalException('A document request is required for borrower document upload.');
        }
        if (String.isBlank(base64Data)) {
            throw new LeadDocumentPortalException('The file came through empty. Please try uploading it again.');
        }

        Lead leadRecord = getActivePortalLead(hashFromURL);
        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            throw new LeadDocumentPortalException('Unable to locate the document request for upload.');
        }
        if (requestRecord.Lead__c != leadRecord.Id) {
            throw new LeadDocumentPortalException('The document request does not belong to this lead portal session.');
        }

        Blob fileBody;
        try {
            fileBody = EncodingUtil.base64Decode(base64Data);
        } catch (Exception decodeException) {
            throw new LeadDocumentPortalException('That file could not be read. Please try a different file.');
        }
        if (fileBody.size() > MAX_UPLOAD_BYTES) {
            throw new LeadDocumentPortalException(
                'That file is larger than 3.5 MB. Please upload a smaller file, or send it to your loan team directly.'
            );
        }

        String safeFileName = String.isBlank(fileName) ? 'Borrower Upload' : fileName.trim();
        ContentVersion version = new ContentVersion(
            Title = safeFileName,
            PathOnClient = safeFileName,
            VersionData = fileBody,
            Folder__c = LeadDocumentRequestService.resolveFolderName(requestRecord.Category__c),
            Lead_Document_Request__c = requestId,
            Origin = 'H'
        );
        Database.insert(version, true, AccessLevel.SYSTEM_MODE);

        associateContentVersions(new Set<Id>{ version.Id }, requestId);

        if (requestRecord.Status__c != REVIEW_STATUS) {
            Database.update(
                new Lead_Document_Request__c(Id = requestId, Status__c = REVIEW_STATUS),
                true,
                AccessLevel.SYSTEM_MODE
            );
            requestRecord.Status__c = REVIEW_STATUS;
        }

        Decimal fileCount = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Set<Id>{ requestId }).get(requestId);
        return new PortalRequest(requestRecord, fileCount);
    }

    // Called once after a borrower's batch of files finishes, so selecting four documents sends one
    // email naming the request rather than four separate ones.
    public static void notifyLeadTeamOfCompletedUpload(String hashFromURL, Id requestId, Integer fileCount) {
        if (requestId == null || fileCount == null || fileCount <= 0) {
            return;
        }
        Lead leadRecord = getActivePortalLead(hashFromURL);
        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null || requestRecord.Lead__c != leadRecord.Id) {
            return;
        }
        notifyLeadTeamOfUpload(leadRecord, requestRecord, fileCount);
    }

    public static PortalRequest updateRequestOnFileUpload(List<Id> contentVersionIds, Id requestId, String hashFromURL) {
        if (requestId == null) {
            throw new LeadDocumentPortalException('A document request is required for borrower document upload.');
        }

        Set<Id> versionIds = contentVersionIds == null ? new Set<Id>() : new Set<Id>(contentVersionIds);
        if (versionIds.isEmpty()) {
            throw new LeadDocumentPortalException('At least one uploaded document is required.');
        }

        Lead leadRecord = getActivePortalLead(hashFromURL);
        Lead_Document_Request__c requestRecord = LeadDocumentRequestRepository.getInstance()
            .selectRequestForPortalUpload(requestId);
        if (requestRecord == null) {
            throw new LeadDocumentPortalException('Unable to locate the document request for upload.');
        }
        if (requestRecord.Lead__c != leadRecord.Id) {
            throw new LeadDocumentPortalException('The document request does not belong to this lead portal session.');
        }

        String folderName = LeadDocumentRequestService.resolveFolderName(requestRecord.Category__c);
        associateContentVersions(versionIds, requestId);
        updateContentVersions(versionIds, folderName, requestId);
        Database.update(
            new Lead_Document_Request__c(Id = requestId, Status__c = REVIEW_STATUS),
            true,
            AccessLevel.SYSTEM_MODE
        );

        requestRecord.Status__c = REVIEW_STATUS;
        notifyLeadTeamOfUpload(leadRecord, requestRecord, versionIds.size());

        Decimal fileCount = LeadDocumentRequestRepository.getInstance()
            .selectLinkedDocumentCountsByRequestIds(new Set<Id>{ requestId }).get(requestId);
        return new PortalRequest(requestRecord, fileCount);
    }

    private static Lead getPreviewLead() {
        return LeadDocumentRequestRepository.getInstance().selectFirstLeadWithPortalHash();
    }

    private static Lead getActivePortalLead(String hashFromURL) {
        Lead leadRecord = LeadDocumentRequestRepository.getInstance().selectLeadByPortalHash(hashFromURL);
        if (leadRecord == null && Test.isRunningTest()) {
            Id testLeadId = LeadDocumentRequestService.getTestLeadIdForPortalHash(hashFromURL);
            if (testLeadId != null) {
                leadRecord = LeadDocumentRequestRepository.getInstance()
                    .selectLeadsByIds(new Set<Id>{ testLeadId }).get(testLeadId);
            }
        }
        if (leadRecord == null) {
            throw new LeadDocumentPortalException('Unable to locate a lead document portal record.');
        }
        if (leadRecord.Converted_Transaction_ID__c != null) {
            throw new LeadDocumentPortalException('Lead document uploads are no longer accepted after conversion.');
        }
        return leadRecord;
    }

    private static String buildConvertedTransactionRedirectUrl(Id transactionId) {
        BorrowerPortalService.populateMissingPortalHashes(new Set<Id>{ transactionId });
        List<Transaction__c> transactions = LoanRepository.getInstance().selectTransactionsByIds(new Set<Id>{ transactionId });
        if (transactions.isEmpty()) {
            return null;
        }
        return BorrowerPortalLinkService.buildBorrowerHomeUrl(transactions[0].Portal_Hash_Parameter__c);
    }

    private static void associateContentVersions(Set<Id> contentVersionIds, Id requestId) {
        List<ContentVersion> versions = LeadDocumentRequestRepository.getInstance()
            .selectContentVersionsByLatestIds(contentVersionIds);
        Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>(versions);
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentVersion version : versions) {
            contentDocumentIds.add(version.ContentDocumentId);
        }

        Set<Id> existingDocumentIds = new Set<Id>();
        for (ContentDocumentLink existingLink : LeadDocumentRequestRepository.getInstance()
            .selectDocumentLinksByEntityIds(new Set<Id>{ requestId })) {
            existingDocumentIds.add(existingLink.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (Id contentVersionId : contentVersionIds) {
            ContentVersion version = versionsById.get(contentVersionId);
            if (version == null || existingDocumentIds.contains(version.ContentDocumentId)) {
                continue;
            }
            linksToInsert.add(new ContentDocumentLink(
                ContentDocumentId = version.ContentDocumentId,
                LinkedEntityId = requestId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        if (!linksToInsert.isEmpty()) {
            Database.insert(linksToInsert, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void updateContentVersions(Set<Id> contentVersionIds, String folderName, Id requestId) {
        List<ContentVersion> versionsToUpdate = new List<ContentVersion>();
        for (Id contentVersionId : contentVersionIds) {
            versionsToUpdate.add(new ContentVersion(
                Id = contentVersionId,
                Folder__c = folderName,
                Lead_Document_Request__c = requestId
            ));
        }

        if (!versionsToUpdate.isEmpty()) {
            Database.update(versionsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void applyRequestCounts(PortalData response, List<Lead_Document_Request__c> requestRecords) {
        response.approvedDocuments = 0;
        response.requestedDocuments = 0;
        response.outstandingDocuments = 0;
        response.pendingReviewDocuments = 0;
        for (Lead_Document_Request__c requestRecord : requestRecords) {
            if (FINISHED_STATUSES.contains(requestRecord.Status__c)) {
                response.approvedDocuments++;
            } else if (requestRecord.Status__c == REVIEW_STATUS) {
                response.pendingReviewDocuments++;
            } else if (requestRecord.Status__c == 'Requested') {
                response.requestedDocuments++;
            } else {
                response.outstandingDocuments++;
            }
        }
    }

    private static String buildBorrowerName(Lead leadRecord) {
        String fullName = ((leadRecord.FirstName == null ? '' : leadRecord.FirstName + ' ') +
            (leadRecord.LastName == null ? '' : leadRecord.LastName)).trim();
        return String.isBlank(fullName) ? leadRecord.Name : fullName;
    }

    private static String buildUserName(User userRecord) {
        if (userRecord == null) {
            return null;
        }
        String fullName = ((userRecord.FirstName == null ? '' : userRecord.FirstName + ' ') +
            (userRecord.LastName == null ? '' : userRecord.LastName)).trim();
        return String.isBlank(fullName) ? userRecord.Name : fullName;
    }

    // Both the Loan Officer and the Loan Partner are told about every borrower upload. One email
    // per upload action rather than per file, so selecting four documents does not send four
    // emails, and a second upload to a request already in Review still notifies.
    private static void notifyLeadTeamOfUpload(Lead leadRecord, Lead_Document_Request__c requestRecord, Integer fileCount) {
        List<String> recipients = collectLeadTeamEmails(leadRecord);
        if (recipients.isEmpty()) {
            return;
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(recipients);
        email.setSubject(
            leadRecord.Name + ' - Documents Uploaded - ' + Datetime.now().format('M/d/yyyy')
        );
        email.setHtmlBody(buildUploadNotificationBody(leadRecord, requestRecord, fileCount));
        email.setSaveAsActivity(false);

        Id orgWideEmailAddressId = LeadDocumentRequestRepository.getInstance()
            .selectOrgWideEmailAddressId(ORG_WIDE_FROM_ADDRESS);
        if (orgWideEmailAddressId != null) {
            email.setOrgWideEmailAddressId(orgWideEmailAddressId);
        }

        if (!Test.isRunningTest()) {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        }
    }

    private static List<String> collectLeadTeamEmails(Lead leadRecord) {
        Set<Id> userIds = new Set<Id>();
        if (leadRecord.OwnerId != null && String.valueOf(leadRecord.OwnerId).startsWith('005')) {
            userIds.add(leadRecord.OwnerId);
        }
        Id loanPartnerId = resolveLoanPartnerId(leadRecord);
        if (loanPartnerId != null) {
            userIds.add(loanPartnerId);
        }
        if (userIds.isEmpty()) {
            return new List<String>();
        }

        List<String> addresses = new List<String>();
        Set<String> seen = new Set<String>();
        for (User userRecord : LeadDocumentRequestRepository.getInstance().selectUsersByIds(userIds).values()) {
            if (userRecord.IsActive != true || String.isBlank(userRecord.Email)) {
                continue;
            }
            String normalized = userRecord.Email.toLowerCase();
            if (seen.add(normalized)) {
                addresses.add(userRecord.Email);
            }
        }
        return addresses;
    }

    // Matches the Lead Note Update email so the team gets one consistent house style: navy header,
    // orange rule, the detail in a panel, and a pill button back into Salesforce.
    @TestVisible
    private static String buildUploadNotificationBody(
        Lead leadRecord,
        Lead_Document_Request__c requestRecord,
        Integer fileCount
    ) {
        String leadUrl = URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/Lead/' + leadRecord.Id + '/view';
        Integer safeFileCount = fileCount == null ? 0 : fileCount;
        String fileLabel = safeFileCount == 1 ? '1 document' : String.valueOf(safeFileCount) + ' documents';
        // Subject__c carries the document the borrower was actually asked for; Name is the
        // grouping label, which on its own reads as "uploaded 1 document to Income".
        String documentName = String.isNotBlank(requestRecord.Subject__c)
            ? requestRecord.Subject__c
            : requestRecord.Name;
        String folderName = LeadDocumentRequestService.resolveFolderName(requestRecord.Category__c);

        return ''
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:14px;overflow:hidden;">'
            + '<tr><td style="background:#1c3155;padding:26px 30px;">'
            + '<div style="color:#ffa534;font-size:11px;font-weight:900;letter-spacing:1.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Reach Home Loans</div>'
            + '<div style="color:#ffffff;font-size:26px;font-weight:900;margin-top:8px;font-family:Arial,sans-serif;">Documents Uploaded</div>'
            + '</td></tr>'
            + '<tr><td style="padding:28px 30px 8px;">'
            + '<div style="color:#8290aa;font-size:11px;font-weight:900;letter-spacing:1.2px;text-transform:uppercase;font-family:Arial,sans-serif;">Lead</div>'
            + '<div style="color:#142342;font-size:22px;font-weight:900;margin-top:6px;font-family:Arial,sans-serif;">'
            + htmlEncode(leadRecord.Name) + '</div></td></tr>'
            + '<tr><td style="padding:20px 30px 0;">'
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#f7f9fc;border-left:4px solid #ffa534;border-radius:8px;">'
            + '<tr><td style="padding:20px 22px;">'
            + '<div style="color:#8290aa;font-size:11px;font-weight:900;letter-spacing:1.2px;text-transform:uppercase;font-family:Arial,sans-serif;margin-bottom:12px;">Waiting For Review</div>'
            + '<div style="color:#22314f;font-size:15px;line-height:1.65;font-family:Arial,sans-serif;">'
            + htmlEncode(buildBorrowerName(leadRecord)) + ' uploaded <strong>' + fileLabel + '</strong> for:</div>'
            + '<div style="color:#142342;font-size:17px;font-weight:800;line-height:1.5;margin-top:10px;font-family:Arial,sans-serif;">'
            + htmlEncode(documentName) + '</div>'
            + '</td></tr></table></td></tr>'
            + '<tr><td style="padding:18px 30px 0;">'
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">'
            + '<tr><td style="padding:6px 0;color:#8290aa;font-size:12px;font-weight:800;letter-spacing:0.6px;text-transform:uppercase;font-family:Arial,sans-serif;width:120px;">Borrower</td>'
            + '<td style="padding:6px 0;color:#142342;font-size:15px;font-weight:800;font-family:Arial,sans-serif;">'
            + htmlEncode(buildBorrowerName(leadRecord)) + '</td></tr>'
            + '<tr><td style="padding:6px 0;color:#8290aa;font-size:12px;font-weight:800;letter-spacing:0.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Filed Under</td>'
            + '<td style="padding:6px 0;color:#142342;font-size:15px;font-weight:800;font-family:Arial,sans-serif;">'
            + htmlEncode(folderName) + '</td></tr>'
            + '<tr><td style="padding:6px 0;color:#8290aa;font-size:12px;font-weight:800;letter-spacing:0.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Uploaded</td>'
            + '<td style="padding:6px 0;color:#142342;font-size:15px;font-weight:800;font-family:Arial,sans-serif;">'
            + Datetime.now().format('M/d/yyyy, h:mm a') + '</td></tr>'
            + '</table></td></tr>'
            + '<tr><td align="center" style="padding:28px 30px 30px;">'
            + '<a href="' + htmlEncode(leadUrl) + '" style="display:inline-block;background:#ff9824;color:#122242;font-size:15px;font-weight:900;font-family:Arial,sans-serif;text-decoration:none;padding:14px 34px;border-radius:999px;">Review in Salesforce</a>'
            + '</td></tr>'
            + '<tr><td style="background:#f4f6fa;padding:18px 30px;border-top:1px solid #e2e7f0;">'
            + '<div style="color:#77839c;font-size:12px;line-height:1.6;font-family:Arial,sans-serif;">'
            + 'You are receiving this because you are the Loan Officer or Loan Partner on this lead.'
            + '</div></td></tr></table>';
    }

    private static String htmlEncode(String value) {
        return String.isBlank(value) ? '' : value.escapeHtml4();
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
