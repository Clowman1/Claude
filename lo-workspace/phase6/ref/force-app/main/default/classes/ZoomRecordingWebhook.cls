@RestResource(urlMapping='/zoom/recording-webhook/*')
global without sharing class ZoomRecordingWebhook {
    @TestVisible private static String testSecret;
    @HttpPost
    global static void receive() {
        RestResponse response = RestContext.response;
        String body = RestContext.request.requestBody == null ? '' : RestContext.request.requestBody.toString();
        Map<String, Object> envelope;
        try {
            envelope = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception error) {
            respond(response, 400, new Map<String, Object>{ 'message' => 'Invalid JSON.' });
            return;
        }

        String eventName = (String) envelope.get('event');
        if (eventName == 'endpoint.url_validation') {
            Map<String, Object> payload = (Map<String, Object>) envelope.get('payload');
            String plainToken = payload == null ? null : (String) payload.get('plainToken');
            String secret = getSecret();
            if (String.isBlank(plainToken) || String.isBlank(secret)) {
                respond(response, 500, new Map<String, Object>{ 'message' => 'Webhook secret is not configured.' });
                return;
            }
            respond(response, 200, new Map<String, Object>{
                'plainToken' => plainToken,
                'encryptedToken' => signature(plainToken, secret)
            });
            return;
        }

        if (!isValidSignature(body, RestContext.request.headers.get('x-zm-request-timestamp'), RestContext.request.headers.get('x-zm-signature'))) {
            log('Zoom Webhook Rejected', 'Signature check failed for event "' + eventName
                + '". Compare the Secret Token in the Zoom app with Zoom_Webhook_Config.Organization_Default.');
            respond(response, 401, new Map<String, Object>{ 'message' => 'Invalid Zoom webhook signature.' });
            return;
        }
        if (eventName != 'recording.completed') {
            respond(response, 200, new Map<String, Object>{ 'received' => true });
            return;
        }

        Map<String, Object> payload = (Map<String, Object>) envelope.get('payload');
        Map<String, Object> recording = payload == null ? null : (Map<String, Object>) payload.get('object');
        if (recording == null) {
            respond(response, 400, new Map<String, Object>{ 'message' => 'Recording payload is missing.' });
            return;
        }
        // This endpoint is a delivery receipt, not an importer.
        //
        // It runs as the Integrations site guest user, and a Guest User License cannot be
        // granted read access to Zoom_Meeting__c records (no View All, and no sharing to
        // guest users), so the meeting lookup returns nothing no matter what field-level
        // security is granted. `without sharing` does not help: this is a license
        // restriction, not a sharing one. Guest users are also limited to read and create
        // on any object, never update.
        //
        // So the receipt is logged and ZoomRecordingSweepBatch does the actual ingestion
        // as an admin within the hour. If near-real-time ever matters, the upgrade path is
        // for this method to publish a Platform Event — its subscriber runs as the
        // Automated Process user and is not subject to guest restrictions.
        String zoomMeetingId = String.valueOf(recording.get('id'));
        Integer fileCount = recording.get('recording_files') instanceof List<Object>
            ? ((List<Object>) recording.get('recording_files')).size()
            : 0;

        log('Zoom Webhook Received', 'recording.completed for Zoom meeting ID ' + zoomMeetingId
            + ' with ' + fileCount + ' file(s). Ingestion happens on the next sweep.');
        respond(response, 200, new Map<String, Object>{
            'received' => true,
            'queued' => true,
            'message' => 'Logged. Ingestion runs on the scheduled sweep.'
        });
    }

    private static void log(String source, String data) {
        try {
            insert new Custom_Log__c(Source__c = source, Data__c = data);
        } catch (Exception ignored) {
            System.debug(LoggingLevel.WARN, 'ZoomRecordingWebhook: could not write Custom_Log__c.');
        }
    }

    private static String getSecret() {
        if (Test.isRunningTest() && !String.isBlank(testSecret)) return testSecret;
        Zoom_Webhook_Config__mdt config = Zoom_Webhook_Config__mdt.getInstance('Organization_Default');
        return config == null ? null : config.Webhook_Secret__c;
    }

    private static Boolean isValidSignature(String body, String timestamp, String incomingSignature) {
        String secret = getSecret();
        if (String.isBlank(secret) || String.isBlank(timestamp) || String.isBlank(incomingSignature)) return false;
        return incomingSignature.toLowerCase() == 'v0=' + signature('v0:' + timestamp + ':' + body, secret).toLowerCase();
    }

    private static String signature(String text, String secret) {
        return EncodingUtil.convertToHex(Crypto.generateMac('HmacSHA256', Blob.valueOf(text), Blob.valueOf(secret)));
    }

    private static void respond(RestResponse response, Integer statusCode, Map<String, Object> payload) {
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}