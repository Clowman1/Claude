/**
 * Emails the Lead Team when a user leaves a manual note on a Consumer Lead.
 *
 * Only Type__c = 'Note' qualifies -- Call / Text / Meeting rows are written by
 * automation and are not notes a user left.
 *
 * Who gets it:
 *   - Lead Owner, Loan Partner, Other  -- always, except whoever wrote the note.
 *   - Scenario Manager                 -- only when @mentioned in the note body,
 *                                         so they aren't inundated by every note.
 */
public without sharing class LeadNoteTeamNotifier {
    private static final String LIGHTNING_BASE =
        'https://reachhomeloans.lightning.force.com/lightning/r/Lead/';
    private static final String NOTE_TYPE = 'Note';
    private static final Set<String> CONSUMER_RECORD_TYPES = new Set<String>{
        'Consumer_Lead_record_type',
        'Consumer_Under_Contract_Lead_Record_Type'
    };

    public static void notifyForNotes(List<Enhanced_Note__c> newNotes) {
        List<Messaging.SingleEmailMessage> emails = buildEmails(newNotes);
        if (emails.isEmpty()) {
            return;
        }
        Messaging.sendEmail(emails, false);
    }

    @TestVisible
    private static List<Messaging.SingleEmailMessage> buildEmails(List<Enhanced_Note__c> newNotes) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        if (newNotes == null || newNotes.isEmpty()) {
            return emails;
        }

        Set<Id> leadIds = new Set<Id>();
        Set<Id> noteIds = new Set<Id>();
        for (Enhanced_Note__c note : newNotes) {
            if (note.Lead__c != null && isUserNote(note)) {
                leadIds.add(note.Lead__c);
                noteIds.add(note.Id);
            }
        }
        if (leadIds.isEmpty()) {
            return emails;
        }

        Map<Id, Lead> leadsById = new Map<Id, Lead>([
            SELECT Id, Name, OwnerId, Loan_Partner__c, Scenario_Manager__c, Other_Lead_Team_Member__c
            FROM Lead
            WHERE Id IN :leadIds
            AND RecordType.DeveloperName IN :CONSUMER_RECORD_TYPES
        ]);
        if (leadsById.isEmpty()) {
            return emails;
        }

        // Re-query so CreatedBy.Name and Body__c are populated regardless of what the trigger carried.
        Map<Id, Enhanced_Note__c> notesById = new Map<Id, Enhanced_Note__c>([
            SELECT Id, Lead__c, Body__c, Subject__c, AuthorRole__c, CreatedDate, CreatedById, CreatedBy.Name
            FROM Enhanced_Note__c
            WHERE Id IN :noteIds
        ]);

        Map<Id, User> usersById = activeTeamUsers(leadsById.values());
        Id orgWideId = orgWideAddressId();

        for (Enhanced_Note__c note : notesById.values()) {
            Lead theLead = leadsById.get(note.Lead__c);
            if (theLead == null) {
                continue;
            }
            List<String> recipients = recipientsFor(theLead, note, usersById);
            if (recipients.isEmpty()) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(recipients);
            mail.setSubject(
                theLead.Name + ' - Note Update - ' + note.CreatedDate.format('M/d/yyyy')
            );
            mail.setHtmlBody(buildBody(theLead, note));
            mail.setSaveAsActivity(false);
            if (orgWideId != null) {
                mail.setOrgWideEmailAddressId(orgWideId);
            }
            emails.add(mail);
        }
        return emails;
    }

    /**
     * A note a person typed, as opposed to a row automation pulled over.
     *
     * Automation always stamps an explicit Type__c -- Call, Text or Meeting from the
     * activity sync, or 'Note' from the Log a Call flow. The Add New Note modal historically
     * saved with Type__c blank, so blank counts as a user note too; without that, notes typed
     * straight into the Notes tab were silently skipped.
     */
    @TestVisible
    private static Boolean isUserNote(Enhanced_Note__c note) {
        return String.isBlank(note.Type__c) || NOTE_TYPE.equals(note.Type__c);
    }

    /**
     * Owner, Loan Partner and Other always; Scenario Manager only when @mentioned.
     * The note's author is never emailed their own note. Deduped, active users only.
     */
    private static List<String> recipientsFor(
        Lead theLead,
        Enhanced_Note__c note,
        Map<Id, User> usersById
    ) {
        List<Id> candidates = new List<Id>{
            theLead.OwnerId,
            theLead.Loan_Partner__c,
            theLead.Other_Lead_Team_Member__c
        };
        if (theLead.Scenario_Manager__c != null
            && mentions(note.Body__c, usersById.get(theLead.Scenario_Manager__c))) {
            candidates.add(theLead.Scenario_Manager__c);
        }

        List<String> recipients = new List<String>();
        Set<String> seen = new Set<String>();
        for (Id userId : candidates) {
            if (userId == null || userId == note.CreatedById) {
                continue;
            }
            User u = usersById.get(userId);
            String address = u == null ? null : u.Email;
            if (String.isBlank(address) || seen.contains(address.toLowerCase())) {
                continue;
            }
            seen.add(address.toLowerCase());
            recipients.add(address);
        }
        return recipients;
    }

    /**
     * True when the note body addresses this user with an "@" handle -- @Byron,
     * @byron.richie, @Byron Richie, or their alias. Requires the name to sit
     * directly against the "@" so ordinary prose like "texted again @ 5:20" and
     * email addresses do not count as a mention.
     */
    @TestVisible
    private static Boolean mentions(String body, User u) {
        if (u == null || String.isBlank(body)) {
            return false;
        }
        String text = body.stripHtmlTags().unescapeHtml4();
        if (!text.contains('@')) {
            return false;
        }

        List<String> handles = new List<String>();
        Boolean hasFirst = String.isNotBlank(u.FirstName);
        Boolean hasLast = String.isNotBlank(u.LastName);
        if (hasFirst) {
            handles.add(u.FirstName);
        }
        if (hasLast) {
            handles.add(u.LastName);
        }
        if (hasFirst && hasLast) {
            handles.add(u.FirstName + ' ' + u.LastName);
            handles.add(u.FirstName + '.' + u.LastName);
            handles.add(u.FirstName + u.LastName);
        }
        if (String.isNotBlank(u.Alias)) {
            handles.add(u.Alias);
        }
        if (String.isNotBlank(u.Email) && u.Email.contains('@')) {
            handles.add(u.Email.substringBefore('@'));
        }

        for (String handle : handles) {
            // (?i) case-insensitive; the handle must not run straight into more word characters,
            // so "@Byron" matches but "@Byronson" does not.
            Pattern p = Pattern.compile('(?i)@' + Pattern.quote(handle) + '(?![A-Za-z0-9._])');
            if (p.matcher(text).find()) {
                return true;
            }
        }
        return false;
    }

    /** OwnerId can be a Queue, so resolve users explicitly rather than through Owner.Email. */
    private static Map<Id, User> activeTeamUsers(List<Lead> leads) {
        Set<Id> userIds = new Set<Id>();
        for (Lead theLead : leads) {
            for (Id userId : new List<Id>{
                theLead.OwnerId,
                theLead.Loan_Partner__c,
                theLead.Scenario_Manager__c,
                theLead.Other_Lead_Team_Member__c
            }) {
                if (userId != null && userId.getSobjectType() == User.SObjectType) {
                    userIds.add(userId);
                }
            }
        }
        Map<Id, User> usersById = new Map<Id, User>();
        if (userIds.isEmpty()) {
            return usersById;
        }
        for (User u : [
            SELECT Id, Email, FirstName, LastName, Alias
            FROM User
            WHERE Id IN :userIds AND IsActive = true
        ]) {
            usersById.put(u.Id, u);
        }
        return usersById;
    }

    private static Id orgWideAddressId() {
        List<OrgWideEmailAddress> addresses = [
            SELECT Id FROM OrgWideEmailAddress WHERE Address = 'reachus@reachhomeloans.com' LIMIT 1
        ];
        return addresses.isEmpty() ? null : addresses[0].Id;
    }

    private static String buildBody(Lead theLead, Enhanced_Note__c note) {
        String author = note.CreatedBy == null ? 'Unknown' : note.CreatedBy.Name;
        String role = String.isBlank(note.AuthorRole__c)
            ? ''
            : ' <span style="color:#66738d;font-weight:600;">&middot; ' + note.AuthorRole__c.escapeHtml4() + '</span>';
        String leadUrl = LIGHTNING_BASE + theLead.Id + '/view';
        String noteBody = String.isBlank(note.Body__c) ? '<p><em>(no note text)</em></p>' : note.Body__c;

        return ''
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:14px;overflow:hidden;">'
            + '<tr><td style="background:#1c3155;padding:26px 30px;">'
            + '<div style="color:#ffa534;font-size:11px;font-weight:900;letter-spacing:1.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Reach Home Loans</div>'
            + '<div style="color:#ffffff;font-size:26px;font-weight:900;margin-top:8px;font-family:Arial,sans-serif;">Note Update</div>'
            + '</td></tr>'
            + '<tr><td style="padding:28px 30px 8px;">'
            + '<div style="color:#8290aa;font-size:11px;font-weight:900;letter-spacing:1.2px;text-transform:uppercase;font-family:Arial,sans-serif;">Lead</div>'
            + '<div style="color:#142342;font-size:22px;font-weight:900;margin-top:6px;font-family:Arial,sans-serif;">'
            + theLead.Name.escapeHtml4() + '</div></td></tr>'
            + '<tr><td style="padding:20px 30px 0;">'
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#f7f9fc;border-left:4px solid #ffa534;border-radius:8px;">'
            + '<tr><td style="padding:20px 22px;">'
            + '<div style="color:#8290aa;font-size:11px;font-weight:900;letter-spacing:1.2px;text-transform:uppercase;font-family:Arial,sans-serif;margin-bottom:12px;">Latest Note</div>'
            + '<div style="color:#22314f;font-size:15px;line-height:1.65;font-family:Arial,sans-serif;">' + noteBody + '</div>'
            + '</td></tr></table></td></tr>'
            + '<tr><td style="padding:18px 30px 0;">'
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">'
            + '<tr><td style="padding:6px 0;color:#8290aa;font-size:12px;font-weight:800;letter-spacing:0.6px;text-transform:uppercase;font-family:Arial,sans-serif;width:120px;">Left By</td>'
            + '<td style="padding:6px 0;color:#142342;font-size:15px;font-weight:800;font-family:Arial,sans-serif;">'
            + author.escapeHtml4() + role + '</td></tr>'
            + '<tr><td style="padding:6px 0;color:#8290aa;font-size:12px;font-weight:800;letter-spacing:0.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Date</td>'
            + '<td style="padding:6px 0;color:#142342;font-size:15px;font-weight:800;font-family:Arial,sans-serif;">'
            + note.CreatedDate.format('M/d/yyyy, h:mm a') + '</td></tr>'
            + '</table></td></tr>'
            + '<tr><td align="center" style="padding:28px 30px 30px;">'
            + '<a href="' + leadUrl + '" style="display:inline-block;background:#ff9824;color:#122242;font-size:15px;font-weight:900;font-family:Arial,sans-serif;text-decoration:none;padding:14px 34px;border-radius:999px;">Open Lead in Salesforce</a>'
            + '</td></tr>'
            + '<tr><td style="background:#f4f6fa;padding:18px 30px;border-top:1px solid #e2e7f0;">'
            + '<div style="color:#77839c;font-size:12px;line-height:1.6;font-family:Arial,sans-serif;">'
            + 'You are receiving this because you are on the Lead Team for this lead &mdash; as Lead Owner, Loan Partner, Scenario Manager, or Other.'
            + '</div></td></tr></table>';
    }
}
