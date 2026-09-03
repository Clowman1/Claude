/**
 * Thin Zoom Server-to-Server client: token, JSON GET, and file download.
 *
 * Zoom's S2S token endpoint requires grant_type=account_credentials, not the
 * grant_type=client_credentials that Salesforce's native OAuth flow sends. Native
 * returns HTTP 200 with a token carrying only marketplace:* scopes, which then fails
 * every data call — so the token is requested here instead, through a Basic-auth
 * external credential that keeps the client secret out of Apex entirely.
 *
 * The token lives one hour and each job run is a single transaction, so it is held in
 * a static for the transaction and not cached across them.
 */
public without sharing class ZoomApiClient {
    private static String transactionToken;

    public class ZoomApiException extends Exception {}

    /** Access token for the Zoom account, acquired once per transaction. */
    public static String token() {
        if (transactionToken != null) return transactionToken;

        Zoom_Webhook_Config__mdt config = Zoom_Webhook_Config__mdt.getInstance('Organization_Default');
        String accountId = config == null ? null : config.Zoom_Account_Id__c;
        if (String.isBlank(accountId)) {
            throw new ZoomApiException('Zoom account ID is not set on Zoom_Webhook_Config.Organization_Default.');
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Zoom_S2S_Token/oauth/token?grant_type=account_credentials&account_id='
            + EncodingUtil.urlEncode(accountId, 'UTF-8'));
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        request.setBody('');
        request.setTimeout(60000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            throw new ZoomApiException('Zoom token request returned ' + response.getStatusCode() + ': ' + response.getBody());
        }
        Object accessToken = ((Map<String, Object>) JSON.deserializeUntyped(response.getBody())).get('access_token');
        if (accessToken == null) {
            throw new ZoomApiException('Zoom token response contained no access_token.');
        }
        transactionToken = String.valueOf(accessToken);
        return transactionToken;
    }

    /** GET a Zoom API path (e.g. '/v2/meetings/123/recordings') and return the parsed JSON. */
    public static Map<String, Object> getJson(String path) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Zoom_S2S_Api' + path);
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + token());
        request.setTimeout(60000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            throw new ZoomApiException('Zoom GET ' + path + ' returned ' + response.getStatusCode() + ': ' + response.getBody());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    }

    /**
     * POST a JSON body to a Zoom API path and return the parsed response.
     *
     * Needed for scheduling on another host's behalf: Zoom's schedule-for privilege is not
     * honoured for user-managed OAuth tokens, only for account-level ones, so those meetings
     * have to be created through this S2S client rather than the per-user named credential.
     */
    public static Map<String, Object> postJson(String path, Map<String, Object> payload) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Zoom_S2S_Api' + path);
        request.setMethod('POST');
        request.setHeader('Authorization', 'Bearer ' + token());
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(payload));
        request.setTimeout(60000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new ZoomApiException('Zoom POST ' + path + ' returned ' + response.getStatusCode() + ': ' + response.getBody());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    }

    /**
     * PATCH a Zoom API path. Zoom answers 204 with no body, so nothing is returned.
     *
     * Reschedules always go out over S2S even for a meeting the host booked themselves: the
     * edit arrives from whoever moved the Salesforce Event, and that user's own Zoom
     * connection has no rights over someone else's meeting.
     */
    public static void patchJson(String path, Map<String, Object> payload) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Zoom_S2S_Api' + path);
        request.setMethod('PATCH');
        request.setHeader('Authorization', 'Bearer ' + token());
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(payload));
        request.setTimeout(60000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new ZoomApiException('Zoom PATCH ' + path + ' returned ' + response.getStatusCode() + ': ' + response.getBody());
        }
    }

    /** DELETE a Zoom API path. A 404 counts as success — the meeting is already gone. */
    public static void deletePath(String path) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Zoom_S2S_Api' + path);
        request.setMethod('DELETE');
        request.setHeader('Authorization', 'Bearer ' + token());
        request.setTimeout(60000);

        HttpResponse response = new Http().send(request);
        Integer status = response.getStatusCode();
        if (status != 404 && (status < 200 || status >= 300)) {
            throw new ZoomApiException('Zoom DELETE ' + path + ' returned ' + status + ': ' + response.getBody());
        }
    }

    /**
     * Downloads a recording file. Zoom serves download_url from zoom.us and 302-redirects
     * to a pre-signed CloudFront URL on ssrweb.zoom.us. Apex does not follow redirects
     * automatically, and Zoom returns the header lowercased, so both cases are checked.
     * The signed URL carries its own authorisation, so no bearer token is sent on hop two.
     */
    public static String download(String downloadUrl) {
        if (String.isBlank(downloadUrl)) return null;

        HttpRequest request = new HttpRequest();
        request.setEndpoint(downloadUrl);
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + token());
        request.setTimeout(120000);
        HttpResponse response = new Http().send(request);

        if (response.getStatusCode() == 301 || response.getStatusCode() == 302) {
            String location = response.getHeader('location');
            if (location == null) location = response.getHeader('Location');
            if (String.isBlank(location)) {
                throw new ZoomApiException('Zoom download redirected with no location header.');
            }
            HttpRequest signed = new HttpRequest();
            signed.setEndpoint(location);
            signed.setMethod('GET');
            signed.setTimeout(120000);
            HttpResponse signedResponse = new Http().send(signed);
            if (signedResponse.getStatusCode() != 200) {
                throw new ZoomApiException('Zoom signed download returned ' + signedResponse.getStatusCode() + '.');
            }
            return signedResponse.getBody();
        }
        if (response.getStatusCode() != 200) {
            throw new ZoomApiException('Zoom download returned ' + response.getStatusCode() + '.');
        }
        return response.getBody();
    }
}