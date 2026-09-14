public with sharing class ZoomMeetingController {
    private static final String ZOOM_NAMED_CREDENTIAL = 'callout:Zoom_User_OAuth';

    public class ZoomMeetingRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String topic;
        @AuraEnabled public Datetime scheduledStart;
        @AuraEnabled public Integer durationMinutes;
        @AuraEnabled public String status;
        @AuraEnabled public String joinUrl;
        @AuraEnabled public Boolean recordingRequested;
        @AuraEnabled public List<ZoomRecordingRow> recordings;
    }

    public class ZoomRecordingRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String fileType;
        @AuraEnabled public String playbackUrl;
        @AuraEnabled public Datetime recordingStart;
        @AuraEnabled public Integer durationSeconds;
    }

    /**
     * One selectable Zoom host. Only users with a Zoom Host Email set can be scheduled
     * for, because that address is what Zoom's schedule_for privilege is granted on.
     */
    public class HostOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    public class LeadContext {
        @AuraEnabled public String leadName;
        @AuraEnabled public String leadEmail;
        @AuraEnabled public String senderName;
        @AuraEnabled public String senderEmail;
        @AuraEnabled public List<ZoomMeetingRow> meetings;
        @AuraEnabled public List<HostOption> hostOptions;
    }

    public class ScheduleResult {
        @AuraEnabled public Id meetingRecordId;
        @AuraEnabled public Id eventId;
        @AuraEnabled public String joinUrl;
        @AuraEnabled public Boolean invitationSent;
        @AuraEnabled public String invitationError;
    }

    /**
     * A meeting is scheduled against either a Lead or a Person Account. This resolves
     * whichever it is into the handful of things the rest of the class needs, so no
     * downstream code has to branch on the record type again.
     *
     * The Event linkage is the one genuine difference: an Event's WhoId must be a Lead or
     * a Contact, never an Account. For a Person Account that means the PersonContactId,
     * and for a business account there is no Who at all, so the Account goes in WhatId.
     */
    private class MeetingSubject {
        Id recordId;
        Boolean isLead;
        String name;
        String firstName;
        String email;
        Id whoId;
        Id whatId;
    }

    private static MeetingSubject resolveSubject(Id recordId) {
        if (recordId == null) throw new AuraHandledException('A Lead or Account is required.');
        MeetingSubject subject = new MeetingSubject();
        subject.recordId = recordId;
        subject.isLead = String.valueOf(recordId).startsWith('00Q');

        if (subject.isLead) {
            Lead lead = [SELECT Id, Name, FirstName, Email FROM Lead WHERE Id = :recordId LIMIT 1];
            subject.name = lead.Name;
            subject.firstName = lead.FirstName;
            subject.email = lead.Email;
            subject.whoId = lead.Id;
        } else {
            Account account = [
                SELECT Id, Name, FirstName, PersonEmail, PersonContactId, IsPersonAccount
                FROM Account WHERE Id = :recordId LIMIT 1
            ];
            subject.name = account.Name;
            subject.firstName = account.FirstName;
            subject.email = account.PersonEmail;
            if (account.IsPersonAccount && account.PersonContactId != null) {
                subject.whoId = account.PersonContactId;
            } else {
                subject.whatId = account.Id;
            }
        }
        return subject;
    }

    @AuraEnabled(cacheable=true)
    public static LeadContext getLeadContext(Id leadId) {
        MeetingSubject subject = resolveSubject(leadId);
        Id subjectId = subject.recordId;
        LeadContext context = new LeadContext();
        context.leadName = subject.name;
        context.leadEmail = subject.email;
        context.senderName = UserInfo.getName();
        context.senderEmail = UserInfo.getUserEmail();
        context.meetings = new List<ZoomMeetingRow>();
        context.hostOptions = buildHostOptions();
        for (Zoom_Meeting__c meeting : [
            SELECT Id, Topic__c, Scheduled_Start__c, Duration_Minutes__c, Status__c, Join_URL__c, Recording_Requested__c,
                (SELECT Id, File_Type__c, Play_URL__c, Recording_Start__c, Duration_Seconds__c FROM Zoom_Recordings__r WHERE Status__c = 'Available' AND Play_URL__c != null ORDER BY Recording_Start__c DESC)
            FROM Zoom_Meeting__c
            WHERE Lead__c = :subjectId OR Account__c = :subjectId
            ORDER BY Scheduled_Start__c DESC
            LIMIT 12
        ]) {
            ZoomMeetingRow row = new ZoomMeetingRow();
            row.id = meeting.Id;
            row.topic = meeting.Topic__c;
            row.scheduledStart = meeting.Scheduled_Start__c;
            row.durationMinutes = meeting.Duration_Minutes__c == null ? null : Integer.valueOf(String.valueOf(meeting.Duration_Minutes__c));
            row.status = meeting.Status__c;
            row.joinUrl = meeting.Join_URL__c;
            row.recordingRequested = meeting.Recording_Requested__c;
            row.recordings = new List<ZoomRecordingRow>();
            for (Zoom_Recording__c recording : meeting.Zoom_Recordings__r) {
                ZoomRecordingRow recordingRow = new ZoomRecordingRow();
                recordingRow.id = recording.Id;
                recordingRow.fileType = recording.File_Type__c;
                recordingRow.playbackUrl = recording.Play_URL__c;
                recordingRow.recordingStart = recording.Recording_Start__c;
                recordingRow.durationSeconds = recording.Duration_Seconds__c == null ? null : Integer.valueOf(String.valueOf(recording.Duration_Seconds__c));
                row.recordings.add(recordingRow);
            }
            context.meetings.add(row);
        }
        return context;
    }

    @AuraEnabled
    public static ScheduleResult scheduleMeeting(
        Id leadId,
        String topic,
        Datetime startDateTime,
        Integer durationMinutes,
        String agenda,
        String borrowerEmail,
        String additionalEmails,
        String invitationSubject,
        String invitationBody,
        Id hostUserId
    ) {
        if (leadId == null || String.isBlank(topic) || startDateTime == null || durationMinutes == null || durationMinutes < 15 || durationMinutes > 240) {
            throw new AuraHandledException('Topic, start date/time, and a duration between 15 minutes and 4 hours are required.');
        }
        Integer meetingHour = Integer.valueOf(startDateTime.format('H', UserInfo.getTimeZone().getID()));
        Integer meetingMinute = Integer.valueOf(startDateTime.format('m', UserInfo.getTimeZone().getID()));
        if (meetingHour < 7 || meetingHour > 21 || (meetingHour == 21 && meetingMinute > 0)) {
            throw new AuraHandledException('Zoom meetings can be scheduled between 7:00 AM and 9:00 PM.');
        }
        MeetingSubject subject = resolveSubject(leadId);
        List<String> recipients = parseRecipients(borrowerEmail, additionalEmails);
        if (recipients.isEmpty()) {
            throw new AuraHandledException('Enter the borrower email or at least one additional recipient before sending the invitation.');
        }
        Id hostId = hostUserId == null ? UserInfo.getUserId() : hostUserId;
        HostInfo host = resolveHost(hostId);
        Map<String, Object> payload = new Map<String, Object>{
            'topic' => topic.trim(),
            'type' => 2,
            'start_time' => startDateTime.format('yyyy-MM-dd\'T\'HH:mm:ss', UserInfo.getTimeZone().getID()),
            'timezone' => UserInfo.getTimeZone().getID(),
            'duration' => durationMinutes,
            'agenda' => agenda,
            'settings' => new Map<String, Object>{ 'waiting_room' => true, 'join_before_host' => false, 'auto_recording' => 'cloud' }
        };
        Map<String, Object> zoomMeeting = host.isSelf
            ? createMeetingAsSelf(payload)
            : createMeetingAsHost(host.zoomPath, payload);
        String joinUrl = (String) zoomMeeting.get('join_url');
        String meetingId = String.valueOf(zoomMeeting.get('id'));
        Event eventRecord = new Event(
            Subject = 'Zoom: ' + topic.trim(),
            // WhoId accepts only a Lead or a Contact. A Person Account contributes its
            // PersonContactId; a business account has no Who and is linked via WhatId.
            WhoId = subject.whoId,
            WhatId = subject.whatId,
            OwnerId = hostId,
            StartDateTime = startDateTime,
            EndDateTime = startDateTime.addMinutes(durationMinutes),
            // Calendar clients render Location as the join control, so the URL goes there
            // rather than a label. In Description the URL sits alone on its own line, which
            // is what Lightning and Outlook need to auto-linkify it instead of leaving raw text.
            Location = joinUrl,
            Description = (String.isBlank(agenda) ? '' : agenda.trim() + '\n\n') + 'Join Zoom Meeting:\n' + joinUrl,
            IsReminderSet = true,
            ReminderDateTime = startDateTime.addMinutes(-15)
        );
        insert eventRecord;
        inviteScheduler(eventRecord.Id, hostId);
        Zoom_Meeting__c meetingRecord = new Zoom_Meeting__c(
            Lead__c = subject.isLead ? subject.recordId : null,
            Account__c = subject.isLead ? null : subject.recordId,
            Zoom_Meeting_Id__c = meetingId,
            Join_URL__c = joinUrl,
            Topic__c = topic.trim(),
            Scheduled_Start__c = startDateTime,
            Duration_Minutes__c = durationMinutes,
            Status__c = 'Scheduled',
            Salesforce_Event_Id__c = eventRecord.Id,
            Recording_Requested__c = true,
            // The host's Salesforce address, not their Zoom one: this is who a reschedule
            // notice comes from and who the calendar invitation names as organiser.
            Host_Email__c = host.email,
            Invite_Sequence__c = 0,
            // Kept so a later reschedule can re-notify exactly who was invited the first time.
            Invitee_Emails__c = truncate(String.join(recipients, '; '), 1000)
        );
        insert meetingRecord;
        ScheduleResult result = new ScheduleResult();
        result.meetingRecordId = meetingRecord.Id;
        result.eventId = eventRecord.Id;
        result.joinUrl = joinUrl;

        ZoomCalendarInvite.Details invite = new ZoomCalendarInvite.Details();
        invite.uid = ZoomCalendarInvite.uidFor(meetingId);
        invite.sequence = 0;
        invite.topic = topic.trim();
        invite.agenda = agenda;
        invite.startsAt = startDateTime;
        invite.durationMinutes = durationMinutes;
        invite.joinUrl = joinUrl;
        invite.organizerName = host.name;
        invite.organizerEmail = host.email;
        invite.attendeeEmails = new List<String>(recipients);
        invite.attendeeEmails.add(host.email);

        try {
            sendInvitation(UserInfo.getUserId(), recipients, invitationSubject, invitationBody, subject.firstName, topic.trim(), startDateTime, durationMinutes, joinUrl, invite);
            result.invitationSent = true;
        } catch (Exception error) {
            result.invitationSent = false;
            result.invitationError = error.getMessage();
        }
        // A host who did not book the meeting themselves is only told about it here. The
        // Salesforce Event alone is silent, and without the attached invitation the meeting
        // never reaches their real calendar at all.
        if (!host.isSelf) {
            try {
                ZoomCalendarInvite.notifyHost(host.email, host.name, subject.name, invite);
            } catch (Exception ignored) {
                // The borrower's invitation is the one that matters; a failed heads-up to the
                // host must not roll back a meeting Zoom has already created.
            }
        }
        return result;
    }

    /**
     * Puts the meeting on the scheduler's calendar as well as the host's.
     *
     * Inviting anyone other than the owner turns the Event into a group event, which is what
     * gives the second person their own copy. The borrower cannot be added the same way — the
     * Event's WhoId already created their relation, and one person cannot hold two relations
     * to the same Event. Their attendance is carried by the calendar invitation instead.
     */
    private static void inviteScheduler(Id eventId, Id hostId) {
        if (hostId == UserInfo.getUserId()) return;
        Database.insert(
            new EventRelation(EventId = eventId, RelationId = UserInfo.getUserId(), IsInvitee = true),
            false
        );
    }

    private static String truncate(String value, Integer maxLength) {
        return value != null && value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    private static List<HostOption> buildHostOptions() {
        List<HostOption> options = new List<HostOption>();
        HostOption self = new HostOption();
        self.value = UserInfo.getUserId();
        self.name = UserInfo.getName();
        self.email = UserInfo.getUserEmail();
        self.label = UserInfo.getName() + ' (me)';
        options.add(self);
        for (User host : [
            SELECT Id, Name, Email, Zoom_Host_Email__c FROM User
            WHERE IsActive = true AND Zoom_Host_Email__c != null AND Id != :UserInfo.getUserId()
            ORDER BY Name
        ]) {
            HostOption option = new HostOption();
            option.value = host.Id;
            option.name = host.Name;
            option.email = host.Email;
            option.label = host.Name + ' (' + host.Zoom_Host_Email__c + ')';
            options.add(option);
        }
        return options;
    }

    /**
     * Who the meeting belongs to.
     *
     * `zoomPath` is the segment that goes into /v2/users/{...}/meetings — 'me' when the
     * scheduler is booking for themselves, otherwise the host's Zoom address. `email` is the
     * host's Salesforce address, which is where the calendar invitation and the heads-up
     * email go; for a shared hosting account those are not the same mailbox.
     */
    private class HostInfo {
        Id userId;
        String name;
        String email;
        String zoomEmail;
        String zoomPath;
        Boolean isSelf;
    }

    /**
     * Zoom schedules on another person's behalf via /v2/users/{their zoom email}/meetings.
     * Salesforce only supplies the address here; the privilege itself is granted account-side
     * in Zoom, which rejects the call if it is missing.
     */
    private static HostInfo resolveHost(Id hostId) {
        HostInfo host = new HostInfo();
        host.userId = hostId;
        host.isSelf = hostId == UserInfo.getUserId();
        if (host.isSelf) {
            host.name = UserInfo.getName();
            host.email = UserInfo.getUserEmail();
            host.zoomPath = 'me';
            return host;
        }
        User hostUser = [SELECT Name, Email, Zoom_Host_Email__c FROM User WHERE Id = :hostId LIMIT 1];
        if (String.isBlank(hostUser.Zoom_Host_Email__c)) {
            throw new AuraHandledException(hostUser.Name + ' has no Zoom Host Email set, so Zoom cannot schedule on their behalf.');
        }
        host.name = hostUser.Name;
        host.email = hostUser.Email;
        host.zoomEmail = hostUser.Zoom_Host_Email__c;
        host.zoomPath = EncodingUtil.urlEncode(hostUser.Zoom_Host_Email__c, 'UTF-8');
        return host;
    }

    /** The running user's own meeting, created on their personal Zoom OAuth connection. */
    private static Map<String, Object> createMeetingAsSelf(Map<String, Object> payload) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ZOOM_NAMED_CREDENTIAL + '/v2/users/me/meetings');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(payload));
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (Exception error) {
            throw new AuraHandledException('Your Zoom account is not connected yet. Use Connect Zoom once it is available, then try again.');
        }
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new AuraHandledException(scheduleErrorMessage(response, 'me'));
        }
        return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    }

    /**
     * A meeting booked under someone else's Zoom account.
     *
     * Zoom honours schedule-for privilege only for account-level tokens — a user-managed
     * OAuth token is rejected no matter which scopes it carries — so this goes through the
     * Server-to-Server client instead of the scheduler's personal connection. Zoom therefore
     * no longer polices who may book for whom; the Zoom Host Email field is the only gate.
     */
    private static Map<String, Object> createMeetingAsHost(String hostPath, Map<String, Object> payload) {
        try {
            return ZoomApiClient.postJson('/v2/users/' + hostPath + '/meetings', payload);
        } catch (Exception error) {
            throw new AuraHandledException('Zoom could not schedule this meeting for that host. ' + error.getMessage());
        }
    }

    private static String scheduleErrorMessage(HttpResponse response, String hostPath) {
        String detail = '';
        try {
            Object zoomMessage = ((Map<String, Object>) JSON.deserializeUntyped(response.getBody())).get('message');
            if (zoomMessage != null) detail = ' Zoom said: ' + String.valueOf(zoomMessage);
        } catch (Exception ignored) {
            detail = '';
        }
        return hostPath == 'me'
            ? 'Zoom could not schedule this meeting. Reconnect Zoom and try again.' + detail
            : 'Zoom would not let you schedule for that host. Confirm they have granted you Scheduling Privilege in Zoom.' + detail;
    }

    private static List<String> parseRecipients(String borrowerEmail, String additionalEmails) {
        Set<String> uniqueEmails = new Set<String>();
        List<String> recipients = new List<String>();
        List<String> candidates = new List<String>();
        if (!String.isBlank(borrowerEmail)) candidates.add(borrowerEmail);
        if (!String.isBlank(additionalEmails)) candidates.addAll(additionalEmails.split('[,;\\n]'));
        for (String candidate : candidates) {
            String email = candidate == null ? '' : candidate.trim();
            if (String.isBlank(email)) continue;
            if (!Pattern.matches('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$', email)) {
                throw new AuraHandledException('Enter valid email addresses separated by commas or semicolons.');
            }
            String normalized = email.toLowerCase();
            if (uniqueEmails.add(normalized)) recipients.add(email);
        }
        return recipients;
    }

    /**
     * Sent as the running user, not the host: an invitation booked on someone else's behalf
     * is written in the scheduler's voice, so the signature card and reply-to must be theirs.
     */
    private static void sendInvitation(
        Id senderId,
        List<String> recipients,
        String invitationSubject,
        String invitationBody,
        String leadFirstName,
        String topic,
        Datetime startDateTime,
        Integer durationMinutes,
        String joinUrl,
        ZoomCalendarInvite.Details invite
    ) {
        User sender = [
            SELECT Name, Email, Phone, Title, NMLS__c, Headshot_URL__c
            FROM User
            WHERE Id = :senderId
            LIMIT 1
        ];
        String formattedDateTime = startDateTime.format('EEEE, MMMM d, yyyy \'at\' h:mm a', UserInfo.getTimeZone().getID());
        String greetingName = String.isBlank(leadFirstName) ? 'there' : leadFirstName.trim();
        String subject = String.isBlank(invitationSubject)
            ? 'Your Mortgage Pre-Approval Review Is Scheduled'
            : invitationSubject.trim();
        String defaultBody =
            'Hi ' + greetingName + ',\n\n' +
            'I\'m looking forward to connecting with you to review your mortgage pre-approval, answer any questions, ' +
            'and walk through the next steps toward your home purchase.\n\n' +
            'Here are the details for our Zoom meeting:\n\n' +
            'When: ' + formattedDateTime + '\n' +
            'Length: ' + durationMinutes + ' minutes\n' +
            'Join Zoom: ' + joinUrl + '\n\n' +
            'Please feel free to reply to this email if you need to reschedule or would like to add anyone else to the conversation.\n\n' +
            'I\'m excited to continue working with you and help make the mortgage process as clear and comfortable as possible.';
        String body = String.isBlank(invitationBody) ? defaultBody : invitationBody.trim();
        body = body.replace('{ZoomLink}', joinUrl).replace('{MeetingDateTime}', formattedDateTime).replace('{LeadName}', greetingName);
        body = removeLegacyInvitationSignOff(body);
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(recipients);
        message.setSubject(subject.replace('{LeadName}', greetingName).replace('{MeetingDateTime}', formattedDateTime));
        message.setPlainTextBody(body);
        String htmlBody = body.escapeHtml4().replace('\n', '<br/>');
        htmlBody += buildZoomSignatureCard(sender);
        message.setHtmlBody(htmlBody);
        message.setReplyTo(sender.Email);
        message.setSenderDisplayName(sender.Name);
        message.setUseSignature(false);
        message.setSaveAsActivity(false);
        // Carries the meeting onto the recipient's own calendar with the host listed as
        // organiser. Without it they get a link in an email and nothing else.
        if (invite != null) {
            message.setFileAttachments(new List<Messaging.EmailFileAttachment>{ ZoomCalendarInvite.attachment(invite) });
        }
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ message });
        if (results.isEmpty() || !results[0].isSuccess()) {
            String errorMessage = results.isEmpty() || results[0].getErrors().isEmpty() ? 'The invitation email could not be sent.' : results[0].getErrors()[0].getMessage();
            throw new AuraHandledException(errorMessage);
        }
    }

    private static String buildZoomSignatureCard(User sender) {
        String headshot = String.isBlank(sender.Headshot_URL__c)
            ? ''
            : '<td style="padding:0 14px 0 0;vertical-align:top;">' +
                '<img src="' + sender.Headshot_URL__c.escapeHtml4() + '" alt="' + sender.Name.escapeHtml4() +
                '" width="92" style="display:block;border:0;border-radius:4px;max-width:92px;height:auto;" />' +
              '</td>';
        String titleLine = String.isBlank(sender.Title) ? '' : '<div style="margin:0 0 3px;color:#40546b;font-size:13px;line-height:18px;">' + sender.Title.escapeHtml4() + '</div>';
        String nmlsLine = String.isBlank(sender.NMLS__c) ? '' : '<div style="margin:0;color:#40546b;font-size:12px;line-height:17px;">NMLS # ' + sender.NMLS__c.escapeHtml4() + '</div>';
        String phoneLine = String.isBlank(sender.Phone) ? '' : '<div style="margin:0;color:#40546b;font-size:12px;line-height:17px;">Direct: ' + formatPhone(sender.Phone).escapeHtml4() + '</div>';
        return '<br/><br/><table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">' +
            '<tr>' + headshot +
            '<td style="vertical-align:top;padding-top:2px;">' +
                '<div style="margin:0 0 4px;color:#16325c;font-size:16px;line-height:20px;font-weight:700;">' + sender.Name.escapeHtml4() + '</div>' +
                titleLine + nmlsLine + phoneLine +
                '<div style="margin:0;color:#40546b;font-size:12px;line-height:17px;">Company NMLS # 2266637</div>' +
                '<div style="margin:5px 0 0;color:#40546b;font-size:12px;line-height:17px;">Reach Home Loans</div>' +
            '</td></tr></table>';
    }

    private static String removeLegacyInvitationSignOff(String body) {
        Matcher signOffMatcher = Pattern.compile('(?is)\\s*\\n\\s*(?:best|kind regards|warmly|thanks|thank you),?\\s*\\n.*$').matcher(body);
        return signOffMatcher.find() ? signOffMatcher.replaceFirst('').trim() : body.trim();
    }

    private static String formatPhone(String phone) {
        String digits = phone == null ? '' : phone.replaceAll('[^0-9]', '');
        return digits.length() == 10
            ? digits.substring(0, 3) + '-' + digits.substring(3, 6) + '-' + digits.substring(6)
            : phone;
    }

    @AuraEnabled
    public static String getFreshStartUrl(Id zoomMeetingRecordId) {
        Zoom_Meeting__c meeting = [SELECT Zoom_Meeting_Id__c FROM Zoom_Meeting__c WHERE Id = :zoomMeetingRecordId LIMIT 1];
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ZOOM_NAMED_CREDENTIAL + '/v2/meetings/' + EncodingUtil.urlEncode(meeting.Zoom_Meeting_Id__c, 'UTF-8'));
        request.setMethod('GET');
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (Exception error) {
            throw new AuraHandledException('Your Zoom account is not connected yet. Use Connect Zoom once it is available, then try again.');
        }
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) throw new AuraHandledException('Zoom could not retrieve the host launch link. Reconnect Zoom and try again.');
        return (String) ((Map<String, Object>) JSON.deserializeUntyped(response.getBody())).get('start_url');
    }

    @AuraEnabled
    public static Integer refreshRecordings(Id zoomMeetingRecordId) {
        if (zoomMeetingRecordId == null) throw new AuraHandledException('A Zoom meeting is required.');
        Zoom_Meeting__c meeting = [SELECT Id, Zoom_Meeting_Id__c FROM Zoom_Meeting__c WHERE Id = :zoomMeetingRecordId LIMIT 1];
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ZOOM_NAMED_CREDENTIAL + '/v2/meetings/' + EncodingUtil.urlEncode(meeting.Zoom_Meeting_Id__c, 'UTF-8') + '/recordings');
        request.setMethod('GET');
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (Exception error) {
            throw new AuraHandledException('Your Zoom account is not connected yet. Reconnect Zoom, then try again.');
        }
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            String zoomMessage = '';
            try {
                zoomMessage = (String) ((Map<String, Object>) JSON.deserializeUntyped(response.getBody())).get('message');
            } catch (Exception ignored) {
                zoomMessage = '';
            }
            throw new AuraHandledException('Zoom recording retrieval returned ' + response.getStatusCode() + (String.isBlank(zoomMessage) ? '.' : ': ' + zoomMessage));
        }
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        return ZoomRecordingWebhookService.importRecordingFiles(meeting.Id, (List<Object>) payload.get('recording_files'));
    }
}