@IsTest
private class RingSenseSubscriptionServiceTest {
    private static final String WEBHOOK =
        'https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/rc_transcription';
    private static final String FILTER = '/ai/ringsense/v1/public/accounts/~/domains/pbx/insights';

    @IsTest
    static void getStatus_lists_subscriptions() {
        ensureAppAuth();
        insert new Call_Insight__c(Title__c = 'Health');
        Test.setMock(HttpCalloutMock.class, new RouteMock(false, false, true));
        Test.startTest();
        RingSenseSubscriptionService.StatusResult result = RingSenseSubscriptionController.getStatus();
        Test.stopTest();
        System.assertEquals(true, result.success, result.message);
        System.assertEquals(1, result.subscriptions.size());
        System.assertEquals('Active', result.subscriptions[0].status);
        System.assertNotEquals(null, result.lastCallInsightCreatedDate);
    }

    @IsTest
    static void reregister_renews_matching_active() {
        ensureAppAuth();
        Test.setMock(HttpCalloutMock.class, new RouteMock(false, false, true));
        Test.startTest();
        RingSenseSubscriptionService.StatusResult result = RingSenseSubscriptionController.reregister();
        Test.stopTest();
        System.assertEquals(true, result.success, result.message);
        System.assert(result.message.contains('Renewed'), result.message);
    }

    @IsTest
    static void reregister_creates_when_missing() {
        ensureAppAuth();
        Test.setMock(HttpCalloutMock.class, new RouteMock(false, true, false));
        Test.startTest();
        RingSenseSubscriptionService.StatusResult result = RingSenseSubscriptionService.reregister();
        Test.stopTest();
        System.assertEquals(true, result.success, result.message);
        System.assert(result.message.contains('Created'), result.message);
    }

