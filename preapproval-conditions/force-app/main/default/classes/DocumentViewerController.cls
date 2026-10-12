// Phase 1b: stays without sharing (borrower uploads are owned by the integration user, see the
// notes below), but every write now checks the target record or file with RecordAccessGuard.
public without sharing class DocumentViewerController {
    // 3.5 MB, the same ceiling as the borrower upload path: base64 in and out of Apex is heap-bound.
    private static final Integer MAX_ROTATED_BYTES = 3500000;
    private static final Map<String, String> FILETYPE_TO_ICON_MAP = new Map<String, String>{
        'jpg' => 'doctype:image',
        'jpeg' => 'doctype:image',
        'png' => 'doctype:image',
        'pdf' => 'doctype:pdf',
        'doc' => 'doctype:word',
        'docx' => 'doctype:word',
        'csv' => 'doctype:csv',
        'xls' => 'doctype:excel',
        'xlsx' => 'doctype:excel',
        'txt' => 'doctype:txt'
    };

    @AuraEnabled
    public static List<DocumentWrapper> getDocs(Id recordId) {
        try {
            List<DocumentWrapper> wrappers = getWrappers(getFiles(recordId));
            applySortOrder(wrappers);
            return wrappers;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Read in SYSTEM_MODE on its own so the drag-and-drop position needs no FLS grant: a field
    // missing from WITH USER_MODE throws and would take the whole tab down for that user.
    private static void applySortOrder(List<DocumentWrapper> wrappers) {
        Set<Id> versionIds = new Set<Id>();
        for (DocumentWrapper wrapper : wrappers) {
            versionIds.add(wrapper.versionId);
        }
        Map<Id, ContentVersion> versions = new Map<Id, ContentVersion>([
            SELECT Id, Sort_Order__c FROM ContentVersion WHERE Id IN :versionIds WITH SYSTEM_MODE
        ]);
        for (DocumentWrapper wrapper : wrappers) {
            ContentVersion version = versions.get(wrapper.versionId);
            wrapper.sortOrder = version == null ? null : version.Sort_Order__c;
        }
    }

    /**
     * Saves a drag and drop on the Documents tab. orderedFileIds is the complete, final order of
     * the destination folder, so one call covers both reordering inside a folder and moving a file
     * into another one.
     *
     * The write is SYSTEM_MODE in this without-sharing class because borrower portal uploads are
     * owned by the integration user and no internal user can edit them otherwise. The USER_MODE
     * link query is the authorization check: only files the user can already see on this record
     * are touched.
     */
    @AuraEnabled
    public static void moveFiles(Id recordId, String folderName, List<Id> orderedFileIds) {
        if (recordId == null || String.isBlank(folderName) || orderedFileIds == null || orderedFileIds.isEmpty()) {
            throw new AuraHandledException('A record, a folder and at least one file are required.');
        }
        try {
            RecordAccessGuard.requireRead(recordId);
            Set<Id> filesOnRecord = getContentDocsIds(retrieveContentDocLinks(recordId));
            if (!filesOnRecord.containsAll(orderedFileIds)) {
                throw new AuraHandledException('One of those files is not on this record.');
            }
            Map<Id, ContentDocument> docs = new Map<Id, ContentDocument>(
                retrieveContentDocs(new Set<Id>(orderedFileIds))
            );
            List<ContentVersion> versions = new List<ContentVersion>();
            for (Integer i = 0; i < orderedFileIds.size(); i++) {
                ContentDocument doc = docs.get(orderedFileIds[i]);
                if (doc == null) {
                    continue;
                }
                versions.add(new ContentVersion(
                    Id = doc.LatestPublishedVersionId,
                    Folder__c = folderName,
                    Sort_Order__c = i
                ));
            }
            Database.update(versions, true, AccessLevel.SYSTEM_MODE);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public static List<ContentDocument> getFiles(Id recordId) {
        List<ContentDocumentLink> contentDocLinks = retrieveContentDocLinks(recordId);
        return retrieveContentDocs(getContentDocsIds(contentDocLinks));
    }

    public static List<ContentDocumentLink> retrieveContentDocLinks(Set<Id> recordIds) {
        return [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :recordIds
            WITH USER_MODE
        ];
    }

    private static List<ContentDocumentLink> retrieveContentDocLinks(Id recordId, String oldFolderName) {
        return [
            SELECT Id, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            AND ContentDocument.LatestPublishedVersion.Folder__c = :String.escapeSingleQuotes(oldFolderName)
            WITH USER_MODE
        ];
    }

    private static List<ContentDocumentLink> retrieveContentDocLinks(Id recordId) {
        return [
            SELECT Id, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            WITH USER_MODE
        ];
    }

    private static Set<Id> getContentDocsIds(List<ContentDocumentLink> contentDocLinks) {
        Set<Id> contentDocsIds = new Set<Id>();
        for (ContentDocumentLink link : contentDocLinks) {
            contentDocsIds.add(link.ContentDocumentId);
        }
        return contentDocsIds;
    }

    public static List<ContentDocument> retrieveContentDocs(Set<Id> contentDocsIds) {
        if (contentDocsIds.isEmpty()) {
            return new List<ContentDocument>();
        }
        return [
            SELECT Id, Title, FileExtension, CreatedDate, CreatedBy.Name, LatestPublishedVersionId,
                LatestPublishedVersion.Folder__c, LatestPublishedVersion.Condition__c,
                LatestPublishedVersion.Condition__r.Name
            FROM ContentDocument
            WHERE Id IN :contentDocsIds
            AND ContentDocument.FileExtension != 'snote'
            WITH USER_MODE
            ORDER BY LatestPublishedVersion.Condition__r.Name ASC
        ];
    }

    private static List<DocumentWrapper> getWrappers(List<ContentDocument> files) {
        List<DocumentWrapper> wrappers = new List<DocumentWrapper>();
        for (ContentDocument file : files) {
            String key = file.FileExtension == null ? null : file.FileExtension.toLowerCase();
            wrappers.add(new DocumentWrapper(file, FILETYPE_TO_ICON_MAP.get(key)));
        }
        return wrappers;
    }

    // The same viewer sits on the Transaction and on the Lead. On a Transaction the targets are
    // Conditions; at pre-approval they are Lead document requests. Both expose Id and Name, which
    // is all the picker reads, so one method serves both.
    @AuraEnabled
    public static List<SObject> getLoanConditions(Id recordId) {
        try {
            if (recordId != null && recordId.getSObjectType() == Lead.SObjectType) {
                return [
                    SELECT Id, Name
                    FROM Lead_Document_Request__c
                    WHERE Lead__c = :recordId
                    WITH USER_MODE
                    ORDER BY Name
                ];
            }
            return [
                SELECT Id, Name
                FROM Condition__c
                WHERE Transaction__c = :recordId
                WITH USER_MODE
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id deleteFile(Id fileId) {
        try {
            Database.delete(new ContentDocument(Id = fileId), true, AccessLevel.USER_MODE);
            return fileId;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void renameFolder(Id recordId, String oldFolderName, String newFolderName) {
        try {
            RecordAccessGuard.requireRead(recordId);
            List<ContentDocumentLink> links = retrieveContentDocLinks(recordId, oldFolderName);
            List<ContentDocument> docs = retrieveContentDocs(getContentDocsIds(links));
            Database.update(assignNewFolderName(docs, newFolderName), false, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static List<ContentVersion> assignNewFolderName(List<ContentDocument> docs, String newFolderName) {
        List<ContentVersion> versionsWithNewFolderName = new List<ContentVersion>();
        for (ContentDocument doc : docs) {
            versionsWithNewFolderName.add(
                new ContentVersion(
                    Id = doc.LatestPublishedVersionId,
                    Folder__c = newFolderName
                )
            );
        }
        return versionsWithNewFolderName;
    }

    @AuraEnabled
    public static void changeFolder(Id recordId, Id fileId, String newFolderName) {
        try {
            // Phase 1b: the file must be on this record, and the record one the user can open.
            RecordAccessGuard.requireRead(recordId);
            if (!getContentDocsIds(retrieveContentDocLinks(recordId)).contains(fileId)) {
                throw RecordAccessGuard.denied();
            }
            List<ContentDocument> docs = retrieveContentDocs(new Set<Id>{ fileId });
            List<ContentVersion> versions = assignNewFolderName(docs, newFolderName);
            // Its old position means nothing in the new folder, so it goes to the end.
            for (ContentVersion version : versions) {
                version.Sort_Order__c = null;
            }
            Database.update(versions, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Finishes an upload made from the Documents tab: files the new version under the chosen
     * folder and, for a single file, renames it to the label the user typed.
     *
     * lightning-file-upload commits the file the moment it is dropped, so the folder and label
     * are applied straight afterwards rather than before the save.
     */
    @AuraEnabled
    public static void applyUploadDetails(List<Id> contentVersionIds, String folderName, String documentLabel) {
        try {
            if (contentVersionIds == null || contentVersionIds.isEmpty()) {
                return;
            }
            // Phase 1b: only versions the running user just uploaded, never an arbitrary Id.
            List<ContentVersion> versions = [
                SELECT Id, Title, PathOnClient
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
                AND CreatedById = :UserInfo.getUserId()
                WITH SYSTEM_MODE
            ];
            if (versions.isEmpty()) {
                return;
            }

            // A label only makes sense for one file; dropping five and naming them all the same
            // would lose which is which, so those keep their own filenames.
            Boolean renameToLabel = versions.size() == 1 && String.isNotBlank(documentLabel);
            for (ContentVersion version : versions) {
                if (String.isNotBlank(folderName)) {
                    version.Folder__c = folderName;
                }
                if (renameToLabel) {
                    version.Title = stripExtension(documentLabel.trim());
                }
            }
            Database.update(versions, true, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Viewers append the real FileExtension, so a label typed as "W2.pdf" would otherwise show
    // as "W2.pdf.pdf".
    @TestVisible
    private static String stripExtension(String label) {
        if (String.isBlank(label)) {
            return label;
        }
        Integer dot = label.lastIndexOf('.');
        if (dot <= 0 || label.length() - dot > 6) {
            return label;
        }
        return label.substring(0, dot);
    }

    @AuraEnabled
    public static void renameFile(Id fileId, String newFileName) {
        try {
            List<ContentDocument> documents = retrieveContentDocs(new Set<Id>{ fileId });
            if (documents.isEmpty()) {
                throw new AuraHandledException('File not found.');
            }
            requireFileOnVisibleRecord(fileId);

            // Rename via latest ContentVersion only; updating ContentDocument.Title often fails with
            // INSUFFICIENT_ACCESS_OR_READONLY for users who can edit the file via the version.
            Database.update(
                new ContentVersion(Id = documents[0].LatestPublishedVersionId, Title = newFileName),
                true,
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Saves a rotated copy of a document as a NEW version of the same ContentDocument, so every
     * ContentDocumentLink, the condition it belongs to, and the folder all survive the rotation.
     * Replacing the file instead would break the links and orphan it, which is exactly the failure
     * mode the Lead linking fix was written to stop.
     *
     * The rotation itself happens in the browser: canvas for images, pdf-lib for PDFs. Apex cannot
     * re-encode either format, so it only persists the bytes it is handed.
     */
    @AuraEnabled
    public static Id saveRotatedDocument(Id contentDocumentId, String base64Data, String fileName) {
        if (contentDocumentId == null || String.isBlank(base64Data)) {
            throw new AuraHandledException('A document and its rotated contents are required.');
        }

        try {
            List<ContentDocument> documents = retrieveContentDocs(new Set<Id>{ contentDocumentId });
            if (documents.isEmpty()) {
                throw new AuraHandledException('File not found.');
            }
            requireFileOnVisibleRecord(contentDocumentId);

            ContentVersion current = [
                SELECT Id, Title, PathOnClient, FileExtension, Folder__c, Sort_Order__c, Lead_Document_Request__c, Condition__c
                FROM ContentVersion
                WHERE Id = :documents[0].LatestPublishedVersionId
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            Blob rotatedBody;
            try {
                rotatedBody = EncodingUtil.base64Decode(base64Data);
            } catch (Exception decodeException) {
                throw new AuraHandledException('The rotated file could not be read. Please try again.');
            }
            if (rotatedBody.size() > MAX_ROTATED_BYTES) {
                throw new AuraHandledException(
                    'That file is too large to rotate and save here. Please rotate it before uploading.'
                );
            }

            ContentVersion rotated = new ContentVersion(
                // Setting ContentDocumentId adds a version rather than creating a separate file.
                ContentDocumentId = contentDocumentId,
                Title = current.Title,
                PathOnClient = String.isBlank(fileName) ? current.PathOnClient : fileName,
                VersionData = rotatedBody,
                Folder__c = current.Folder__c,
                Sort_Order__c = current.Sort_Order__c,
                Lead_Document_Request__c = current.Lead_Document_Request__c,
                Condition__c = current.Condition__c,
                ReasonForChange = 'Rotated by ' + UserInfo.getName()
            );
            Database.insert(rotated, true, AccessLevel.SYSTEM_MODE);
            return rotated.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Returns the current bytes so the browser can rotate them. Fetching the file over its download
     * URL fails inside a Lightning modal on some browsers, and this keeps the whole round trip in
     * one place regardless of where the modal is opened from.
     */
    @AuraEnabled
    public static DocumentContentDto getDocumentContent(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('A document is required.');
        }
        try {
            List<ContentDocument> documents = retrieveContentDocs(new Set<Id>{ contentDocumentId });
            if (documents.isEmpty()) {
                throw new AuraHandledException('File not found.');
            }

            ContentVersion current = [
                SELECT Id, Title, FileExtension, ContentSize, VersionData
                FROM ContentVersion
                WHERE Id = :documents[0].LatestPublishedVersionId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (current.ContentSize != null && current.ContentSize > MAX_ROTATED_BYTES) {
                throw new AuraHandledException(
                    'That file is too large to rotate here. Please rotate it before uploading.'
                );
            }

            DocumentContentDto dto = new DocumentContentDto();
            dto.contentVersionId = current.Id;
            dto.title = current.Title;
            dto.extension = current.FileExtension == null ? '' : current.FileExtension.toLowerCase();
            dto.base64Data = EncodingUtil.base64Encode(current.VersionData);
            return dto;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // The borrower portal uploads a long PDF as "Name (part 2 of 3)". Once merged back together
    // those parts are redundant; anything else that went into a merge is kept.
    private static final Pattern SPLIT_PART_TITLE = Pattern.compile('.*\\(part \\d+ of \\d+\\)$');
    private static final List<String> MERGE_SHARED_FIELDS = new List<String>{
        'Lead_Document_Request__c', 'Condition__c', 'Condition_Document_Review_Status__c'
    };

    /**
     * Files a PDF that was merged in the browser, then deletes the portal split parts it replaces.
     *
     * The merged file itself is saved by the DocumentMergeBridge page straight through the REST
     * API, because a merged statement is routinely bigger than the 3.5 MB this class can carry.
     * Only the filing happens here: the first source's folder and position, every record link any
     * source had (a Lead request counts its files through those links), and the request, condition
     * and review status when every source agrees on them.
     *
     * Returns how many parts were deleted. A part that cannot be deleted is left in place rather
     * than undoing a merge that has already been saved.
     */
    @AuraEnabled
    public static Integer finishMerge(Id recordId, Id mergedVersionId, List<Id> sourceDocumentIds) {
        if (recordId == null || mergedVersionId == null || sourceDocumentIds == null || sourceDocumentIds.isEmpty()) {
            throw new AuraHandledException('A record, the merged file and the files it came from are required.');
        }
        try {
            RecordAccessGuard.requireRead(recordId);
            // Only a file this user has just created, never an arbitrary version.
            List<ContentVersion> merged = [
                SELECT Id, ContentDocumentId FROM ContentVersion
                WHERE Id = :mergedVersionId AND CreatedById = :UserInfo.getUserId()
                WITH SYSTEM_MODE
            ];
            if (merged.isEmpty()) {
                throw RecordAccessGuard.denied();
            }
            Id mergedDocumentId = merged[0].ContentDocumentId;
            Set<Id> filesOnRecord = getContentDocsIds(retrieveContentDocLinks(recordId));
            if (!filesOnRecord.contains(mergedDocumentId) || !filesOnRecord.containsAll(sourceDocumentIds)) {
                throw new AuraHandledException('One of those files is not on this record.');
            }

            Map<Id, ContentVersion> sources = new Map<Id, ContentVersion>();
            for (ContentVersion version : [
                SELECT ContentDocumentId, Title, Folder__c, Sort_Order__c,
                    Lead_Document_Request__c, Condition__c, Condition_Document_Review_Status__c
                FROM ContentVersion
                WHERE ContentDocumentId IN :sourceDocumentIds AND IsLatest = TRUE
                WITH SYSTEM_MODE
            ]) {
                sources.put(version.ContentDocumentId, version);
            }
            ContentVersion first = sources.get(sourceDocumentIds[0]);
            ContentVersion filing = new ContentVersion(
                Id = mergedVersionId,
                Folder__c = first.Folder__c,
                Sort_Order__c = first.Sort_Order__c
            );
            for (String field : MERGE_SHARED_FIELDS) {
                Boolean everySourceAgrees = true;
                for (ContentVersion source : sources.values()) {
                    everySourceAgrees &= source.get(field) == first.get(field);
                }
                if (everySourceAgrees) {
                    filing.put(field, first.get(field));
                }
            }
            Database.update(filing, true, AccessLevel.SYSTEM_MODE);

            insertMergedLinks(mergedDocumentId, sourceDocumentIds);

            List<ContentDocument> parts = new List<ContentDocument>();
            for (ContentVersion source : sources.values()) {
                if (SPLIT_PART_TITLE.matcher(source.Title).matches()) {
                    parts.add(new ContentDocument(Id = source.ContentDocumentId));
                }
            }
            Integer deleted = 0;
            for (Database.DeleteResult result : Database.delete(parts, false, AccessLevel.SYSTEM_MODE)) {
                deleted += result.isSuccess() ? 1 : 0;
            }
            return deleted;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Users, groups and libraries are sharing, not filing, and the owner link is automatic.
    private static void insertMergedLinks(Id mergedDocumentId, List<Id> sourceDocumentIds) {
        Set<Id> linked = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId FROM ContentDocumentLink
            WHERE ContentDocumentId = :mergedDocumentId
            WITH SYSTEM_MODE
        ]) {
            linked.add(link.LinkedEntityId);
        }
        Set<Schema.SObjectType> notRecords = new Set<Schema.SObjectType>{
            User.SObjectType, Group.SObjectType, ContentWorkspace.SObjectType
        };
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ShareType, Visibility FROM ContentDocumentLink
            WHERE ContentDocumentId IN :sourceDocumentIds
            WITH SYSTEM_MODE
        ]) {
            if (linked.contains(link.LinkedEntityId) || notRecords.contains(link.LinkedEntityId.getSObjectType())) {
                continue;
            }
            linked.add(link.LinkedEntityId);
            links.add(new ContentDocumentLink(
                ContentDocumentId = mergedDocumentId,
                LinkedEntityId = link.LinkedEntityId,
                // Inferred is set by the platform only.
                ShareType = link.ShareType == 'I' ? 'V' : link.ShareType,
                Visibility = link.Visibility
            ));
        }
        Database.insert(links, true, AccessLevel.SYSTEM_MODE);
    }

    public class DocumentContentDto {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public String base64Data;
    }

    // Moving a document re-points it at another request or condition and re-derives the folder
    // from that target, so the file ends up filed where its new owner says it belongs. A folder
    // the user set by hand is respected: changeFolder writes Folder__c directly and this only
    // overwrites it when the move itself supplies a different destination.
    @AuraEnabled
    public static void relateFileToCondition(Id fileId, Id conditionId) {
        try {
            ContentDocument documentRecord = retrieveContentDocs(new Set<Id>{ fileId })[0];
            Set<Id> versionIds = new Set<Id>{ documentRecord.LatestPublishedVersionId };
            requireFileOnVisibleRecord(fileId);

            if (conditionId != null && conditionId.getSObjectType() == Lead_Document_Request__c.SObjectType) {
                Lead_Document_Request__c targetRequest = [
                    SELECT Id, Category__c, Lead__c
                    FROM Lead_Document_Request__c
                    WHERE Id = :conditionId
                    WITH USER_MODE
                    LIMIT 1
                ];
                // Phase 1b: requests are Public Read/Write, so check the Lead they belong to.
                RecordAccessGuard.requireRead(targetRequest.Lead__c);
                // SYSTEM_MODE, like the rest of this class: borrower uploads are owned by the
                // integration user, and USER_MODE enforces record sharing even here, so a Loan
                // Officer or Loan Partner filing one under the right condition would be refused.
                Database.update(
                    new ContentVersion(
                        Id = documentRecord.LatestPublishedVersionId,
                        Lead_Document_Request__c = targetRequest.Id,
                        Folder__c = LeadDocumentRequestService.resolveFolderName(targetRequest.Category__c)
                    ),
                    true,
                    AccessLevel.SYSTEM_MODE
                );
                Database.update(
                    new Lead_Document_Request__c(Id = targetRequest.Id, Status__c = 'Review'),
                    true,
                    AccessLevel.SYSTEM_MODE
                );
                return;
            }

            // Phase 1b: FileUploadHandler is without sharing, so the condition must be visible here.
            // A null condition is the viewer's "None" choice (unlink) and is left alone.
            if (conditionId != null) {
                RecordAccessGuard.requireRead(conditionId);
            }
            FileUploadHandler.updateContentVersions(versionIds, documentRecord.LatestPublishedVersion.Folder__c, conditionId);
            FileUploadHandler.setLoanConditionToReview(conditionId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + '. ' + e.getStackTraceString());
        }
    }

    // Phase 1b: the SYSTEM_MODE writes above exist so internal users can file borrower uploads
    // they can only read (owned by the integration user). A readable file is not enough on its
    // own, since files on Public Read/Write objects are readable by everyone: it must also sit
    // on a Lead, Account, Transaction or Condition the running user can open, or be their own.
    private static void requireFileOnVisibleRecord(Id contentDocumentId) {
        List<ContentDocument> docs = [
            SELECT OwnerId FROM ContentDocument WHERE Id = :contentDocumentId WITH SYSTEM_MODE LIMIT 1
        ];
        if (docs.isEmpty()) {
            throw RecordAccessGuard.denied();
        }
        if (docs[0].OwnerId == UserInfo.getUserId()) {
            return;
        }
        Set<Schema.SObjectType> parentTypes = new Set<Schema.SObjectType>{
            Lead.SObjectType, Account.SObjectType, Transaction__c.SObjectType, Condition__c.SObjectType
        };
        Set<Id> parentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            WITH SYSTEM_MODE
        ]) {
            if (parentTypes.contains(link.LinkedEntityId.getSObjectType())) {
                parentIds.add(link.LinkedEntityId);
            }
        }
        if (RecordAccessGuard.readable(parentIds).isEmpty()) {
            throw RecordAccessGuard.denied();
        }
    }

    public class DocumentWrapper {
        @AuraEnabled public Id id;
        // The thumbnail rendition is addressed by version, not by document.
        @AuraEnabled public Id versionId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileType;
        @AuraEnabled public String fileTypeIcon;
        @AuraEnabled public String folderName;
        @AuraEnabled public String conditionName;
        @AuraEnabled public Id conditionId;
        @AuraEnabled public String createdBy;
        @AuraEnabled public Datetime createdDate;
        // Drag-and-drop position inside the folder; null until someone reorders it.
        @AuraEnabled public Decimal sortOrder;

        public DocumentWrapper(ContentDocument file, String iconName) {
            id = file.Id;
            versionId = file.LatestPublishedVersionId;
            fileName = file.Title;
            fileType = file.FileExtension;
            fileTypeIcon = iconName;
            folderName = file.LatestPublishedVersion.Folder__c;
            conditionName = file.LatestPublishedVersion.Condition__r == null ? 'None' : file.LatestPublishedVersion.Condition__r.Name;
            conditionId = file.LatestPublishedVersion.Condition__c;
            createdBy = file.CreatedBy.Name;
            createdDate = file.CreatedDate;
        }
    }
}
