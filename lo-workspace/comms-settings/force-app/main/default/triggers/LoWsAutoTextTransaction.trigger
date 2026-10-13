// comms-settings: automated texts for External LO loans (LoWsAutoTextService).
trigger LoWsAutoTextTransaction on Transaction__c (after insert, after update) {
    LoWsAutoTextService.onTransactions(Trigger.new, Trigger.oldMap);
}
