@IsTest
private class ZoomRecordingSweepBatchTest {

    private static final String DUE = '88800011122';
    private static final String NO_LEAD = '88800011133';
    private static final String FUTURE = '88800011144';
    private static final String EXPIRED = '88800011155';

    @TestSetup
    static void makeData() {
        Lead lead = new Lead(FirstName = 'Sweep', LastName = 'Borrower', Company = 'Test', Email = 'sweep@example.com');
        insert lead;

        List<Zoom_Meeting__c> meetings = new List<Zoom_Meeting__c>();
        meetings.add(build(DUE, 'Happened yesterday, needs pulling', lead.Id, System.now().addDays(-1)));
        meetings.add(build(NO_LEAD, 'Ad-hoc, no Lead', null, System.now().addDays(-1)));
        meetings.add(build(FUTURE, 'Not happened yet', lead.Id, System.now().addDays(2)));
        meetings.add(build(EXPIRED, 'Never produced a recording', lead.Id, System.now().addDays(-30)));
        insert meetings;
    }

    private static Zoom_Meeting__c build(String zoomId, String topic, Id leadId, Datetime startsAt) {
        Zoom_Meeting__c meeting = new Zoom_Meeting__c();
        meeting.put('Zoom_Meeting_Id__c', zoomId);
        meeting.put('Topic__c', topic);
        meeting.put('Status__c', 'Scheduled');
        meeting.put('Scheduled_Start__c', startsAt);
        if (leadId != null) meeting.put('Lead__c', leadId);
        return meeting;
    }

    private class SweepMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            if (request.getEndpoint().contains('/oauth/token')) {
                response.setBody('{"access_token":"tok"}');
            } else if (request.getEndpoint().contains('/recordings')) {
                response.setBody('{"recording_play_passcode":"pc","recording_files":[' +
                    '{"id":"sweep-transcript","file_type":"TRANSCRIPT","status":"completed",' +
                    '"download_url":"https://zoom.us/rec/download/transcript"}]}');
            } else {
                response.setBody('WEBVTT\r\n\r\n1\r\n00:00:01.000 --> 00:00:02.000\r\nZach Fritz: Ready to go.\r\n');
            }
            return response;
        }
    }

    @IsTest
    static void sweepsOnlyPastMeetingsThatHaveALead() {
        Test.setMock(HttpCalloutMock.class, new SweepMock());

        Test.startTest();
        ZoomRecordingSweepBatch.start();
        Test.stopTest();

        Id dueId = [SELECT Id FROM Zoom_Meeting__c WHERE Zoom_Meeting_Id__c = :DUE].Id;
        System.assertEquals(1, [SELECT COUNT() FROM Call_Insight__c WHERE Zoom_Meeting__c = :dueId],
            'The due meeting should have been ingested');
        System.assertEquals('Completed',
            [SELECT Status__c FROM Zoom_Meeting__c WHERE Zoom_Meeting_Id__c = :DUE].Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'ApplicationSummaryService'],
            'A Lead meeting with a transcript must queue the Application Summary');

        System.assertEquals('Scheduled',
            [SELECT Status__c FROM Zoom_Meeting__c WHERE Zoom_Meeting_Id__c = :NO_LEAD].Status__c,
            'A meeting with no Lead must be left alone entirely');
        System.assertEquals('Scheduled',
            [SELECT Status__c FROM Zoom_Meeting__c WHERE Zoom_Meeting_Id__c = :FUTURE].Status__c,
            'A meeting that has not happened yet must not be swept');
        System.assertEquals(0, [SELECT COUNT() FROM Call_Insight__c WHERE Source__c = 'Zoom'
            AND Zoom_Meeting__r.Zoom_Meeting_Id__c = :NO_LEAD],
            'Nothing may be stored for a meeting with no Lead');
    }

    @IsTest
    static void marksExpiredMeetingsAndStopsRetrying() {
        Test.setMock(HttpCalloutMock.class, new SweepMock());

        Test.startTest();
        ZoomRecordingSweepBatch.start();
        Test.stopTest();

        System.assertEquals('Error',
            [SELECT Status__c FROM Zoom_Meeting__c WHERE Zoom_Meeting_Id__c = :EXPIRED].Status__c,
            'Past the lookback window a meeting is a permanent miss and must stop being retried');
        System.assert([SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'Zoom Recording Sweep'] > 0,
            'The sweep must leave a record of what it did');
    }

    @IsTest
    static void schedulerLaunchesTheBatch() {
        Test.setMock(HttpCalloutMock.class, new SweepMock());
        Test.startTest();
        String jobId = System.schedule('Zoom Sweep Test', '0 0 1 * * ?', new ZoomRecordingSweepScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}