/**
 * Turns a scheduled Zoom meeting into a real calendar invitation.
 *
 * This org has no Einstein Activity Capture, so a Salesforce Event never reaches anybody's
 * Outlook: the host used to end up with a silent Salesforce-only calendar entry and the
 * borrower with a plain email. An iCalendar attachment is the only thing that puts the
 * meeting on both real calendars, with each side listed as an attendee of the other's copy,
 * and it is what makes the host's copy an invitation rather than a link to nowhere.
 *
 * The same UID is reused for every later notice about the meeting, with SEQUENCE bumped, so
 * a reschedule updates the existing calendar entry instead of adding a second one.
 */
public without sharing class ZoomCalendarInvite {
    /** Line length RFC 5545 folds at, counting the CRLF that follows it. */
    private static final Integer FOLD_AT = 74;

    public class Details {
        public String uid;
        public Integer sequence = 0;
        public Boolean isCancellation = false;
        public String topic;
        public String agenda;
        public Datetime startsAt;
        public Integer durationMinutes;
        public String joinUrl;
        public String organizerName;
        public String organizerEmail;
        public List<String> attendeeEmails = new List<String>();
    }

    public static String uidFor(String zoomMeetingId) {
        return 'zoom-' + zoomMeetingId + '@reachhomeloans.com';
    }

    public static Messaging.EmailFileAttachment attachment(Details details) {
        Messaging.EmailFileAttachment ics = new Messaging.EmailFileAttachment();
        ics.setFileName(details.isCancellation ? 'cancelled.ics' : 'invite.ics');
        // The method parameter is what makes Outlook and Gmail render this as an invitation
        // with Accept/Decline. Without it both show a file to download and nothing lands on
        // the calendar.
        ics.setContentType('text/calendar; charset=UTF-8; method=' + (details.isCancellation ? 'CANCEL' : 'REQUEST'));
        ics.setBody(Blob.valueOf(body(details)));
        ics.setInline(false);
        return ics;
    }

    /** One plain email carrying the invitation. Every notice about a meeting goes out this way. */
    public static void send(List<String> recipients, String emailSubject, String bodyText, String replyTo, String senderName, Details details) {
        if (recipients == null || recipients.isEmpty()) return;
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(recipients);
        message.setSubject(emailSubject);
        message.setPlainTextBody(bodyText);
        message.setHtmlBody(bodyText.escapeHtml4().replace('\n', '<br/>'));
        if (String.isNotBlank(replyTo)) message.setReplyTo(replyTo);
        if (String.isNotBlank(senderName)) message.setSenderDisplayName(senderName);
        message.setUseSignature(false);
        message.setSaveAsActivity(false);
        message.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment(details) });
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ message });
    }

    /**
     * The host's own notice. A meeting booked on someone's behalf otherwise appears on their
     * Salesforce calendar with no warning and never reaches the calendar they actually watch.
     */
    public static void notifyHost(String hostEmail, String hostName, String subjectName, Details details) {
        String text = 'Hi ' + firstWord(hostName) + ',\n\n'
            + UserInfo.getName() + ' scheduled a Zoom meeting for you'
            + (String.isBlank(subjectName) ? '' : ' with ' + subjectName) + '.\n\n'
            + 'What: ' + details.topic + '\n'
            + 'When: ' + longDate(details.startsAt) + '\n'
            + 'Length: ' + details.durationMinutes + ' minutes\n'
            + 'Join Zoom: ' + details.joinUrl + '\n\n'
            + 'Accept the attached invitation to put it on your calendar. It is on your Salesforce '
            + 'calendar as well, and moving it there will update Zoom and re-notify everyone invited.';
        send(
            new List<String>{ hostEmail },
            'Zoom scheduled: ' + details.topic + ' - ' + longDate(details.startsAt),
            text,
            UserInfo.getUserEmail(),
            UserInfo.getName(),
            details
        );
    }

    public static String longDate(Datetime value) {
        return value.format('EEEE, MMMM d, yyyy \'at\' h:mm a', UserInfo.getTimeZone().getID());
    }

    private static String firstWord(String value) {
        if (String.isBlank(value)) return 'there';
        return value.trim().split(' ')[0];
    }

    @TestVisible
    private static String body(Details details) {
        Integer minutes = details.durationMinutes == null ? 30 : details.durationMinutes;
        String description = (String.isBlank(details.agenda) ? '' : details.agenda.trim() + '\n\n')
            + 'Join Zoom Meeting:\n' + details.joinUrl;
        List<String> lines = new List<String>{
            'BEGIN:VCALENDAR',
            'PRODID:-//Reach Home Loans//Salesforce Zoom Scheduler//EN',
            'VERSION:2.0',
            'CALSCALE:GREGORIAN',
            'METHOD:' + (details.isCancellation ? 'CANCEL' : 'REQUEST'),
            'BEGIN:VEVENT',
            'UID:' + details.uid,
            'SEQUENCE:' + (details.sequence == null ? 0 : details.sequence),
            'DTSTAMP:' + utc(Datetime.now()),
            'DTSTART:' + utc(details.startsAt),
            'DTEND:' + utc(details.startsAt.addMinutes(minutes)),
            'SUMMARY:' + escapeText(details.topic),
            'DESCRIPTION:' + escapeText(description),
            'LOCATION:' + escapeText(details.joinUrl),
            'ORGANIZER;CN=' + quotable(details.organizerName) + ':mailto:' + details.organizerEmail,
            'STATUS:' + (details.isCancellation ? 'CANCELLED' : 'CONFIRMED'),
            'TRANSP:OPAQUE'
        };
        for (String email : details.attendeeEmails) {
            if (String.isBlank(email)) continue;
            lines.add('ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE;CN='
                + quotable(email.trim()) + ':mailto:' + email.trim());
        }
        if (!details.isCancellation) {
            lines.addAll(new List<String>{
                'BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:Reminder', 'TRIGGER:-PT15M', 'END:VALARM'
            });
        }
        lines.add('END:VEVENT');
        lines.add('END:VCALENDAR');

        List<String> folded = new List<String>();
        for (String line : lines) folded.add(fold(line));
        return String.join(folded, '\r\n') + '\r\n';
    }

    private static String utc(Datetime value) {
        return value.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
    }

    /**
     * A property value longer than 75 octets has to continue on a following line that starts
     * with a space. An agenda or a Zoom URL with a long password routinely crosses that, and
     * Outlook drops the whole VEVENT rather than the offending line.
     */
    private static String fold(String line) {
        if (line.length() <= FOLD_AT) return line;
        List<String> parts = new List<String>{ line.substring(0, FOLD_AT) };
        Integer cursor = FOLD_AT;
        while (cursor < line.length()) {
            Integer next = Math.min(cursor + FOLD_AT - 1, line.length());
            parts.add(' ' + line.substring(cursor, next));
            cursor = next;
        }
        return String.join(parts, '\r\n');
    }

    private static String escapeText(String value) {
        if (String.isBlank(value)) return '';
        return value.replace('\\', '\\\\')
            .replace(';', '\\;')
            .replace(',', '\\,')
            .replace('\r\n', '\\n')
            .replace('\n', '\\n');
    }

    /** Parameter values cannot carry the characters that delimit parameters. */
    private static String quotable(String value) {
        if (String.isBlank(value)) return '';
        return value.replaceAll('[":;,]', ' ').trim();
    }
}
