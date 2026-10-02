/**
 * Maps Database.SaveResult status codes to Partner Workspace import copy.
 * Platform messages (restricted picklist, duplicate) must not reach the UI.
 */
public with sharing class ExternalLoCsvDmlMessage {
    public static final String FALLBACK = 'That row couldn\'t be saved. Ask an admin for help.';

    public static String fromSaveResult(Database.SaveResult saveResult) {
        if (saveResult == null || saveResult.getErrors().isEmpty()) {
            return FALLBACK;
        }
        Database.Error error = saveResult.getErrors()[0];
        return fromStatus(error.getStatusCode(), error.getMessage());
    }

    @TestVisible
    static String fromStatus(StatusCode code, String message) {
        if (code == StatusCode.DUPLICATE_VALUE) {
            if (message != null && message.contains('Unique_Key__c')) {
                return 'That partner is already in your realtor list.';
            }
            return 'That row is a duplicate of a record you already have.';
        }
        if (code == StatusCode.INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST) {
            return 'One of the values in that row is not an allowed option. Check type and try again.';
        }
        if (code == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION) {
            return String.isBlank(message) ? FALLBACK : message;
        }
        if (code == StatusCode.INSUFFICIENT_ACCESS
            || code == StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
            || code == StatusCode.INSUFFICIENT_ACCESS_OR_READONLY) {
            return 'You do not have access to save that row. Ask an admin for help.';
        }
        return FALLBACK;
    }
}