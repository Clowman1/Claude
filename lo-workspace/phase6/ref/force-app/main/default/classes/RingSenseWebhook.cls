@RestResource(urlMapping='/rc_transcription')
global without sharing class RingSenseWebhook {
    @TestVisible
    private static Boolean throwOnEnqueue = false;

    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;

        String validationToken = req.headers?.get('Validation-Token');
        if (String.isNotBlank(validationToken)) {
            RestContext.response.addHeader('Validation-Token', validationToken);
            RestContext.response.addHeader('Content-Type', 'application/json');
        }

        RestContext.response.addHeader('Content-Type', 'application/json');

        String body = req.requestBody == null ? '' : req.requestBody.toString();

        if (String.isBlank(body)) {
            RestContext.response.responseBody = Blob.valueOf('{"status":"ok","detail":"empty"}');
            return;
        }

        try {
            if (throwOnEnqueue) {
                throw new CalloutException('forced_enqueue_failure');
            }
            System.enqueueJob(new CallInsightIngestJob(body));
            RestContext.response.responseBody = Blob.valueOf('{"status":"ok"}');
        } catch (Exception e) {
            CallInsightIngestionService.logWebhookError(
                e.getTypeName() + ': ' + e.getMessage() + ' | ' + e.getStackTraceString()
            );
            RestContext.response.statusCode = 500;
            RestContext.response.responseBody = Blob.valueOf('{"status":"error","message":"enqueue_failed"}');
        }
    }
}