/**
 * Phase 1b (External LO): record-level checks for controllers that deliberately run without
 * sharing. Those classes take record Ids straight from the browser, so each entry point asks
 * this class first and refuses an Id the running user could not open in the UI.
 *
 * - Internal users: UserRecordAccess (sharing, role hierarchy, View All / Modify All).
 * - Partner Workspace (community) users: the ownership rule the portal's own detail queries use
 *   (LeadRepository.selectPortalLeadDetail, LoanRepository.selectPortalLoanDetail). Their license
 *   has no Lead object access, so UserRecordAccess cannot be trusted to say yes for them.
 * - Guest users: always refused. No guest page legitimately reaches a guarded method, but several
 *   guest profiles hold these classes through the Condition_Files_Permissions permission set.
 *
 * without sharing only so the portal ownership queries are not hidden by sharing themselves.
 */
public without sharing class RecordAccessGuard {
    public static final String NO_ACCESS = 'You do not have access to this record.';

    @TestVisible
    private static String userType = UserInfo.getUserType();

    public static void requireRead(Id recordId) {
        require(recordId, false);
    }

    public static void requireEdit(Id recordId) {
        require(recordId, true);
    }

    public static Set<Id> readable(Set<Id> recordIds) {
        return filter(recordIds, false);
    }

    public static AuraHandledException denied() {
        // setMessage so callers that rewrap with e.getMessage() keep the text.
        AuraHandledException e = new AuraHandledException(NO_ACCESS);
        e.setMessage(NO_ACCESS);
        return e;
    }

    private static void require(Id recordId, Boolean needEdit) {
        if (recordId == null || !filter(new Set<Id>{ recordId }, needEdit).contains(recordId)) {
            throw denied();
        }
    }

    private static Set<Id> filter(Set<Id> recordIds, Boolean needEdit) {
        Set<Id> allowed = new Set<Id>();
        Set<Id> pending = recordIds == null ? new Set<Id>() : recordIds.clone();
        pending.remove(null);
        if (pending.isEmpty() || userType == 'Guest') {
            return allowed;
        }

        if (userType != 'Standard') {
            Id me = UserInfo.getUserId();
            for (Lead leadRecord : [SELECT Id FROM Lead WHERE Id IN :pending AND OwnerId = :me]) {
                allowed.add(leadRecord.Id);
            }
            for (Transaction__c loan : [
                SELECT Id FROM Transaction__c
                WHERE Id IN :pending AND (Loan_Officer__c = :me OR OwnerId = :me)
            ]) {
                allowed.add(loan.Id);
            }
            // Leads and loans are decided by ownership alone for portal users.
            for (Id recordId : recordIds) {
                if (recordId != null
                    && (recordId.getSObjectType() == Lead.SObjectType
                        || recordId.getSObjectType() == Transaction__c.SObjectType)) {
                    pending.remove(recordId);
                }
            }
        }

        // UserRecordAccess accepts at most 200 Ids per query.
        List<Id> batch = new List<Id>();
        for (Id recordId : pending) {
            batch.add(recordId);
            if (batch.size() == 200) {
                allowed.addAll(queryAccess(batch, needEdit));
                batch.clear();
            }
        }
        if (!batch.isEmpty()) {
            allowed.addAll(queryAccess(batch, needEdit));
        }
        return allowed;
    }

    private static Set<Id> queryAccess(List<Id> recordIds, Boolean needEdit) {
        Set<Id> allowed = new Set<Id>();
        for (UserRecordAccess access : [
            SELECT RecordId, HasReadAccess, HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId() AND RecordId IN :recordIds
        ]) {
            if (needEdit ? access.HasEditAccess : access.HasReadAccess) {
                allowed.add(access.RecordId);
            }
        }
        return allowed;
    }
}
