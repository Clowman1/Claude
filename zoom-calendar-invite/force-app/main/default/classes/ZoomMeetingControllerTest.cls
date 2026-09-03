@IsTest
private class ZoomMeetingControllerTest {
    private class ZoomMock implements HttpCalloutMock {
        public String postEndpoint;
        public HTTPResponse respond(HTTPRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            if (request.getEndpoint().contains('oauth/token')) {
                // Scheduling for another host goes out over the Server-to-Server client,
                // which trades for an account token before it calls the meetings endpoint.
                response.setBody('{"access_token":"s2s-test-token","expires_in":3600}');
            } else if (request.getMethod() == 'POST') {
                postEndpoint = request.getEndpoint();
                response.setBody('{"id":987654321,"join_url":"https://zoom.us/j/987654321"}');
            } else if (request.getEndpoint().contains('/recordings')) {
                response.setBody('{"recording_files":[{"id":"recording-file-1","file_type":"MP4","play_url":"https://zoom.us/rec/play/example","recording_start":"2026-08-07T19:00:00Z","recording_end":"2026-08-07T19:00:42Z"}]}');
            } else {
                response.setBody('{"start_url":"https://zoom.us/s/987654321?zak=fresh"}');
            }
            return response;
        }
    }

    @IsTest
    static void createsAndLaunchesLeadZoomMeeting() {
        Lead lead = new Lead(LastName = 'Zoom Test', Company = 'Reach', Email = 'borrower@example.com');
        insert lead;
        Test.setMock(HttpCalloutMock.class, new ZoomMock());
        Test.startTest();
        ZoomMeetingController.ScheduleResult result = ZoomMeetingController.scheduleMeeting(
            lead.Id,
            'Borrower Review',
            System.now().addDays(1),
            30,
            'Review loan options.',
            lead.Email,
            'co.borrower@example.com;realtor@example.com',
            'Your Mortgage Pre-Approval Zoom Meeting',
            'Hello {LeadName}, join your meeting here: {ZoomLink} on {MeetingDateTime}.',
            null
        );
        Test.stopTest();
        System.assertEquals('https://zoom.us/j/987654321', result.joinUrl);
        Zoom_Meeting__c meeting = [SELECT Lead__c, Topic__c, Status__c, Salesforce_Event_Id__c, Recording_Requested__c FROM Zoom_Meeting__c WHERE Id = :result.meetingRecordId];
        System.assertEquals(lead.Id, meeting.Lead__c);
        System.assertEquals('Borrower Review', meeting.Topic__c);
        System.assertEquals('Scheduled', meeting.Status__c);
        System.assertNotEquals(null, meeting.Salesforce_Event_Id__c);
        System.assertEquals(true, meeting.Recording_Requested__c);
        System.assertEquals(true, result.invitationSent);
        System.assertEquals(1, ZoomMeetingController.getLeadContext(lead.Id).meetings.size());
    }

    @IsTest
    static void createsPersonAccountZoomMeeting() {
        Id personRecordType = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'PersonAccount' LIMIT 1
        ].Id;
        Account person = new Account(
            RecordTypeId = personRecordType,
            FirstName = 'Pat',
            LastName = 'Realtor',
            PersonEmail = 'pat.realtor@example.com'
        );
        insert person;

        Test.setMock(HttpCalloutMock.class, new ZoomMock());
        Test.startTest();
        ZoomMeetingController.ScheduleResult result = ZoomMeetingController.scheduleMeeting(
            person.Id,
            'Realtor Partnership Call',
            System.now().addDays(1),
            30,
            'Discuss referrals.',
            'pat.realtor@example.com',
            null,
            'Your Zoom Meeting',
            'Hello {LeadName}, join here: {ZoomLink} on {MeetingDateTime}.',
            null
        );
        Test.stopTest();

        Zoom_Meeting__c meeting = [
            SELECT Lead__c, Account__c, Topic__c, Status__c, Salesforce_Event_Id__c
            FROM Zoom_Meeting__c WHERE Id = :result.meetingRecordId
        ];
        System.assertEquals(person.Id, meeting.Account__c, 'The Account lookup must be set');
        System.assertEquals(null, meeting.Lead__c, 'A meeting has a Lead or an Account, never both');

        // An Event's WhoId accepts only a Lead or a Contact. For a Person Account that has
        // to be the PersonContactId — assigning the Account Id here throws at insert.
        Id personContactId = [SELECT PersonContactId FROM Account WHERE Id = :person.Id].PersonContactId;
        Event scheduled = [SELECT WhoId, WhatId, Subject FROM Event WHERE Id = :meeting.Salesforce_Event_Id__c];
        System.assertEquals(personContactId, scheduled.WhoId,
            'A Person Account Event must point at the person Contact, not the Account');

