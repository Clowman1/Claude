// Stamps External_LO__c for the External LO restriction rule (see ExternalLoStampService).
trigger ExternalLoStampDocRequest on Lead_Document_Request__c (before insert, before update) {
    ExternalLoStampService.stampChildren(Trigger.new, Trigger.oldMap);
}