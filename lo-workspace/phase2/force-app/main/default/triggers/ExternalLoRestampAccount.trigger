// Re-stamps child records when an outside LO gains or loses this record (see ExternalLoStampService).
trigger ExternalLoRestampAccount on Account (after update) {
    ExternalLoStampService.restampChildrenOf(Trigger.new, Trigger.oldMap);
}
