/**
 * Use-case service that builds the loan-grouped review queue used by the
 * Pending Review Utility LWC. Returns Conditions assigned to the current
 * user that either:
 *   - are in Status='Review' (the canonical "needs processor action" state), or
 *   - have an unread Condition_Comment__c (a borrower has replied / left a
 *     comment that the processor has not yet seen, even if the parent
 *     Condition is still sitting in Requested / New / Submitted, etc.).
 *
 * The unread-comment branch is what surfaces borrower portal replies into
 * the Pending Review queue regardless of how the comment was created
 * (Create_Condition_Comment flow OR ConditionCommentService.createComment).
 *
 * Layering: Service (orchestration) -> TransactionConditionRepository (SOQL).
 */
public with sharing class ConditionReviewQueueService {

    private static final String STATUS_REVIEW = 'Review';
    private static final String REVIEW_STATUS_FIELD = 'Condition_Document_Review_Status__c';
    private static final String REVIEW_PENDING = 'Pending Review';

    public class LoanQueueDto {
        @AuraEnabled public Id loanId;
        @AuraEnabled public String loanName;
        @AuraEnabled public String borrowerName;
        @AuraEnabled public String loanNumber;
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public String lenderName;
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public String stage;
        @AuraEnabled public Integer pendingConditionsCount;
        @AuraEnabled public Integer unreadCommentsCount;
        @AuraEnabled public List<ConditionDto> conditions;

        public LoanQueueDto() {
            this.conditions = new List<ConditionDto>();
            this.pendingConditionsCount = 0;
            this.unreadCommentsCount = 0;
        }
    }

    public class ConditionDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String category;
        @AuraEnabled public String status;
        @AuraEnabled public Integer documentCount;
        @AuraEnabled public Integer unreadCommentCount;
        @AuraEnabled public Integer commentCount;
    }

    @AuraEnabled
    public static List<LoanQueueDto> buildQueue() {
        Id currentUserId = UserInfo.getUserId();

        List<LoanQueueDto> leadQueue = buildLeadQueue(currentUserId);

        List<Condition__c> conditions = queryReviewConditionsForUser(currentUserId);
        if (conditions.isEmpty()) {
            return leadQueue;
        }

        Set<Id> conditionIds = new Set<Id>();
        for (Condition__c c : conditions) {
            conditionIds.add(c.Id);
        }

        Map<Id, Integer> documentCountsByConditionId = selectPendingDocumentCountsByConditionIds(conditionIds);

        Map<Id, LoanQueueDto> queueByLoanId = new Map<Id, LoanQueueDto>();
        for (Condition__c condition : conditions) {
            Integer documentCount = documentCountsByConditionId.containsKey(condition.Id)
                ? documentCountsByConditionId.get(condition.Id)
                : 0;
            Integer unreadCommentCount = condition.Condition_Comments__r != null
                ? condition.Condition_Comments__r.size()
                : 0;

            // Comment-only items are dismissed by marking the unread comment
            // read. Document-backed Review items still require processor
            // action through approve/reject.
            if (!shouldIncludeCondition(condition, documentCount, unreadCommentCount)) {
                continue;
            }

            LoanQueueDto loanDto = queueByLoanId.get(condition.Transaction__c);
            if (loanDto == null) {
                loanDto = buildLoanDto(condition.Transaction__r);
                queueByLoanId.put(condition.Transaction__c, loanDto);
            }

            loanDto.conditions.add(buildConditionDto(condition, documentCount, unreadCommentCount));
            loanDto.pendingConditionsCount++;
            loanDto.unreadCommentsCount += unreadCommentCount;
        }

        List<LoanQueueDto> combined = new List<LoanQueueDto>(queueByLoanId.values());
        combined.addAll(leadQueue);
        return combined;
    }

    // Pre-approval document requests join the same queue as Transaction conditions, so a Loan
    // Officer has one tray rather than two. A Lead has no Assigned_To__c by design: both the Owner
    // and the Loan Partner are responsible, so both see the item and either can clear it.
    @TestVisible
    private static List<LoanQueueDto> buildLeadQueue(Id currentUserId) {
        List<LoanQueueDto> leadQueue = new List<LoanQueueDto>();

        List<Lead_Document_Request__c> requests = [
            SELECT Id, Name, Subject__c, Category__c, Status__c, Lead__c,
                   Lead__r.Name, Lead__r.FirstName, Lead__r.LastName, Lead__r.Status
            FROM Lead_Document_Request__c
            WHERE Status__c = :STATUS_REVIEW
              AND Lead__c != NULL
              AND Lead__r.IsConverted = FALSE
              AND (Lead__r.OwnerId = :currentUserId OR Lead__r.Loan_Partner__c = :currentUserId)
            ORDER BY Lead__r.Name, Name
        ];
        if (requests.isEmpty()) {
            return leadQueue;
        }

        Set<Id> requestIds = new Set<Id>();
        for (Lead_Document_Request__c requestRecord : requests) {
            requestIds.add(requestRecord.Id);
        }
        Map<Id, Integer> documentCounts = selectPendingDocumentCountsByConditionIds(requestIds);

        Map<Id, LoanQueueDto> queueByLeadId = new Map<Id, LoanQueueDto>();
        for (Lead_Document_Request__c requestRecord : requests) {
            Integer documentCount = documentCounts.containsKey(requestRecord.Id)
                ? documentCounts.get(requestRecord.Id)
                : 0;
            // A request only reaches Review when a borrower uploads, but a document that has
            // already been actioned should not keep the row in the tray.
            if (documentCount == null || documentCount == 0) {
                continue;
            }

            LoanQueueDto leadDto = queueByLeadId.get(requestRecord.Lead__c);
            if (leadDto == null) {
                leadDto = new LoanQueueDto();
                leadDto.loanId = requestRecord.Lead__c;
                leadDto.loanName = requestRecord.Lead__r.Name;
                leadDto.borrowerName = buildLeadBorrowerName(requestRecord.Lead__r);
                leadDto.stage = 'Pre-Approval';
                leadDto.lenderName = 'Pre-Approval';
                queueByLeadId.put(requestRecord.Lead__c, leadDto);
            }

            ConditionDto dto = new ConditionDto();
            dto.id = requestRecord.Id;
            dto.name = requestRecord.Name;
            dto.title = String.isNotBlank(requestRecord.Subject__c)
                ? requestRecord.Subject__c
                : requestRecord.Name;
            dto.category = requestRecord.Category__c;
            dto.status = requestRecord.Status__c;
            dto.documentCount = documentCount;
            // Pre-approval conditions carry no comment thread by design.
            dto.unreadCommentCount = 0;
            dto.commentCount = 0;

            leadDto.conditions.add(dto);
            leadDto.pendingConditionsCount++;
        }

        leadQueue.addAll(queueByLeadId.values());
        return leadQueue;
    }

    private static String buildLeadBorrowerName(Lead leadRecord) {
        if (leadRecord == null) {
            return null;
        }
        String fullName = ((leadRecord.FirstName == null ? '' : leadRecord.FirstName + ' ') +
            (leadRecord.LastName == null ? '' : leadRecord.LastName)).trim();
        return String.isBlank(fullName) ? leadRecord.Name : fullName;
    }

    private static Boolean shouldIncludeCondition(
        Condition__c condition,
        Integer documentCount,
        Integer unreadCommentCount
    ) {
        if (unreadCommentCount != null && unreadCommentCount > 0) {
            return true;
        }

        return condition.Status__c == STATUS_REVIEW
            && documentCount != null
            && documentCount > 0;
    }

    private static Map<Id, Integer> selectPendingDocumentCountsByConditionIds(Set<Id> conditionIds) {
        Map<Id, Integer> countsByConditionId = new Map<Id, Integer>();
        if (conditionIds == null || conditionIds.isEmpty()) {
            return countsByConditionId;
        }

        Map<Id, Id> conditionIdByDocumentId = new Map<Id, Id>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :conditionIds
        ]) {
            conditionIdByDocumentId.put(link.ContentDocumentId, link.LinkedEntityId);
        }
        if (conditionIdByDocumentId.isEmpty()) {
            return countsByConditionId;
        }

        Set<Id> documentIds = conditionIdByDocumentId.keySet();
        String query = 'SELECT Id, ContentDocumentId';
        if (Schema.SObjectType.ContentVersion.fields.getMap().containsKey(REVIEW_STATUS_FIELD)) {
            query += ', ' + REVIEW_STATUS_FIELD;
        }
        query += ' FROM ContentVersion WHERE IsLatest = TRUE AND ContentDocumentId IN :documentIds';

        for (SObject row : Database.query(query)) {
            String status = Schema.SObjectType.ContentVersion.fields.getMap().containsKey(REVIEW_STATUS_FIELD)
                ? (String) row.get(REVIEW_STATUS_FIELD)
                : null;
            if (!String.isBlank(status) && status != REVIEW_PENDING) {
                continue;
            }
            Id conditionId = conditionIdByDocumentId.get((Id) row.get('ContentDocumentId'));
            countsByConditionId.put(
                conditionId,
                countsByConditionId.containsKey(conditionId) ? countsByConditionId.get(conditionId) + 1 : 1
            );
        }
        return countsByConditionId;
    }

    private static List<Condition__c> queryReviewConditionsForUser(Id currentUserId) {
        // SOQL does not allow semi-joins inside nested (OR) WHERE expressions,
        // so first collect the IDs of Conditions (assigned to the user) that
        // have an unread comment, then OR them into the main query with a
        // bind variable.
        Set<Id> conditionIdsWithUnreadComments = new Set<Id>();
        for (Condition_Comment__c unreadComment : [
            SELECT Condition__c
            FROM Condition_Comment__c
            WHERE Read__c = FALSE
              AND Condition__c != NULL
              AND Condition__r.Assigned_To__c = :currentUserId
        ]) {
            conditionIdsWithUnreadComments.add(unreadComment.Condition__c);
        }

        // Surface conditions that are EITHER explicitly in Review status OR
        // have an unread borrower comment. The unread-comment branch catches
        // borrower portal replies on Conditions that haven't yet been moved
        // out of Requested/New/Submitted etc., which previously left those
        // replies invisible to the assigned processor.
        return [
            SELECT
                Id,
                Name,
                Description__c,
                Subject__c,
                Status__c,
                Category__c,
                Transaction__c,
                Transaction__r.Id,
                Transaction__r.Name,
                Transaction__r.Loan_Number__c,
                Transaction__r.Loan_Amount__c,
                Transaction__r.Lender_lookup__r.Name,
                Transaction__r.Property_Address__c,
                Transaction__r.Borrower_First_Name__c,
                Transaction__r.Borrower_Last_Name__c,
                Transaction__r.Status__c,
                (
                    SELECT Id
                    FROM Condition_Comments__r
                    WHERE Read__c = FALSE
                )
            FROM Condition__c
            WHERE Assigned_To__c = :currentUserId
              AND Transaction__c != NULL
              AND (
                  Status__c = :STATUS_REVIEW
                  OR Id IN :conditionIdsWithUnreadComments
              )
            ORDER BY Transaction__c, LastModifiedDate DESC
        ];
    }

    private static LoanQueueDto buildLoanDto(Transaction__c loan) {
        LoanQueueDto dto = new LoanQueueDto();
        if (loan == null) {
            return dto;
        }
        dto.loanId = loan.Id;
        dto.loanName = loan.Name;
        dto.loanNumber = loan.Loan_Number__c;
        dto.loanAmount = loan.Loan_Amount__c;
        dto.lenderName = loan.Lender_lookup__r == null ? null : loan.Lender_lookup__r.Name;
        dto.propertyAddress = loan.Property_Address__c;
        dto.stage = loan.Status__c;
        dto.borrowerName = buildBorrowerName(loan);
        return dto;
    }

    private static String buildBorrowerName(Transaction__c loan) {
        String firstName = loan.Borrower_First_Name__c;
        String lastName = loan.Borrower_Last_Name__c;
        if (String.isNotBlank(firstName) && String.isNotBlank(lastName)) {
            return firstName.trim() + ' ' + lastName.trim();
        }
        if (String.isNotBlank(lastName)) {
            return lastName.trim();
        }
        if (String.isNotBlank(firstName)) {
            return firstName.trim();
        }
        return loan.Name;
    }

    private static ConditionDto buildConditionDto(Condition__c condition, Integer documentCount, Integer unreadCommentCount) {
        ConditionDto dto = new ConditionDto();
        dto.id = condition.Id;
        dto.name = condition.Name;
        dto.title = String.isNotBlank(condition.Description__c) ? condition.Description__c
            : (String.isNotBlank(condition.Subject__c) ? condition.Subject__c : condition.Name);
        dto.category = condition.Category__c;
        dto.status = condition.Status__c;
        dto.documentCount = documentCount;
        dto.unreadCommentCount = unreadCommentCount;
        dto.commentCount = unreadCommentCount;
        return dto;
    }
}
