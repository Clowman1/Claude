// Zoom meetings are both stamped (from their Lead/Account) and a parent (of Zoom recordings).
trigger ExternalLoStampZoomMeeting on Zoom_Meeting__c (before insert, before update, after update) {
    if (Trigger.isBefore) {
        ExternalLoStampService.stampChildren(Trigger.new, Trigger.oldMap);
    } else {
        ExternalLoStampService.restampChildrenOf(Trigger.new, Trigger.oldMap);
    }
}
