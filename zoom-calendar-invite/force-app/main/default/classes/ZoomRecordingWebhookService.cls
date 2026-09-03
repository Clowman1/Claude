public without sharing class ZoomRecordingWebhookService {
    // Zoom returns CHAT, TIMELINE and CC files alongside the media. None are playable
    // recordings, and TIMELINE carries no play_url at all, so storing them mislabels
    // them as Video and puts dead links in the UI.
    private static final Set<String> IGNORED_FILE_TYPES = new Set<String>{ 'CHAT', 'TIMELINE', 'CC' };

    @TestVisible static Boolean skipDmlForTest = false;

    public static Integer importRecordingFiles(Id zoomMeetingRecordId, List<Object> rawFiles) {
        return importRecordingFiles(zoomMeetingRecordId, rawFiles, null);
    }

    public static Integer importRecordingFiles(Id zoomMeetingRecordId, List<Object> rawFiles, String playPasscode) {
        if (zoomMeetingRecordId == null || rawFiles == null) return 0;

        List<Zoom_Recording__c> recordings = new List<Zoom_Recording__c>();
        for (Object rawFile : rawFiles) {
            Map<String, Object> file = (Map<String, Object>) rawFile;
            String recordingFileId = String.valueOf(file.get('id'));
            if (String.isBlank(recordingFileId) || recordingFileId == 'null') continue;
            String fileType = mapRecordingType((String) file.get('file_type'));
            if (fileType == null) continue;
            Datetime recordingStart = parseZoomDateTime((String) file.get('recording_start'));
            Datetime recordingEnd = parseZoomDateTime((String) file.get('recording_end'));
            Zoom_Recording__c recording = new Zoom_Recording__c();
            recording.put('Zoom_Meeting__c', zoomMeetingRecordId);
            recording.put('Zoom_Recording_File_Id__c', recordingFileId);
            recording.put('File_Type__c', fileType);
            recording.put('Play_URL__c', (String) file.get('play_url'));
            recording.put('Play_Passcode__c', playPasscode);
            recording.put('Recording_Start__c', recordingStart);
            recording.put('Duration_Seconds__c', recordingStart == null || recordingEnd == null ? null : Decimal.valueOf(String.valueOf((recordingEnd.getTime() - recordingStart.getTime()) / 1000)));
            recording.put('Status__c', 'Available');
            recordings.add(recording);
        }
        if (Test.isRunningTest() && skipDmlForTest) return recordings.size();
        if (!recordings.isEmpty()) {
            // Insert, not upsert. This runs as the Integrations site guest user, and
            // Salesforce allows guest users only read and create on an object — never
            // update. Zoom retries are tolerated by ignoring duplicate file IDs; healing
            // an existing row is left to ZoomIngestionService, which runs as an admin.
            for (Database.SaveResult result : Database.insert(recordings, false)) {
                if (!result.isSuccess() && result.getErrors()[0].getStatusCode() != StatusCode.DUPLICATE_VALUE) {
                    throw new AuraHandledException('Unable to save Zoom recording: ' + result.getErrors()[0].getMessage());
                }
            }
        }
        return recordings.size();
    }

    /** Returns null for file types that should not be stored at all. */
    public static String mapRecordingType(String zoomFileType) {
        String value = zoomFileType == null ? '' : zoomFileType.toUpperCase();
        if (IGNORED_FILE_TYPES.contains(value)) return null;
        if (value == 'M4A' || value == 'AUDIO_ONLY') return 'Audio';
        if (value.contains('TRANSCRIPT') || value == 'VTT') return 'Transcript';
        if (value.contains('SUMMARY')) return 'Summary';
        return 'Video';
    }

    public static Datetime parseZoomDateTime(String value) {
        if (String.isBlank(value)) return null;
        return (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
    }
}