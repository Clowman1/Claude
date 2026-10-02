// Stamps External_LO__c for the External LO restriction rule (see ExternalLoStampService).
trigger ExternalLoStampAppraisalOrder on Appraisal_Order__c (before insert, before update) {
    ExternalLoStampService.stampChildren(Trigger.new, Trigger.oldMap);
}