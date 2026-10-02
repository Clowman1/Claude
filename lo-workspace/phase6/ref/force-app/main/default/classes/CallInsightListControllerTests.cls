@IsTest
public class CallInsightListControllerTests {

    @IsTest
    public static void testGetCallInsights() {

        Account a = new Account(Name = 'Test');
        insert a;

        Lead l = new Lead(LastName = 'Test');
        insert l;

        Test.startTest();
        CallInsightListController.getCallInsights(l.Id, 'RingSense');
        CallInsightListController.getCallInsights(a.Id, 'RingSense');
        CallInsightListController.getCallInsights(l.Id, 'Zoom');
        Test.stopTest();
    }

    /**
     * The two tabs must partition the same object: nothing may appear in both, and
     * nothing may be dropped. RingSense rows predate Source__c and are null, which is
     * why its filter is "not Zoom" rather than "= RingSense".
     */
    @IsTest
    public static void sourceFilterPartitionsInsightsWithNoOverlap() {
        Lead lead = new Lead(LastName = 'Partition', Company = 'Test');
        insert lead;

        List<SObject> insights = new List<SObject>();
        insights.add(newInsight(lead.Id, 'Zoom', 'zoom row'));
        insights.add(newInsight(lead.Id, 'RingSense', 'ringsense row'));
        insights.add(newInsight(lead.Id, null, 'legacy row with no source'));
        insert insights;

        Test.startTest();
        List<Call_Insight__c> zoomRows = CallInsightListController.getCallInsights(lead.Id, 'Zoom');
        List<Call_Insight__c> otherRows = CallInsightListController.getCallInsights(lead.Id, 'RingSense');
        Test.stopTest();

        System.assertEquals(1, zoomRows.size(), 'The Zoom tab shows only Zoom-sourced insights');
        System.assertEquals('Zoom', zoomRows[0].Source__c);
        System.assertEquals(2, otherRows.size(),
            'The RingSense tab must include legacy rows whose Source__c is null');
        for (Call_Insight__c row : otherRows) {
            System.assertNotEquals('Zoom', row.Source__c, 'A Zoom row must never appear on the RingSense tab');
        }
    }

    @IsTest
    public static void zoomRecordingsExcludeUnplayableFiles() {
        Zoom_Meeting__c meeting = new Zoom_Meeting__c();
        meeting.put('Zoom_Meeting_Id__c', '77700011122');
        meeting.put('Topic__c', 'Recording tab test');
        meeting.put('Status__c', 'Completed');
        insert meeting;

        // Recordings are only returned for meetings with an insight on a record the user can open.
        Lead lead = new Lead(LastName = 'Recording', Company = 'Test');
        insert lead;
        SObject insight = newInsight(lead.Id, 'Zoom', 'recording row');
        insight.put('Zoom_Meeting__c', meeting.Id);
        insert insight;

        List<Zoom_Recording__c> files = new List<Zoom_Recording__c>();
        files.add(newRecording(meeting.Id, 'rec-video', 'Video', 'https://zoom.us/rec/play/v', 'Available'));
        files.add(newRecording(meeting.Id, 'rec-audio', 'Audio', 'https://zoom.us/rec/play/a', 'Available'));
        // No play URL: this is what a TIMELINE file looks like, and it rendered as a dead link.
        files.add(newRecording(meeting.Id, 'rec-nourl', 'Video', null, 'Available'));
        // Deleted in Zoom: the link would 404.
        files.add(newRecording(meeting.Id, 'rec-gone', 'Video', 'https://zoom.us/rec/play/g', 'Deleted'));
        insert files;

        Test.startTest();
        List<Zoom_Recording__c> playable = CallInsightListController.getZoomRecordings(new List<Id>{ meeting.Id });
        List<Zoom_Recording__c> none = CallInsightListController.getZoomRecordings(new List<Id>());
        List<Zoom_Recording__c> nullArg = CallInsightListController.getZoomRecordings(null);
        Test.stopTest();

        System.assertEquals(2, playable.size(),
            'Only playable, available files belong on the Recording tab');
        for (Zoom_Recording__c file : playable) {
            System.assertNotEquals(null, file.Play_URL__c);
            System.assertEquals('Available', file.Status__c);
        }
        System.assertEquals(0, none.size(), 'No meetings means no query');
        System.assertEquals(0, nullArg.size(), 'A null argument must not throw');
    }

    private static Zoom_Recording__c newRecording(Id meetingId, String fileId, String type, String url, String status) {
        Zoom_Recording__c recording = new Zoom_Recording__c();
        recording.put('Zoom_Meeting__c', meetingId);
        recording.put('Zoom_Recording_File_Id__c', fileId);
        recording.put('File_Type__c', type);
        recording.put('Play_URL__c', url);
        recording.put('Status__c', status);
        return recording;
    }

    private static SObject newInsight(Id leadId, String source, String title) {
        SObject insight = Schema.getGlobalDescribe().get('Call_Insight__c').newSObject();
        insight.put('Lead__c', leadId);
        insight.put('Title__c', title);
        if (source != null) insight.put('Source__c', source);
        return insight;
    }
}