@isTest(SeeAllData=true)
private class RealtorEventWorkspaceControllerTest {
    @isTest static void supportsInviteManagement() {
        Id personAccountRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        User joe = [SELECT Id, Name FROM User WHERE Username = 'jolmsted@reachhomeloans.com' LIMIT 1];
        Account realtor = new Account(RecordTypeId = personAccountRecordTypeId, FirstName = 'Workspace', LastName = 'Realtor', PersonEmail = 'workspace.realtor@example.com', PersonMobilePhone = '5551112222', Type__c = 'Realtor Account', Group__pc = 'Realtor', Is_Realtor__c = true, Nickley_Realtor_LO__c = 'Joe Olmsted');
        insert realtor;
        realtor = [SELECT Id, PersonContactId FROM Account WHERE Id = :realtor.Id];
        Account guest = new Account(RecordTypeId = personAccountRecordTypeId, FirstName = 'Workspace', LastName = 'Guest', PersonEmail = 'workspace.guest@example.com', PersonMobilePhone = '5553334444');
        insert guest;
        guest = [SELECT Id, PersonContactId FROM Account WHERE Id = :guest.Id];
        Campaign campaign = new Campaign(Name = 'Coffee/Lunch Workspace test', Type = 'Event', StartDate = Date.today(), Event_Time__c = Time.newInstance(12, 30, 0, 0), OwnerId = joe.Id); insert campaign;
        Test.startTest();
        RealtorEventWorkspaceController.Workspace workspace = RealtorEventWorkspaceController.getWorkspace(campaign.Id);
        List<RealtorEventWorkspaceController.RealtorOption> searchResults = RealtorEventWorkspaceController.searchPersonAccounts(campaign.Id, 'Guest');
        RealtorEventWorkspaceController.addInvitees(campaign.Id, new List<Id>{ realtor.PersonContactId, guest.PersonContactId });
        RealtorEventWorkspaceController.Workspace refreshedWorkspace = RealtorEventWorkspaceController.getWorkspace(campaign.Id);
        RealtorEventWorkspaceController.InvitationDraft draft = RealtorEventWorkspaceController.getInvitationDraft(campaign.Id);
        System.assert(draft.emailBody.contains('12:30 PM'), 'The invitation body should include the Campaign event time.');
        RealtorEventWorkspaceController.SendResult sendResult = RealtorEventWorkspaceController.sendInvitations(campaign.Id, draft.emailSubject, draft.emailBody, draft.smsBody);
        CampaignMember member = [SELECT Id FROM CampaignMember WHERE CampaignId = :campaign.Id AND ContactId = :realtor.PersonContactId LIMIT 1];
        RealtorEventWorkspaceController.SendResult resendResult = RealtorEventWorkspaceController.resendInvitation(member.Id);
        Account lateGuest = new Account(RecordTypeId = personAccountRecordTypeId, FirstName = 'Workspace', LastName = 'Late Guest', PersonEmail = 'workspace.late.guest@example.com', PersonMobilePhone = '5555556666');
        insert lateGuest;
        lateGuest = [SELECT PersonContactId FROM Account WHERE Id = :lateGuest.Id];
        RealtorEventWorkspaceController.addInvitees(campaign.Id, new List<Id>{ lateGuest.PersonContactId });
        RealtorEventWorkspaceController.InvitationDraft lateDraft = RealtorEventWorkspaceController.getInvitationDraft(campaign.Id);
        RealtorEventWorkspaceController.SendResult lateSendResult = RealtorEventWorkspaceController.sendInvitations(campaign.Id, lateDraft.emailSubject, lateDraft.emailBody, lateDraft.smsBody);
        RealtorEventWorkspaceController.removeInvitee(member.Id);
        Test.stopTest();
        System.assertEquals(true, workspace.isEvent);
        Set<Id> searchedContactIds = new Set<Id>();
        for (RealtorEventWorkspaceController.RealtorOption option : searchResults) searchedContactIds.add(option.contactId);
        System.assert(searchedContactIds.contains(guest.PersonContactId), 'Expected the non-Nickley Person Account to be available from org search.');
        System.assertEquals(2, refreshedWorkspace.invitees.size(), 'All campaign invitees, including non-Nickley Person Accounts, should load in the invite list.');
        System.assertEquals(2, draft.inviteeCount, 'The invitation preview should include every invitee.');
        System.assertEquals(2, draft.pendingInviteeCount, 'Only people with Invite List status should be included in the first send.');
        System.assert(!draft.emailBody.contains('{{YesLink}}'), 'The delivered HTML invitation renders RSVP buttons instead of raw links.');
        System.assertEquals(0, sendResult.emailsSent, 'Batch processing begins after the request returns.');
        System.assertEquals(0, sendResult.smsQueued, 'Batch processing begins after the request returns.');
        System.assert(sendResult.message.contains('queued in batches of 10'), 'New invitations should be marked queued for safe batch processing.');
        System.assertEquals(1, resendResult.emailsSent, 'A resend should target one person only.');
        System.assertEquals(0, resendResult.smsQueued, 'A resend must not send an SMS.');
        System.assertEquals(1, lateDraft.pendingInviteeCount, 'A later-added person should be the only pending invitee.');
        System.assertEquals(0, lateSendResult.emailsSent, 'The later send should also run asynchronously.');
        System.assertEquals(0, lateSendResult.smsQueued, 'The later send should also run asynchronously.');
        System.assertEquals(2, [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaign.Id], 'Only the removed invitee should be absent.');
        System.assertEquals(2, [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaign.Id AND Status = 'Invitation Sent'], 'Only the remaining recipients should have completed the queued email send.');
    }

