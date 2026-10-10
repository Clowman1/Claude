@isTest
private class ExternalLoCsvDmlMessageTest {

    @isTest
    static void fromSaveResult_mapsKnownCodesAndFallsBack() {
        System.assertEquals(
            ExternalLoCsvDmlMessage.FALLBACK,
            ExternalLoCsvDmlMessage.fromSaveResult(null)
        );
        List<Database.SaveResult> failedShares = ExternalLoPartnerLinkWriter.insertAccountShares(
            new List<AccountShare>{ new AccountShare() }
        );
        String mapped = ExternalLoCsvDmlMessage.fromSaveResult(failedShares[0]);
        System.assertNotEquals(null, mapped);
        System.assertEquals(false, mapped.contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST'), mapped);
        System.assertEquals(false, mapped.contains('INSUFFICIENT_ACCESS'), mapped);
    }

    @isTest
    static void fromStatus_mapsEachRequestedCode() {
        System.assertEquals(
            'That partner is already in your realtor list.',
            ExternalLoCsvDmlMessage.fromStatus(StatusCode.DUPLICATE_VALUE, 'duplicate value found: Unique_Key__c')
        );
        System.assertEquals(
            'That row is a duplicate of a record you already have.',
            ExternalLoCsvDmlMessage.fromStatus(StatusCode.DUPLICATE_VALUE, 'duplicate')
        );
        System.assertEquals(
            'One of the values in that row is not an allowed option. Check type and try again.',
            ExternalLoCsvDmlMessage.fromStatus(StatusCode.INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST, 'raw')
        );
        System.assertEquals(
            'Weekly target must be whole numbers.',
            ExternalLoCsvDmlMessage.fromStatus(StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION, 'Weekly target must be whole numbers.')
        );
        System.assertEquals(
            ExternalLoCsvDmlMessage.FALLBACK,
            ExternalLoCsvDmlMessage.fromStatus(StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION, '')
        );
        String accessCopy = 'You do not have access to save that row. Ask an admin for help.';
        System.assertEquals(accessCopy, ExternalLoCsvDmlMessage.fromStatus(StatusCode.INSUFFICIENT_ACCESS, 'raw'));
        System.assertEquals(
            accessCopy,
            ExternalLoCsvDmlMessage.fromStatus(StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY, 'raw')
        );
        System.assertEquals(
            accessCopy,
            ExternalLoCsvDmlMessage.fromStatus(StatusCode.INSUFFICIENT_ACCESS_OR_READONLY, 'raw')
        );
        System.assertEquals(
            ExternalLoCsvDmlMessage.FALLBACK,
            ExternalLoCsvDmlMessage.fromStatus(StatusCode.REQUIRED_FIELD_MISSING, 'Name is required')
        );
    }
}