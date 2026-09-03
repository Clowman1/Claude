@IsTest
private class ZoomEventSyncTest {
    private class ZoomMock implements HttpCalloutMock {
        public String lastMethod;
        public String lastEndpoint;
        public String lastBody;
        public HTTPResponse respond(HTTPRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().contains('oauth/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"s2s-test-token","expires_in":3600}');
                return response;
            }
            lastMethod = request.getMethod();
            lastEndpoint = request.getEndpoint();
            lastBody = request.getBody();
            response.setStatusCode(204);
            response.setBody('');
            return response;
        }
    }

    private static Zoom_Meeting__c scheduledMeeting(Datetime startsAt) {
        Lead lead = new Lead(LastName = 'Zoom Sync', Company = 'Reach', Email = 'borrower@example.com');
        insert lead;
        Event calendarEvent = new Event(
            Subject = 'Zoom: Borrower Review',
            WhoId = lead.Id,
            StartDateTime = startsAt,
            EndDateTime = startsAt.addMinutes(30)
        );
        insert calendarEvent;
        Zoom_Meeting__c meeting = new Zoom_Meeting__c(
            Lead__c = lead.Id,
            Zoom_Meeting_Id__c = '987654321',
            Join_URL__c = 'https://zoom.us/j/987654321',
            Topic__c = 'Borrower Review',
            Scheduled_Start__c = startsAt,
            Duration_Minutes__c = 30,
            Status__c = 'Scheduled',
            Salesforce_Event_Id__c = calendarEvent.Id,
            Host_Email__c = UserInfo.getUserEmail(),
            Invite_Sequence__c = 0,
            Invitee_Emails__c = 'borrower@example.com; realtor@example.com'
        );
        insert meeting;
        return meeting;
    }

    @IsTest
    static void movingTheEventReschedulesZoomAndTheMeetingRecord() {
        Datetime original = Datetime.newInstance(Date.today().addDays(7), Time.newInstance(14, 0, 0, 0));
        Zoom_Meeting__c meeting = scheduledMeeting(original);
        ZoomMock mock = new ZoomMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Datetime moved = original.addDays(2);
        Test.startTest();
        update new Event(Id = (Id) meeting.Salesforce_Event_Id__c, StartDateTime = moved, EndDateTime = moved.addMinutes(45));
        Test.stopTest();

        Zoom_Meeting__c synced = [
            SELECT Scheduled_Start__c, Duration_Minutes__c, Invite_Sequence__c, Status__c
            FROM Zoom_Meeting__c WHERE Id = :meeting.Id
        ];
        System.assertEquals('PATCH', mock.lastMethod, 'Zoom must be told the meeting moved');
        System.assertEquals(true, mock.lastEndpoint.endsWith('/v2/meetings/987654321'), 'Endpoint was ' + mock.lastEndpoint);
        System.assertEquals(true, mock.lastBody.contains('"duration":45'), 'The new duration must go to Zoom: ' + mock.lastBody);
        System.assertEquals(moved, synced.Scheduled_Start__c, 'The meeting record must follow the calendar');
        System.assertEquals(45, Integer.valueOf(synced.Duration_Minutes__c));
        System.assertEquals(1, Integer.valueOf(synced.Invite_Sequence__c), 'A reschedule is the next sequence of the same invitation');
        System.assertEquals('Scheduled', synced.Status__c);
    }

    @IsTest
    static void deletingTheEventCancelsTheZoomMeeting() {
        Datetime original = Datetime.newInstance(Date.today().addDays(7), Time.newInstance(14, 0, 0, 0));
        Zoom_Meeting__c meeting = scheduledMeeting(original);
        ZoomMock mock = new ZoomMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        delete new Event(Id = (Id) meeting.Salesforce_Event_Id__c);
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod, 'The Zoom meeting must be cancelled too');
        System.assertEquals(
            'Cancelled',
            [SELECT Status__c FROM Zoom_Meeting__c WHERE Id = :meeting.Id].Status__c
        );
    }

    /** A meeting already in the past is housekeeping, not a cancellation. */
    @IsTest
    static void deletingAPastEventLeavesZoomAlone() {
        Zoom_Meeting__c meeting = scheduledMeeting(System.now().addDays(-3));
        ZoomMock mock = new ZoomMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        delete new Event(Id = (Id) meeting.Salesforce_Event_Id__c);
        Test.stopTest();

        System.assertEquals(null, mock.lastMethod, 'Zoom must not be called for a meeting that already happened');
        System.assertEquals(
            'Scheduled',
            [SELECT Status__c FROM Zoom_Meeting__c WHERE Id = :meeting.Id].Status__c
        );
    }

    /** Nothing on the Event that Zoom cares about changed, so nothing should go out. */
    @IsTest
    static void unrelatedEventEditsAreIgnored() {
        Zoom_Meeting__c meeting = scheduledMeeting(Datetime.newInstance(Date.today().addDays(7), Time.newInstance(14, 0, 0, 0)));
        ZoomMock mock = new ZoomMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        update new Event(Id = (Id) meeting.Salesforce_Event_Id__c, Description = 'Added a note.');
        Test.stopTest();

        System.assertEquals(null, mock.lastMethod, 'A description edit is not a reschedule');
        System.assertEquals(0, Integer.valueOf([SELECT Invite_Sequence__c FROM Zoom_Meeting__c WHERE Id = :meeting.Id].Invite_Sequence__c));
    }
}
