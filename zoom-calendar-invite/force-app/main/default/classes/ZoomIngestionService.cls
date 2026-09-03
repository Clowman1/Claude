/**
 * Pulls one Zoom meeting's recordings into Salesforce.
 *
 * Writes the transcript and Zoom's own AI summary onto Call_Insight__c (the object that
 * already feeds ApplicationSummaryService) and the playable files onto Zoom_Recording__c.
 * Media is never copied into Salesforce, only referenced.
 *
 * A meeting carries either a Lead or a Person Account, and only those are ingested. Zoom
 * returns no borrower emails for guest participants, so a meeting with neither cannot be
 * attributed to anyone and is skipped rather than guessed at.
 */
public without sharing class ZoomIngestionService {

    public class Result {
        public Boolean success = false;
        public Boolean skipped = false;
        public String message;
        public Id callInsightId;
        public Integer recordingsStored = 0;
        public Integer transcriptChars = 0;
        public Boolean summaryFound = false;
    }

    public static Result ingest(Id zoomMeetingRecordId) {
        Result result = new Result();

        List<Zoom_Meeting__c> meetings = [
            SELECT Id, Zoom_Meeting_Id__c, Topic__c, Lead__c, Account__c, Status__c,
                   Scheduled_Start__c, Duration_Minutes__c
            FROM Zoom_Meeting__c
            WHERE Id = :zoomMeetingRecordId
            LIMIT 1
        ];
        if (meetings.isEmpty()) {
            result.message = 'Zoom meeting record not found.';
            return result;
        }
        Zoom_Meeting__c meeting = meetings[0];

        // A meeting belongs to either a Lead or a Person Account. With neither, there is
        // nothing to attribute the conversation to, and nothing is stored.
        if (meeting.Lead__c == null && meeting.Account__c == null) {
            result.skipped = true;
            result.message = 'No Lead or Account on the meeting; nothing stored.';
            return result;
        }
        if (String.isBlank(meeting.Zoom_Meeting_Id__c)) {
            result.message = 'Meeting has no Zoom meeting ID.';
            log('Zoom Ingestion', 'Meeting ' + meeting.Id + ' has no Zoom_Meeting_Id__c.');
            return result;
        }

        try {
            Map<String, Object> payload = ZoomApiClient.getJson(
                '/v2/meetings/' + EncodingUtil.urlEncode(meeting.Zoom_Meeting_Id__c, 'UTF-8') + '/recordings');

            String passcode = (String) payload.get('recording_play_passcode');
            List<Object> files = (List<Object>) payload.get('recording_files');
            if (files == null || files.isEmpty()) {
                meeting.Last_Sync_Attempt__c = System.now();
                update meeting;
                result.skipped = true;
                result.message = 'Zoom reports no recording files yet.';
                return result;
            }

            String transcriptUrl;
            String summaryUrl;
            List<Zoom_Recording__c> recordings = new List<Zoom_Recording__c>();

            for (Object rawFile : files) {
                Map<String, Object> file = (Map<String, Object>) rawFile;
                String zoomType = (String) file.get('file_type');
                String mapped = ZoomRecordingWebhookService.mapRecordingType(zoomType);
                if (mapped == null) continue;

                if ('TRANSCRIPT'.equals(zoomType)) transcriptUrl = (String) file.get('download_url');
                if ('SUMMARY'.equals(zoomType)) summaryUrl = (String) file.get('download_url');

                String fileId = String.valueOf(file.get('id'));
                if (String.isBlank(fileId) || fileId == 'null') continue;
                Datetime startsAt = ZoomRecordingWebhookService.parseZoomDateTime((String) file.get('recording_start'));
                Datetime endsAt = ZoomRecordingWebhookService.parseZoomDateTime((String) file.get('recording_end'));

                Zoom_Recording__c recording = new Zoom_Recording__c();
                recording.put('Zoom_Meeting__c', meeting.Id);
                recording.put('Zoom_Recording_File_Id__c', fileId);
                recording.put('File_Type__c', mapped);
                recording.put('Play_URL__c', (String) file.get('play_url'));
                recording.put('Play_Passcode__c', passcode);
                recording.put('Recording_Start__c', startsAt);
                recording.put('Duration_Seconds__c', startsAt == null || endsAt == null
                    ? null
                    : Decimal.valueOf(String.valueOf((endsAt.getTime() - startsAt.getTime()) / 1000)));
                recording.put('Status__c', 'completed'.equalsIgnoreCase(String.valueOf(file.get('status'))) ? 'Available' : 'Pending');
                recordings.add(recording);
            }

            // Every callout must happen before the first DML: Apex refuses to call out
            // once a transaction has uncommitted work pending.
            String transcript = transcriptUrl == null ? null : ZoomVttParser.toPlainText(ZoomApiClient.download(transcriptUrl));
            Map<String, String> summary = summaryUrl == null ? new Map<String, String>() : parseSummary(ZoomApiClient.download(summaryUrl));
            result.transcriptChars = transcript == null ? 0 : transcript.length();
            result.summaryFound = !summary.isEmpty();

            // ---- callouts finished; DML from here down ----

            // Upsert on the Zoom file ID rather than insert. A plain insert silently skipped
            // rows that already existed, which left recordings imported before a field was
            // added — the play passcode, for instance — permanently empty.
            for (Database.UpsertResult upsertResult
                    : Database.upsert(recordings, Zoom_Recording__c.Zoom_Recording_File_Id__c, false)) {
                if (upsertResult.isSuccess()) {
                    result.recordingsStored++;
                } else {
                    log('Zoom Ingestion', 'Recording upsert failed on meeting ' + meeting.Id
                        + ': ' + upsertResult.getErrors()[0].getMessage());
                }
            }

            if (transcript != null || !summary.isEmpty()) {
                result.callInsightId = writeInsight(meeting, transcript, summary);
            }

            meeting.Status__c = 'Completed';
            meeting.Last_Sync_Attempt__c = System.now();
            update meeting;

            result.success = true;
            result.message = 'Stored ' + result.recordingsStored + ' recording(s), '
                + result.transcriptChars + ' transcript chars, summary=' + result.summaryFound + '.';
            return result;

        } catch (Exception error) {
            result.message = error.getTypeName() + ': ' + error.getMessage();
            log('Zoom Ingestion Error', 'Meeting ' + meeting.Id + ' (' + meeting.Zoom_Meeting_Id__c + '): '
                + error.getMessage() + ' | ' + error.getStackTraceString());
            return result;
        }
    }

    /**
     * Zoom's SUMMARY file is JSON: overall_summary plus timestamped chapter items.
     * Highlights and next steps are read defensively — those AI options were enabled
     * later than the earliest recordings, so the keys may be absent or may appear
     * under either a snake_case or camelCase name.
     */
    @TestVisible
    private static Map<String, String> parseSummary(String raw) {
        Map<String, String> mapped = new Map<String, String>();
        if (String.isBlank(raw)) return mapped;

        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(raw);
        } catch (Exception ignored) {
            return mapped;
        }

        String overall = text(parsed, new List<String>{ 'overall_summary', 'summary_overview', 'summary' });
        if (String.isNotBlank(overall)) mapped.put('Summary__c', overall);

        String nextSteps = text(parsed, new List<String>{ 'next_steps', 'nextSteps', 'summary_next_steps' });
        if (String.isNotBlank(nextSteps)) mapped.put('Next_Steps__c', nextSteps);

        String highlights = text(parsed, new List<String>{ 'highlights', 'recording_highlights' });
        if (String.isNotBlank(highlights)) mapped.put('HighLights__c', highlights);

        // Smart chapters become the bulleted summary, matching how RingSense uses that field.
        List<Object> items = parsed.get('items') instanceof List<Object> ? (List<Object>) parsed.get('items') : null;
        if (items != null && !items.isEmpty()) {
            List<String> chapters = new List<String>();
            for (Object rawItem : items) {
                Map<String, Object> item = (Map<String, Object>) rawItem;
                String label = String.valueOf(item.get('label'));
                String detail = String.valueOf(item.get('summary'));
                if (String.isBlank(detail) || detail == 'null') detail = String.valueOf(item.get('short_summary'));
                if (String.isBlank(label) || label == 'null') continue;
                chapters.add('• ' + label + (String.isBlank(detail) || detail == 'null' ? '' : ': ' + detail));
            }
            if (!chapters.isEmpty()) mapped.put('Bulleted_Summary__c', String.join(chapters, '\n'));
        }
        return mapped;
    }

    /** First non-blank value among candidate keys, flattening lists to newline-joined text. */
    private static String text(Map<String, Object> source, List<String> keys) {
        for (String key : keys) {
            Object value = source.get(key);
            if (value == null) continue;
            if (value instanceof List<Object>) {
                List<String> parts = new List<String>();
                for (Object entry : (List<Object>) value) {
                    if (entry instanceof Map<String, Object>) {
                        Map<String, Object> entryMap = (Map<String, Object>) entry;
                        Object nested = entryMap.get('summary') != null ? entryMap.get('summary') : entryMap.get('label');
                        if (nested != null) parts.add(String.valueOf(nested));
                    } else {
                        parts.add(String.valueOf(entry));
                    }
                }
                if (!parts.isEmpty()) return String.join(parts, '\n');
            } else {
                String flat = String.valueOf(value);
                if (String.isNotBlank(flat) && flat != 'null') return flat;
            }
        }
        return null;
    }

    /** One Call_Insight__c per Zoom meeting, updated in place when the sweep re-runs. */
    private static Id writeInsight(Zoom_Meeting__c meeting, String transcript, Map<String, String> summary) {
        List<Call_Insight__c> existing = [
            SELECT Id FROM Call_Insight__c WHERE Zoom_Meeting__c = :meeting.Id LIMIT 1
        ];
        SObject insight = existing.isEmpty()
            ? Schema.getGlobalDescribe().get('Call_Insight__c').newSObject()
            : existing[0];

        insight.put('Source__c', 'Zoom');
        insight.put('Zoom_Meeting__c', meeting.Id);
        insight.put('Lead__c', meeting.Lead__c);
        insight.put('Account__c', meeting.Account__c);
        insight.put('Title__c', meeting.Topic__c);
        // The tab orders and labels rows by these two, so a Zoom row without them would
        // sort to the bottom with a blank date.
        insight.put('Recording_Start_DateTime__c', meeting.Scheduled_Start__c);
        if (meeting.Duration_Minutes__c != null) {
            insight.put('Duration__c', String.valueOf(meeting.Duration_Minutes__c.intValue()) + ' min');
        }
        // Direction__c is left alone: it carries RingSense's inbound/outbound call
        // direction, which has no meaning for a scheduled video meeting.
        if (transcript != null) insight.put('Transcript__c', transcript);
        for (String field : summary.keySet()) {
            insight.put(field, summary.get(field));
        }

        if (existing.isEmpty()) { insert insight; } else { update insight; }
        return insight.Id;
    }

    private static void log(String source, String data) {
        try {
            insert new Custom_Log__c(
                Source__c = source,
                Data__c = data == null || data.length() <= 131000 ? data : data.substring(0, 131000) + '...[truncated]'
            );
        } catch (Exception ignored) {
            System.debug(LoggingLevel.WARN, 'ZoomIngestionService: could not write Custom_Log__c.');
        }
    }
}