/**
 * Thin controller for the external LO Perfect Day homepage LWC.
 */
public with sharing class PerfectDayHomeController {

    @AuraEnabled(cacheable=true)
    public static PerfectDayHomeModels.PerfectDayHomeData getPerfectDayHomeData(String cacheBust) {
        // cacheBust is the LWC wire cache key only. Date.now() does not fit Apex Integer.
        try {
            return PerfectDayHomeService.getHomeData();
        } catch (Exception error) {
            throw toAura(error, 'Unable to load Perfect Day. Please try again.');
        }
    }

    @AuraEnabled
    public static void deferUpNextItem(Id recordId, String objectApiName, String deferOption) {
        try {
            PerfectDayHomeService.deferUpNextItem(recordId, objectApiName, deferOption);
        } catch (Exception error) {
            throw toAura(error, 'Unable to defer this action. Please try again.');
        }
    }

    @AuraEnabled
    public static void completeUpNextItem(Id recordId, String objectApiName) {
        try {
            PerfectDayHomeService.completeUpNextItem(recordId, objectApiName);
        } catch (Exception error) {
            throw toAura(error, 'Unable to complete this task. Please try again.');
        }
    }

    /** Up Next "Open all" modal: everything, uncapped, grouped overdue / today / upcoming. */
    @AuraEnabled
    public static List<ExternalLoPromptService.PromptItem> getAllUpNext() {
        try {
            return ExternalLoPromptService.getAllUpNext(UserInfo.getUserId());
        } catch (Exception error) {
            throw toAura(error, 'Unable to load Up Next. Please try again.');
        }
    }

    @TestVisible
    private static AuraHandledException toAura(Exception error, String fallbackMessage) {
        String message;
        if (error instanceof DomainException) {
            message = error.getMessage();
        } else {
            message = fallbackMessage;
        }
        if (String.isBlank(message)) {
            message = fallbackMessage;
        }
        AuraHandledException wrapped = new AuraHandledException(message);
        wrapped.setMessage(message);
        return wrapped;
    }
}