    @isTest static void supportsCampaignCoHosts() {
        Campaign campaign = new Campaign(Name = 'Campaign Co-Host Test', Type = 'Event', StartDate = Date.today());
        insert campaign;

        Test.startTest();
        RealtorEventWorkspaceController.addCoHosts(campaign.Id, new List<Id>{ UserInfo.getUserId() });
        RealtorEventWorkspaceController.Workspace workspace = RealtorEventWorkspaceController.getWorkspace(campaign.Id);
        RealtorEventWorkspaceController.removeCoHost(workspace.coHosts[0].coHostRecordId);
        Test.stopTest();

        System.assertEquals(1, workspace.coHosts.size(), 'The selected Reach employee should be stored as an event co-host.');
        System.assertEquals(0, [SELECT COUNT() FROM Campaign_Co_Host__c WHERE Campaign__c = :campaign.Id], 'Removing a co-host should remove only that host association.');
    }

    @isTest static void supportsBulkRemovalAndEventDeletion() {
        Campaign campaign = new Campaign(Name = 'Coffee/Lunch Delete Test', Type = 'Event', StartDate = Date.today(), EndDate = Date.today());
        insert campaign;

        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = 'Bulk One', Email = 'bulk.one@example.com'),
            new Contact(LastName = 'Bulk Two', Email = 'bulk.two@example.com')
        };
        insert contacts;

        List<CampaignMember> members = new List<CampaignMember>();
        for (Contact contactRecord : contacts) {
            members.add(new CampaignMember(CampaignId = campaign.Id, ContactId = contactRecord.Id, Status = 'Invite List'));
        }
        insert members;

        RealtorEventWorkspaceController.removeInvitees(new List<Id>{ members[0].Id, members[1].Id });

        System.assertEquals(0, [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaign.Id], 'Bulk removal should remove the selected invitees.');

        insert new CampaignMember(CampaignId = campaign.Id, ContactId = contacts[0].Id, Status = 'Invite List');
        insert new Campaign_Co_Host__c(Campaign__c = campaign.Id, Co_Host__c = UserInfo.getUserId());
        Event linkedEvent = new Event(
            Subject = 'Coffee/Lunch Delete Test',
            StartDateTime = System.now().addDays(1),
            EndDateTime = System.now().addDays(1).addHours(1),
            WhatId = campaign.Id
        );
        insert linkedEvent;

        Test.startTest();
        RealtorEventWorkspaceController.deleteRealtorEvent(campaign.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Campaign WHERE Id = :campaign.Id], 'Deleting the event should remove the Campaign.');
        System.assertEquals(0, [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaign.Id], 'Deleting the event should remove invitees.');
        System.assertEquals(0, [SELECT COUNT() FROM Campaign_Co_Host__c WHERE Campaign__c = :campaign.Id], 'Deleting the event should remove co-host links.');
        System.assertEquals(0, [SELECT COUNT() FROM Event WHERE WhatId = :campaign.Id], 'Deleting the event should remove the linked calendar event.');
    }

    @isTest
    static void sendsFiveDayReminderOnlyToNonRespondersOnce() {
        Campaign campaign = new Campaign(
            Name = 'Coffee/Lunch Reminder Test',
            Type = 'Event',
            Status = 'Planned',
            StartDate = Date.today().addDays(5),
            EndDate = Date.today().addDays(5),
            Event_Time__c = Time.newInstance(12, 0, 0, 0),
            Description = 'Please join us for coffee and lunch.'
        );
        insert campaign;
        RealtorEventWorkspaceController.ensureEventMemberStatuses(campaign.Id);

        Contact pendingContact = new Contact(LastName = 'Reminder Pending', Email = 'reminder.pending@example.com');
        Contact confirmedContact = new Contact(LastName = 'Reminder Confirmed', Email = 'reminder.confirmed@example.com');
        insert new List<Contact>{ pendingContact, confirmedContact };
        CampaignMember pendingMember = new CampaignMember(
            CampaignId = campaign.Id,
            ContactId = pendingContact.Id,
            Status = 'Invitation Sent'
        );
        CampaignMember confirmedMember = new CampaignMember(
            CampaignId = campaign.Id,
            ContactId = confirmedContact.Id,
            Status = 'Yes - Attending'
        );
        insert new List<CampaignMember>{ pendingMember, confirmedMember };

        Test.startTest();
        Database.executeBatch(new RealtorEventReminderBatch(Date.today().addDays(5)), 10);
        Test.stopTest();

        pendingMember = [
            SELECT RSVP_Reminder_Sent_At__c, Event_Invite_Token__c
            FROM CampaignMember WHERE Id = :pendingMember.Id
        ];
        confirmedMember = [
            SELECT RSVP_Reminder_Sent_At__c
            FROM CampaignMember WHERE Id = :confirmedMember.Id
        ];
        System.assertNotEquals(null, pendingMember.RSVP_Reminder_Sent_At__c, 'The pending invitee should receive one reminder.');
        System.assertNotEquals(null, pendingMember.Event_Invite_Token__c, 'The reminder must preserve a working RSVP token.');
        System.assertEquals(null, confirmedMember.RSVP_Reminder_Sent_At__c, 'An attendee who responded must not receive a reminder.');
    }

    @isTest
    static void sendsDayBeforeReminderOnlyToConfirmedAttendeesOnce() {
        Campaign campaign = new Campaign(
            Name = 'Happy Hour Day Before Test',
            Type = 'Event',
            Status = 'Planned',
            StartDate = Date.today().addDays(1),
            EndDate = Date.today().addDays(1),
            Event_Time__c = Time.newInstance(16, 0, 0, 0),
            Description = 'Join us for Happy Hour.'
        );
        insert campaign;
        RealtorEventWorkspaceController.ensureEventMemberStatuses(campaign.Id);

        Contact pendingContact = new Contact(LastName = 'DayBefore Pending', Email = 'daybefore.pending@example.com');
        Contact confirmedContact = new Contact(LastName = 'DayBefore Confirmed', Email = 'daybefore.confirmed@example.com');
        Contact declinedContact = new Contact(LastName = 'DayBefore Declined', Email = 'daybefore.declined@example.com');
        insert new List<Contact>{ pendingContact, confirmedContact, declinedContact };
        CampaignMember pendingMember = new CampaignMember(
            CampaignId = campaign.Id, ContactId = pendingContact.Id, Status = 'Invitation Sent'
        );
        CampaignMember confirmedMember = new CampaignMember(
            CampaignId = campaign.Id, ContactId = confirmedContact.Id, Status = 'Yes - Attending'
        );
        CampaignMember declinedMember = new CampaignMember(
            CampaignId = campaign.Id, ContactId = declinedContact.Id, Status = 'No - Unable to Attend'
        );
        insert new List<CampaignMember>{ pendingMember, confirmedMember, declinedMember };

        Test.startTest();
        Database.executeBatch(
            new RealtorEventReminderBatch(Date.today().addDays(1), RealtorEventReminderBatch.MODE_DAY_BEFORE),
            10
        );
        Test.stopTest();

        Map<Id, CampaignMember> saved = new Map<Id, CampaignMember>([
            SELECT Id, Event_Reminder_Sent_At__c, RSVP_Reminder_Sent_At__c
            FROM CampaignMember
            WHERE CampaignId = :campaign.Id
        ]);
        System.assertNotEquals(
            null, saved.get(confirmedMember.Id).Event_Reminder_Sent_At__c,
            'A confirmed attendee should receive the day-before reminder.'
        );
        System.assertEquals(
            null, saved.get(pendingMember.Id).Event_Reminder_Sent_At__c,
            'Someone who never responded must not receive the day-before reminder.'
        );
        System.assertEquals(
            null, saved.get(declinedMember.Id).Event_Reminder_Sent_At__c,
            'Someone who declined must not receive the day-before reminder.'
        );
        // The two reminders use separate stamps, so neither can suppress the other.
        System.assertEquals(
            null, saved.get(confirmedMember.Id).RSVP_Reminder_Sent_At__c,
            'The day-before reminder must not touch the RSVP reminder stamp.'
        );
    }

    @isTest
    static void resendNamesThePressingUserNotTheCampaignOwner() {
        Campaign campaign = new Campaign(
            Name = 'Resend Host Test',
            Type = 'Event',
            Status = 'Planned',
            StartDate = Date.today().addDays(7),
            EndDate = Date.today().addDays(7),
            Event_Time__c = Time.newInstance(16, 0, 0, 0)
        );
        insert campaign;
        campaign = [SELECT Id, Name, StartDate, Event_Time__c, Description, OwnerId, Owner.Name
                    FROM Campaign WHERE Id = :campaign.Id];
        Contact invitee = new Contact(LastName = 'Resend Target', Email = 'resend.target@example.com');
        insert invitee;
        CampaignMember member = new CampaignMember(
            CampaignId = campaign.Id, ContactId = invitee.Id, Status = 'Invitation Sent'
        );
        insert member;
        member = [SELECT Id, ContactId, Contact.FirstName, Contact.Email, Event_Invite_Token__c
                  FROM CampaignMember WHERE Id = :member.Id];

        String template = '{{HostName}} would love to have you join us for {{EventName}}.';

        Test.startTest();
        String asOwner = RealtorEventWorkspaceController.renderInvitation(template, campaign, member);
        String asPresser = RealtorEventWorkspaceController.renderInvitation(
            template, campaign, member, 'Joe Olmsted'
        );
        String blankFallback = RealtorEventWorkspaceController.renderInvitation(
            template, campaign, member, null
        );
        Test.stopTest();

        System.assert(
            asOwner.contains(campaign.Owner.Name),
            'Without an override the campaign owner is still named, so the invitation batch is unchanged.'
        );
        System.assert(asPresser.contains('Joe Olmsted'), 'A resend must name the person who pressed the button.');
        System.assert(
            !asPresser.contains(campaign.Owner.Name),
            'A resend must not name the campaign owner, who did not send it.'
        );
        System.assert(
            blankFallback.contains(campaign.Owner.Name),
            'A blank override falls back to the campaign owner rather than leaving the token unresolved.'
        );
    }

    @isTest
    static void dayBeforeReminderHtmlOmitsRsvpButtons() {
        Campaign campaign = new Campaign(
            Name = 'Happy Hour Render Test',
            Type = 'Event',
            Status = 'Planned',
            StartDate = Date.today().addDays(1),
            EndDate = Date.today().addDays(1),
            Event_Time__c = Time.newInstance(16, 0, 0, 0)
        );
        insert campaign;
        // renderInvitation reads campaign.Owner.Name, so the relationship must be loaded.
        campaign = [
            SELECT Id, Name, StartDate, Event_Time__c, Description, OwnerId, Owner.Name
            FROM Campaign WHERE Id = :campaign.Id
        ];
        Contact attendee = new Contact(LastName = 'Render Attendee', Email = 'render.attendee@example.com');
        insert attendee;
        CampaignMember member = new CampaignMember(
            CampaignId = campaign.Id, ContactId = attendee.Id, Status = 'Yes - Attending'
        );
        insert member;
        member = [
            SELECT Id, CampaignId, ContactId, Contact.FirstName, Contact.Name, Contact.Email, Event_Invite_Token__c
            FROM CampaignMember WHERE Id = :member.Id
        ];
        User sender = [
            SELECT Id, Name, FirstName, Email, Phone, MobilePhone, Title, Headshot_URL__c, NMLS__c
            FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];

        Test.startTest();
        String html = RealtorEventWorkspaceController.renderEventReminderHtml(
            'Hi {{FirstName}},\n\nSee you tomorrow.', campaign, member, sender, new List<User>()
        );
        Test.stopTest();

        System.assert(!html.contains('Yes, I\'ll Attend'), 'The day-before email must not offer an RSVP Yes button.');
        System.assert(!html.contains('No, I Can\'t Attend'), 'The day-before email must not offer an RSVP No button.');
        System.assert(!html.contains('/event-rsvp?m='), 'The day-before email must not contain RSVP response links.');
        System.assert(html.contains('asset=happy-hour'), 'The day-before email should still show the event artwork.');
    }

    @isTest
    static void reminderSchedulerStartsTheBatch() {
        Test.startTest();
        new RealtorEventReminderScheduler().execute(null);
        Test.stopTest();
        System.assert(true, 'The daily scheduler should start the reminder batch without an exception.');
    }
}