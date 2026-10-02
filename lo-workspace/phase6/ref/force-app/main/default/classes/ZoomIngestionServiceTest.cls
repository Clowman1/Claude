@IsTest
private class ZoomIngestionServiceTest {

    private static final String WITH_LEAD = '99900011122';
    private static final String NO_LEAD = '99900011133';
    private static final String PRE_SEEDED = '99900011144';

    /**
     * Data is created in @TestSetup rather than inline: Apex forbids a callout after
     * uncommitted DML in the same transaction, and every test here makes callouts.
     */
    @TestSetup
    static void makeData() {
        Lead lead = new Lead(FirstName = 'Test', LastName = 'Borrower', Company = 'Test', Email = 'zoomtest@example.com');
        insert lead;

        Zoom_Meeting__c withLead = new Zoom_Meeting__c();
        withLead.put('Zoom_Meeting_Id__c', WITH_LEAD);
        withLead.put('Topic__c', 'Zoom Meeting - Test Borrower');
        withLead.put('Status__c', 'Scheduled');
        withLead.put('Lead__c', lead.Id);

        Zoom_Meeting__c withoutLead = new Zoom_Meeting__c();
        withoutLead.put('Zoom_Meeting_Id__c', NO_LEAD);
        withoutLead.put('Topic__c', 'Ad-hoc meeting, no Lead');
        withoutLead.put('Status__c', 'Scheduled');

        Zoom_Meeting__c preSeeded = new Zoom_Meeting__c();
        preSeeded.put('Zoom_Meeting_Id__c', PRE_SEEDED);
        preSeeded.put('Topic__c', 'Already partly ingested');
        preSeeded.put('Status__c', 'Scheduled');
        preSeeded.put('Lead__c', lead.Id);

        insert new List<Zoom_Meeting__c>{ withLead, withoutLead, preSeeded };

        // Simulates a prior sweep: one insight and one recording already exist. A test
        // method cannot ingest twice (DML then callout is illegal in one transaction),
        // so the second run is modelled as pre-existing data instead.
        SObject existing = Schema.getGlobalDescribe().get('Call_Insight__c').newSObject();
        existing.put('Source__c', 'Zoom');
        existing.put('Zoom_Meeting__c', preSeeded.Id);
        existing.put('Lead__c', lead.Id);
        existing.put('Summary__c', 'stale summary from the previous run');
        insert existing;

        Zoom_Recording__c alreadyThere = new Zoom_Recording__c();
        alreadyThere.put('Zoom_Meeting__c', preSeeded.Id);
        alreadyThere.put('Zoom_Recording_File_Id__c', 'file-mp4-preseeded');
        alreadyThere.put('File_Type__c', 'Video');
        alreadyThere.put('Status__c', 'Available');
        insert alreadyThere;
    }

    private static Id meetingId(String zoomId) {
        return [SELECT Id FROM Zoom_Meeting__c WHERE Zoom_Meeting_Id__c = :zoomId LIMIT 1].Id;
    }

    /** Dispatches on endpoint so one mock covers token, list, transcript and summary. */
    private class ZoomMock implements HttpCalloutMock {
        private Boolean includeSummary;
        private ZoomMock(Boolean includeSummary) { this.includeSummary = includeSummary; }

        public HttpResponse respond(HttpRequest request) {
            String endpoint = request.getEndpoint();
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (endpoint.contains('/oauth/token')) {
                response.setBody('{"access_token":"test-token","expires_in":3599}');
            } else if (endpoint.contains('/recordings')) {
                String summaryFile = includeSummary
                    ? ',{"id":"file-summary","file_type":"SUMMARY","status":"completed","download_url":"https://zoom.us/rec/download/summary"}'
                    : '';
                response.setBody(
                    '{"recording_play_passcode":"passcode-abc","recording_files":[' +
                    '{"id":"file-mp4","file_type":"MP4","status":"completed","play_url":"https://zoom.us/rec/play/mp4",' +
                    '"recording_start":"2026-08-20T15:29:19Z","recording_end":"2026-08-20T15:53:34Z"},' +
                    '{"id":"file-timeline","file_type":"TIMELINE","status":"completed"},' +
                    '{"id":"file-transcript","file_type":"TRANSCRIPT","status":"completed","download_url":"https://zoom.us/rec/download/transcript"}' +
                    summaryFile + ']}'
                );
            } else if (endpoint.contains('/download/transcript')) {
                response.setBody('WEBVTT\r\n\r\n1\r\n00:00:01.000 --> 00:00:02.000\r\nZach Fritz: Hello there.\r\n');
            } else if (endpoint.contains('/download/summary')) {
                response.setBody('{"total_items":1,"overall_summary":"Discussed the pre-approval.",' +
                    '"items":[{"label":"Pre-approval review","summary":"Walked through documents needed."}]}');
            }
            return response;
        }
    }

