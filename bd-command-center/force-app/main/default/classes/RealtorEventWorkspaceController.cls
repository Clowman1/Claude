public with sharing class RealtorEventWorkspaceController {
    public class RealtorOption {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public Boolean hasEmail;
        @AuraEnabled public Id campaignMemberId;
        @AuraEnabled public String memberStatus;
        @AuraEnabled public Boolean emailDelivered = false;
        @AuraEnabled public Boolean smsDelivered = false;
        @AuraEnabled public Boolean smsFailed = false;
        @AuraEnabled public String smsError;
        @AuraEnabled public String emailDeliveredText;
        @AuraEnabled public String smsDeliveredText;
        // Reminder emails are separate sends from the original invitation, so they get their own
        // badges. Without these the list showed no date for the most recent email.
        @AuraEnabled public Boolean rsvpReminderSent = false;
        @AuraEnabled public String rsvpReminderText;
        @AuraEnabled public Boolean eventReminderSent = false;
        @AuraEnabled public String eventReminderText;
    }

    public class StatusOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public StatusOption(String statusLabel) {
            label = statusLabel;
            value = statusLabel;
        }
    }

    public class CoHostOption {
        @AuraEnabled public Id coHostRecordId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String title;
    }

    public class InvitationDraft {
        @AuraEnabled public String emailSubject;
        @AuraEnabled public String emailBody;
        @AuraEnabled public String smsBody;
        @AuraEnabled public Integer inviteeCount = 0;
        @AuraEnabled public Integer emailEligibleCount = 0;
        @AuraEnabled public Integer smsEligibleCount = 0;
        @AuraEnabled public Integer pendingInviteeCount = 0;
        @AuraEnabled public Integer pendingEmailCount = 0;
    }

    public class SendResult {
        @AuraEnabled public Integer emailsSent = 0;
        @AuraEnabled public Integer emailSkipped = 0;
        @AuraEnabled public Integer smsQueued = 0;
        @AuraEnabled public String message;
    }

    // Texts used to fail silently, so a send could report success while delivering nothing.
    // Every attempt now records an outcome on the Campaign Member for the invite list to show.
    private class SmsOutcome {
        private Integer queued = 0;
        private Integer failed = 0;
        private Integer skipped = 0;
        private String firstError;
    }

    public class Workspace {
        @AuraEnabled public Boolean isEvent;
        @AuraEnabled public String campaignName;
        @AuraEnabled public String hostName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Integer pendingInviteeCount = 0;
        @AuraEnabled public Integer confirmedCount = 0;
        @AuraEnabled public Integer declinedCount = 0;
        @AuraEnabled public Integer awaitingResponseCount = 0;
        @AuraEnabled public Integer nickleyTeamCount = 0;
        @AuraEnabled public Boolean allNickleyTeamInvited = false;
        @AuraEnabled public List<RealtorOption> realtors = new List<RealtorOption>();
        @AuraEnabled public List<RealtorOption> invitees = new List<RealtorOption>();
        @AuraEnabled public List<StatusOption> statusOptions = new List<StatusOption>();
        @AuraEnabled public List<CoHostOption> coHosts = new List<CoHostOption>();
    }

    @AuraEnabled
    public static Workspace getWorkspace(Id campaignId) {
        Campaign campaign = [SELECT Id, Name, Type, StartDate, Owner.Name FROM Campaign WHERE Id = :campaignId LIMIT 1];
        Workspace workspace = new Workspace();
        workspace.isEvent = campaign.Type == 'Event';
        workspace.campaignName = campaign.Name;
        workspace.hostName = campaign.Owner.Name;
        workspace.startDate = campaign.StartDate;
        if (!workspace.isEvent) return workspace;
        // Loading an event workspace must be read-only.  Loan Officers can view
        // campaigns but do not have permission to create CampaignMemberStatus
        // setup records; attempting that DML here prevented the workspace from
        // rendering for every event.  Statuses are provisioned by the event and
        // invitation actions before members are created or sent.
        Map<Id, CampaignMember> memberByContactId = new Map<Id, CampaignMember>();
        for (CampaignMember member : [
            SELECT Id, ContactId, Status, Contact.Name, Contact.Phone, Contact.Email,
                   Contact.AccountId, Contact.Account.Name, Contact.Account.Phone,
                   Contact.Account.PersonMobilePhone, Contact.Account.PersonEmail,
                   Invite_Email_Sent_At__c, Invite_SMS_Sent_At__c, Invite_SMS_Error__c,
                   RSVP_Reminder_Sent_At__c, Event_Reminder_Sent_At__c
            FROM CampaignMember
            WHERE CampaignId = :campaignId AND ContactId != null
        ]) {
            memberByContactId.put(member.ContactId, member);
            RealtorOption invitee = new RealtorOption();
            invitee.campaignMemberId = member.Id;
            invitee.memberStatus = member.Status;
            invitee.contactId = member.ContactId;
            invitee.accountId = member.Contact.AccountId;
            invitee.name = member.Contact.AccountId == null ? member.Contact.Name : member.Contact.Account.Name;
            invitee.phone = member.Contact.AccountId == null
                ? member.Contact.Phone
                : (String.isBlank(member.Contact.Account.PersonMobilePhone) ? member.Contact.Account.Phone : member.Contact.Account.PersonMobilePhone);
            invitee.email = member.Contact.AccountId == null ? member.Contact.Email : member.Contact.Account.PersonEmail;
            invitee.hasEmail = !String.isBlank(invitee.email);
            applyDeliveryStatus(invitee, member);
            workspace.invitees.add(invitee);
            if (member.Status == 'Invite List') {
                workspace.pendingInviteeCount++;
                workspace.awaitingResponseCount++;
            } else if (member.Status == 'Yes - Attending') {
                workspace.confirmedCount++;
            } else if (member.Status == 'No - Unable to Attend') {
                workspace.declinedCount++;
            } else {
                workspace.awaitingResponseCount++;
            }
        }
        for (CampaignMemberStatus status : [
            SELECT Label
            FROM CampaignMemberStatus
            WHERE CampaignId = :campaignId
            ORDER BY SortOrder
        ]) {
            workspace.statusOptions.add(new StatusOption(status.Label));
        }
        for (Account realtor : [SELECT Id, Name, PersonContactId, Phone, PersonMobilePhone, PersonEmail FROM Account WHERE Nickley_Realtor_LO__c = :workspace.hostName AND Type__c = 'Realtor Account' AND PersonContactId != null ORDER BY Name]) {
            RealtorOption option = new RealtorOption();
            option.accountId = realtor.Id; option.contactId = realtor.PersonContactId; option.name = realtor.Name;
            option.phone = String.isBlank(realtor.PersonMobilePhone) ? realtor.Phone : realtor.PersonMobilePhone;
            option.email = realtor.PersonEmail;
            option.hasEmail = !String.isBlank(option.email);
            CampaignMember member = memberByContactId.get(realtor.PersonContactId);
            if (member != null) { option.campaignMemberId = member.Id; option.memberStatus = member.Status; }
            workspace.realtors.add(option);
        }
        Set<Id> nickleyTeamContactIds = getNickleyTeamContactIds();
        workspace.nickleyTeamCount = nickleyTeamContactIds.size();
        workspace.allNickleyTeamInvited = !nickleyTeamContactIds.isEmpty()
            && memberByContactId.keySet().containsAll(nickleyTeamContactIds);
        for (Campaign_Co_Host__c record : [
            SELECT Id, Co_Host__c, Co_Host__r.Name, Co_Host__r.Email, Co_Host__r.Title
            FROM Campaign_Co_Host__c
            WHERE Campaign__c = :campaignId AND Co_Host__r.IsActive = true
            ORDER BY CreatedDate
        ]) {
            CoHostOption option = new CoHostOption();
            option.coHostRecordId = record.Id;
            option.userId = record.Co_Host__c;
            option.name = record.Co_Host__r.Name;
            option.email = record.Co_Host__r.Email;
            option.title = record.Co_Host__r.Title;
            workspace.coHosts.add(option);
        }
        return workspace;
    }

    @AuraEnabled(cacheable=true)
    public static List<CoHostOption> searchReachEmployees(String searchTerm) {
        List<CoHostOption> results = new List<CoHostOption>();
        String normalizedTerm = String.isBlank(searchTerm) ? '' : searchTerm.trim();
        if (normalizedTerm.length() < 2) return results;
        String searchPattern = '%' + normalizedTerm + '%';
        for (User userRecord : [
            SELECT Id, Name, Email, Title
            FROM User
            WHERE IsActive = true AND (Name LIKE :searchPattern OR Email LIKE :searchPattern)
            ORDER BY Name
            LIMIT 20
        ]) {
            CoHostOption option = new CoHostOption();
            option.userId = userRecord.Id;
            option.name = userRecord.Name;
            option.email = userRecord.Email;
            option.title = userRecord.Title;
            results.add(option);
        }
        return results;
    }

    @AuraEnabled
    public static void addCoHosts(Id campaignId, List<Id> userIds) {
        if (campaignId == null || userIds == null || userIds.isEmpty()) return;
        Set<Id> requestedIds = new Set<Id>(userIds);
        Set<Id> existingIds = new Set<Id>();
        for (Campaign_Co_Host__c record : [SELECT Co_Host__c FROM Campaign_Co_Host__c WHERE Campaign__c = :campaignId]) {
            existingIds.add(record.Co_Host__c);
        }
        Map<Id, User> activeUsers = new Map<Id, User>([SELECT Id FROM User WHERE Id IN :requestedIds AND IsActive = true]);
        List<Campaign_Co_Host__c> inserts = new List<Campaign_Co_Host__c>();
        for (Id userId : requestedIds) {
            if (activeUsers.containsKey(userId) && !existingIds.contains(userId)) {
                inserts.add(new Campaign_Co_Host__c(Campaign__c = campaignId, Co_Host__c = userId));
            }
        }
        if (!inserts.isEmpty()) insert inserts;
    }

    @AuraEnabled
    public static void removeCoHost(Id coHostRecordId) {
        if (coHostRecordId != null) delete [SELECT Id FROM Campaign_Co_Host__c WHERE Id = :coHostRecordId LIMIT 1];
    }

    @AuraEnabled
    public static Integer addAllNickleyTeamInvitees(Id campaignId) {
        if (campaignId == null) return 0;
        Set<Id> contactIds = getNickleyTeamContactIds();
        Set<Id> existingContactIds = new Set<Id>();
        for (CampaignMember member : [SELECT ContactId FROM CampaignMember WHERE CampaignId = :campaignId AND ContactId IN :contactIds]) {
            existingContactIds.add(member.ContactId);
        }
        contactIds.removeAll(existingContactIds);
        if (!contactIds.isEmpty()) addInvitees(campaignId, new List<Id>(contactIds));
        return contactIds.size();
    }

    private static Set<Id> getNickleyTeamContactIds() {
        Set<Id> contactIds = new Set<Id>();
        for (Account accountRecord : [
            SELECT PersonContactId
            FROM Account
            WHERE IsPersonAccount = true AND PersonContactId != null
              AND (Realtor_Group__c LIKE '%Nickley%' OR PersonEmail LIKE '%nickley%')
        ]) contactIds.add(accountRecord.PersonContactId);
        return contactIds;
    }

    @AuraEnabled(cacheable=true)
    public static List<RealtorOption> searchPersonAccounts(Id campaignId, String searchTerm) {
        List<RealtorOption> results = new List<RealtorOption>();
        String normalizedTerm = String.isBlank(searchTerm) ? '' : searchTerm.trim();
        if (campaignId == null || normalizedTerm.length() < 2) return results;

        String searchPattern = '%' + normalizedTerm + '%';
        Map<Id, CampaignMember> memberByContactId = new Map<Id, CampaignMember>();
        for (CampaignMember member : [
            SELECT Id, ContactId, Status
            FROM CampaignMember
            WHERE CampaignId = :campaignId AND ContactId != null
        ]) memberByContactId.put(member.ContactId, member);

        for (Account personAccount : [
            SELECT Id, Name, PersonContactId, Phone, PersonMobilePhone, PersonEmail
            FROM Account
            WHERE IsPersonAccount = true
              AND PersonContactId != null
              AND (Name LIKE :searchPattern OR PersonEmail LIKE :searchPattern OR Phone LIKE :searchPattern OR PersonMobilePhone LIKE :searchPattern)
            ORDER BY Name
            LIMIT 20
        ]) {
            RealtorOption option = new RealtorOption();
            option.accountId = personAccount.Id;
            option.contactId = personAccount.PersonContactId;
            option.name = personAccount.Name;
            option.phone = String.isBlank(personAccount.PersonMobilePhone) ? personAccount.Phone : personAccount.PersonMobilePhone;
            option.email = personAccount.PersonEmail;
            option.hasEmail = !String.isBlank(option.email);
            CampaignMember member = memberByContactId.get(personAccount.PersonContactId);
            if (member != null) { option.campaignMemberId = member.Id; option.memberStatus = member.Status; }
            results.add(option);
        }
        return results;
    }

    @AuraEnabled
    public static void addInvitees(Id campaignId, List<Id> contactIds) {
        if (campaignId == null || contactIds == null || contactIds.isEmpty()) return;
        ensureEventMemberStatuses(campaignId);
        Set<Id> requestedContactIds = new Set<Id>(contactIds), existingContactIds = new Set<Id>();
        for (CampaignMember member : [SELECT ContactId FROM CampaignMember WHERE CampaignId = :campaignId AND ContactId IN :requestedContactIds]) existingContactIds.add(member.ContactId);
        List<CampaignMember> membersToInsert = new List<CampaignMember>();
        for (Id contactId : requestedContactIds) if (!existingContactIds.contains(contactId)) membersToInsert.add(new CampaignMember(CampaignId = campaignId, ContactId = contactId, Status = 'Invite List'));
        if (!membersToInsert.isEmpty()) insert membersToInsert;
    }

    @AuraEnabled
    public static void removeInvitee(Id campaignMemberId) {
        if (campaignMemberId != null) removeInvitees(new List<Id>{ campaignMemberId });
    }

    @AuraEnabled
    public static void removeInvitees(List<Id> campaignMemberIds) {
        if (campaignMemberIds == null || campaignMemberIds.isEmpty()) return;
        if (!Schema.sObjectType.CampaignMember.isDeletable()) {
            throw new AuraHandledException('You do not have permission to remove invitees from this event.');
        }
        delete [SELECT Id FROM CampaignMember WHERE Id IN :campaignMemberIds];
    }

    @AuraEnabled
    public static void deleteRealtorEvent(Id campaignId) {
        if (campaignId == null) throw new AuraHandledException('Missing event to delete.');
        Campaign campaign = [SELECT Id, Name, Type FROM Campaign WHERE Id = :campaignId LIMIT 1];
        if (campaign.Type != 'Event') {
            throw new AuraHandledException('Only event campaigns can be deleted from this workspace.');
        }
        List<CampaignMember> members = [SELECT Id FROM CampaignMember WHERE CampaignId = :campaignId];
        if (!members.isEmpty()) delete members;
        List<Campaign_Co_Host__c> coHosts = [SELECT Id FROM Campaign_Co_Host__c WHERE Campaign__c = :campaignId];
        if (!coHosts.isEmpty()) delete coHosts;
        List<Event> linkedEvents = [SELECT Id FROM Event WHERE WhatId = :campaignId];
        if (!linkedEvents.isEmpty()) delete linkedEvents;
        delete campaign;
    }

    @AuraEnabled public static void updateInviteStatus(Id campaignMemberId, String status) { if (campaignMemberId != null && !String.isBlank(status)) update new CampaignMember(Id = campaignMemberId, Status = status); }

    @AuraEnabled
    public static InvitationDraft getInvitationDraft(Id campaignId) {
        Campaign campaign = [
            SELECT Id, Name, StartDate, EndDate, Event_Time__c, Description, Owner.Name
            FROM Campaign WHERE Id = :campaignId LIMIT 1
        ];
        InvitationDraft draft = new InvitationDraft();
        for (CampaignMember member : [
            SELECT Id, Status, Contact.AccountId, Contact.Email, Contact.MobilePhone, Contact.Phone,
                   Contact.Account.PersonMobilePhone, Contact.Account.Phone
            FROM CampaignMember WHERE CampaignId = :campaignId AND ContactId != null
        ]) {
            draft.inviteeCount++;
            if (!String.isBlank(member.Contact.Email)) draft.emailEligibleCount++;
            String phone = member.Contact.MobilePhone;
            if (String.isBlank(phone)) phone = member.Contact.Phone;
            if (String.isBlank(phone) && member.Contact.AccountId != null) {
                phone = String.isBlank(member.Contact.Account.PersonMobilePhone)
                    ? member.Contact.Account.Phone : member.Contact.Account.PersonMobilePhone;
            }
            if (!String.isBlank(phone)) draft.smsEligibleCount++;
            if (member.Status == 'Invite List') {
                draft.pendingInviteeCount++;
                if (!String.isBlank(member.Contact.Email)) draft.pendingEmailCount++;
            }
        }
        String eventDate = campaign.StartDate == null ? 'the scheduled date' : campaign.StartDate.format();
        draft.emailSubject = 'You\'re invited: ' + campaign.Name;
        draft.emailBody =
            'Hi {{FirstName}},\n\n'
            + '{{HostName}} would love to have you join us for {{EventName}} on ' + eventDate
            + (campaign.Event_Time__c == null ? '' : ' at ' + formatEventTime(campaign.Event_Time__c)) + '.\n\n'
            + (String.isBlank(campaign.Description) ? '' : campaign.Description + '\n\n')
            + (artworkTypeFor(campaign.Name) == 'lunch'
                ? 'Lunch is on us. It\'s an easy hour to trade notes on the market and talk about how we can take great care of the people you work with.\n\n'
                : '')
            + 'Please use the RSVP buttons below to let us know if you can attend.\n\n'
            + 'We hope to see you there!';
        draft.smsBody = 'Check your email inbox for an invite to our upcoming event from {{HostNames}}.';
        return draft;
    }

    public static String formatEventTime(Time eventTime) {
        Integer hour = eventTime.hour();
        Integer minute = eventTime.minute();
        Integer displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        String displayMinute = minute < 10 ? '0' + String.valueOf(minute) : String.valueOf(minute);
        return String.valueOf(displayHour) + ':' + displayMinute + (hour >= 12 ? ' PM' : ' AM');
    }

    @AuraEnabled
    public static SendResult sendInvitations(Id campaignId, String emailSubject, String emailBody, String smsBody) {
        if (campaignId == null || String.isBlank(emailSubject) || String.isBlank(emailBody) || String.isBlank(smsBody)) {
            throw new AuraHandledException('Complete the invitation subject, email body, and SMS message before sending.');
        }
        Campaign campaign = [SELECT Id, Name, StartDate, EndDate, Event_Time__c, Description, Owner.Name FROM Campaign WHERE Id = :campaignId LIMIT 1];
        ensureEventMemberStatuses(campaignId);
        List<CampaignMember> members = [
            SELECT Id, Status, Event_Invite_Token__c, ContactId, Contact.FirstName, Contact.Email,
                   Contact.AccountId, Contact.MobilePhone, Contact.Phone, Contact.Account.PersonMobilePhone, Contact.Account.Phone
            FROM CampaignMember WHERE CampaignId = :campaignId AND ContactId != null AND Status = 'Invite List'
        ];
        SendResult outcome = new SendResult();
        if (members.isEmpty()) {
            throw new AuraHandledException('There are no new people waiting for an invitation. Add someone to the invite list, or use Resend Email for one existing invitee.');
        }

        List<CampaignMember> queueUpdates = new List<CampaignMember>();
        for (CampaignMember member : members) {
            if (String.isBlank(member.Event_Invite_Token__c)) {
                member.Event_Invite_Token__c = generateToken();
            }
            // This prevents a second click from sending the same person again while the
            // queued batches are still working. A failed email is returned to Invite List.
            member.Status = 'Invitation Queued';
            queueUpdates.add(member);
        }
        update queueUpdates;
        System.enqueueJob(new InvitationSendBatch(campaignId, UserInfo.getUserId(), emailSubject, emailBody, smsBody, null));
        outcome.message = members.size() + ' new invitation(s) queued in batches of 10. Each person receives an email first, then an SMS only when that email succeeds.';
        return outcome;
    }

    // Campaign events can have 90+ invitees. Processing in small chained Queueable batches
    // keeps the email and Twilio work below transaction limits and excludes people already sent.
    private class InvitationSendBatch implements Queueable, Database.AllowsCallouts {
        private final Integer batchSize = 10;
        private Id campaignId;
        private Id senderId;
        private String emailSubject;
        private String emailBody;
        private String smsBody;
        private Id lastMemberId;

        private InvitationSendBatch(Id campaignId, Id senderId, String emailSubject, String emailBody, String smsBody, Id lastMemberId) {
            this.campaignId = campaignId;
            this.senderId = senderId;
            this.emailSubject = emailSubject;
            this.emailBody = emailBody;
            this.smsBody = smsBody;
            this.lastMemberId = lastMemberId;
        }

        public void execute(QueueableContext context) {
            Campaign campaign = [SELECT Id, Name, StartDate, EndDate, Event_Time__c, Description, Owner.Name, Owner.FirstName FROM Campaign WHERE Id = :campaignId LIMIT 1];
            String memberQuery = 'SELECT Id, Event_Invite_Token__c, ContactId, Contact.FirstName, Contact.Email, '
                + 'Contact.AccountId, Contact.MobilePhone, Contact.Phone, Contact.Account.PersonMobilePhone, Contact.Account.Phone '
                + 'FROM CampaignMember WHERE CampaignId = :campaignId AND ContactId != null AND Status = \'Invitation Queued\'';
            if (lastMemberId != null) memberQuery += ' AND Id > :lastMemberId';
            memberQuery += ' ORDER BY Id LIMIT ' + batchSize;
            List<CampaignMember> members = Database.query(memberQuery);
            if (members.isEmpty()) return;

            User sender = [SELECT Id, Name, Headshot_URL__c, Title, Phone, MobilePhone, Email, NMLS__c FROM User WHERE Id = :senderId LIMIT 1];
            List<User> coHosts = getCampaignCoHosts(campaignId);
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            List<Id> emailMemberIds = new List<Id>();
            List<CampaignMember> statusUpdates = new List<CampaignMember>();
            for (CampaignMember member : members) {
                if (String.isBlank(member.Contact.Email)) {
                    statusUpdates.add(new CampaignMember(Id = member.Id, Status = 'Invite List'));
                    continue;
                }
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                setInviteeOnlyRecipient(email, member.Contact.Email);
                email.setSubject(emailSubject);
                email.setPlainTextBody(renderInvitation(emailBody, campaign, member));
                email.setHtmlBody(renderInvitationHtml(emailBody, campaign, member, sender, coHosts));
                email.setReplyTo(sender.Email);
                email.setSenderDisplayName(sender.Name);
                email.setSaveAsActivity(false);
                emails.add(email);
                emailMemberIds.add(member.Id);
            }

            Set<Id> emailedMemberIds = new Set<Id>();
            if (!emails.isEmpty()) {
                List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
                for (Integer index = 0; index < results.size(); index++) {
                    if (results[index].isSuccess()) {
                        emailedMemberIds.add(emailMemberIds[index]);
                        statusUpdates.add(new CampaignMember(
                            Id = emailMemberIds[index],
                            Status = 'Invitation Sent',
                            Invite_Email_Sent_At__c = Datetime.now()
                        ));
                    } else {
                        // Keep failed deliveries eligible for a corrected, later retry.
                        statusUpdates.add(new CampaignMember(Id = emailMemberIds[index], Status = 'Invite List'));
                    }
                }
            }
            if (!statusUpdates.isEmpty()) update statusUpdates;
            if (!emailedMemberIds.isEmpty()) {
                SmsOutcome textOutcome = sendInvitationTexts(
                    members, emailedMemberIds, smsBody, hostFirstNames(campaignId, campaign.Owner.FirstName));
                if (textOutcome.failed > 0 || textOutcome.skipped > 0) {
                    System.debug(LoggingLevel.ERROR, 'Event invitation texts for campaign ' + campaignId
                        + ': queued=' + textOutcome.queued + ' failed=' + textOutcome.failed
                        + ' skipped=' + textOutcome.skipped + ' firstError=' + textOutcome.firstError);
                }
            }

            Id nextCursor = members[members.size() - 1].Id;
            List<CampaignMember> nextBatch = [
                SELECT Id FROM CampaignMember
                WHERE CampaignId = :campaignId AND ContactId != null AND Status = 'Invitation Queued' AND Id > :nextCursor
                ORDER BY Id LIMIT 1
            ];
            if (!nextBatch.isEmpty()) {
                System.enqueueJob(new InvitationSendBatch(campaignId, senderId, emailSubject, emailBody, smsBody, nextCursor));
            }
        }
    }

    // Send only to the Campaign Members selected by the current Invite List query. This avoids
    // campaign-wide broadcasts, which would text every prior invitee again when someone new is added.
    private static SmsOutcome sendInvitationTexts(
        List<CampaignMember> members,
        Set<Id> emailedMemberIds,
        String smsBody,
        String hostNames
    ) {
        SmsOutcome outcome = new SmsOutcome();
        // {{HostName}} is still honored so invitation drafts saved before multi-host support keep working.
        String renderedBody = smsBody.replace('{{HostNames}}', hostNames).replace('{{HostName}}', hostNames);
        List<CampaignMember> deliveryUpdates = new List<CampaignMember>();
        Datetime attemptedAt = Datetime.now();
        for (CampaignMember member : members) {
            if (!emailedMemberIds.contains(member.Id)) continue;
            String phone = firstNonBlank(
                member.Contact.MobilePhone,
                member.Contact.Phone,
                member.Contact.Account.PersonMobilePhone,
                member.Contact.Account.Phone
            );
            if (String.isBlank(phone)) {
                outcome.skipped++;
                deliveryUpdates.add(new CampaignMember(
                    Id = member.Id,
                    Invite_SMS_Sent_At__c = null,
                    Invite_SMS_Error__c = 'No mobile or phone number on file.'
                ));
                continue;
            }

            // The installed Twilio action applies the org's configured sender and opt-out rules.
            // It is invoked per Contact so previously sent Campaign Members are never included.
            try {
                if (!Test.isRunningTest()) {
                    Map<String, Object> input = new Map<String, Object>{
                        'RecipientPhone' => phone,
                        'RecipientRecordId' => String.valueOf(member.ContactId),
                        'MessageBody' => renderedBody
                    };
                    Flow.Interview.Realtor_Event_Send_Invite_SMS textFlow =
                        new Flow.Interview.Realtor_Event_Send_Invite_SMS(input);
                    textFlow.start();
                }
                outcome.queued++;
                deliveryUpdates.add(new CampaignMember(
                    Id = member.Id,
                    Invite_SMS_Sent_At__c = attemptedAt,
                    Invite_SMS_Error__c = null
                ));
            } catch (Exception smsException) {
                // A single SMS provider failure must not stop the remaining invitation batches,
                // but it is recorded so the invite list can show who still needs a text.
                outcome.failed++;
                String reason = smsException.getTypeName() + ': ' + smsException.getMessage();
                if (String.isBlank(outcome.firstError)) outcome.firstError = reason;
                System.debug(LoggingLevel.ERROR, 'Event invitation SMS failed for CampaignMember ' + member.Id + ': ' + reason);
                deliveryUpdates.add(new CampaignMember(
                    Id = member.Id,
                    Invite_SMS_Sent_At__c = null,
                    Invite_SMS_Error__c = reason.abbreviate(255)
                ));
            }
        }
        if (!deliveryUpdates.isEmpty()) update deliveryUpdates;
        return outcome;
    }

    // Drives the delivered / failed badges on each invite list row. A blank timestamp with no
    // recorded error means nothing was attempted yet, which reads differently from a failure.
    private static void applyDeliveryStatus(RealtorOption invitee, CampaignMember member) {
        // Invitations sent before these fields existed have no timestamp, but any status past
        // 'Invite List' means the email did go out. Report that rather than a false "not sent".
        Boolean emailImplied = member.Invite_Email_Sent_At__c == null
            && !String.isBlank(member.Status) && member.Status != 'Invite List';
        invitee.emailDelivered = member.Invite_Email_Sent_At__c != null || emailImplied;
        invitee.smsDelivered = member.Invite_SMS_Sent_At__c != null;
        invitee.smsError = member.Invite_SMS_Error__c;
        invitee.smsFailed = !String.isBlank(member.Invite_SMS_Error__c);
        invitee.emailDeliveredText = member.Invite_Email_Sent_At__c != null
            ? 'Email sent ' + member.Invite_Email_Sent_At__c.format('M/d h:mm a')
            : (emailImplied ? 'Email sent' : 'Email not sent');
        if (invitee.smsDelivered) {
            invitee.smsDeliveredText = 'Text sent ' + member.Invite_SMS_Sent_At__c.format('M/d h:mm a');
        } else if (invitee.smsFailed) {
            invitee.smsDeliveredText = 'Text failed';
        } else {
            invitee.smsDeliveredText = 'Text not sent';
        }
        invitee.rsvpReminderSent = member.RSVP_Reminder_Sent_At__c != null;
        invitee.rsvpReminderText = invitee.rsvpReminderSent
            ? 'RSVP reminder ' + member.RSVP_Reminder_Sent_At__c.format('M/d h:mm a')
            : null;
        invitee.eventReminderSent = member.Event_Reminder_Sent_At__c != null;
        invitee.eventReminderText = invitee.eventReminderSent
            ? 'Day-before reminder ' + member.Event_Reminder_Sent_At__c.format('M/d h:mm a')
            : null;
    }

    private static String firstNonBlank(String first, String second, String third, String fourth) {
        if (!String.isBlank(first)) return first;
        if (!String.isBlank(second)) return second;
        if (!String.isBlank(third)) return third;
        return fourth;
    }

    @AuraEnabled
    public static SendResult resendInvitation(Id campaignMemberId) {
        if (campaignMemberId == null) {
            throw new AuraHandledException('Select an invitee before resending an invitation.');
        }
        CampaignMember member = [
            SELECT Id, CampaignId, Status, Event_Invite_Token__c, ContactId, Contact.FirstName, Contact.Email,
                   Contact.AccountId, Contact.MobilePhone, Contact.Phone, Contact.Account.PersonMobilePhone, Contact.Account.Phone
            FROM CampaignMember WHERE Id = :campaignMemberId LIMIT 1
        ];
        if (String.isBlank(member.Contact.Email)) {
            throw new AuraHandledException('This invitee does not have an email address. Add an email to the Person Account before resending.');
        }
        Campaign campaign = [SELECT Id, Name, StartDate, EndDate, Event_Time__c, Description, Owner.Name FROM Campaign WHERE Id = :member.CampaignId LIMIT 1];
        ensureEventMemberStatuses(campaign.Id);
        if (String.isBlank(member.Event_Invite_Token__c)) {
            member.Event_Invite_Token__c = generateToken();
            update member;
        }
        InvitationDraft draft = getInvitationDraft(campaign.Id);
        User sender = [SELECT Id, Name, Headshot_URL__c, Title, Phone, MobilePhone, Email, NMLS__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        List<User> coHosts = getCampaignCoHosts(campaign.Id);
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        setInviteeOnlyRecipient(email, member.Contact.Email);
        email.setSubject(draft.emailSubject);
        // A resend comes from whoever pressed the button: their name in the copy, their
        // signature card, their reply-to, and their display name. The campaign owner is not
        // named, otherwise the email would read as being from someone who did not send it.
        String pressingHostName = UserInfo.getName();
        email.setPlainTextBody(renderInvitation(draft.emailBody, campaign, member, pressingHostName));
        email.setHtmlBody(renderInvitationHtml(draft.emailBody, campaign, member, sender, coHosts, pressingHostName));
        email.setReplyTo(UserInfo.getUserEmail());
        email.setSenderDisplayName(UserInfo.getName());
        email.setSaveAsActivity(false);
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
        if (results.isEmpty() || !results[0].isSuccess()) {
            throw new AuraHandledException('Salesforce could not resend this invitation. Please review the invitee email address and try again.');
        }
        SendResult outcome = new SendResult();
        outcome.emailsSent = 1;
        outcome.message = 'Invitation email resent to ' + member.Contact.Email + '. No SMS was sent.';
        return outcome;
    }

    @TestVisible
    private static void ensureEventMemberStatuses(Id campaignId) {
        Set<String> existingLabels = new Set<String>();
        Integer nextSortOrder = 1;
        for (CampaignMemberStatus status : [SELECT Label, SortOrder FROM CampaignMemberStatus WHERE CampaignId = :campaignId]) {
            existingLabels.add(status.Label);
            if (status.SortOrder != null && status.SortOrder >= nextSortOrder) {
                nextSortOrder = status.SortOrder + 1;
            }
        }
        List<CampaignMemberStatus> inserts = new List<CampaignMemberStatus>();
        if (!existingLabels.contains('Invite List')) inserts.add(new CampaignMemberStatus(CampaignId = campaignId, Label = 'Invite List', SortOrder = nextSortOrder++, IsDefault = false, HasResponded = false));
        if (!existingLabels.contains('Invitation Queued')) inserts.add(new CampaignMemberStatus(CampaignId = campaignId, Label = 'Invitation Queued', SortOrder = nextSortOrder++, IsDefault = false, HasResponded = false));
        if (!existingLabels.contains('Invitation Sent')) inserts.add(new CampaignMemberStatus(CampaignId = campaignId, Label = 'Invitation Sent', SortOrder = nextSortOrder++, IsDefault = false, HasResponded = false));
        if (!existingLabels.contains('Yes - Attending')) inserts.add(new CampaignMemberStatus(CampaignId = campaignId, Label = 'Yes - Attending', SortOrder = nextSortOrder++, IsDefault = false, HasResponded = true));
        if (!existingLabels.contains('No - Unable to Attend')) inserts.add(new CampaignMemberStatus(CampaignId = campaignId, Label = 'No - Unable to Attend', SortOrder = nextSortOrder++, IsDefault = false, HasResponded = true));
        if (!inserts.isEmpty()) insert inserts;
    }

    public static String renderInvitation(String body, Campaign campaign, CampaignMember member) {
        return renderInvitation(body, campaign, member, campaign.Owner.Name);
    }

    /**
     * The hostName override exists so a resend reads as coming from the person who pressed the
     * button, rather than always naming the campaign owner.
     */
    public static String renderInvitation(String body, Campaign campaign, CampaignMember member, String hostName) {
        String token = member.Event_Invite_Token__c;
        String baseUrl = 'https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/event-rsvp';
        String yesLink = baseUrl + '?m=' + member.Id + '&t=' + token + '&r=Yes';
        String noLink = baseUrl + '?m=' + member.Id + '&t=' + token + '&r=No';
        String eventDate = campaign.StartDate == null ? '' : campaign.StartDate.format();
        String resolvedHost = String.isBlank(hostName) ? campaign.Owner.Name : hostName;
        return body
            .replace('{{FirstName}}', String.isBlank(member.Contact.FirstName) ? 'there' : member.Contact.FirstName)
            .replace('{{HostName}}', resolvedHost)
            .replace('{{EventName}}', campaign.Name)
            .replace('{{EventDate}}', eventDate)
            .replace('{{YesLink}}', yesLink)
            .replace('{{NoLink}}', noLink);
    }

    @TestVisible
    private static String renderInvitationHtml(String body, Campaign campaign, CampaignMember member, User sender) {
        return renderInvitationHtml(body, campaign, member, sender, new List<User>());
    }

    public static String renderInvitationHtml(String body, Campaign campaign, CampaignMember member, User sender, List<User> coHosts) {
        return renderInvitationHtml(body, campaign, member, sender, coHosts, campaign.Owner.Name);
    }

    public static String renderInvitationHtml(
        String body,
        Campaign campaign,
        CampaignMember member,
        User sender,
        List<User> coHosts,
        String hostName
    ) {
        String token = member.Event_Invite_Token__c;
        String baseUrl = 'https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/event-rsvp';
        String yesLink = baseUrl + '?m=' + member.Id + '&t=' + token + '&r=Yes';
        String noLink = baseUrl + '?m=' + member.Id + '&t=' + token + '&r=No';
        String plainBody = renderInvitation(body, campaign, member, hostName);
        // Do not display legacy raw RSVP URLs when a user edits an older template.
        List<String> visibleLines = new List<String>();
        for (String line : plainBody.split('\n')) {
            String normalized = line == null ? '' : line.trim().toLowerCase();
            if ((normalized.startsWith('yes:') || normalized.startsWith('no:')) && normalized.contains('/event-rsvp')) continue;
            visibleLines.add(line);
        }
        String artworkType = artworkTypeFor(campaign.Name);
        String artworkUrl = 'https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/event-rsvp?asset=' + artworkType;
        List<String> htmlLines = new List<String>();
        for (String line : visibleLines) {
            // Put the visual break immediately before the RSVP instruction, after the event details.
            if (line != null && line.trim().toLowerCase().contains('please use the rsvp buttons below')) {
                htmlLines.add('<div style="padding:8px 0 18px;"><img src="' + artworkUrl + '" alt="' + htmlEncode(campaign.Name) + ' invitation" width="520" style="display:block;width:100%;max-width:520px;height:auto;border-radius:10px;"/></div>');
            }
            htmlLines.add(htmlEncode(line).replace('\n', '<br/>'));
        }
        String copy = String.join(htmlLines, '<br/>');
        return '<!doctype html><html><body style="margin:0;padding:0;background:#f3f6fb;font-family:Arial,sans-serif;color:#172b4d;">'
            + '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f3f6fb;padding:24px 8px;"><tr><td align="center">'
            + '<table role="presentation" width="600" cellspacing="0" cellpadding="0" style="max-width:600px;background:#ffffff;border-radius:12px;overflow:hidden;">'
            + '<tr><td style="padding:28px 34px 18px;font-size:16px;line-height:24px;">' + copy + '</td></tr>'
            + '<tr><td align="center" style="padding:8px 34px 28px;">'
            + '<a href="' + yesLink + '" style="display:inline-block;background:#2e844a;color:#ffffff;text-decoration:none;border-radius:999px;padding:12px 26px;margin:4px 6px;font-weight:bold;">Yes, I\'ll Attend</a>'
            + '<a href="' + noLink + '" style="display:inline-block;background:#ba0517;color:#ffffff;text-decoration:none;border-radius:999px;padding:12px 26px;margin:4px 6px;font-weight:bold;">No, I Can\'t Attend</a>'
            + '</td></tr><tr><td style="padding:0 34px 30px;">' + buildSignatureCards(sender, coHosts) + '</td></tr>'
            + '</table></td></tr></table></body></html>';
    }

    private static List<User> getCampaignCoHosts(Id campaignId) {
        List<User> results = new List<User>();
        if (campaignId == null) return results;
        for (Campaign_Co_Host__c record : [
            SELECT Co_Host__r.Id, Co_Host__r.Name, Co_Host__r.FirstName, Co_Host__r.Headshot_URL__c, Co_Host__r.Title,
                   Co_Host__r.Phone, Co_Host__r.MobilePhone, Co_Host__r.Email, Co_Host__r.NMLS__c
            FROM Campaign_Co_Host__c
            WHERE Campaign__c = :campaignId AND Co_Host__r.IsActive = true
            ORDER BY CreatedDate
        ]) results.add(record.Co_Host__r);
        return results;
    }

    // Event hosts are the campaign owner plus any active co-hosts. Invitation texts name every
    // host by first name -- "Rhett, Joe and Brandon" -- rather than the owner alone.
    public static String hostFirstNames(Id campaignId, String ownerFirstName) {
        List<String> names = new List<String>();
        if (!String.isBlank(ownerFirstName)) names.add(ownerFirstName.trim());
        for (User coHost : getCampaignCoHosts(campaignId)) {
            if (String.isBlank(coHost.FirstName)) continue;
            String firstName = coHost.FirstName.trim();
            if (!names.contains(firstName)) names.add(firstName);
        }
        if (names.isEmpty()) return 'our team';
        if (names.size() == 1) return names[0];
        String finalName = names.remove(names.size() - 1);
        return String.join(names, ', ') + ' and ' + finalName;
    }

    /**
     * Day-before reminder for people who already confirmed. Deliberately does NOT render the
     * Yes / No RSVP buttons: the recipient has already said yes, and a stray tap on "No" the
     * night before would silently drop them from the headcount.
     */
    public static String renderEventReminderHtml(
        String body,
        Campaign campaign,
        CampaignMember member,
        User sender,
        List<User> coHosts
    ) {
        String plainBody = renderInvitation(body, campaign, member);
        List<String> htmlLines = new List<String>();
        for (String line : plainBody.split('\n')) {
            htmlLines.add(htmlEncode(line).replace('\n', '<br/>'));
        }
        String copy = String.join(htmlLines, '<br/>');
        String artworkType = artworkTypeFor(campaign.Name);
        String artworkUrl = 'https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/event-rsvp?asset='
            + artworkType;
        return '<!doctype html><html><body style="margin:0;padding:0;background:#f3f6fb;font-family:Arial,sans-serif;color:#172b4d;">'
            + '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f3f6fb;padding:24px 8px;"><tr><td align="center">'
            + '<table role="presentation" width="600" cellspacing="0" cellpadding="0" style="max-width:600px;background:#ffffff;border-radius:12px;overflow:hidden;">'
            + '<tr><td style="padding:28px 34px 18px;font-size:16px;line-height:24px;">' + copy + '</td></tr>'
            + '<tr><td style="padding:0 34px 18px;"><img src="' + artworkUrl + '" alt="' + htmlEncode(campaign.Name)
            + '" width="532" style="display:block;width:100%;max-width:532px;height:auto;border-radius:10px;"/></td></tr>'
            + '<tr><td style="padding:0 34px 30px;">' + buildSignatureCards(sender, coHosts) + '</td></tr>'
            + '</table></td></tr></table></body></html>';
    }

    public static void setInviteeOnlyRecipient(Messaging.SingleEmailMessage email, String inviteeEmail) {
        // Event messages are intentionally sent only to the invitee. The sender and co-hosts
        // are represented by their signature cards and must never receive per-invitee copies.
        email.setToAddresses(new List<String>{ inviteeEmail });
    }

    private static String buildSignatureCards(User sender, List<User> coHosts) {
        String result = buildSignatureCard(sender);
        for (User coHost : coHosts) {
            if (coHost.Id != sender.Id) result += '<div style="margin-top:18px;">' + buildSignatureCard(coHost) + '</div>';
        }
        return result;
    }

    private static String buildSignatureCard(User sender) {
        String phone = String.isBlank(sender.Phone) ? sender.MobilePhone : sender.Phone;
        String title = String.isBlank(sender.Title) ? '' : '<div style="color:#52647a;font-size:14px;">' + htmlEncode(sender.Title) + '</div>';
        String phoneLine = String.isBlank(phone) ? '' : '<div style="color:#52647a;font-size:14px;">Direct: ' + htmlEncode(FormattingUtility.formatPhone(phone)) + '</div>';
        String emailLine = String.isBlank(sender.Email) ? '' : '<div style="color:#52647a;font-size:14px;">' + htmlEncode(sender.Email) + '</div>';
        String nmlsLine = String.isBlank(sender.NMLS__c) ? '' : '<div style="color:#52647a;font-size:14px;">NMLS # ' + htmlEncode(sender.NMLS__c) + '</div>';
        String image = String.isBlank(sender.Headshot_URL__c) ? ''
            : '<td style="padding-right:14px;vertical-align:top;"><img src="' + sender.Headshot_URL__c + '" alt="' + htmlEncode(sender.Name) + '" width="72" height="72" style="display:block;border-radius:50%;object-fit:cover;"/></td>';
        return '<table role="presentation" cellspacing="0" cellpadding="0" style="border-top:1px solid #d8dde6;padding-top:18px;"><tr>' + image
            + '<td style="vertical-align:top;"><div style="font-size:18px;font-weight:bold;color:#16325c;">' + htmlEncode(sender.Name) + '</div>'
            + title + phoneLine + emailLine + '<div style="color:#52647a;font-size:14px;">Reach Home Loans</div>' + nmlsLine + '<div style="color:#52647a;font-size:14px;">Company NMLS # 2266637</div>' + '</td></tr></table>';
    }

    private static String htmlEncode(String value) {
        if (value == null) return '';
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace('\'', '&#39;');
    }

    public static void startReminderBatch() {
        // Five days out: nudge anyone who has not answered.
        Database.executeBatch(new RealtorEventReminderBatch(Date.today().addDays(5)), 10);
        // Day before: confirm with everyone who said yes.
        Database.executeBatch(
            new RealtorEventReminderBatch(Date.today().addDays(1), RealtorEventReminderBatch.MODE_DAY_BEFORE),
            10
        );
    }

    // The invitation artwork follows the event name: happy hour, lunch, else coffee.
    public static String artworkTypeFor(String campaignName) {
        String name = campaignName == null ? '' : campaignName.toLowerCase();
        if (name.contains('happy hour')) return 'happy-hour';
        if (name.contains('lunch')) return 'lunch';
        return 'coffee-lunch';
    }

    public static String generateToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    }
}