        System.assertEquals(1, ZoomMeetingController.getLeadContext(person.Id).meetings.size(),
            'The assistant must list the meeting back on the Account');
    }

    @IsTest
    static void rejectsAnInvalidInvitationEmail() {
        Lead lead = new Lead(LastName = 'Zoom Email Test', Company = 'Reach');
        insert lead;
        Boolean didThrow = false;
        try {
            ZoomMeetingController.scheduleMeeting(
                lead.Id, 'Borrower Review', System.now().addDays(1), 30, '', 'not-an-email', '', 'Subject', 'Body', null
            );
        } catch (AuraHandledException error) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow, 'An invalid email address should be rejected before Zoom is called.');
    }

    @IsTest
    static void rejectsMeetingsOutsideAllowedHours() {
        Lead lead = new Lead(LastName = 'Zoom Time Test', Company = 'Reach', Email = 'borrower@example.com');
        insert lead;
        Boolean didThrow = false;
        try {
            ZoomMeetingController.scheduleMeeting(
                lead.Id,
                'Late Meeting',
                Datetime.newInstance(Date.today().addDays(1), Time.newInstance(21, 15, 0, 0)),
                30,
                '',
                lead.Email,
                '',
                'Subject',
                'Body',
                null
            );
        } catch (AuraHandledException error) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow, 'Meetings after 9:00 PM should be rejected.');
    }

    @IsTest
    static void importsCompletedRecordingForMeeting() {
        Lead lead = new Lead(LastName = 'Zoom Recording Test', Company = 'Reach');
        insert lead;
        Zoom_Meeting__c meeting = new Zoom_Meeting__c(
            Lead__c = lead.Id,
            Zoom_Meeting_Id__c = '987654321',
            Topic__c = 'Recording Test',
            Scheduled_Start__c = System.now(),
            Duration_Minutes__c = 15,
            Status__c = 'Scheduled',
            Recording_Requested__c = true
        );
        insert meeting;
        Test.setMock(HttpCalloutMock.class, new ZoomMock());
        ZoomRecordingWebhookService.skipDmlForTest = true;
        Test.startTest();
        Integer imported = ZoomMeetingController.refreshRecordings(meeting.Id);
        Test.stopTest();
        System.assertEquals(1, imported);
    }

    @IsTest
    static void returnsFreshHostLaunchUrl() {
        Lead lead = new Lead(LastName = 'Zoom Start URL Test', Company = 'Reach');
        insert lead;
        Zoom_Meeting__c meeting = new Zoom_Meeting__c(
            Lead__c = lead.Id,
            Zoom_Meeting_Id__c = '2468013579',
            Topic__c = 'Start URL Test',
            Scheduled_Start__c = System.now(),
            Duration_Minutes__c = 15,
            Status__c = 'Scheduled'
        );
        insert meeting;
        Test.setMock(HttpCalloutMock.class, new ZoomMock());
        Test.startTest();
        String startUrl = ZoomMeetingController.getFreshStartUrl(meeting.Id);
        Test.stopTest();
        System.assertEquals('https://zoom.us/s/987654321?zak=fresh', startUrl);
    }
    /**
     * Scheduling on someone else's behalf must hit /v2/users/{their zoom email}/meetings
     * rather than /users/me, and hand the resulting Salesforce Event to that person.
     */
    @IsTest
    static void schedulesUnderAnotherHostsZoomAccount() {
        User host = new User(
            LastName = 'Zoom Host',
            Username = 'zoomhost' + System.currentTimeMillis() + '@reachhomeloans.com.zoomtest',
            Email = 'zoomhost@example.com',
            Alias = 'zhost',
            Zoom_Host_Email__c = 'events@example.com',
            TimeZoneSidKey = UserInfo.getTimeZone().getID(),
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert host;
        }
        Lead lead = new Lead(LastName = 'Zoom Host Test', Company = 'Reach', Email = 'borrower@example.com');
        insert lead;
        ZoomMock mock = new ZoomMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        ZoomMeetingController.ScheduleResult result = ZoomMeetingController.scheduleMeeting(
            lead.Id,
            'Host Review',
            Datetime.newInstance(Date.today().addDays(1), Time.newInstance(10, 0, 0, 0)),
            30,
            '',
            lead.Email,
            '',
            'Subject',
            'Body',
            host.Id
        );
        Test.stopTest();
        System.assertEquals(
            true,
            mock.postEndpoint.contains(EncodingUtil.urlEncode('events@example.com', 'UTF-8')),
            'The meeting must be created under the host Zoom account. Endpoint was: ' + mock.postEndpoint
        );
        System.assertEquals(
            host.Id,
            [SELECT OwnerId FROM Event WHERE Id = :result.eventId].OwnerId,
            'The Salesforce Event should belong to the host, not the scheduler.'
        );
        // The scheduler has to be an invitee, otherwise the meeting they booked never shows
        // up on their own calendar at all.
        System.assertEquals(
            1,
            [SELECT COUNT() FROM EventRelation WHERE EventId = :result.eventId AND RelationId = :UserInfo.getUserId() AND IsInvitee = true],
            'The scheduler should be invited to the event they booked.'
        );
        Zoom_Meeting__c meeting = [SELECT Host_Email__c, Invite_Sequence__c, Invitee_Emails__c FROM Zoom_Meeting__c WHERE Id = :result.meetingRecordId];
        System.assertEquals('zoomhost@example.com', meeting.Host_Email__c, 'The host to notify is the host user, not the scheduler.');
        System.assertEquals(0, Integer.valueOf(meeting.Invite_Sequence__c));
        System.assertEquals(
            true,
            meeting.Invitee_Emails__c.contains('borrower@example.com'),
            'Who was invited has to be kept, or a reschedule has nobody to notify.'
        );
    }
}