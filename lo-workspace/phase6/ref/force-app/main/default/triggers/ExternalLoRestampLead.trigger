// Re-stamps child records when an outside LO gains or loses this record (see ExternalLoStampService).
trigger ExternalLoRestampLead on Lead (after update) {
    ExternalLoStampService.restampChildrenOf(Trigger.new, Trigger.oldMap);
}