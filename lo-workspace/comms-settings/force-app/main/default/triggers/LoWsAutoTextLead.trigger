// comms-settings: automated texts for External LO leads (LoWsAutoTextService).
trigger LoWsAutoTextLead on Lead (after insert, after update) {
    LoWsAutoTextService.onLeads(Trigger.new, Trigger.oldMap);
}
