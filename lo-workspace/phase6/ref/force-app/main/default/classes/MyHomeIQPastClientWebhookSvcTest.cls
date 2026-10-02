@IsTest
private class MyHomeIQPastClientWebhookSvcTest {
    private static final String TEST_ENDPOINT = 'https://api.myhomeiq.report/test/webhooks';
    private static Integer requestCount = 0;
    private static Map<String, Object> lastPayload;

    @IsTest
    static void sendsForReachPrimaryOccupancyTransitionToPostClosed() {
        Transaction__c qualifying = createTransaction('Funding', 'Biz Dev - Reach', 'Primary Residence');
        Transaction__c investment = createTransaction('Funding', 'Biz Dev - Reach', 'Investment');
        Transaction__c secondHome = createTransaction('Funding', 'Biz Dev - Reach', 'Second Home');
        Transaction__c noOccupancy = createTransaction('Funding', 'Biz Dev - Reach', null);
        Transaction__c otherBizDev = createTransaction('Funding', 'Biz Dev - Pugh', 'Primary Residence');
        insert new List<Transaction__c>{
            qualifying, investment, secondHome, noOccupancy, otherBizDev
        };

        resetMock();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        for (Transaction__c transactionRecord : new List<Transaction__c>{
            qualifying, investment, secondHome, noOccupancy, otherBizDev
        }) {
            transactionRecord.Status__c = 'Post-Closed';
        }
        update new List<Transaction__c>{
            qualifying, investment, secondHome, noOccupancy, otherBizDev
        };
        Test.stopTest();

        System.assertEquals(1, requestCount,
            'Only the Reach primary-occupancy Transaction should be sent.');
        System.assertEquals(
            String.valueOf(qualifying.Id),
            String.valueOf(lastPayload.get('transactionId'))
        );
        System.assertEquals('PastClientPostClosed', lastPayload.get('eventType'));
        System.assertEquals('Biz Dev - Reach', lastPayload.get('bizDev'));
        System.assertEquals('Primary Residence', lastPayload.get('occupancy'));
        System.assertEquals('Funding', lastPayload.get('oldStatus'));
        System.assertEquals('Post-Closed', lastPayload.get('newStatus'));

        Map<String, Object> transactionFields =
            (Map<String, Object>) lastPayload.get('transactionFields');
        System.assert(transactionFields.size() > 10,
            'Expected the full Transaction field set in the payload.');
        System.assertEquals(transactionFields.size(), lastPayload.get('transactionFieldCount'));
        System.assertEquals('Post-Closed', transactionFields.get('Status__c'));
        System.assertEquals('Primary Residence', transactionFields.get('Occupancy__c'));
    }

    /**
     * Occupancy holds legacy spellings that are not in the picklist value set,
     * so prove the end-to-end path fires for one of them and not just for the
     * canonical 'Primary Residence'.
     */
    @IsTest
    static void sendsForLegacyPrimaryOccupancySpelling() {
        Transaction__c legacyPrimary = createTransaction('Funding', 'Biz Dev - Reach', 'Primary');
        insert legacyPrimary;

        resetMock();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        legacyPrimary.Status__c = 'Post-Closed';
        update legacyPrimary;
        Test.stopTest();

        System.assertEquals(1, requestCount,
            'The legacy "Primary" occupancy value should still be sent.');
        System.assertEquals('Primary', lastPayload.get('occupancy'));
    }

    /**
     * A DPA 2nd is a companion down-payment-assistance lien on the same
     * borrower as a real first mortgage, so it must never be sent.
     */
    @IsTest
    static void excludesDpaSecondLien() {
        Transaction__c realFirst =
            createTransaction('Funding', 'Biz Dev - Reach', 'Primary Residence');
        realFirst.Loan_Type_1st_TD__c = 'Conventional';
        Transaction__c dpaSecond =
            createTransaction('Funding', 'Biz Dev - Reach', 'Primary Residence');
        dpaSecond.Loan_Type_1st_TD__c = 'DPA 2nd';
        dpaSecond.Loan_Amount_1st__c = 10000;
        insert new List<Transaction__c>{ realFirst, dpaSecond };

        resetMock();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        realFirst.Status__c = 'Post-Closed';
        dpaSecond.Status__c = 'Post-Closed';
        update new List<Transaction__c>{ realFirst, dpaSecond };
        Test.stopTest();

        System.assertEquals(1, requestCount,
            'The DPA 2nd companion lien must not be sent.');
        System.assertEquals(
            String.valueOf(realFirst.Id),
            String.valueOf(lastPayload.get('transactionId')),
            'Only the real first mortgage should be sent.'
        );
        System.assertEquals('Conventional', lastPayload.get('loanType'));
    }

    /**
     * SOQL NOT LIKE can silently drop rows whose field is null, so pin the
     * behaviour: a blank loan type is not a DPA and must still send.
     */
    @IsTest
    static void sendsWhenLoanTypeIsBlank() {
        Transaction__c noLoanType =
            createTransaction('Funding', 'Biz Dev - Reach', 'Primary Residence');
        noLoanType.Loan_Type_1st_TD__c = null;
        insert noLoanType;

        resetMock();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        noLoanType.Status__c = 'Post-Closed';
        update noLoanType;
        Test.stopTest();

        System.assertEquals(1, requestCount,
            'A blank loan type must not be treated as a DPA 2nd.');
    }

