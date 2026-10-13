// comms-settings: N4 borrower text when document requests are sent (LoWsAutoTextService).
trigger LoWsAutoTextDocRequest on Lead_Document_Request__c (after insert, after update) {
    LoWsAutoTextService.onDocRequests(Trigger.new, Trigger.oldMap);
}
