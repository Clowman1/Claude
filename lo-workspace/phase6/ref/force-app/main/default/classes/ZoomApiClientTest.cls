@IsTest
private class ZoomApiClientTest {

    private class Responder implements HttpCalloutMock {
        private Integer tokenStatus;
        private String tokenBody;
        private Integer dataStatus;
        private String locationHeader;

        private Responder(Integer tokenStatus, String tokenBody, Integer dataStatus, String locationHeader) {
            this.tokenStatus = tokenStatus;
            this.tokenBody = tokenBody;
            this.dataStatus = dataStatus;
            this.locationHeader = locationHeader;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().contains('/oauth/token')) {
                response.setStatusCode(tokenStatus);
                response.setBody(tokenBody);
                return response;
            }
            response.setStatusCode(dataStatus);
            response.setBody('{"code":' + dataStatus + ',"message":"nope"}');
            if (locationHeader != null) response.setHeader('location', locationHeader);
            return response;
        }
    }

    private static Responder happyToken(Integer dataStatus, String location) {
        return new Responder(200, '{"access_token":"tok"}', dataStatus, location);
    }

    @IsTest
    static void tokenFailureIsLoudNotSilent() {
        Test.setMock(HttpCalloutMock.class, new Responder(401, '{"error":"invalid_client"}', 200, null));
        Test.startTest();
        try {
            ZoomApiClient.token();
            System.assert(false, 'A rejected token must throw, not return null');
        } catch (ZoomApiClient.ZoomApiException expected) {
            System.assert(expected.getMessage().contains('401'), expected.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void tokenResponseWithoutAccessTokenThrows() {
        Test.setMock(HttpCalloutMock.class, new Responder(200, '{"scope":"marketplace:read"}', 200, null));
        Test.startTest();
        try {
            ZoomApiClient.token();
            System.assert(false, 'A token response with no access_token must throw');
        } catch (ZoomApiClient.ZoomApiException expected) {
            System.assert(expected.getMessage().contains('no access_token'), expected.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void getJsonSurfacesHttpErrors() {
        Test.setMock(HttpCalloutMock.class, happyToken(429, null));
        Test.startTest();
        try {
            ZoomApiClient.getJson('/v2/meetings/1/recordings');
            System.assert(false, 'A 429 must throw rather than return an empty map');
        } catch (ZoomApiClient.ZoomApiException expected) {
            System.assert(expected.getMessage().contains('429'), expected.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void downloadHandlesBlankUrlAndBadRedirect() {
        Test.setMock(HttpCalloutMock.class, happyToken(302, null));
        Test.startTest();
        System.assertEquals(null, ZoomApiClient.download(null), 'A blank URL is a no-op, not an error');
        try {
            // A 302 with no location header is unrecoverable and must not be mistaken for content.
            ZoomApiClient.download('https://zoom.us/rec/download/abc');
            System.assert(false, 'A redirect with no location header must throw');
        } catch (ZoomApiClient.ZoomApiException expected) {
            System.assert(expected.getMessage().contains('location'), expected.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void downloadFailureThrows() {
        Test.setMock(HttpCalloutMock.class, happyToken(404, null));
        Test.startTest();
        try {
            ZoomApiClient.download('https://zoom.us/rec/download/abc');
            System.assert(false, 'A 404 download must throw');
        } catch (ZoomApiClient.ZoomApiException expected) {
            System.assert(expected.getMessage().contains('404'), expected.getMessage());
        }
        Test.stopTest();
    }
}