    @IsTest
    static void recognizesDpaLoanTypeVariants() {
        for (String dpaValue : new List<String>{ 'DPA 2nd', 'dpa 2nd', 'DPA2nd', 'DPA' }) {
            System.assert(
                MyHomeIQPastClientWebhookSvc.isDpaSecondLien(dpaValue),
                'Expected this value to count as a DPA lien: ' + dpaValue
            );
        }

        for (String nonDpaValue : new List<String>{
            null, '', 'Conventional', 'CONV', 'FHA', 'VA', 'Jumbo', 'NonQM', 'HELOC', 'Other'
        }) {
            System.assert(
                !MyHomeIQPastClientWebhookSvc.isDpaSecondLien(nonDpaValue),
                'Expected this value not to count as a DPA lien: ' + nonDpaValue
            );
        }
    }

    @IsTest
    static void doesNotSendWhenAlreadyPostClosed() {
        Transaction__c transactionRecord =
            createTransaction('Post-Closed', 'Biz Dev - Reach', 'Primary Residence');
        insert transactionRecord;

        resetMock();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        transactionRecord.Loan_Number__c = '1526000999';
        update transactionRecord;
        Test.stopTest();

        System.assertEquals(0, requestCount,
            'Editing a Transaction that is already Post-Closed must not resend.');
        System.assertEquals(0, MyHomeIQPastClientWebhookSvc.enqueuedJobCount,
            'Expected no queued job when the status did not transition.');
    }

    @IsTest
    static void recognizesLegacyPrimaryOccupancyValues() {
        for (String primaryValue : new List<String>{
            'Primary Residence', 'Primary', 'PrimaryResidence', 'primary residence', 'PRIMARY'
        }) {
            System.assert(
                MyHomeIQPastClientWebhookSvc.isPrimaryOccupancy(primaryValue),
                'Expected this value to count as primary occupancy: ' + primaryValue
            );
        }

        for (String nonPrimaryValue : new List<String>{
            null, '', 'Investment', 'Investment - Rental', 'Second Home', '2ndHome',
            'SecondHome', 'Investor'
        }) {
            System.assert(
                !MyHomeIQPastClientWebhookSvc.isPrimaryOccupancy(nonPrimaryValue),
                'Expected this value not to count as primary occupancy: ' + nonPrimaryValue
            );
        }
    }

    @IsTest
    static void ignoresEmptyAndNullInput() {
        resetMock();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        MyHomeIQPastClientWebhookSvc.enqueueForStatusChanges(null, null);
        MyHomeIQPastClientWebhookSvc.send(null);
        MyHomeIQPastClientWebhookSvc.send(
            new List<MyHomeIQPastClientWebhookSvc.StatusChange>()
        );
        Test.stopTest();

        System.assertEquals(0, requestCount, 'Expected no callout for empty input.');
    }

    @IsTest
    static void throwsWhenMyHomeIQRejectsThePayload() {
        Transaction__c transactionRecord =
            createTransaction('Post-Closed', 'Biz Dev - Reach', 'Primary Residence');
        insert transactionRecord;

        resetMock();
        Test.setMock(HttpCalloutMock.class, new FailureMock());

        Boolean threw = false;
        Test.startTest();
        try {
            MyHomeIQPastClientWebhookSvc.send(
                new List<MyHomeIQPastClientWebhookSvc.StatusChange>{
                    new MyHomeIQPastClientWebhookSvc.StatusChange(
                        transactionRecord.Id, 'Funding', 'Post-Closed'
                    )
                }
            );
        } catch (MyHomeIQPastClientWebhookSvc.WebhookException expected) {
            threw = true;
            System.assert(expected.getMessage().contains('401'),
                'Expected the HTTP status in the failure message.');
        }
        Test.stopTest();

        System.assert(threw, 'Expected a WebhookException on a non-2xx response.');
    }

    private static void resetMock() {
        requestCount = 0;
        lastPayload = null;
        MyHomeIQPastClientWebhookSvc.enqueuedJobCount = 0;
        MyHomeIQPastClientWebhookSvc.endpointOverride = TEST_ENDPOINT;
    }

    private static Transaction__c createTransaction(String status, String bizDev, String occupancy) {
        return new Transaction__c(
            Name = 'MyHomeIQ Test ' + status + ' ' + bizDev + ' ' + occupancy,
            Status__c = status,
            Biz_Dev__c = bizDev,
            Occupancy__c = occupancy,
            Loan_Number__c = '1526000001',
            Loan_Amount_1st__c = 425000
        );
    }

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            // The same trigger also drives the pre-existing Zapier post-close
            // hook, so only count requests aimed at MyHomeIQ.
            if (request.getEndpoint() == TEST_ENDPOINT) {
                requestCount++;
                lastPayload = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                System.assertEquals('POST', request.getMethod());
                System.assertEquals('application/json', request.getHeader('Content-Type'));
            }

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"status":"ok"}');
            return response;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            requestCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(401);
            response.setBody('{"errors":[{"detail":"Missing api-key header"}]}');
            return response;
        }
    }
}