    @IsTest
    static void storesTranscriptAndSummaryOnCallInsight() {
        Id target = meetingId(WITH_LEAD);
        Test.setMock(HttpCalloutMock.class, new ZoomMock(true));

        Test.startTest();
        ZoomIngestionService.Result result = ZoomIngestionService.ingest(target);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(3, result.recordingsStored,
            'MP4, TRANSCRIPT and SUMMARY are stored; only TIMELINE is skipped');
        System.assertEquals(true, result.summaryFound, 'Summary file should have been parsed');
        System.assertNotEquals(null, result.callInsightId, 'A Call_Insight__c should exist');

        Call_Insight__c insight = [
            SELECT Source__c, Lead__c, Zoom_Meeting__c, Transcript__c, Summary__c, Bulleted_Summary__c, Title__c
            FROM Call_Insight__c WHERE Id = :result.callInsightId
        ];
        System.assertEquals('Zoom', insight.Source__c);
        System.assertEquals(target, insight.Zoom_Meeting__c);
        System.assertNotEquals(null, insight.Lead__c, 'The insight must inherit the meeting Lead');
        System.assertEquals('Zach Fritz: Hello there.', insight.Transcript__c, 'Transcript should be cleaned, not raw VTT');
        System.assertEquals('Discussed the pre-approval.', insight.Summary__c);
        System.assert(insight.Bulleted_Summary__c.contains('Pre-approval review'),
            'Smart chapters should populate the bulleted summary');

        Zoom_Meeting__c reloaded = [SELECT Status__c, Last_Sync_Attempt__c FROM Zoom_Meeting__c WHERE Id = :target];
        System.assertEquals('Completed', reloaded.Status__c);
        System.assertNotEquals(null, reloaded.Last_Sync_Attempt__c);

        System.assertEquals('passcode-abc',
            [SELECT Play_Passcode__c FROM Zoom_Recording__c WHERE Zoom_Recording_File_Id__c = 'file-mp4'].Play_Passcode__c,
            'The play passcode must be captured; recordings made before the Zoom setting changed still require it');
    }

    @IsTest
    static void leavesMeetingOpenWhenTranscriptHasNotArrivedYet() {
        // Zoom publishes media first and the transcript minutes later. Marking the meeting
        // Completed on media alone stopped the sweep before the transcript existed, which
        // permanently lost it for a real 28-minute borrower call.
        Id target = meetingId(WITH_LEAD);
        Test.setMock(HttpCalloutMock.class, new MediaOnlyMock());

        Test.startTest();
        ZoomIngestionService.Result result = ZoomIngestionService.ingest(target);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Media without a transcript is not a finished ingestion');
        System.assertEquals(true, result.skipped);
        System.assertEquals(2, result.recordingsStored, 'The media files are still worth storing');
        System.assertEquals('Scheduled',
            [SELECT Status__c FROM Zoom_Meeting__c WHERE Id = :target].Status__c,
            'The meeting must stay open so the next sweep retries for the transcript');
        System.assertNotEquals(null,
            [SELECT Last_Sync_Attempt__c FROM Zoom_Meeting__c WHERE Id = :target].Last_Sync_Attempt__c,
            'The attempt is still recorded so the 7-day expiry can fire');
    }

