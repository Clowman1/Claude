@IsTest
private class RingSenseWebhookTest {

    private static void prepRestContext(String body, Map<String, String> headers) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/rc_transcription';
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(body);
        if (headers != null) {
            for (String k : headers.keySet()) {
                req.headers.put(k, headers.get(k));
            }
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void webhook_empty_body_returns_ok_empty() {
        prepRestContext('', null);
        Test.startTest();
        RingSenseWebhook.handleWebhook();
        Test.stopTest();
        String resp = RestContext.response.responseBody.toString();
        System.assert(resp.contains('"status":"ok"'), 'Expected ok for empty body, got: ' + resp);
        System.assert(resp.contains('"detail":"empty"'), 'Expected empty detail: ' + resp);
        System.assertEquals(0, [SELECT COUNT() FROM Call_Insight__c], 'Empty body must not enqueue ingest');
    }

    @IsTest
    static void webhook_validation_token_header_is_echoed() {
        prepRestContext('', new Map<String, String>{ 'Validation-Token' => 'abc-123' });
        Test.startTest();
        RingSenseWebhook.handleWebhook();
        Test.stopTest();
        System.assertEquals('abc-123', RestContext.response.headers.get('Validation-Token'));
        System.assertEquals('application/json', RestContext.response.headers.get('Content-Type'));
    }

    @IsTest
    static void webhook_invalid_json_returns_ok_and_logs_after_job() {
        Integer logsBefore = [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'RingSense Webhook Error'];
        prepRestContext('this is not json', null);
        Test.startTest();
        RingSenseWebhook.handleWebhook();
        String resp = RestContext.response.responseBody.toString();
        System.assert(resp.contains('"status":"ok"'), 'HTTP must ack immediately, got: ' + resp);
        System.assertEquals(0, [SELECT COUNT() FROM Call_Insight__c]);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Call_Insight__c]);
        System.assert(
            [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'RingSense Webhook Error'] > logsBefore,
            'Expected ingest error log after Queueable'
        );
    }

    @IsTest
    static void webhook_missing_body_node_returns_ok_and_logs_after_job() {
        Integer logsBefore = [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'RingSense Webhook'];
        prepRestContext('{"eventType":"x"}', null);
        Test.startTest();
        RingSenseWebhook.handleWebhook();
        String resp = RestContext.response.responseBody.toString();
        System.assert(resp.contains('"status":"ok"'), 'HTTP must ack immediately, got: ' + resp);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Call_Insight__c]);
        System.assert(
            [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'RingSense Webhook'] > logsBefore,
            'Expected missing-body log after Queueable'
        );
    }

    @IsTest
    static void testWebhook() {
        String jsonBody = '{' +
            '"body": {' +
                '"callDirection": "Outbound",' +
                '"ownerExtensionId": "63521941008",' +
                '"speakerInfo": [' +
                    '{"extensionId": "63521941008", "phoneNumber": "+13213042004"},' +
                    '{"extensionId": null, "phoneNumber": "+18135175526"}' +
                '],' +
                '"insights": {' +
                    '"Transcript": [{"text": "Hello"}],' +
                    '"Highlights": [{"value": "highlight"}],' +
                    '"Summary": [{"value": "summary"}],' +
                    '"NextSteps": [{"value": "next"}],' +
                    '"BulletedSummary": [{"value": "bullet"}],' +
                    '"AIScore": [{"value": "8"}]' +
                '}' +
            '}' +
        '}';

        prepRestContext(jsonBody, null);
        Integer before = [SELECT COUNT() FROM Call_Insight__c];

        Test.startTest();
        RingSenseWebhook.handleWebhook();
        System.assert(RestContext.response.responseBody.toString().contains('"status":"ok"'));
        System.assertEquals(
            before,
            [SELECT COUNT() FROM Call_Insight__c],
            'Ingest must not run on the HTTP thread'
        );
        Test.stopTest();

        System.assertEquals(
            before + 1,
            [SELECT COUNT() FROM Call_Insight__c],
            'Expected one Call Insight inserted by Queueable'
        );
        Call_Insight__c ci = [
            SELECT Recipient_Phone_Number__c, AI_Score__c
            FROM Call_Insight__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('+18135175526', ci.Recipient_Phone_Number__c);
        System.assertEquals(8, ci.AI_Score__c);
    }

    @IsTest
    static void webhook_enqueue_failure_returns_500() {
        prepRestContext('{"body":{}}', null);
        RingSenseWebhook.throwOnEnqueue = true;
        Test.startTest();
        RingSenseWebhook.handleWebhook();
        Test.stopTest();
        System.assertEquals(500, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('enqueue_failed'));
        System.assert(
            [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'RingSense Webhook Error'] > 0
        );
    }

    @IsTest
    static void ingest_job_parses_payload() {
        String jsonBody =
            '{"body":{"callDirection":"Inbound","ownerExtensionId":"1","speakerInfo":[],"insights":{"Transcript":[{"text":"Hi"}]}}}';
        Test.startTest();
        System.enqueueJob(new CallInsightIngestJob(jsonBody));
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Call_Insight__c]);
    }
}