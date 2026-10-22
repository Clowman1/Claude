trigger TwilioStopKeyword on TwilioSF__Message__c (after insert) {
    TwilioStopKeywordService.onInsert(Trigger.new);
}
