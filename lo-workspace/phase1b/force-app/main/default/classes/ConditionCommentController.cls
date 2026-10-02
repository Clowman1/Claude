public with sharing class ConditionCommentController {
    @AuraEnabled(cacheable=true)
    public static List<ConditionCommentService.ConditionCommentDto> getComments(
        Id conditionId,
        Boolean isPortalView
    ) {
        return ConditionCommentService.getComments(conditionId, isPortalView);
    }

    @AuraEnabled
    public static ConditionCommentService.ConditionCommentDto createComment(
        Id conditionId,
        String commentText,
        Boolean isPortalComment,
        Boolean isPublic
    ) {
        return ConditionCommentService.createComment(conditionId, commentText, isPortalComment, isPublic);
    }

    @AuraEnabled
    public static ConditionCommentService.ConditionCommentDto markCommentAsRead(Id commentId) {
        return ConditionCommentService.markAsRead(commentId);
    }

    /**
     * Phase 1b: moved here from BorrowerDocumentPortalController so internal users (and External
     * LOs) never need that guest-portal class. Flags a processor comment the running user just
     * posted as unread for the borrower. The with-sharing query is the guard: the comment must be
     * the user's own and on a condition they can see. The write itself stays in
     * BorrowerPortalService's without-sharing writer, because Loan Officers can read the loan but
     * not edit its comments.
     */
    @AuraEnabled
    public static void markProcessorCommentUnreadForBorrower(Id commentId) {
        List<Condition_Comment__c> ownComments = [
            SELECT Id FROM Condition_Comment__c
            WHERE Id = :commentId AND CreatedById = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (ownComments.isEmpty()) {
            throw RecordAccessGuard.denied();
        }
        try {
            BorrowerPortalService.markProcessorCommentUnreadForBorrower(commentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ConditionCommentService.ConditionCommentDto toggleCommentVisibility(
        Id commentId,
        Boolean isPublic
    ) {
        return ConditionCommentService.updateVisibility(commentId, isPublic);
    }
}