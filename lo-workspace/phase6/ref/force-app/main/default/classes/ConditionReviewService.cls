/**
 * Use-case service that owns the review-action mutations triggered from the
 * Pending Review Utility: rejection, document un-association, and moving a
 * document from one Condition to another.
 *
 * The reject path delegates downstream side-effects (status flip back to
 * Requested, file cleanup, borrower email) to the existing
 * `Remove_Documents_From_Conditions` record-triggered flow by writing the
 * same fields the existing Aura `ConditionsDocumentViewer` writes today.
 */
public without sharing class ConditionReviewService {

    public class ConditionReviewServiceException extends Exception {}
    private static final String REVIEW_STATUS_FIELD = 'Condition_Document_Review_Status__c';
    private static final String REVIEW_ACCEPTED = 'Accepted';
    private static final String REVIEW_REJECTED = 'Rejected';
    private static final String REVIEW_PENDING = 'Pending Review';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REQUESTED = 'Requested';
    private static final String STATUS_REVIEW = 'Review';

    public static void rejectCondition(
        Id conditionId,
        String rejectionReason,
        Boolean emailBorrower,
        List<Id> contentDocumentIdsToUnassociate
    ) {
        if (conditionId == null) {
            throw new ConditionReviewServiceException('A condition is required.');
        }
        requireConditionAccess(conditionId, null);

        Boolean shouldEmail = emailBorrower == true;
        if (shouldEmail && String.isBlank(rejectionReason)) {
            throw new ConditionReviewServiceException(
                'A rejection reason is required when emailing the borrower.'
            );
        }

        Condition__c conditionUpdate = new Condition__c(Id = conditionId);
        conditionUpdate.RemoveDocumentsFromCondition__c = true;
        conditionUpdate.Email_Reject_Note_To_Borrower__c = 'No';
        if (String.isNotBlank(rejectionReason)) {
            conditionUpdate.RejectionNotes__c = rejectionReason.trim();
        }

        update new List<Condition__c>{ conditionUpdate };

        if (contentDocumentIdsToUnassociate != null && !contentDocumentIdsToUnassociate.isEmpty()) {
            unassociateDocuments(conditionId, new Set<Id>(contentDocumentIdsToUnassociate));
        }

        if (shouldEmail) {
            sendBorrowerRejectionEmail(conditionId);
        }
    }

    public static void approveDocument(
        Id conditionId,
        Id contentDocumentId,
        Boolean approveConditionWhenNoPending
    ) {
        if (conditionId == null || contentDocumentId == null) {
            throw new ConditionReviewServiceException('A condition and document are required.');
        }
        requireConditionAccess(conditionId, contentDocumentId);

        updateLatestContentVersionStatus(contentDocumentId, REVIEW_ACCEPTED, null);

        Integer pendingDocumentCount = countPendingDocuments(conditionId);
        if (pendingDocumentCount == 0) {
            // Completing the last document review is the processor's explicit
            // acknowledgement of any borrower portal reply on this condition.
            // Without this, an approved condition remains in Pending Review
            // solely because its already-reviewed portal comment is still unread.
            if (approveConditionWhenNoPending != false) {
                markBorrowerCommentsRead(conditionId);
            }
            Database.update(
                new Condition__c(
                    Id = conditionId,
                    Status__c = approveConditionWhenNoPending == false ? STATUS_REQUESTED : STATUS_APPROVED
                ),
                true,
                AccessLevel.SYSTEM_MODE
            );
        } else {
            Database.update(
                new Condition__c(
                    Id = conditionId,
                    Status__c = STATUS_REVIEW
                ),
                true,
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    // Phase 1b: this service is without sharing and its controllers pass client Ids straight in.
    // The condition must be one the running user can open (Condition__c follows its Transaction),
    // and a named document must be one they can already read, so no file in the org can be
    // pulled onto a visible condition (which would expose it). Read, not edit, so every
    // reviewer who can open the loan today keeps working.
    private static void requireConditionAccess(Id conditionId, Id contentDocumentId) {
        RecordAccessGuard.requireRead(conditionId);
        if (contentDocumentId != null
            && [SELECT COUNT() FROM ContentDocument WHERE Id = :contentDocumentId WITH USER_MODE] == 0) {
            throw RecordAccessGuard.denied();
        }
    }

    private static void markBorrowerCommentsRead(Id conditionId) {
        List<Condition_Comment__c> commentsToMarkRead = new List<Condition_Comment__c>();
        for (Condition_Comment__c commentRecord : [
            SELECT Id
            FROM Condition_Comment__c
            WHERE Condition__c = :conditionId
              AND Portal_Comment__c = TRUE
              AND Read__c = FALSE
        ]) {
            commentsToMarkRead.add(new Condition_Comment__c(
                Id = commentRecord.Id,
                Read__c = TRUE
            ));
        }

        if (!commentsToMarkRead.isEmpty()) {
            Database.update(commentsToMarkRead, false, AccessLevel.SYSTEM_MODE);
        }
    }

    public static void rejectDocument(
        Id conditionId,
        Id contentDocumentId,
        String rejectionReason,
        Boolean emailBorrower,
        String updatedConditionDescription
    ) {
        if (conditionId == null || contentDocumentId == null) {
            throw new ConditionReviewServiceException('A condition and document are required.');
        }
        requireConditionAccess(conditionId, contentDocumentId);

        Boolean shouldEmail = emailBorrower == true;
        if (shouldEmail && String.isBlank(rejectionReason)) {
            throw new ConditionReviewServiceException(
                'A rejection reason is required when emailing the borrower.'
            );
        }

        updateLatestContentVersionStatus(contentDocumentId, REVIEW_REJECTED, 'Junk');
        unassociateDocuments(conditionId, new Set<Id>{ contentDocumentId });

        Condition__c conditionUpdate = new Condition__c(Id = conditionId);
        conditionUpdate.RemoveDocumentsFromCondition__c = false;
        conditionUpdate.Email_Reject_Note_To_Borrower__c = '';
        conditionUpdate.Status__c = countPendingDocuments(conditionId) > 0 ? STATUS_REVIEW : STATUS_REQUESTED;
        if (String.isNotBlank(rejectionReason)) {
            conditionUpdate.RejectionNotes__c = rejectionReason.trim();
        }
        if (String.isNotBlank(updatedConditionDescription)) {
            conditionUpdate.Description__c = updatedConditionDescription.trim();
        }
        Database.update(conditionUpdate, true, AccessLevel.SYSTEM_MODE);

        if (shouldEmail) {
            sendBorrowerRejectionEmail(conditionId);
        }
    }

    public static void unassociateDocuments(Id conditionId, Set<Id> contentDocumentIds) {
        if (conditionId == null) {
            throw new ConditionReviewServiceException('A condition is required.');
        }
        requireConditionAccess(conditionId, null);
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }

        List<ContentDocumentLink> linksToDelete = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :conditionId
              AND ContentDocumentId IN :contentDocumentIds
        ];

        if (!linksToDelete.isEmpty()) {
            delete linksToDelete;
        }
    }

    public static void moveDocumentToCondition(
        Id contentDocumentId,
        Id fromConditionId,
        Id toConditionId
    ) {
        if (contentDocumentId == null || fromConditionId == null || toConditionId == null) {
            throw new ConditionReviewServiceException(
                'A document, source condition, and target condition are required.'
            );
        }
        if (fromConditionId == toConditionId) {
            return;
        }
        requireConditionAccess(fromConditionId, contentDocumentId);
        RecordAccessGuard.requireRead(toConditionId);

        List<ContentDocumentLink> existingTargetLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
              AND LinkedEntityId = :toConditionId
            LIMIT 1
        ];
        if (existingTargetLinks.isEmpty()) {
            ContentDocumentLink newLink = new ContentDocumentLink(
                ContentDocumentId = contentDocumentId,
                LinkedEntityId = toConditionId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
            insert newLink;
        }

        List<ContentDocumentLink> sourceLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
              AND LinkedEntityId = :fromConditionId
        ];
        if (!sourceLinks.isEmpty()) {
            delete sourceLinks;
        }

        if (Schema.SObjectType.ContentVersion.fields.getMap().containsKey('Condition__c')) {
            List<ContentVersion> latestVersions = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                  AND IsLatest = TRUE
            ];
            for (ContentVersion version : latestVersions) {
                version.put('Condition__c', toConditionId);
            }
            if (!latestVersions.isEmpty()) {
                Database.update(latestVersions, false, AccessLevel.SYSTEM_MODE);
            }
        }
    }

    private static void updateLatestContentVersionStatus(
        Id contentDocumentId,
        String reviewStatus,
        String folder
    ) {
        List<ContentVersion> latestVersions = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
              AND IsLatest = TRUE
        ];

        if (latestVersions.isEmpty()) {
            return;
        }

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.ContentVersion.fields.getMap();
        for (ContentVersion version : latestVersions) {
            if (fields.containsKey(REVIEW_STATUS_FIELD)) {
                version.put(REVIEW_STATUS_FIELD, reviewStatus);
            }
            if (String.isNotBlank(folder) && fields.containsKey('Folder__c')) {
                version.put('Folder__c', folder);
            }
        }
        Database.update(latestVersions, true, AccessLevel.SYSTEM_MODE);
    }

    private static Integer countPendingDocuments(Id conditionId) {
        if (conditionId == null) {
            return 0;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :conditionId
        ];
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            documentIds.add(link.ContentDocumentId);
        }
        if (documentIds.isEmpty()) {
            return 0;
        }

        String query = 'SELECT Id';
        if (Schema.SObjectType.ContentVersion.fields.getMap().containsKey(REVIEW_STATUS_FIELD)) {
            query += ', ' + REVIEW_STATUS_FIELD;
        }
        query += ' FROM ContentVersion WHERE IsLatest = TRUE AND ContentDocumentId IN :documentIds';

        Integer pendingCount = 0;
        for (SObject row : Database.query(query)) {
            String status = Schema.SObjectType.ContentVersion.fields.getMap().containsKey(REVIEW_STATUS_FIELD)
                ? (String) row.get(REVIEW_STATUS_FIELD)
                : null;
            if (String.isBlank(status) || status == REVIEW_PENDING) {
                pendingCount++;
            }
        }
        return pendingCount;
    }

    private static void sendBorrowerRejectionEmail(Id conditionId) {
        List<Condition__c> conditions = [
            SELECT Id,
                Transaction__c,
                Transaction__r.Borrower_Email__c,
                Transaction__r.Portal_Link_As_URL__c,
                Transaction__r.Borrower_Name__r.PersonContactId
            FROM Condition__c
            WHERE Id = :conditionId
            LIMIT 1
        ];
        if (
            conditions.isEmpty()
            || conditions[0].Transaction__c == null
            || String.isBlank(conditions[0].Transaction__r?.Borrower_Email__c)
        ) {
            return;
        }
        Condition__c conditionRecord = conditions[0];

        List<Condition_Settings__c> settings = [
            SELECT Email_Rejection_Template_Name__c
            FROM Condition_Settings__c
            LIMIT 1
        ];
        if (settings.isEmpty() || String.isBlank(settings[0].Email_Rejection_Template_Name__c)) {
            return;
        }

        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :settings[0].Email_Rejection_Template_Name__c
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return;
        }

        ensureBorrowerPortalHash(conditionRecord.Transaction__c);

        Id recipientId = conditionRecord.Transaction__r.Borrower_Name__r?.PersonContactId;
        Messaging.SingleEmailMessage renderedTemplate = Messaging.renderStoredEmailTemplate(
            templates[0].Id,
            recipientId,
            conditionId
        );

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setReplyTo(UserInfo.getUserEmail());
        email.setToAddresses(new List<String>{ conditionRecord.Transaction__r.Borrower_Email__c });
        if (recipientId != null) {
            email.setTargetObjectId(recipientId);
            email.setTreatTargetObjectAsRecipient(false);
        }
        email.setSubject(renderedTemplate.getSubject());
        email.setHtmlBody(repairBorrowerPortalLinks(renderedTemplate.getHtmlBody(), conditionRecord.Transaction__c));
        email.setPlainTextBody(repairBorrowerPortalLinks(renderedTemplate.getPlainTextBody(), conditionRecord.Transaction__c));
        email.setWhatId(conditionRecord.Transaction__c);
        email.setSaveAsActivity(true);

        if (!Test.isRunningTest()) {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        }
    }

    private static void ensureBorrowerPortalHash(Id transactionId) {
        if (transactionId == null) {
            return;
        }
        try {
            BorrowerPortalService.populateMissingPortalHashes(new Set<Id>{ transactionId });
        } catch (Exception ex) {
            // A missing portal encryption key should not block the rejection workflow.
        }
    }

    @TestVisible
    private static String repairBorrowerPortalLinks(String body, Id transactionId) {
        if (String.isBlank(body) || transactionId == null) {
            return body;
        }

        List<Transaction__c> transactions = [
            SELECT Id, Portal_Link_As_URL__c
            FROM Transaction__c
            WHERE Id = :transactionId
            LIMIT 1
        ];
        if (transactions.isEmpty() || String.isBlank(transactions[0].Portal_Link_As_URL__c)) {
            return body;
        }

        String portalUrl = htmlEncode(transactions[0].Portal_Link_As_URL__c);
        String repairedBody = body;
        repairedBody = repairedBody.replace('href="https://reachhomeloans.my.site.com/documents"', 'href="' + portalUrl + '"');
        repairedBody = repairedBody.replace('href="https://reachhomeloans.my.site.com/documents/"', 'href="' + portalUrl + '"');
        repairedBody = repairedBody.replace('href=""', 'href="' + portalUrl + '"');
        repairedBody = repairedBody.replace('href=" "', 'href="' + portalUrl + '"');
        repairedBody = repairedBody.replace('href="null"', 'href="' + portalUrl + '"');
        repairedBody = repairedBody.replace('href="&quot;&quot;"', 'href="' + portalUrl + '"');
        return repairedBody;
    }

    private static String htmlEncode(String value) {
        return value == null ? '' : value.escapeHtml4();
    }
}