    @IsTest
    static void getStatus_auth_failure_logs() {
        ensureAppAuth();
        Test.setMock(HttpCalloutMock.class, new RouteMock(true, false, false));
        Test.startTest();
        RingSenseSubscriptionService.StatusResult result = RingSenseSubscriptionService.getStatus();
        Test.stopTest();
        System.assertEquals(false, result.success);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'RingSense Subscription']
        );
    }

    @IsTest
    static void getStatus_maps_non_matching_and_partial_records() {
        ensureAppAuth();
        RouteMock mock = new RouteMock(false, false, false);
        mock.partialRecords = true;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        RingSenseSubscriptionService.StatusResult result = RingSenseSubscriptionService.getStatus();
        Test.stopTest();
        System.assertEquals(true, result.success, result.message);
        System.assertEquals(4, result.subscriptions.size());
    }

    @IsTest
    static void reregister_creates_when_existing_is_not_active() {
        ensureAppAuth();
        RouteMock mock = new RouteMock(false, false, true);
        mock.forceInactive = true;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        RingSenseSubscriptionService.StatusResult result = RingSenseSubscriptionService.reregister();
        Test.stopTest();
        System.assertEquals(true, result.success, result.message);
        System.assert(result.message.contains('Created'), result.message);
    }

    @IsTest
    static void ringCentralApi_consumers_and_models_are_covered() {
        ensureAppAuth();
        Test.setMock(HttpCalloutMock.class, new RouteMock(false, false, true));
        Test.startTest();
        RingCentralApi_Models.GetUserCallRecordsResponse calls =
            new RingCentralApi.GetUserCallRecords('tok', null, '').consume();
        RingCentralApi_Models.GetUserCallRecordsResponse callsDated =
            new RingCentralApi.GetUserCallRecords('tok', null, '2026-01-01').consume();
        RingCentralApi_Models.GetUserCallRecordsResponse callsNext =
            new RingCentralApi.GetUserCallRecords('tok', 'https://platform.ringcentral.com/restapi/v1.0/account/~/call-log?page=2', null).consume();
        RingCentralApi_Models.MessageStoreResponse msgs =
            new RingCentralApi.GetUserMessageRecords('tok', null, '123', '').consume();
        RingCentralApi_Models.MessageStoreResponse msgsDated =
            new RingCentralApi.GetUserMessageRecords('tok', null, '123', '2026-01-01').consume();
        RingCentralApi_Models.MessageStoreResponse msgsNext =
            new RingCentralApi.GetUserMessageRecords(
                'tok',
                'https://platform.ringcentral.com/restapi/v1.0/account/~/extension/123/message-store?page=2',
                '123',
                null
            ).consume();
        Test.stopTest();
        System.assertNotEquals(null, calls);
        System.assertNotEquals(null, callsDated);
        System.assertNotEquals(null, callsNext);
        System.assertNotEquals(null, msgs);
        System.assertNotEquals(null, msgsDated);
        System.assertNotEquals(null, msgsNext);

        RingCentralApi_Models.TokenResponse token = new RingCentralApi_Models.TokenResponse();
        token.access_token = 'a';
        token.token_type = 'Bearer';
        System.assertEquals('a', token.getAccessToken());
        System.assertEquals('Bearer', token.getTokenType());
        System.assertNotEquals(null, RingCentralApi_Models.parseRCTime('2026-01-01T00:00:00.000Z'));
        System.assertEquals('a=1&b=2', RingCentralApi.urlEncode(new Map<String, String>{ 'a' => '1', 'b' => '2' }));
    }

    private static void ensureAppAuth() {
        RingCentralAppAuth__c existing = RingCentralAppAuth__c.getOrgDefaults();
        if (existing.Id == null) {
            existing.SetupOwnerId = UserInfo.getOrganizationId();
            existing.ClientId__c = 'test-client';
            existing.ClientSecret__c = 'test-secret';
            insert existing;
        }
    }

    private class RouteMock implements HttpCalloutMock {
        Boolean failAuth;
        Boolean emptyList;
        Boolean matchingActive;
        Boolean partialRecords;
        Boolean forceInactive;

        RouteMock(Boolean failAuth, Boolean emptyList, Boolean matchingActive) {
            this.failAuth = failAuth;
            this.emptyList = emptyList;
            this.matchingActive = matchingActive;
            this.partialRecords = false;
            this.forceInactive = false;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            if (endpoint != null && endpoint.contains('/oauth/token')) {
                if (failAuth) {
                    res.setStatusCode(401);
                    res.setBody('{"error":"invalid_client"}');
                    return res;
                }
                res.setStatusCode(200);
                res.setBody('{"access_token":"test_access_token","token_type":"Bearer"}');
                return res;
            }
            if (endpoint != null && endpoint.contains('call-log')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"records":[{"id":"1","direction":"Inbound","fromObj":{"phoneNumber":"+1"},"to":{"phoneNumber":"+2"}}],' +
                    '"paging":{"page":1},"navigation":{"nextPage":{"uri":"https://next"}}}'
                );
                return res;
            }
            if (endpoint != null && endpoint.contains('message-store')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"uri":"u","records":[{"id":1,"fromObj":{"phoneNumber":"+1"},"to":[{"phoneNumber":"+2"}],' +
                    '"attachments":[{"id":1,"uri":"a"}],"conversation":{"id":"c"}}],' +
                    '"paging":{"page":1},"navigation":{"nextPage":{"uri":"https://next"}}}'
                );
                return res;
            }
            if (req.getMethod() == 'GET' && endpoint != null && endpoint.contains('/subscription') && !endpoint.contains('/subscription/')) {
                res.setStatusCode(200);
                res.setBody(listJson());
                return res;
            }
            if (req.getMethod() == 'POST' && endpoint != null && endpoint.endsWith('/subscription')) {
                res.setStatusCode(200);
                res.setBody(recordJson('created-id', 'Active'));
                return res;
            }
            if (req.getMethod() == 'PUT') {
                res.setStatusCode(200);
                res.setBody(recordJson('42fd4022-4a55-49a1-9cac-8f851a60b72b', 'Active'));
                return res;
            }
            res.setStatusCode(404);
            res.setBody('{}');
            return res;
        }

        private String listJson() {
            if (emptyList) {
                return '{"uri":"https://platform.ringcentral.com/restapi/v1.0/subscription","records":[]}';
            }
            if (partialRecords) {
                return '{"uri":"https://platform.ringcentral.com/restapi/v1.0/subscription","records":[' +
                    '{"id":"no-mode","status":"Active","eventFilters":["' + FILTER + '"]},' +
                    '{"id":"wrong-addr","status":"Active","eventFilters":["' + FILTER + '"],' +
                    '"deliveryMode":{"address":"https://other.example/hook","transportType":"WebHook"}},' +
                    '{"id":"no-filters","status":"Active","deliveryMode":{"address":"' + WEBHOOK + '","transportType":"WebHook"}},' +
                    '{"id":"other-filter","status":"Active","eventFilters":["/other"],' +
                    '"deliveryMode":{"address":"' + WEBHOOK + '","transportType":"WebHook"}}' +
                    ']}';
            }
            if (matchingActive) {
                String status = forceInactive ? 'Blacklisted' : 'Active';
                return '{"uri":"https://platform.ringcentral.com/restapi/v1.0/subscription","records":[' +
                    recordJson('42fd4022-4a55-49a1-9cac-8f851a60b72b', status) +
                    ']}';
            }
            return '{"uri":"https://platform.ringcentral.com/restapi/v1.0/subscription","records":[]}';
        }

        private String recordJson(String id, String status) {
            return '{' +
                '"uri":"https://platform.ringcentral.com/restapi/v1.0/subscription/' +
                id +
                '",' +
                '"id":"' +
                id +
                '",' +
                '"status":"' +
                status +
                '",' +
                '"eventFilters":["' +
                FILTER +
                '"],' +
                '"expirationTime":"2036-08-15T14:45:43.061Z",' +
                '"expiresIn":315359628,' +
                '"deliveryMode":{"address":"' +
                WEBHOOK +
                '","transportType":"WebHook","encryption":false}' +
                '}';
        }
    }
}