/**
 * LO Workspace, Phase 6: inbound landing-page leads.
 *
 * POST https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/lo-landing-page
 * Header  X-Reach-Webhook-Key: <LO_Landing_Page_Config__mdt.Default.Webhook_Secret__c>
 * Body    JSON, see LoWsLeadIntakeService.processLandingPage for the keys (loEmail identifies the LO).
 *
 * Runs as the Integrations site guest user, which may only read and create, never update (see
 * ZoomRecordingWebhook). A Nurturing takeover is an update, so this endpoint only authenticates,
 * sanity-checks and publishes LO_Workspace_Intake__e; its subscriber does the work as the
 * Automated Process user. Rejected calls are logged here, accepted ones by the subscriber.
 */
@RestResource(urlMapping='/lo-landing-page')
global without sharing class LoLandingPageWebhook {
    @TestVisible private static String testSecret;

    @HttpPost
    global static void receive() {
        RestResponse response = RestContext.response;
        String body = RestContext.request.requestBody == null ? '' : RestContext.request.requestBody.toString();
        String secret = getSecret();
        if (String.isBlank(secret)) {
            reject(response, 503, 'Webhook is not configured.', body);
            return;
        }
        String key = null;
        for (String h : RestContext.request.headers.keySet()) {
            if (h.equalsIgnoreCase('X-Reach-Webhook-Key')) key = RestContext.request.headers.get(h);
        }
        if (!secret.equals(key)) { // equals(): Apex == / != ignore case
            reject(response, 401, 'Invalid webhook key.', null); // never store an unauthenticated body
            return;
        }
        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            reject(response, 400, 'Body must be a JSON object.', body);
            return;
        }
        if (payload == null || payload.get('loEmail') == null) {
            reject(response, 400, 'loEmail is required.', body);
            return;
        }
        if (payload.containsKey('kind')) { // reserved for internal duplicate alerts on the same event
            reject(response, 400, '"kind" is not an accepted field.', body);
            return;
        }
        Database.SaveResult r = EventBus.publish(new LO_Workspace_Intake__e(Payload__c = body.left(32000)));
        if (!r.isSuccess()) {
            reject(response, 500, 'Could not queue the lead: ' + r.getErrors()[0].getMessage(), body);
            return;
        }
        respond(response, 202, new Map<String, Object>{ 'received' => true });
    }

    private static void reject(RestResponse response, Integer status, String message, String body) {
        try {
            insert new Custom_Log__c(
                Source__c = LoWsLeadIntakeService.LOG_SOURCE + ' Rejected',
                Data__c = ('HTTP ' + status + ': ' + message + (body == null ? '' : '\n\n' + body)).left(32000)
            );
        } catch (Exception ignored) {
            System.debug(LoggingLevel.WARN, 'LoLandingPageWebhook: could not write Custom_Log__c.');
        }
        respond(response, status, new Map<String, Object>{ 'received' => false, 'message' => message });
    }

    private static String getSecret() {
        if (Test.isRunningTest() && testSecret != null) return testSecret;
        LO_Landing_Page_Config__mdt config = LO_Landing_Page_Config__mdt.getInstance('Default');
        return config == null ? null : config.Webhook_Secret__c;
    }

    private static void respond(RestResponse response, Integer statusCode, Map<String, Object> payload) {
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}