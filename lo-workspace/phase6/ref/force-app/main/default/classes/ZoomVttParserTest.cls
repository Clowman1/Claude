@IsTest
private class ZoomVttParserTest {

    // Shape copied from the real Nehme recording transcript, CRLF included.
    private static final String REAL_SHAPE =
        'WEBVTT\r\n' +
        '\r\n' +
        '1\r\n' +
        '00:00:55.100 --> 00:00:56.140\r\n' +
        'Zach Fritz: Hi, Sean?\r\n' +
        '\r\n' +
        '2\r\n' +
        '00:01:21.010 --> 00:01:21.940\r\n' +
        'Zach Fritz: Hello?\r\n' +
        '\r\n' +
        '3\r\n' +
        '00:01:44.980 --> 00:01:46.200\r\n' +
        'Hicham Nehme : I am now in Qatar.\r\n';

    @IsTest
    static void stripsCuesAndMergesConsecutiveSpeakerTurns() {
        String result = ZoomVttParser.toPlainText(REAL_SHAPE);

        System.assertEquals('Zach Fritz: Hi, Sean? Hello?\nHicham Nehme: I am now in Qatar.', result,
            'Consecutive cues from one speaker should merge into a single turn');
        System.assert(!result.contains('-->'), 'Timestamps must be stripped');
        System.assert(!result.contains('WEBVTT'), 'Header must be stripped');
    }

    @IsTest
    static void keepsNumbersThatAreSpokenWords() {
        // A bare number is a cue index only when a timestamp follows it.
        String vtt = 'WEBVTT\r\n\r\n1\r\n00:00:01.000 --> 00:00:02.000\r\nZach Fritz: The rate is\r\n2026\r\n';
        String result = ZoomVttParser.toPlainText(vtt);
        System.assert(result.contains('2026'), 'A spoken number must not be mistaken for a cue index: ' + result);
    }

    @IsTest
    static void truncatesBeyondFieldLimit() {
        String longLine = 'Zach Fritz: ' + 'word '.repeat(20000);
        String vtt = 'WEBVTT\r\n\r\n1\r\n00:00:01.000 --> 00:00:02.000\r\n' + longLine + '\r\n';
        String result = ZoomVttParser.toPlainText(vtt);

        System.assertEquals(ZoomVttParser.MAX_LENGTH, result.length(),
            'Result must be capped at the Transcript__c field limit');
        System.assert(result.endsWith('characters.]'), 'Truncation must be visible, not silent');
    }

    @IsTest
    static void handlesBlankAndUnlabelledInput() {
        System.assertEquals(null, ZoomVttParser.toPlainText(null));
        System.assertEquals(null, ZoomVttParser.toPlainText(''));
        System.assertEquals(null, ZoomVttParser.toPlainText('WEBVTT\r\n\r\n'));

        String noSpeaker = 'WEBVTT\r\n\r\n1\r\n00:00:01.000 --> 00:00:02.000\r\nJust some words.\r\n';
        System.assertEquals('Just some words.', ZoomVttParser.toPlainText(noSpeaker));
    }
}