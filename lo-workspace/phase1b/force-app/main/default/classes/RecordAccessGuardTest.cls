/**
 * Phase 1b: proves each guarded entry point still serves a legitimate user and refuses an
 * External Loan Officer who passes the Id of another LO's record.
 *
 * Two External LOs (profile, role and External_LO_Access exactly as in production):
 * - loA can open the data: owns the Lead and Account, and holds a Manual READ share on the
 *   Transaction, which mirrors an internal LO's read-only loan access.
 * - loB owns nothing and must be refused everywhere.
 * The Transaction is owned by the admin running the test, as a processor-owned file would be.
 *
 * without sharing on purpose: controllers with no sharing keyword inherit their caller's mode.
 * From Aura that is without sharing, so the test must call them the same way or runAs would
 * enforce sharing that production does not.
 */
@IsTest
private without sharing class RecordAccessGuardTest {

    @TestSetup
    static void setup() {
        User loA = newExternalLo('p1b.loa');
        User loB = newExternalLo('p1b.lob');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ loA, loB };
            // External_LO_Access directly (as asked) plus the External_Loan_Officer group the real
            // users get, which carries the object permissions (Condition__c, requests, files).
            Id permSetId = [SELECT Id FROM PermissionSet WHERE Name = 'External_LO_Access'].Id;
            Id groupId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'External_Loan_Officer'].Id;
            Test.calculatePermissionSetGroup(groupId);
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = loA.Id, PermissionSetId = permSetId),
                new PermissionSetAssignment(AssigneeId = loB.Id, PermissionSetId = permSetId),
                new PermissionSetAssignment(AssigneeId = loA.Id, PermissionSetGroupId = groupId),
                new PermissionSetAssignment(AssigneeId = loB.Id, PermissionSetGroupId = groupId)
            };
        }

        Lead leadRecord = new Lead(
            FirstName = 'Guard', LastName = 'Borrower', Company = 'Guard Borrower',
            Status = 'New', Email = 'p1b.guard.lead@example.com', OwnerId = loA.Id
        );
        insert leadRecord;

        Account accountRecord = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId(),
            FirstName = 'Guard', LastName = 'Client', PersonEmail = 'p1b.guard.client@example.com',
            OwnerId = loA.Id
        );
        insert accountRecord;

        Transaction__c loan = new Transaction__c(Name = 'P1B Guard Loan');
        insert loan;
        insert new Transaction__Share(
            ParentId = loan.Id, UserOrGroupId = loA.Id, AccessLevel = 'Read', RowCause = 'Manual'
        );

        Condition__c conditionRecord = new Condition__c(
            Transaction__c = loan.Id, Status__c = 'Requested', Subject__c = 'Guard', Description__c = 'Guard'
        );
        insert conditionRecord;

        insert new Lead_Document_Request__c(
            Lead__c = leadRecord.Id, Name = 'Guard Request', Subject__c = 'Guard Request',
            Description__c = 'Please upload', Category__c = 'Income', Type__c = 'Loan Officer',
            Status__c = 'Requested', Include_In_Email__c = true, Can_Borrower_See__c = true
        );
        // Same Lead, but a request loB can see: stands in for the Public Read/Write visibility an
        // internal user has, so only the new Lead check can refuse loB.
        insert new Lead_Document_Request__c(
            Lead__c = leadRecord.Id, Name = 'Guard Request B', Subject__c = 'Guard Request B',
            Description__c = 'Please upload', Category__c = 'Income', Type__c = 'Loan Officer',
            Status__c = 'Requested', Include_In_Email__c = true, Can_Borrower_See__c = true
        );

        // A borrower file on the loan, also linked to a Checklist loB can see, so that loB can
        // READ it. That is exactly the case the DocumentViewer guard must still refuse.
        ContentVersion version = new ContentVersion(
            Title = 'P1B Guard File', PathOnClient = 'guard.pdf', VersionData = Blob.valueOf('x'),
            FirstPublishLocationId = loan.Id
        );
        insert version;
        // Stamped to loB below so the Checklist Restriction Rule lets loB read it (and so the file).
        Checklist__c openRecord = new Checklist__c(Transaction__c = loan.Id);
        insert openRecord;
        // The stamp trigger only recomputes when the parent changes, so a direct update sticks.
        update new Checklist__c(Id = openRecord.Id, External_LO__c = loB.Id);
        update new Lead_Document_Request__c(
            Id = [SELECT Id FROM Lead_Document_Request__c WHERE Name = 'Guard Request B'].Id, External_LO__c = loB.Id
        );
        insert new ContentDocumentLink(
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId,
            LinkedEntityId = openRecord.Id, ShareType = 'V', Visibility = 'AllUsers'
        );

        // ExternalLoStampCallInsight stamps External_LO__c = loA from the Lead owner.
        insert new Call_Insight__c(Lead__c = leadRecord.Id, Title__c = 'Guard call');
    }

    // ---------- RecordAccessGuard itself ----------

    @IsTest
    static void guardAllowsVisibleRecordsAndRefusesOthers() {
        Id leadId = leadId();
        Id loanId = loanId();
        System.runAs(lo('p1b.loa')) {
            RecordAccessGuard.requireRead(leadId);
            RecordAccessGuard.requireEdit(leadId);
            RecordAccessGuard.requireRead(loanId);
            System.assert(RecordAccessGuard.readable(new Set<Id>{ leadId, loanId, null }).containsAll(new Set<Id>{ leadId, loanId }));
        }
        System.runAs(lo('p1b.lob')) {
            assertDenied(new GuardCall(leadId, false));
            assertDenied(new GuardCall(loanId, false));
            assertDenied(new GuardCall(null, false));
            System.assertEquals(0, RecordAccessGuard.readable(new Set<Id>{ leadId, loanId }).size());
        }
    }

    @IsTest
    static void readShareDoesNotGrantEdit() {
        Id loanId = loanId();
        System.runAs(lo('p1b.loa')) {
            assertDenied(new GuardCall(loanId, true));
        }
    }

    @IsTest
    static void guestIsAlwaysRefused() {
        RecordAccessGuard.userType = 'Guest';
        assertDenied(new GuardCall(leadId(), false));
    }

    @IsTest
    static void portalUsersAreJudgedByOwnership() {
        Id leadId = leadId();
        Id loanId = loanId();
        User loA = lo('p1b.loa');
        Transaction__c loan = new Transaction__c(Id = loanId, Loan_Officer__c = loA.Id);
        update loan;
        RecordAccessGuard.userType = 'PowerCustomerSuccess';
        System.runAs(loA) {
            RecordAccessGuard.requireRead(leadId);
            RecordAccessGuard.requireRead(loanId);
        }
        System.runAs(lo('p1b.lob')) {
            assertDenied(new GuardCall(leadId, false));
            assertDenied(new GuardCall(loanId, false));
        }
    }

    // ---------- Guarded controllers ----------

    @IsTest
    static void callInsights() {
        Id leadId = leadId();
        Zoom_Meeting__c meeting = new Zoom_Meeting__c();
        meeting.put('Zoom_Meeting_Id__c', '99900011122');
        meeting.put('Topic__c', 'Guard');
        meeting.put('Status__c', 'Completed');
        insert meeting;
        Call_Insight__c insight = [SELECT Id FROM Call_Insight__c WHERE Lead__c = :leadId];
        insight.Zoom_Meeting__c = meeting.Id;
        insight.Source__c = 'Zoom';
        update insight;
        Zoom_Recording__c recording = new Zoom_Recording__c();
        recording.put('Zoom_Meeting__c', meeting.Id);
        recording.put('Zoom_Recording_File_Id__c', 'guard-rec');
        recording.put('File_Type__c', 'Video');
        recording.put('Play_URL__c', 'https://zoom.us/rec/play/guard');
        recording.put('Status__c', 'Available');
        insert recording;
        List<Id> meetingIds = new List<Id>{ meeting.Id };

        System.runAs(lo('p1b.loa')) {
            System.assertEquals(1, CallInsightListController.getCallInsights(leadId, 'Zoom').size());
            System.assertEquals(1, CallInsightListController.getZoomRecordings(meetingIds).size());
        }
        System.runAs(lo('p1b.lob')) {
            Boolean threw = false;
            try {
                CallInsightListController.getCallInsights(leadId, 'Zoom');
            } catch (Exception e) {
                threw = true;
            }
            System.assert(threw, 'loB must not read another LO\'s call insights');
            System.assertEquals(0, CallInsightListController.getZoomRecordings(meetingIds).size(),
                'loB must not get recording links for another LO\'s meeting');
        }
    }

    @IsTest
    static void accountRecordHero() {
        Id accountId = [SELECT Id FROM Account WHERE PersonEmail = 'p1b.guard.client@example.com'].Id;
        System.runAs(lo('p1b.lob')) {
            Boolean threw = false;
            try {
                AccountRecordHeroController.createPastClientLead(accountId, 'Purchase');
            } catch (Exception e) {
                threw = true;
            }
            System.assert(threw, 'loB must not copy another LO\'s Person Account into a Lead');
        }
        System.runAs(lo('p1b.loa')) {
            System.assertNotEquals(null, AccountRecordHeroController.createPastClientLead(accountId, 'Purchase'));
        }
    }

    @IsTest
    static void leadNotes() {
        Id leadId = leadId();
        System.runAs(lo('p1b.loa')) {
            LeadNotesFormController.saveNotes(leadId, '{"a":"b"}');
            System.assertEquals('{"a":"b"}', LeadNotesFormController.getNotes(leadId));
        }
        System.runAs(lo('p1b.lob')) {
            Boolean readThrew = false;
            Boolean writeThrew = false;
            try { LeadNotesFormController.getNotes(leadId); } catch (Exception e) { readThrew = true; }
            try { LeadNotesFormController.saveNotes(leadId, 'x'); } catch (Exception e) { writeThrew = true; }
            System.assert(readThrew && writeThrew, 'loB must not read or overwrite another LO\'s lead notes');
        }
        System.assertEquals('{"a":"b"}', [SELECT Lead_Notes_JSON__c FROM Lead WHERE Id = :leadId].Lead_Notes_JSON__c);
    }

    @IsTest
    static void transactionFormsServeVisibleLoansOnly() {
        Id loanId = loanId();
        // Writes as the admin (a processor's edit access). A read-share LO passes the guard too,
        // but Transaction automation refuses the save with INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY,
        // exactly as it does for internal LOs today, so the guard is not what decides that case.
        TransactionNotesFormController.saveNotes(loanId, '{"n":"1"}');
        SubmissionQualityChecklistController.saveChecklistAnswers(loanId, new Map<String, String>());
        System.runAs(lo('p1b.loa')) {
            System.assertEquals('{"n":"1"}', TransactionNotesFormController.getNotes(loanId));
            SubmissionQualityChecklistController.getExistingChecklist(loanId);
        }
        System.runAs(lo('p1b.lob')) {
            Integer refused = 0;
            try { TransactionNotesFormController.getNotes(loanId); } catch (Exception e) { refused++; }
            try { TransactionNotesFormController.saveNotes(loanId, 'x'); } catch (Exception e) { refused++; }
            try { SubmissionQualityChecklistController.getExistingChecklist(loanId); } catch (Exception e) { refused++; }
            try { SubmissionQualityChecklistController.saveChecklistAnswers(loanId, new Map<String, String>()); } catch (Exception e) { refused++; }
            try { ChecklistController.getChecklist(loanId, 'any', null); } catch (Exception e) { refused++; }
            System.assertEquals(5, refused, 'loB must be refused by every Transaction form method');
        }
    }

    @IsTest
    static void documentViewerWrites() {
        Id loanId = loanId();
        ContentVersion version = [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Title = 'P1B Guard File' AND IsLatest = TRUE
        ];
        Id conditionId = [SELECT Id FROM Condition__c WHERE Transaction__c = :loanId].Id;

        System.runAs(lo('p1b.lob')) {
            System.assertEquals(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :version.ContentDocumentId WITH USER_MODE],
                'Setup: loB can read the file through the Public Read/Write link');
            Integer refused = 0;
            try { DocumentViewerController.renameFile(version.ContentDocumentId, 'hijacked'); } catch (Exception e) { refused++; }
            try { DocumentViewerController.changeFolder(loanId, version.ContentDocumentId, 'Junk'); } catch (Exception e) { refused++; }
            try { DocumentViewerController.moveFiles(loanId, 'Junk', new List<Id>{ version.ContentDocumentId }); } catch (Exception e) { refused++; }
            try { DocumentViewerController.relateFileToCondition(version.ContentDocumentId, conditionId); } catch (Exception e) { refused++; }
            System.assertEquals(4, refused, 'loB must not change a file on another LO\'s loan');
            // Not an upload of theirs: silently ignored.
            DocumentViewerController.applyUploadDetails(new List<Id>{ version.Id }, 'Junk', 'hijacked');
        }
        System.assertEquals('P1B Guard File', [SELECT Title FROM ContentVersion WHERE Id = :version.Id].Title);

        System.runAs(lo('p1b.loa')) {
            DocumentViewerController.renameFile(version.ContentDocumentId, 'Renamed by LO');
            DocumentViewerController.changeFolder(loanId, version.ContentDocumentId, 'Income');
        }
        ContentVersion after = [SELECT Title, Folder__c FROM ContentVersion WHERE ContentDocumentId = :version.ContentDocumentId AND IsLatest = TRUE];
        System.assertEquals('Renamed by LO', after.Title);
        System.assertEquals('Income', after.Folder__c);
    }

    @IsTest
    static void conditionUploadAndReview() {
        Id loanId = loanId();
        Id conditionId = [SELECT Id FROM Condition__c WHERE Transaction__c = :loanId].Id;
        ContentVersion adminFile = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Title = 'P1B Guard File' AND IsLatest = TRUE];

        System.runAs(lo('p1b.lob')) {
            Integer refused = 0;
            try { LoanConditionController.contentVersionUpdate(conditionId, new List<Id>{ adminFile.Id }); } catch (Exception e) { refused++; }
            try { ConditionReviewService.approveDocument(conditionId, adminFile.ContentDocumentId, true); } catch (Exception e) { refused++; }
            try { ConditionReviewService.rejectCondition(conditionId, 'no', false, null); } catch (Exception e) { refused++; }
            System.assertEquals(3, refused, 'loB must not upload to or review another LO\'s condition');
        }

        System.runAs(lo('p1b.loa')) {
            // Someone else's file is never linked, even on a visible condition.
            LoanConditionController.contentVersionUpdate(conditionId, new List<Id>{ adminFile.Id });
        }
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :conditionId]);

        // Legitimate reviewer (the admin): a document on the condition is approved.
        insert new ContentDocumentLink(
            ContentDocumentId = adminFile.ContentDocumentId, LinkedEntityId = conditionId,
            ShareType = 'V', Visibility = 'AllUsers'
        );
        ConditionReviewService.approveDocument(conditionId, adminFile.ContentDocumentId, true);
        System.assertEquals('Approved', [SELECT Status__c FROM Condition__c WHERE Id = :conditionId].Status__c);
    }

    @IsTest
    static void leadRequestUpload() {
        Id requestId = [SELECT Id FROM Lead_Document_Request__c WHERE Name = 'Guard Request'].Id;
        ContentVersion adminFile = [SELECT Id FROM ContentVersion WHERE Title = 'P1B Guard File' AND IsLatest = TRUE];
        Id requestBId = [SELECT Id FROM Lead_Document_Request__c WHERE Name = 'Guard Request B'].Id;
        System.runAs(lo('p1b.lob')) {
            ContentVersion own = new ContentVersion(Title = 'B upload', PathOnClient = 'b.pdf', VersionData = Blob.valueOf('z'));
            insert own;
            Boolean threw = false;
            try {
                LeadDocumentRequestService.handleInternalFileUpload(requestBId, new List<Id>{ own.Id });
            } catch (Exception e) {
                threw = true;
            }
            System.assert(threw, 'loB must not file documents on another LO\'s lead');
        }
        ContentVersion own = new ContentVersion(Title = 'LO upload', PathOnClient = 'lo.pdf', VersionData = Blob.valueOf('y'));
        System.runAs(lo('p1b.loa')) {
            insert own;
            LeadDocumentRequestService.handleInternalFileUpload(requestId, new List<Id>{ own.Id, adminFile.Id });
            // Read as loA: the admin cannot see loA's private file.
            System.assertEquals(requestId, [SELECT Lead_Document_Request__c FROM ContentVersion WHERE Id = :own.Id].Lead_Document_Request__c,
                'The LO\'s own upload is filed');
        }
        System.assertEquals(null, [SELECT Lead_Document_Request__c FROM ContentVersion WHERE Id = :adminFile.Id].Lead_Document_Request__c,
            'Only the LO\'s own upload is filed; the other Id is ignored');
    }

    @IsTest
    static void markCommentUnreadOnlyForAuthor() {
        Id conditionId = [SELECT Id FROM Condition__c WHERE Transaction__c = :loanId()].Id;
        Condition_Comment__c comment = new Condition_Comment__c(
            Condition__c = conditionId, Comment_Text__c = 'Please resend', Portal_Comment__c = false,
            Public__c = true, Read__c = true
        );
        insert comment;

        System.runAs(lo('p1b.loa')) {
            Boolean threw = false;
            try {
                ConditionCommentController.markProcessorCommentUnreadForBorrower(comment.Id);
            } catch (Exception e) {
                threw = true;
            }
            System.assert(threw, 'Only the comment\'s author may flag it');
        }
        System.assertEquals(true, [SELECT Read__c FROM Condition_Comment__c WHERE Id = :comment.Id].Read__c);

        ConditionCommentController.markProcessorCommentUnreadForBorrower(comment.Id);
        System.assertEquals(false, [SELECT Read__c FROM Condition_Comment__c WHERE Id = :comment.Id].Read__c);
    }

    // ---------- helpers ----------

    private class GuardCall {
        Id recordId;
        Boolean edit;
        GuardCall(Id recordId, Boolean edit) {
            this.recordId = recordId;
            this.edit = edit;
        }
    }

    private static void assertDenied(GuardCall call) {
        Boolean threw = false;
        try {
            if (call.edit) {
                RecordAccessGuard.requireEdit(call.recordId);
            } else {
                RecordAccessGuard.requireRead(call.recordId);
            }
        } catch (AuraHandledException e) {
            threw = e.getMessage() == RecordAccessGuard.NO_ACCESS;
        }
        System.assert(threw, 'Expected access to ' + call.recordId + ' to be refused');
    }

    private static Id leadId() {
        return [SELECT Id FROM Lead WHERE Email = 'p1b.guard.lead@example.com'].Id;
    }

    private static Id loanId() {
        return [SELECT Id FROM Transaction__c WHERE Name = 'P1B Guard Loan'].Id;
    }

    private static User lo(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias.right(8)];
    }

    private static User newExternalLo(String alias) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = alias + suffix + '@reach-p1b.test',
            Email = alias + '@reach-p1b.test',
            LastName = alias,
            Alias = alias.right(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}
