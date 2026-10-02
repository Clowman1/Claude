/**
 * Converts a Zoom cloud-recording WEBVTT transcript into speaker-labelled plain text
 * for Call_Insight__c.Transcript__c.
 *
 * Zoom's VTT looks like this (CRLF line endings):
 *
 *     WEBVTT
 *
 *     1
 *     00:00:55.100 --> 00:00:56.140
 *     Zach Fritz: Hi, Sean?
 *
 * Cue numbers and timestamps are dropped: they roughly double the character count and
 * an 86-minute meeting already exceeds the 90,000-character field limit as raw VTT.
 * Speaker labels are kept because the analysis pipeline needs to know who committed
 * to what. Consecutive cues from one speaker are merged into a single turn.
 */
public with sharing class ZoomVttParser {
    @TestVisible private static final Integer MAX_LENGTH = 90000;
    private static final String TRUNCATION_NOTE = '\n\n[Transcript truncated at 90,000 characters.]';

    public static String toPlainText(String vtt) {
        if (String.isBlank(vtt)) return null;

        List<String> lines = vtt.replace('\r', '').split('\n');
        List<String> turns = new List<String>();
        String currentSpeaker = null;
        List<String> currentText = new List<String>();

        for (Integer i = 0; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;
            if (line.startsWith('WEBVTT') || line.startsWith('NOTE ')) continue;
            if (line.contains('-->')) continue;
            // A bare number is a cue index only when the next line is its timestamp.
            // Otherwise it is someone saying "2026" and must be kept.
            if (line.isNumeric() && i + 1 < lines.size() && lines[i + 1].contains('-->')) continue;

            String speaker = extractSpeaker(line);
            String text = speaker == null ? line : line.substring(line.indexOf(':') + 1).trim();
            if (String.isBlank(text)) continue;

            if (speaker != null && speaker != currentSpeaker) {
                flush(turns, currentSpeaker, currentText);
                currentSpeaker = speaker;
                currentText = new List<String>{ text };
            } else {
                currentText.add(text);
            }
        }
        flush(turns, currentSpeaker, currentText);

        String result = String.join(turns, '\n');
        if (result.length() > MAX_LENGTH) {
            result = result.substring(0, MAX_LENGTH - TRUNCATION_NOTE.length()) + TRUNCATION_NOTE;
        }
        return String.isBlank(result) ? null : result;
    }

    /** Returns the speaker name for a "Name: text" cue, or null when the cue has no label. */
    private static String extractSpeaker(String line) {
        Integer colon = line.indexOf(':');
        if (colon <= 0) return null;
        String candidate = line.substring(0, colon).trim();
        // Timestamps and long prefixes are not speaker names. Zoom caps display names at 128.
        if (candidate.length() > 60 || candidate.contains('-->')) return null;
        return String.isBlank(candidate) ? null : candidate;
    }

    private static void flush(List<String> turns, String speaker, List<String> text) {
        if (text == null || text.isEmpty()) return;
        String joined = String.join(text, ' ');
        turns.add(speaker == null ? joined : speaker + ': ' + joined);
    }
}