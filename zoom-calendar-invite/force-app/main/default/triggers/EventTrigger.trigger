trigger EventTrigger on Event (before insert, before update, after update, after delete) {
    if(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)){
        EventTriggerHandler.beforeInsertUpdate(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        ZoomEventSync.afterUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        ZoomEventSync.afterDelete(Trigger.old);
    }
}
