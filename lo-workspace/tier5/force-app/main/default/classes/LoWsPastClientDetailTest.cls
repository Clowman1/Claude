@isTest
private class LoWsPastClientDetailTest {

    private static Account insertClient() {
        Account client = LoWsPartnerTagService.newPastClient('Pat', 'Client', null, '4075550101', 'pat.client@example.com', 'Orlando', null);
        client.Most_Recent_Loan_Amount__c = 300000;
        client.Most_Recent_Closing_Date__c = Date.today().addYears(-2);
        insert client;
        return client;
    }

    @isTest
    static void detail_listsLoansAndLoggedCalls() {
        Account client = insertClient();
        Account person = [SELECT PersonContactId FROM Account WHERE Id = :client.Id];
        insert new Transaction__c(
            Name = 'Client Loan',
            Borrower_Name__c = client.Id,
            Loan_Officer__c = UserInfo.getUserId(),
            Status__c = 'Post-Closed',
            Closing_Date__c = Date.today().addYears(-1),
            Loan_Amount_1st__c = 310000,
            Property_Address__c = '1 Lake Dr',
            Property_City__c = 'Orlando'
        );
        insert new Task(Subject = 'Call', Type = 'Call', Status = 'Completed', WhoId = person.PersonContactId,
            WhatId = client.Id, ActivityDate = Date.today());

        Test.startTest();
        ExternalLoPortalService.PastClientDetail detail = ExternalLoPortalController.getPastClientDetail(client.Id);
        Test.stopTest();

        System.assertEquals('Pat', detail.firstName);
        System.assertEquals(true, detail.isOwner);
        System.assertEquals(true, detail.isPastClient);
        System.assertEquals(1, detail.loans.size());
        System.assertEquals(true, detail.loans[0].canOpen);
        System.assert(detail.loans[0].propertyAddress.contains('1 Lake Dr'));
        System.assertEquals(1, detail.loggedCalls.size());
        System.assertNotEquals(null, detail.recentLoanAmount);
    }

    @isTest
    static void detail_refusesNonAccountIds() {
        try {
            ExternalLoPortalController.getPastClientDetail(UserInfo.getUserId());
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('could not be found'), e.getMessage());
        }
    }

    @isTest
    static void accountWorkspaceView_routesClientsAndRealtors() {
        Account client = insertClient();
        Account realtor = LoWsPartnerTagService.newPastClient('Rae', 'Realtor', null, '4075550102', 'rae.realtor@example.com', null, null);
        realtor.Group__pc = 'Realtor';
        realtor.Type__c = null;
        Account other = LoWsPartnerTagService.newPastClient('Ollie', 'Other', null, '4075550103', 'ollie.other@example.com', null, null);
        other.Group__pc = null;
        insert new List<Account>{ realtor, other };

        System.assertEquals('pastClients', ExternalLoPortalController.getAccountWorkspaceView(client.Id));
        System.assertEquals('realtors', ExternalLoPortalController.getAccountWorkspaceView(realtor.Id));
        System.assertEquals(null, ExternalLoPortalController.getAccountWorkspaceView(other.Id));
        System.assertEquals(null, ExternalLoPortalController.getAccountWorkspaceView(null));
        System.assertEquals(null, ExternalLoPortalController.getAccountWorkspaceView(UserInfo.getUserId()));
    }
}