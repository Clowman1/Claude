public with sharing class RingSenseSubscriptionController {
    @AuraEnabled
    public static RingSenseSubscriptionService.StatusResult getStatus() {
        return RingSenseSubscriptionService.getStatus();
    }

    @AuraEnabled
    public static RingSenseSubscriptionService.StatusResult reregister() {
        return RingSenseSubscriptionService.reregister();
    }
}