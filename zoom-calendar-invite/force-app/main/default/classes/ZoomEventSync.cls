/**
 * Keeps Zoom and the invitees in step with the Salesforce Event.
 *
 * The Event is the source of truth for a Salesforce-scheduled Zoom. Moving it used to change
 * nothing else: Zoom still held the original time, Zoom_Meeting__c still held the original
 * time, and nobody told the borrower. Deleting it left a live Zoom meeting behind.
 *
 * Both paths call out, so the work is handed to a queueable. The Event is already committed
 * by then, which is why the reschedule path re-reads it rather than carrying values across.
 */
public without sharing class ZoomEventSync implements Queueable, Database.AllowsCallouts {
    private final List<Id> meetingIds;
    private final Boolean isCancellation;

    private ZoomEventSync(List<Id> meetingIds, Boolean isCancellation) {
        this.meetingIds = meetingIds;
        this.isCancellation = isCancellation;
    }

    public static void afterUpdate(List<Event> updated, Map<Id, Event> previous) {
        Set<Id> changedEventIds = new Set<Id>();
        for (Event record : updated) {
            Event before = previous.get(record.Id);
            if (record.StartDateTime != before.StartDateTime
                || record.EndDateTime != before.EndDateTime
                || record.Subject != before.Subject) {
                changedEventIds.add(record.Id);
            }
        }
        enqueue(changedEventIds, false);
    }

    public static void afterDelete(List<Event> deleted) {
        Set<Id> deletedEventIds = new Set<Id>();
        for (Event record : deleted) {
            // Housekeeping deletes old activities in bulk. Only a meeting that has not
            // happened yet is worth cancelling in Zoom.
            if (record.StartDateTime != null && record.StartDateTime > System.now()) {
                deletedEventIds.add(record.Id);
            }
        }
        enqueue(deletedEventIds, true);
    }

    private static void enqueue(Set<Id> eventIds, Boolean isCancellation) {
        if (eventIds.isEmpty()) return;
        List<String> eventKeys = new List<String>();
        for (Id eventId : eventIds) {
            eventKeys.add(String.valueOf(eventId));
        }
        List<Id> affected = new List<Id>(new Map<Id, Zoom_Meeting__c>([
            SELECT Id FROM Zoom_Meeting__c
            WHERE Salesforce_Event_Id__c IN :eventKeys AND Status__c = 'Scheduled'
        ]).keySet());
        if (affected.isEmpty()) return;
        System.enqueueJob(new ZoomEventSync(affected, isCancellation));
    }

    public void execute(QueueableContext context) {
        List<Zoom_Meeting__c> meetings = [
            SELECT Id, Zoom_Meeting_Id__c, Topic__c, Join_URL__c, Scheduled_Start__c, Duration_Minutes__c,
                Invite_Sequence__c, Invitee_Emails__c, Host_Email__c, Salesforce_Event_Id__c, Status__c
            FROM Zoom_Meeting__c WHERE Id IN :meetingIds
        ];
        Map<Id, Event> events = isCancellation ? new Map<Id, Event>() : eventsFor(meetings);
        Map<String, String> hostNames = hostNamesFor(meetings);
        List<Zoom_Meeting__c> changed = new List<Zoom_Meeting__c>();

        for (Zoom_Meeting__c meeting : meetings) {
            try {
                Zoom_Meeting__c result = isCancellation
                    ? cancel(meeting, hostNames)
                    : reschedule(meeting, events, hostNames);
                if (result != null) {
                    changed.add(result);
                }
            } catch (Exception error) {
                // One meeting Zoom will not accept must not strand the others. The stamp is
                // the record that a sync was attempted and did not land.
                changed.add(new Zoom_Meeting__c(Id = meeting.Id, Last_Sync_Attempt__c = System.now()));
                System.debug(LoggingLevel.ERROR, 'Zoom sync failed for ' + meeting.Id + ': ' + error.getMessage());
            }
        }
        if (!changed.isEmpty()) {
            update changed;
        }
    }

    private Zoom_Meeting__c reschedule(Zoom_Meeting__c meeting, Map<Id, Event> events, Map<String, String> hostNames) {
        Event calendarEvent = events.get((Id) meeting.Salesforce_Event_Id__c);
        if (calendarEvent == null || calendarEvent.StartDateTime == null) {
            return null;
        }
        Integer minutes = calendarEvent.EndDateTime == null
            ? Integer.valueOf(meeting.Duration_Minutes__c)
            : Integer.valueOf((calendarEvent.EndDateTime.getTime() - calendarEvent.StartDateTime.getTime()) / 60000);
        String topic = strippedSubject(calendarEvent.Subject, meeting.Topic__c);
        if (calendarEvent.StartDateTime == meeting.Scheduled_Start__c
            && minutes == Integer.valueOf(meeting.Duration_Minutes__c)
            && topic == meeting.Topic__c) {
            return null;
        }

        ZoomApiClient.patchJson(
            '/v2/meetings/' + EncodingUtil.urlEncode(meeting.Zoom_Meeting_Id__c, 'UTF-8'),
            new Map<String, Object>{
                'topic' => topic,
                'start_time' => calendarEvent.StartDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
                'duration' => minutes
            }
        );

        Integer sequence = nextSequence(meeting);
        notifyInvitees(meeting, topic, calendarEvent.StartDateTime, minutes, sequence, false, hostNames);
        return new Zoom_Meeting__c(
            Id = meeting.Id,
            Topic__c = topic,
            Scheduled_Start__c = calendarEvent.StartDateTime,
            Duration_Minutes__c = minutes,
            Invite_Sequence__c = sequence,
            Last_Sync_Attempt__c = System.now()
        );
    }

    private Zoom_Meeting__c cancel(Zoom_Meeting__c meeting, Map<String, String> hostNames) {
        ZoomApiClient.deletePath('/v2/meetings/' + EncodingUtil.urlEncode(meeting.Zoom_Meeting_Id__c, 'UTF-8'));
        Integer sequence = nextSequence(meeting);
        notifyInvitees(
            meeting,
            meeting.Topic__c,
            meeting.Scheduled_Start__c,
            meeting.Duration_Minutes__c == null ? 30 : Integer.valueOf(meeting.Duration_Minutes__c),
            sequence,
            true,
            hostNames
        );
        return new Zoom_Meeting__c(
            Id = meeting.Id,
            Status__c = 'Cancelled',
            Invite_Sequence__c = sequence,
            Last_Sync_Attempt__c = System.now()
        );
    }

    private void notifyInvitees(
        Zoom_Meeting__c meeting,
        String topic,
        Datetime startsAt,
        Integer minutes,
        Integer sequence,
        Boolean cancelled,
        Map<String, String> hostNames
    ) {
        List<String> recipients = recipientsFor(meeting);
        if (recipients.isEmpty() || startsAt == null) {
            return;
        }

        ZoomCalendarInvite.Details invite = new ZoomCalendarInvite.Details();
        invite.uid = ZoomCalendarInvite.uidFor(meeting.Zoom_Meeting_Id__c);
        invite.sequence = sequence;
        invite.isCancellation = cancelled;
        invite.topic = topic;
        invite.startsAt = startsAt;
        invite.durationMinutes = minutes;
        invite.joinUrl = meeting.Join_URL__c;
        invite.organizerEmail = meeting.Host_Email__c;
        invite.organizerName = hostNames.containsKey(meeting.Host_Email__c)
            ? hostNames.get(meeting.Host_Email__c)
            : meeting.Host_Email__c;
        invite.attendeeEmails = recipients;

        String whenLabel = ZoomCalendarInvite.longDate(startsAt);
        String text = cancelled
            ? 'Your Zoom meeting "' + topic + '" on ' + whenLabel + ' has been cancelled.\n\n'
                + 'Accepting the attached notice removes it from your calendar. '
                + 'Reply to this email if you would like to find another time.'
            : 'Your Zoom meeting has been rescheduled.\n\n'
                + 'What: ' + topic + '\n'
                + 'New time: ' + whenLabel + '\n'
                + 'Length: ' + minutes + ' minutes\n'
                + 'Join Zoom: ' + meeting.Join_URL__c + '\n\n'
                + 'The attached invitation updates the entry already on your calendar. '
                + 'The Zoom link has not changed.';
        ZoomCalendarInvite.send(
            recipients,
            (cancelled ? 'Cancelled: ' : 'Updated: ') + topic + ' - ' + whenLabel,
            text,
            meeting.Host_Email__c,
            invite.organizerName,
            invite
        );
    }

    /** Everyone the first invitation went to, plus the host. */
    private List<String> recipientsFor(Zoom_Meeting__c meeting) {
        Set<String> seen = new Set<String>();
        List<String> recipients = new List<String>();
        List<String> candidates = String.isBlank(meeting.Invitee_Emails__c)
            ? new List<String>()
            : meeting.Invitee_Emails__c.split(';');
        candidates.add(meeting.Host_Email__c);
        for (String candidate : candidates) {
            String email = candidate == null ? '' : candidate.trim();
            if (String.isBlank(email)) {
                continue;
            }
            if (seen.add(email.toLowerCase())) {
                recipients.add(email);
            }
        }
        return recipients;
    }

    private static Integer nextSequence(Zoom_Meeting__c meeting) {
        return (meeting.Invite_Sequence__c == null ? 0 : Integer.valueOf(meeting.Invite_Sequence__c)) + 1;
    }

    /**
     * The Event's Subject is written as "Zoom: <topic>" at scheduling time. A host who renames
     * it on the calendar means the new name, but the prefix is ours rather than theirs.
     */
    private static String strippedSubject(String eventSubject, String fallback) {
        if (String.isBlank(eventSubject)) {
            return fallback;
        }
        String subject = eventSubject.trim();
        return subject.startsWithIgnoreCase('Zoom: ') ? subject.substring(6).trim() : subject;
    }

    private static Map<Id, Event> eventsFor(List<Zoom_Meeting__c> meetings) {
        Set<Id> eventIds = new Set<Id>();
        for (Zoom_Meeting__c meeting : meetings) {
            if (String.isNotBlank(meeting.Salesforce_Event_Id__c)) {
                eventIds.add((Id) meeting.Salesforce_Event_Id__c);
            }
        }
        return new Map<Id, Event>([SELECT Id, Subject, StartDateTime, EndDateTime FROM Event WHERE Id IN :eventIds]);
    }

    private static Map<String, String> hostNamesFor(List<Zoom_Meeting__c> meetings) {
        Set<String> emails = new Set<String>();
        for (Zoom_Meeting__c meeting : meetings) {
            if (String.isNotBlank(meeting.Host_Email__c)) {
                emails.add(meeting.Host_Email__c);
            }
        }
        Map<String, String> names = new Map<String, String>();
        for (User host : [SELECT Name, Email FROM User WHERE Email IN :emails]) {
            names.put(host.Email, host.Name);
        }
        return names;
    }
}
