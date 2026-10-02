@isTest(SeeAllData=true)
private class RealtorEventRsvpServiceTest {
    @isTest static void recordsYesRsvpFromSecureLink() {
        Id personAccountRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Account attendee = new Account(RecordTypeId = personAccountRecordTypeId, FirstName = 'RSVP', LastName = 'Guest', PersonEmail = 'rsvp.guest@example.com');
        insert attendee;
        attendee = [SELECT PersonContactId FROM Account WHERE Id = :attendee.Id];
        Campaign campaign = new Campaign(Name = 'RSVP test', Type = 'Event', StartDate = Date.today());
        insert campaign;
        // getWorkspace is read-only now; adding an invitee is what provisions the RSVP statuses.
        RealtorEventWorkspaceController.addInvitees(campaign.Id, new List<Id>{ attendee.PersonContactId });
        CampaignMember member = [SELECT Id FROM CampaignMember WHERE CampaignId = :campaign.Id];
        member.Status = 'Invitation Sent';
        member.Event_Invite_Token__c = 'test-token';
        update member;
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/event-rsvp';
        request.httpMethod = 'POST';
        request.params.put('m', member.Id);
        request.params.put('t', 'test-token');
        request.params.put('r', 'Yes');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        Test.startTest();
        RealtorEventRsvpService.submitResponse();
        Test.stopTest();
        System.assertEquals('Yes - Attending', [SELECT Status FROM CampaignMember WHERE Id = :member.Id].Status);
        System.assertEquals(200, RestContext.response.statusCode);
    }

    @isTest static void rendersRsvpConfirmationPage() {
        Id personAccountRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Account attendee = new Account(RecordTypeId = personAccountRecordTypeId, FirstName = 'Preview', LastName = 'Guest');
        insert attendee;
        attendee = [SELECT PersonContactId FROM Account WHERE Id = :attendee.Id];
        Campaign campaign = new Campaign(Name = 'RSVP preview test', Type = 'Event', StartDate = Date.today());
        insert campaign;
        RealtorEventWorkspaceController.getWorkspace(campaign.Id);
        CampaignMember member = new CampaignMember(CampaignId = campaign.Id, ContactId = attendee.PersonContactId, Status = 'Invitation Sent', Event_Invite_Token__c = 'preview-token');
        insert member;
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/event-rsvp';
        request.httpMethod = 'GET';
        request.params.put('m', member.Id);
        request.params.put('t', 'preview-token');
        request.params.put('r', 'No');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        Test.startTest();
        RealtorEventRsvpService.previewResponse();
        Test.stopTest();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('Confirm response'));
    }

    @isTest static void servesPublicInvitationArtwork() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/event-rsvp';
        request.httpMethod = 'GET';
        request.params.put('asset', 'coffee-lunch');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        Test.startTest();
        RealtorEventRsvpService.previewResponse();
        Test.stopTest();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertNotEquals(null, RestContext.response.responseBody);
        System.assert(RestContext.response.responseBody.size() > 0);
    }
}