@IsTest
private class ZoomRecordingWebhookTest {
    private static final String SECRET = 'zoom-webhook-test-secret';

    @IsTest
    static void importsCompletedRecordingFromSignedWebhook() {
        ZoomRecordingWebhook.testSecret = SECRET;
        ZoomRecordingWebhookService.skipDmlForTest = true;

        String body = '{"event":"recording.completed","payload":{"object":{"id":2468013579,"recording_files":[{"id":"webhook-file-1","file_type":"MP4","play_url":"https://zoom.us/rec/play/webhook","recording_start":"2026-08-07T19:00:00Z","recording_end":"2026-08-07T19:01:00Z"}]}}}';
        String timestamp = '1723057200';
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/zoom/recording-webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader('x-zm-request-timestamp', timestamp);
        request.addHeader('x-zm-signature', 'v0=' + hmac('v0:' + timestamp + ':' + body));
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        ZoomRecordingWebhook.receive();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, ((Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString())).get('received'));
    }

    @IsTest
    static void returnsZoomChallengeResponse() {
        ZoomRecordingWebhook.testSecret = SECRET;
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/zoom/recording-webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{"event":"endpoint.url_validation","payload":{"plainToken":"zoom-challenge"}}');
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        ZoomRecordingWebhook.receive();
        Test.stopTest();

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('zoom-challenge', response.get('plainToken'));
        System.assertEquals(hmac('zoom-challenge'), response.get('encryptedToken'));
    }

    @IsTest
    static void rejectsWebhookWithInvalidSignature() {
        ZoomRecordingWebhook.testSecret = SECRET;
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/zoom/recording-webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{"event":"recording.completed","payload":{"object":{"id":2468013579}}}');
        request.addHeader('x-zm-request-timestamp', '1723057200');
        request.addHeader('x-zm-signature', 'v0=not-valid');
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        ZoomRecordingWebhook.receive();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest
    static void rejectsMalformedPayload() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/zoom/recording-webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('not-json');
        RestContext.request = request;
        RestContext.response = new RestResponse();

        ZoomRecordingWebhook.receive();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void skipsNonMediaFileTypesAndMapsTheRest() {
        // Live Zoom payloads carry CHAT, TIMELINE and CC files. TIMELINE has no
        // play_url, so storing any of them produced dead links labelled "Video".
        System.assertEquals(null, ZoomRecordingWebhookService.mapRecordingType('TIMELINE'), 'TIMELINE must be skipped');
        System.assertEquals(null, ZoomRecordingWebhookService.mapRecordingType('CHAT'), 'CHAT must be skipped');
        System.assertEquals(null, ZoomRecordingWebhookService.mapRecordingType('CC'), 'CC must be skipped');
        System.assertEquals('Video', ZoomRecordingWebhookService.mapRecordingType('MP4'));
        System.assertEquals('Audio', ZoomRecordingWebhookService.mapRecordingType('M4A'));
        System.assertEquals('Transcript', ZoomRecordingWebhookService.mapRecordingType('TRANSCRIPT'));
        System.assertEquals('Summary', ZoomRecordingWebhookService.mapRecordingType('SUMMARY'));

        // A real five-file payload should yield three stored rows, not five.
        ZoomRecordingWebhookService.skipDmlForTest = true;
        List<Object> files = (List<Object>) JSON.deserializeUntyped(
            '[{"id":"f1","file_type":"MP4","play_url":"https://zoom.us/rec/play/a"},' +
            '{"id":"f2","file_type":"TRANSCRIPT","play_url":"https://zoom.us/rec/play/b"},' +
            '{"id":"f3","file_type":"CHAT","play_url":"https://zoom.us/rec/play/c"},' +
            '{"id":"f4","file_type":"M4A","play_url":"https://zoom.us/rec/play/d"},' +
            '{"id":"f5","file_type":"TIMELINE"}]'
        );
        Integer stored = ZoomRecordingWebhookService.importRecordingFiles(Id.valueOf('a2e000000000001AAA'), files);
        System.assertEquals(3, stored, 'CHAT and TIMELINE must not be stored');
    }

    @IsTest
    static void logsReceiptForMatchedEvent() {
        ZoomRecordingWebhook.testSecret = SECRET;

        String body = '{"event":"recording.completed","payload":{"object":{"id":98318597742,"recording_files":[{"id":"f1","file_type":"MP4"},{"id":"f2","file_type":"TRANSCRIPT"}]}}}';
        String timestamp = '1723057200';
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/zoom/recording-webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader('x-zm-request-timestamp', timestamp);
        request.addHeader('x-zm-signature', 'v0=' + hmac('v0:' + timestamp + ':' + body));
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        ZoomRecordingWebhook.receive();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Custom_Log__c entry = [SELECT Data__c FROM Custom_Log__c WHERE Source__c = 'Zoom Webhook Received' LIMIT 1];
        System.assert(entry.Data__c.contains('98318597742'), 'The receipt must name the Zoom meeting ID');
        System.assert(entry.Data__c.contains('2 file'), 'The receipt must record how many files Zoom reported');
    }

    @IsTest
    static void rejectedSignatureIsLogged() {
        ZoomRecordingWebhook.testSecret = SECRET;
        String body = '{"event":"recording.completed","payload":{"object":{"id":1}}}';
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/zoom/recording-webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader('x-zm-request-timestamp', '1723057200');
        request.addHeader('x-zm-signature', 'v0=deadbeef');
        RestContext.request = request;
        RestContext.response = new RestResponse();

        ZoomRecordingWebhook.receive();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assert([SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'Zoom Webhook Rejected'] > 0,
            'A rejected signature must leave a trace naming the likely cause');
    }

    private static String hmac(String text) {
        return EncodingUtil.convertToHex(Crypto.generateMac('HmacSHA256', Blob.valueOf(text), Blob.valueOf(SECRET)));
    }
}