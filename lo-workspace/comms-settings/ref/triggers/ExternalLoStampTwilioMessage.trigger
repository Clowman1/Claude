// LO Workspace (O3): origin loan/lead, phone key and Workspace LO stamp on Twilio texts (see LoWsTextsService).
trigger ExternalLoStampTwilioMessage on TwilioSF__Message__c (before insert, before update) {
    LoWsTextsService.stamp(Trigger.new, Trigger.oldMap);
}