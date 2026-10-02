public with sharing class LeadDocumentCarryForwardService {
    public class CarryForwardException extends Exception {}
    @TestVisible private static Boolean forceExceptionForTest = false;

    private class ConvertedRequestContext {
        Lead leadRecord;
        Lead_Document_Request__c requestRecord;
        Condition__c conditionRecord;
    }

    public static void carryForward(Set<Id> leadIds) {
        if (Test.isRunningTest() && forceExceptionForTest) {
            throw new CarryForwardException('Forced carry-forward failure for test coverage.');
        }
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        Map<Id, Lead> leadsById = LeadDocumentRequestRepository.getInstance().selectLeadsByIds(leadIds);
        // Runs first and unconditionally: a Lead can have documents on it without a single
        // condition ever having been raised.
        carryForwardLeadFiles(leadsById);

        List<Lead_Document_Request__c> requestRecords =
            LeadDocumentRequestRepository.getInstance().selectUnconvertedByLeadIds(leadsById.keySet());
        if (requestRecords.isEmpty()) {
            return;
        }

        List<ConvertedRequestContext> contexts = new List<ConvertedRequestContext>();
        List<Condition__c> conditionsToInsert = new List<Condition__c>();
        for (Lead_Document_Request__c requestRecord : requestRecords) {
            Lead leadRecord = leadsById.get(requestRecord.Lead__c);
            if (leadRecord == null || leadRecord.Converted_Transaction_ID__c == null) {
                continue;
            }

            ConvertedRequestContext context = new ConvertedRequestContext();
            context.leadRecord = leadRecord;
            context.requestRecord = requestRecord;
            context.conditionRecord = buildConditionFromRequest(requestRecord, leadRecord.Converted_Transaction_ID__c);
            contexts.add(context);
            conditionsToInsert.add(context.conditionRecord);
        }

        if (contexts.isEmpty()) {
            return;
        }

        Database.SaveResult[] insertResults = Database.insert(conditionsToInsert, false, AccessLevel.SYSTEM_MODE);
        List<Lead_Document_Request__c> requestsToUpdate = new List<Lead_Document_Request__c>();
        Map<Id, ConvertedRequestContext> contextsByRequestId = new Map<Id, ConvertedRequestContext>();
        Set<Id> conditionIds = new Set<Id>();
        for (Integer i = 0; i < insertResults.size(); i++) {
            if (!insertResults[i].isSuccess()) {
                continue;
            }
            ConvertedRequestContext context = contexts[i];
            context.conditionRecord.Id = insertResults[i].getId();
            contextsByRequestId.put(context.requestRecord.Id, context);
            conditionIds.add(context.conditionRecord.Id);
            requestsToUpdate.add(new Lead_Document_Request__c(
                Id = context.requestRecord.Id,
                Converted_Condition__c = context.conditionRecord.Id
            ));
        }

        if (!requestsToUpdate.isEmpty()) {
            Database.update(requestsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }

        carryForwardFiles(contextsByRequestId, conditionIds);
        BorrowerPortalService.populateMissingPortalHashes(getConvertedTransactionIds(leadsById.values()));
    }

    // The Lead keeps a four-value category list named after the Documents-tab folders; the
    // Transaction keeps its own 22. Credit at pre-approval is almost always the photo ID, and
    // anything unmapped becomes Generic for Processing to recategorise.
    private static final Map<String, String> CONDITION_CATEGORY_BY_REQUEST_CATEGORY = new Map<String, String>{
        'Income' => 'Income',
        'Asset' => 'Assets',
        'Credit' => 'ID',
        'Other' => 'Generic'
    };

    private static Condition__c buildConditionFromRequest(Lead_Document_Request__c requestRecord, Id transactionId) {
        return new Condition__c(
            Transaction__c = transactionId,
            Name = requestRecord.Name,
            Status__c = requestRecord.Status__c,
            Description__c = requestRecord.Description__c,
            Subject__c = requestRecord.Subject__c,
            Category__c = resolveConditionPicklistValue(
                Condition__c.Category__c,
                resolveConditionCategory(requestRecord),
                'Generic'
            ),
            Type__c = resolveConditionPicklistValue(
                Condition__c.Type__c,
                requestRecord.Type__c,
                'Processor'
            ),
            Requested_Date__c = requestRecord.Requested_Date__c,
            Include_In_Email__c = requestRecord.Include_In_Email__c,
            Can_Borrower_See__c = requestRecord.Can_Borrower_See__c,
            Lead_Document_Request_Reference__c = requestRecord.Lead_Document_Request_Reference__c,
            Condition_Group_Key__c = requestRecord.Lead_Document_Request_Reference__r == null
                ? null
                : requestRecord.Lead_Document_Request_Reference__r.Condition_Group_Key__c,
            // The Borrower__c row survives conversion - it gains a Transaction__c stamp rather than
            // being recreated - so the assignment carries across unchanged.
            Borrower__c = requestRecord.Borrower__c,
            Assigned_To_Primary__c = requestRecord.Assigned_To_Primary__c
        );
    }

    /**
     * The Documents tab's own files - the ones added straight to the Lead rather than against a
     * condition.
     *
     * Lead conversion reparents those files to the new Person Account as part of the convert
     * itself, seconds before the Transaction exists, so nothing downstream can still find them on
     * the Lead. They are picked back up from the Account instead, bounded to documents created
     * after the Lead was: that keeps a repeat borrower's earlier loan out of the new file.
     */
    private static void carryForwardLeadFiles(Map<Id, Lead> leadsById) {
        Map<Id, Lead> leadsBySourceEntityId = new Map<Id, Lead>();
        Set<Id> transactionIds = new Set<Id>();
        for (Lead leadRecord : leadsById.values()) {
            if (leadRecord.Converted_Transaction_ID__c == null) {
                continue;
            }
            transactionIds.add(leadRecord.Converted_Transaction_ID__c);
            // The Lead first, in case this runs before the reparenting, and the Account after.
            leadsBySourceEntityId.put(leadRecord.Id, leadRecord);
            if (leadRecord.ConvertedAccountId != null) {
                leadsBySourceEntityId.put(leadRecord.ConvertedAccountId, leadRecord);
            }
        }
        if (leadsBySourceEntityId.isEmpty()) {
            return;
        }

        List<ContentDocumentLink> sourceLinks = LeadDocumentRequestRepository.getInstance()
            .selectDocumentLinksByEntityIds(leadsBySourceEntityId.keySet());
        if (sourceLinks.isEmpty()) {
            return;
        }

        Set<Id> candidateDocumentIds = new Set<Id>();
        for (ContentDocumentLink sourceLink : sourceLinks) {
            candidateDocumentIds.add(sourceLink.ContentDocumentId);
        }
        Map<Id, Datetime> createdDateByDocumentId = new Map<Id, Datetime>();
        for (ContentDocument document : [
            SELECT Id, CreatedDate FROM ContentDocument WHERE Id IN :candidateDocumentIds WITH SYSTEM_MODE
        ]) {
            createdDateByDocumentId.put(document.Id, document.CreatedDate);
        }

        Set<String> existingPairs = new Set<String>();
        for (ContentDocumentLink existingLink : LeadDocumentRequestRepository.getInstance()
            .selectDocumentLinksByEntityIds(transactionIds)) {
            existingPairs.add(existingLink.LinkedEntityId + ':' + existingLink.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (ContentDocumentLink sourceLink : sourceLinks) {
            Lead leadRecord = leadsBySourceEntityId.get(sourceLink.LinkedEntityId);
            if (leadRecord == null) {
                continue;
            }
            Datetime documentCreated = createdDateByDocumentId.get(sourceLink.ContentDocumentId);
            Boolean fromTheAccount = sourceLink.LinkedEntityId == leadRecord.ConvertedAccountId;
            if (fromTheAccount && (documentCreated == null || documentCreated < leadRecord.CreatedDate)) {
                continue;
            }
            addLinkIfMissing(
                linksToInsert,
                existingPairs,
                sourceLink.ContentDocumentId,
                leadRecord.Converted_Transaction_ID__c
            );
        }

        if (!linksToInsert.isEmpty()) {
            new FileLinker().insertLinks(linksToInsert);
        }
    }

    /**
     * Borrower uploads are owned by the portal guest user, and the Loan Officer doing the
     * conversion has no share on them. Sharing, not field access, is what blocks the link, so this
     * has to be a without-sharing class rather than a SYSTEM_MODE call.
     */
    private without sharing class FileLinker {
        private void insertLinks(List<ContentDocumentLink> links) {
            Database.insert(links, false, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * Name is the grouping label the Loan Officer and the borrower both see, and the catalogue
     * sets it independently of the four-value category. The two oldest ID entries in that
     * catalogue were filed under Other, which would land a photo ID in Generic rather than ID.
     * Those rows are corrected, but requests raised from them before that still exist.
     */
    private static String resolveConditionCategory(Lead_Document_Request__c requestRecord) {
        if ('Identification'.equalsIgnoreCase(requestRecord.Name)) {
            return 'ID';
        }
        return CONDITION_CATEGORY_BY_REQUEST_CATEGORY.get(requestRecord.Category__c);
    }

    private static String resolveConditionPicklistValue(
        Schema.SObjectField fieldToken,
        String requestedValue,
        String fallbackValue
    ) {
        String resolvedValue = String.isBlank(requestedValue) ? fallbackValue : requestedValue;
        Schema.DescribeFieldResult describeResult = fieldToken.getDescribe();
        if (!describeResult.isRestrictedPicklist()) {
            return resolvedValue;
        }
        for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == resolvedValue) {
                return resolvedValue;
            }
        }
        return fallbackValue;
    }

    private static void carryForwardFiles(Map<Id, ConvertedRequestContext> contextsByRequestId, Set<Id> conditionIds) {
        if (contextsByRequestId.isEmpty()) {
            return;
        }

        Set<Id> sourceRequestIds = contextsByRequestId.keySet();
        List<ContentDocumentLink> sourceLinks = LeadDocumentRequestRepository.getInstance()
            .selectDocumentLinksByEntityIds(sourceRequestIds);
        if (sourceLinks.isEmpty()) {
            return;
        }

        Set<Id> contentDocumentIds = new Set<Id>();
        Set<Id> targetEntityIds = new Set<Id>(conditionIds);
        for (ContentDocumentLink sourceLink : sourceLinks) {
            ConvertedRequestContext context = contextsByRequestId.get(sourceLink.LinkedEntityId);
            if (context == null || context.conditionRecord?.Id == null || context.leadRecord?.Converted_Transaction_ID__c == null) {
                continue;
            }
            contentDocumentIds.add(sourceLink.ContentDocumentId);
            targetEntityIds.add(context.leadRecord.Converted_Transaction_ID__c);
        }

        Set<String> existingPairs = new Set<String>();
        for (ContentDocumentLink existingLink : LeadDocumentRequestRepository.getInstance()
            .selectDocumentLinksByEntityIds(targetEntityIds)) {
            existingPairs.add(existingLink.LinkedEntityId + ':' + existingLink.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (ContentDocumentLink sourceLink : sourceLinks) {
            ConvertedRequestContext context = contextsByRequestId.get(sourceLink.LinkedEntityId);
            if (context == null || context.conditionRecord?.Id == null || context.leadRecord?.Converted_Transaction_ID__c == null) {
                continue;
            }
            addLinkIfMissing(linksToInsert, existingPairs, sourceLink.ContentDocumentId, context.conditionRecord.Id);
            addLinkIfMissing(linksToInsert, existingPairs, sourceLink.ContentDocumentId, context.leadRecord.Converted_Transaction_ID__c);
        }

        if (!linksToInsert.isEmpty()) {
            new FileLinker().insertLinks(linksToInsert);
        }

        stampContentVersions(contextsByRequestId, sourceLinks, contentDocumentIds);
    }

    private static void addLinkIfMissing(
        List<ContentDocumentLink> linksToInsert,
        Set<String> existingPairs,
        Id contentDocumentId,
        Id linkedEntityId
    ) {
        String key = linkedEntityId + ':' + contentDocumentId;
        if (existingPairs.contains(key)) {
            return;
        }
        existingPairs.add(key);
        linksToInsert.add(new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = linkedEntityId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        ));
    }

    private static void stampContentVersions(
        Map<Id, ConvertedRequestContext> contextsByRequestId,
        List<ContentDocumentLink> sourceLinks,
        Set<Id> contentDocumentIds
    ) {
        Map<Id, Set<Id>> conditionIdsByContentDocumentId = new Map<Id, Set<Id>>();
        for (ContentDocumentLink sourceLink : sourceLinks) {
            ConvertedRequestContext context = contextsByRequestId.get(sourceLink.LinkedEntityId);
            if (context == null || context.conditionRecord?.Id == null) {
                continue;
            }
            if (!conditionIdsByContentDocumentId.containsKey(sourceLink.ContentDocumentId)) {
                conditionIdsByContentDocumentId.put(sourceLink.ContentDocumentId, new Set<Id>());
            }
            conditionIdsByContentDocumentId.get(sourceLink.ContentDocumentId).add(context.conditionRecord.Id);
        }

        List<ContentVersion> versionsToUpdate = new List<ContentVersion>();
        for (ContentVersion version : LeadDocumentRequestRepository.getInstance()
            .selectLatestContentVersionsByDocumentIds(contentDocumentIds)) {
            Set<Id> conditionIdsForDocument = conditionIdsByContentDocumentId.get(version.ContentDocumentId);
            if (conditionIdsForDocument == null || conditionIdsForDocument.size() != 1) {
                continue;
            }
            Id conditionId = new List<Id>(conditionIdsForDocument)[0];
            versionsToUpdate.add(new ContentVersion(
                Id = version.Id,
                Condition__c = conditionId
            ));
        }

        if (!versionsToUpdate.isEmpty()) {
            Database.update(versionsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static Set<Id> getConvertedTransactionIds(List<Lead> leadRecords) {
        Set<Id> transactionIds = new Set<Id>();
        for (Lead leadRecord : leadRecords) {
            if (leadRecord.Converted_Transaction_ID__c != null) {
                transactionIds.add(leadRecord.Converted_Transaction_ID__c);
            }
        }
        return transactionIds;
    }
}