// Re-stamps child records when an outside LO gains or loses this record (see ExternalLoStampService).
trigger ExternalLoRestampTransaction on Transaction__c (after update) {
    ExternalLoStampService.restampChildrenOf(Trigger.new, Trigger.oldMap);
}