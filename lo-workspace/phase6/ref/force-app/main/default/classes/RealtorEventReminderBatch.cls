public class RealtorEventReminderBatch implements Database.Batchable<SObject> {
    /** Nudge people who have not answered yet, five days out. */
    public static final String MODE_RSVP = 'RSVP';
    /** Confirm the day before to people who already said yes. */
    public static final String MODE_DAY_BEFORE = 'DAY_BEFORE';

    private Date targetEventDate;
    private String mode;

    public RealtorEventReminderBatch(Date targetEventDate) {
        this(targetEventDate, MODE_RSVP);
    }

    public RealtorEventReminderBatch(Date targetEventDate, String mode) {
        this.targetEventDate = targetEventDate;
        this.mode = mode == MODE_DAY_BEFORE ? MODE_DAY_BEFORE : MODE_RSVP;
    }

    @TestVisible
    private Boolean isDayBefore() {
        return mode == MODE_DAY_BEFORE;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        // Each mode has its own stamp field, so the two reminders never suppress one another
        // and nobody receives either of them twice.
        if (isDayBefore()) {
            return Database.getQueryLocator([
                SELECT Id, CampaignId, ContactId, Contact.FirstName, Contact.Name, Contact.Email,
                       Status, Event_Invite_Token__c, Event_Reminder_Sent_At__c
                FROM CampaignMember
                WHERE Campaign.Type = 'Event'
                  AND Campaign.StartDate = :targetEventDate
                  AND ContactId != null
                  AND Contact.Email != null
                  AND Event_Reminder_Sent_At__c = null
                  AND Status = 'Yes - Attending'
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, CampaignId, ContactId, Contact.FirstName, Contact.Name, Contact.Email,
                   Status, Event_Invite_Token__c, RSVP_Reminder_Sent_At__c
            FROM CampaignMember
            WHERE Campaign.Type = 'Event'
              AND Campaign.StartDate = :targetEventDate
              AND ContactId != null
              AND Contact.Email != null
              AND RSVP_Reminder_Sent_At__c = null
              AND Status IN ('Invitation Sent', 'Sent')
        ]);
    }

    public void execute(Database.BatchableContext context, List<CampaignMember> members) {
        if (members.isEmpty()) {
            return;
        }

        Set<Id> campaignIds = new Set<Id>();
        for (CampaignMember member : members) {
            campaignIds.add(member.CampaignId);
        }

        Map<Id, Campaign> campaignsById = new Map<Id, Campaign>([
            SELECT Id, Name, OwnerId, Owner.Name, StartDate, Event_Time__c, Description
            FROM Campaign
            WHERE Id IN :campaignIds
        ]);

        Set<Id> ownerIds = new Set<Id>();
        for (Campaign campaign : campaignsById.values()) {
            ownerIds.add(campaign.OwnerId);
        }

        Map<Id, User> ownersById = new Map<Id, User>([
            SELECT Id, Name, FirstName, Email, Phone, MobilePhone, Title,
                   Headshot_URL__c, NMLS__c
            FROM User
            WHERE Id IN :ownerIds
        ]);

        Map<Id, List<User>> coHostsByCampaignId = new Map<Id, List<User>>();
        for (Campaign_Co_Host__c assignment : [
            SELECT Campaign__c, Co_Host__c, Co_Host__r.Id, Co_Host__r.Name,
                   Co_Host__r.FirstName, Co_Host__r.Email, Co_Host__r.Phone,
                   Co_Host__r.MobilePhone, Co_Host__r.Title,
                   Co_Host__r.Headshot_URL__c, Co_Host__r.NMLS__c
            FROM Campaign_Co_Host__c
            WHERE Campaign__c IN :campaignIds
              AND Co_Host__r.IsActive = true
            ORDER BY CreatedDate
        ]) {
            if (!coHostsByCampaignId.containsKey(assignment.Campaign__c)) {
                coHostsByCampaignId.put(assignment.Campaign__c, new List<User>());
            }
            coHostsByCampaignId.get(assignment.Campaign__c).add(assignment.Co_Host__r);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<CampaignMember> membersForEmail = new List<CampaignMember>();
        for (CampaignMember member : members) {
            Campaign campaign = campaignsById.get(member.CampaignId);
            User sender = campaign == null ? null : ownersById.get(campaign.OwnerId);
            if (campaign == null || sender == null) {
                continue;
            }

            if (String.isBlank(member.Event_Invite_Token__c)) {
                member.Event_Invite_Token__c = RealtorEventWorkspaceController.generateToken();
            }

            String body;
            if (isDayBefore()) {
                // A flat confirmation of a commitment already made: no RSVP ask, and no
                // invitation to cancel.
                body = 'Hi {{FirstName}},\n\n' +
                    'Quick reminder that {{EventName}} is tomorrow, ' + campaign.StartDate.format() +
                    ' at ' + RealtorEventWorkspaceController.formatEventTime(campaign.Event_Time__c) + '.\n\n';
                if (!String.isBlank(campaign.Description)) {
                    body += campaign.Description.trim() + '\n\n';
                }
                body += 'We are looking forward to seeing you there!';
            } else {
                body = 'Hi {{FirstName}},\n\n' +
                    'This is a friendly reminder to let us know if you\'ll be joining us for {{EventName}} on ' +
                    campaign.StartDate.format() + ' at ' +
                    RealtorEventWorkspaceController.formatEventTime(campaign.Event_Time__c) + '.\n\n';
                if (!String.isBlank(campaign.Description)) {
                    body += campaign.Description.trim() + '\n\n';
                }
                body += 'Please use the RSVP buttons below to let us know if you can attend.\n\n' +
                    'We hope to see you there!';
            }

            List<User> coHosts = coHostsByCampaignId.containsKey(campaign.Id)
                ? coHostsByCampaignId.get(campaign.Id)
                : new List<User>();
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ member.Contact.Email });
            email.setSubject(
                isDayBefore() ? 'Tomorrow: ' + campaign.Name : 'Reminder: Please RSVP - ' + campaign.Name
            );
            email.setPlainTextBody(RealtorEventWorkspaceController.renderInvitation(body, campaign, member));
            // The day-before build omits the RSVP buttons; see renderEventReminderHtml.
            email.setHtmlBody(
                isDayBefore()
                    ? RealtorEventWorkspaceController.renderEventReminderHtml(body, campaign, member, sender, coHosts)
                    : RealtorEventWorkspaceController.renderInvitationHtml(body, campaign, member, sender, coHosts)
            );
            if (!String.isBlank(sender.Email)) {
                email.setReplyTo(sender.Email);
                email.setSenderDisplayName(sender.Name);
            }
            email.setSaveAsActivity(false);
            emails.add(email);
            membersForEmail.add(member);
        }

        if (emails.isEmpty()) {
            return;
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);
        Datetime sentAt = System.now();
        List<CampaignMember> successfulMembers = new List<CampaignMember>();
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                CampaignMember member = membersForEmail[index];
                if (isDayBefore()) {
                    member.Event_Reminder_Sent_At__c = sentAt;
                } else {
                    member.RSVP_Reminder_Sent_At__c = sentAt;
                }
                successfulMembers.add(member);
            }
        }
        if (!successfulMembers.isEmpty()) {
            update successfulMembers;
        }
    }

    public void finish(Database.BatchableContext context) {
    }
}