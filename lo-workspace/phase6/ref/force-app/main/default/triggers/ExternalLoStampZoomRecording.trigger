// Stamps External_LO__c for the External LO restriction rule (see ExternalLoStampService).
trigger ExternalLoStampZoomRecording on Zoom_Recording__c (before insert, before update) {
    ExternalLoStampService.stampChildren(Trigger.new, Trigger.oldMap);
}