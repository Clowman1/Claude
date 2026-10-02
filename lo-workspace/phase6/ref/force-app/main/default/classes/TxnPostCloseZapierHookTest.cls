@IsTest
private class TxnPostCloseZapierHookTest {
    private static Integer callCount = 0;
    private static List<String> requestBodies = new List<String>();

    private class ZapierWebhookMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            requestBodies.add(req.getBody());
            System.assertEquals('https://hooks.zapier.com/hooks/catch/449994/4u772qa/', req.getEndpoint());
            System.assertEquals('POST', req.getMethod());
            System.assertEquals('application/json', req.getHeader('Content-Type'));

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('ok');
            return response;
        }
    }

    @IsTest
    static void sendsWebhookOnceForEligiblePostClosedTransaction() {
        Transaction__c txn = new Transaction__c(
            Status__c = 'Post-Closed',
            Biz_Dev__c = 'Biz Dev - Reach',
            Loan_Purpose__c = 'Purchase',
            Loan_Number__c = '1234567890'
        );
        insert txn;

        callCount = 0;
        requestBodies.clear();
        Test.setMock(HttpCalloutMock.class, new ZapierWebhookMock());

        TxnPostCloseZapierHook.Request requestItem = new TxnPostCloseZapierHook.Request();
        requestItem.transactionId = txn.Id;

        Test.startTest();
        TxnPostCloseZapierHook.send(new List<TxnPostCloseZapierHook.Request>{ requestItem });
        TxnPostCloseZapierHook.send(new List<TxnPostCloseZapierHook.Request>{ requestItem });
        Test.stopTest();

        Transaction__c updatedTxn = [
            SELECT Zapier_Post_Closed_Webhook_Sent_At__c
            FROM Transaction__c
            WHERE Id = :txn.Id
        ];

        System.assertEquals(1, callCount);
        System.assertNotEquals(null, updatedTxn.Zapier_Post_Closed_Webhook_Sent_At__c);
        System.assert(requestBodies[0].contains('"transactionId"'));
        System.assert(requestBodies[0].contains((String) txn.Id));
        System.assert(requestBodies[0].contains('"transaction"'));

        System.assertEquals(1, callCount);
    }

    @IsTest
    static void skipsNonMatchingTransactions() {
        Transaction__c txn = new Transaction__c(
            Status__c = 'Funding',
            Biz_Dev__c = 'Biz Dev - Reach',
            Loan_Purpose__c = 'Purchase',
            Loan_Number__c = '2222222222'
        );
        insert txn;

        callCount = 0;
        requestBodies.clear();
        Test.setMock(HttpCalloutMock.class, new ZapierWebhookMock());

        TxnPostCloseZapierHook.Request requestItem = new TxnPostCloseZapierHook.Request();
        requestItem.transactionId = txn.Id;

        Test.startTest();
        TxnPostCloseZapierHook.send(new List<TxnPostCloseZapierHook.Request>{ requestItem });
        Test.stopTest();

        Transaction__c updatedTxn = [
            SELECT Zapier_Post_Closed_Webhook_Sent_At__c
            FROM Transaction__c
            WHERE Id = :txn.Id
        ];

        System.assertEquals(0, callCount);
        System.assertEquals(null, updatedTxn.Zapier_Post_Closed_Webhook_Sent_At__c);
    }

    @IsTest
    static void includesPrimaryBorrowerDateOfBirth() {
        Id personRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'PersonAccount'
            LIMIT 1
        ].Id;
        Account borrower = new Account(
            RecordTypeId = personRt,
            FirstName = 'Dob',
            LastName = 'Tester',
            PersonBirthdate = Date.newInstance(1985, 3, 17),
            PersonMobilePhone = '+15551234567',
            PersonEmail = 'dob.tester@example.com'
        );
        insert borrower;

        Transaction__c txn = new Transaction__c(
            Status__c = 'Post-Closed',
            Biz_Dev__c = 'Biz Dev - Reach',
            Loan_Purpose__c = 'Purchase',
            Loan_Number__c = '3333333333',
            Borrower_Name__c = borrower.Id
        );
        insert txn;

        callCount = 0;
        requestBodies.clear();
        Test.setMock(HttpCalloutMock.class, new ZapierWebhookMock());

        TxnPostCloseZapierHook.Request requestItem = new TxnPostCloseZapierHook.Request();
        requestItem.transactionId = txn.Id;

        Test.startTest();
        TxnPostCloseZapierHook.send(new List<TxnPostCloseZapierHook.Request>{ requestItem });
        Test.stopTest();

        System.assertEquals(1, callCount);
        // Flat top-level keys are what Zapier can actually map; the nested
        // transaction.*__c paths do not resolve in LeadConnector.
        for (String expected : new List<String>{
                '"borrowerDateOfBirth":"1985-03-17"',
                '"borrowerFirstName":"Dob"',
                '"borrowerLastName":"Tester"',
                '"borrowerPhone":"+15551234567"',
                '"borrowerEmail":"dob.tester@example.com"'}) {
            System.assert(requestBodies[0].contains(expected),
                'Missing ' + expected + ' in payload: ' + requestBodies[0]);
        }
    }
}