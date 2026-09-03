@IsTest
private class ZoomCalendarInviteTest {
    private static ZoomCalendarInvite.Details details() {
        ZoomCalendarInvite.Details invite = new ZoomCalendarInvite.Details();
        invite.uid = ZoomCalendarInvite.uidFor('987654321');
        invite.topic = 'Pre-Approval Review, with notes; and more';
        invite.agenda = 'Line one\nLine two';
        invite.startsAt = Datetime.newInstanceGmt(2026, 9, 9, 17, 0, 0);
        invite.durationMinutes = 30;
        invite.joinUrl = 'https://zoom.us/j/94760381983?pwd=sTeSQAPXIcdhfQabNQaQaID6xpDJ1u.1';
        invite.organizerName = 'Brandon Brotsky';
        invite.organizerEmail = 'brandon@reachhomeloans.com';
        invite.attendeeEmails = new List<String>{ 'borrower@example.com', 'brandon@reachhomeloans.com' };
        return invite;
    }

    @IsTest
    static void buildsAnInvitationEveryCalendarClientAccepts() {
        String ics = ZoomCalendarInvite.attachment(details()).getBody().toString();

        System.assertEquals(true, ics.contains('METHOD:REQUEST'), ics);
        System.assertEquals(true, ics.contains('UID:zoom-987654321@reachhomeloans.com'), ics);
        System.assertEquals(true, ics.contains('DTSTART:20260909T170000Z'), ics);
        System.assertEquals(true, ics.contains('DTEND:20260909T173000Z'), ics);
        System.assertEquals(true, ics.contains('ORGANIZER;CN=Brandon Brotsky:mailto:brandon@reachhomeloans.com'), ics);
        System.assertEquals(
            true,
            ics.contains('CN=borrower@example.com:mailto:borrower@example.com'),
            'The other party has to be a named attendee, not just a line of text: ' + ics
        );
        // A comma or semicolon inside a value ends the property unless it is escaped.
        System.assertEquals(true, ics.contains('SUMMARY:Pre-Approval Review\\, with notes\\; and more'), ics);
        System.assertEquals(true, ics.contains('\\n'), 'Line breaks in the agenda must be escaped, not literal');
        for (String line : ics.split('\r\n')) {
            System.assertEquals(true, line.length() <= 75, 'Every line must be folded to 75 octets: ' + line);
        }
    }

    @IsTest
    static void cancellationCarriesTheSameUidAndANewSequence() {
        ZoomCalendarInvite.Details invite = details();
        invite.isCancellation = true;
        invite.sequence = 3;
        Messaging.EmailFileAttachment ics = ZoomCalendarInvite.attachment(invite);
        String body = ics.getBody().toString();

        System.assertEquals(true, ics.getContentType().contains('method=CANCEL'), ics.getContentType());
        System.assertEquals(true, body.contains('METHOD:CANCEL'), body);
        System.assertEquals(true, body.contains('STATUS:CANCELLED'), body);
        System.assertEquals(true, body.contains('SEQUENCE:3'), body);
        System.assertEquals(
            true,
            body.contains('UID:zoom-987654321@reachhomeloans.com'),
            'A cancellation has to name the same event the invitation created'
        );
        System.assertEquals(false, body.contains('BEGIN:VALARM'), 'A cancelled meeting needs no reminder');
    }

    @IsTest
    static void notifiesTheHostWithTheInvitationAttached() {
        Boolean sent = false;
        Test.startTest();
        try {
            ZoomCalendarInvite.notifyHost('brandon@reachhomeloans.com', 'Brandon Brotsky', 'Diana Atehortua', details());
            sent = true;
        } catch (Exception error) {
            sent = false;
        }
        Test.stopTest();
        System.assertEquals(true, sent, 'The host must get their own notice');
    }
}