    /** Media only — what Zoom returns in the minutes right after a recording finishes. */
    private class MediaOnlyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            if (request.getEndpoint().contains('/oauth/token')) {
                response.setBody('{"access_token":"test-token"}');
            } else {
                response.setBody('{"recording_play_passcode":"pc","recording_files":[' +
                    '{"id":"media-mp4","file_type":"MP4","status":"completed","play_url":"https://zoom.us/rec/play/m"},' +
                    '{"id":"media-m4a","file_type":"M4A","status":"completed","play_url":"https://zoom.us/rec/play/a"}]}');
            }
            return response;
        }
    }

    @IsTest
    static void readsBothSummaryFilesNotJustTheLast() {
        // Zoom returns two SUMMARY files that differ only by recording_type. Keying on
        // file_type alone kept whichever arrived last, so a real call lost either its
        // summary or its next steps depending on Zoom's ordering.
        String summaryFile = '{"total_items":1,"overall_summary":"Reviewed two loan scenarios.",' +
            '"items":[{"label":"Scenario comparison","summary":"Walked through both options."}]}';
        Map<String, String> fromSummary = ZoomIngestionService.parseSummary(summaryFile);
        System.assertEquals('Reviewed two loan scenarios.', fromSummary.get('Summary__c'));
        System.assert(fromSummary.get('Bulleted_Summary__c').contains('Scenario comparison'));

        String nextStepsFile = '{"total_items":2,"is_group_by_person":true,"items":[' +
            '{"action_item_text":"Send the PDF with both scenarios.","assignee_name":"Joe"},' +
            '{"action_item_text":"Review and decide.","assignee_name":"paulcoen"}]}';
        String nextSteps = ZoomIngestionService.parseNextSteps(nextStepsFile);
        System.assertEquals('Joe: Send the PDF with both scenarios.\npaulcoen: Review and decide.', nextSteps,
            'Action items carry action_item_text and assignee_name, not the label/summary pair');

        // The next-steps shape must not be mistaken for a smart-chapters file.
        System.assertEquals(0, ZoomIngestionService.parseSummary('{"items":[{"action_item_text":"x"}]}').size(),
            'An action-item file has no summary or chapters to offer');
        System.assertEquals(null, ZoomIngestionService.parseNextSteps('not json'));
        System.assertEquals(null, ZoomIngestionService.parseNextSteps('{"items":[]}'));
    }

    @IsTest
    static void skipsMeetingWithNoLead() {
        Id target = meetingId(NO_LEAD);
        Test.setMock(HttpCalloutMock.class, new ZoomMock(true));

        Test.startTest();
        ZoomIngestionService.Result result = ZoomIngestionService.ingest(target);
        Test.stopTest();

        System.assertEquals(true, result.skipped, 'A meeting with no Lead must be skipped');
        System.assertEquals(false, result.success);
        System.assertEquals(0, [SELECT COUNT() FROM Call_Insight__c WHERE Zoom_Meeting__c = :target],
            'Nothing may be stored for a meeting that cannot be tied to a Lead');
    }

    @IsTest
    static void updatesExistingInsightRatherThanDuplicating() {
        Id target = meetingId(PRE_SEEDED);
        Test.setMock(HttpCalloutMock.class, new ZoomMock(true));

        Test.startTest();
        ZoomIngestionService.Result result = ZoomIngestionService.ingest(target);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(1, [SELECT COUNT() FROM Call_Insight__c WHERE Zoom_Meeting__c = :target],
            'A re-run must update the existing insight, not create a second');
        System.assertEquals('Discussed the pre-approval.',
            [SELECT Summary__c FROM Call_Insight__c WHERE Zoom_Meeting__c = :target].Summary__c,
            'The stale summary from the previous run must be refreshed');
        System.assertEquals(4, [SELECT COUNT() FROM Zoom_Recording__c WHERE Zoom_Meeting__c = :target],
            'The pre-existing recording survives and the three new files are added');
        System.assertEquals('passcode-abc',
            [SELECT Play_Passcode__c FROM Zoom_Recording__c WHERE Zoom_Recording_File_Id__c = 'file-mp4'].Play_Passcode__c,
            'Upsert must refresh rows, not skip them — insert left old rows missing new fields');
    }

    @IsTest
    static void handlesMissingSummaryFile() {
        Id target = meetingId(WITH_LEAD);
        Test.setMock(HttpCalloutMock.class, new ZoomMock(false));

        Test.startTest();
        ZoomIngestionService.Result result = ZoomIngestionService.ingest(target);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(false, result.summaryFound, 'No summary file means no summary fields');
        Call_Insight__c insight = [SELECT Transcript__c, Summary__c FROM Call_Insight__c WHERE Id = :result.callInsightId];
        System.assertNotEquals(null, insight.Transcript__c, 'The transcript alone is still worth storing');
        System.assertEquals(null, insight.Summary__c);
    }

    @IsTest
    static void logsAndReportsApiFailure() {
        Id target = meetingId(WITH_LEAD);
        Test.setMock(HttpCalloutMock.class, new FailingMock());

        Test.startTest();
        ZoomIngestionService.Result result = ZoomIngestionService.ingest(target);
        Test.stopTest();

        System.assertEquals(false, result.success, 'A Zoom error must not report success');
        System.assertNotEquals(null, result.message);
        System.assert([SELECT COUNT() FROM Custom_Log__c WHERE Source__c = 'Zoom Ingestion Error'] > 0,
            'Failures must be logged, not swallowed — that is how the original bug went unnoticed');
    }

    private class FailingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().contains('/oauth/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"test-token"}');
            } else {
                response.setStatusCode(429);
                response.setBody('{"code":429,"message":"Too many requests"}');
            }
            return response;
        }
    }

    @IsTest
    static void parseSummaryToleratesJunk() {
        System.assertEquals(0, ZoomIngestionService.parseSummary(null).size());
        System.assertEquals(0, ZoomIngestionService.parseSummary('not json at all').size());
        System.assertEquals(0, ZoomIngestionService.parseSummary('{}').size());

        // next_steps and highlights were enabled after the earliest recordings, so the
        // parser must pick them up whenever they start appearing.
        Map<String, String> mapped = ZoomIngestionService.parseSummary(
            '{"overall_summary":"S","next_steps":["Send paystubs","Order appraisal"],"highlights":"H"}');
        System.assertEquals('S', mapped.get('Summary__c'));
        System.assertEquals('Send paystubs\nOrder appraisal', mapped.get('Next_Steps__c'));
        System.assertEquals('H', mapped.get('HighLights__c'));
    }
}