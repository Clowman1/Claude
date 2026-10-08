trigger ClientActivityCallInsightRouter on Call_Insight__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        ClientActivityTransactionRouter.routeCallInsights(Trigger.new);
    }
    if (Trigger.isAfter) {
        ClientActivityTransactionRouter.stampProcessorCallFromInsights(Trigger.new);
        if (Trigger.isInsert) {
            // Summarizing needs a callout, so it runs in a Queueable rather than inline.
            ApplicationSummaryService.enqueueForInsights(Trigger.new);
        }
    }
}