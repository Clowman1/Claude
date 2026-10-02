// ReachTxPostClosedWebhookSvc was removed 2026-08-28: it duplicated the
// post-closed Zapier feed already handled by the record-triggered flow ->
// TxnPostCloseZapierHook, and pointed at a stale Zapier account id.
trigger ReachTxPostClosedWebhook on Transaction__c (after update) {
    MyHomeIQPastClientWebhookSvc.enqueueForStatusChanges(
        Trigger.new,
        Trigger.oldMap
    );
}