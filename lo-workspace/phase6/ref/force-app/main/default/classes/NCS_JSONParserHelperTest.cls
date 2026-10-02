/**
 * @author Andrei Karanko
 * @date 3/7/2024
 * description
 */
@IsTest
private with sharing class NCS_JSONParserHelperTest {
    private static final String TEST_STRING_WITH_BODY_PROPERTY_IN_THE_MIDDLE = '[{"account_sid":"AC_REDACTED_TWILIO_ACCOUNT_SID","api_version":"2010-04-01",' +
        '"body":"Hi "Antonia", Thank you for your referral, we are actively reaching out to Candi Kallsen unless otherwise specified in ' +
        'your notes. -Reach Home Loans","date_created":"Wed, 06 Mar 2024 14:57:47 +0000","date_sent":"Wed, 06 Mar 2024 14:57:47 +0000",' +
        '"date_updated":"Wed, 06 Mar 2024 14:57:47 +0000","direction":"outbound-api","error_code":null,"error_message":null,"from":"+17722385990"},' +
        '{"account_sid":"AC_REDACTED_TWILIO_ACCOUNT_SID","api_version":"2010-04-01","body":"A new Biz Dev - Reach Lead has been submitted ' +
        'from Antonia Mander. Please use the following link to view the Lead now: https://reachhomeloans.lightning.force.com/lightning/r/Lead/00QQi000006ikEzMAI/view",' +
        '"date_created":"Wed, 06 Mar 2024 14:57:45 +0000","date_sent":"Wed, 06 Mar 2024 14:57:45 +0000","date_updated":"Wed, 06 Mar 2024 14:57:48 +0000",' +
        '"direction":"outbound-api","error_code":null,"error_message":null,"from":"+17722385990"}]';
    private static final String TEST_STRING_WITH_BODY_PROPERTY_AT_THE_END = '[{"account_sid":"AC_REDACTED_TWILIO_ACCOUNT_SID",' +
        '"api_version":"2010-04-01","date_created":"Wed, 06 Mar 2024 14:57:47 +0000","date_sent":"Wed, 06 Mar 2024 14:57:47 +0000","date_updated":' +
        '"Wed, 06 Mar 2024 14:57:47 +0000","direction":"outbound-api","error_code":null,"error_message":null,"from":"+17722385990","body":"Hi "Antonia", ' +
        'Thank you for your referral, we are actively reaching out to Candi Kallsen unless otherwise specified in your notes. -Reach Home Loans"}]';

    @IsTest
    private static void escapeQuotesInTheMiddleBodyTest() {
        String result;
        Test.startTest();
        result = NCS_JSONParserHelper.escapeQuotesInBody(TEST_STRING_WITH_BODY_PROPERTY_IN_THE_MIDDLE);
        List<Object> deserializedListOfMessages = (List<Object>) JSON.deserializeUntyped(result);
        Test.stopTest();

        Assert.isTrue(!deserializedListOfMessages.isEmpty(), 'JSON string after escaping quotes should be successfully deserialized');
    }

    @IsTest
    private static void escapeQuotesAtTheEndBodyTest() {
        String result;
        Test.startTest();
        result = NCS_JSONParserHelper.escapeQuotesInBody(TEST_STRING_WITH_BODY_PROPERTY_AT_THE_END);
        List<Object> deserializedListOfMessages = (List<Object>) JSON.deserializeUntyped(result);
        Test.stopTest();

        Assert.isTrue(!deserializedListOfMessages.isEmpty(), 'JSON string after escaping quotes should be successfully deserialized');
    }
}