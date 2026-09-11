/**
 * Tells the person who sent a lead email that it bounced.
 *
 * Salesforce flags the bounce on the EmailMessage itself (IsBounced) but tells nobody, so a
 * request for documents can bounce off a mistyped address and the Loan Officer carries on
 * waiting for an upload that can never arrive.
 *
 * The email is not linked to the Lead directly - these sends use setTargetObjectId, which logs an
 * activity instead - so the Lead is reached through EmailMessage.ActivityId -> Task.WhoId.
 */
public without sharing class LeadEmailBounceNotifier {

    private static final String FROM_ADDRESS = 'reachus@reachhomeloans.com';

    public class BounceNotificationException extends Exception {}

    @InvocableMethod(
        label='Notify Sender Of Bounced Email'
        description='Emails the sender of a bounced lead email so a bad address is noticed instead of silently waited on.'
        category='Lead'
    )
    public static void notifyBouncedEmails(List<Id> emailMessageIds) {
        if (emailMessageIds == null || emailMessageIds.isEmpty()) {
            return;
        }
        for (Id emailMessageId : emailMessageIds) {
            notifySender(emailMessageId);
        }
    }

    @TestVisible
    private static void notifySender(Id emailMessageId) {
        List<EmailMessage> messages = [
            SELECT Id, Subject, ToAddress, MessageDate, IsBounced, ActivityId,
                   CreatedById, CreatedBy.Name, CreatedBy.Email
            FROM EmailMessage
            WHERE Id = :emailMessageId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (messages.isEmpty() || messages[0].IsBounced != true) {
            return;
        }
        EmailMessage message = messages[0];
        if (String.isBlank(message.CreatedBy.Email)) {
            return;
        }

        Lead leadRecord = resolveLead(message.ActivityId);
        if (leadRecord == null) {
            // Bounces on Contact or Transaction email are someone else's problem; this notifier
            // exists for the lead-stage request emails.
            return;
        }

        sendAlert(message.CreatedBy.Email, message, leadRecord);
    }

    // Split out so the alert itself can be exercised without a bounced EmailMessage: ActivityId
    // is not writable, so the real chain cannot be assembled in a test.
    @TestVisible
    private static void sendAlert(String recipient, EmailMessage message, Lead leadRecord) {
        Messaging.SingleEmailMessage alert = new Messaging.SingleEmailMessage();
        alert.setToAddresses(new List<String>{ recipient });
        alert.setSubject('Email to ' + leadRecord.Name + ' bounced back');
        alert.setHtmlBody(buildBody(message, leadRecord));
        alert.setSaveAsActivity(false);

        Id orgWideId = resolveOrgWideAddressId();
        if (orgWideId != null) {
            alert.setOrgWideEmailAddressId(orgWideId);
        }

        if (!Test.isRunningTest()) {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ alert });
        }
    }

    @TestVisible
    private static Lead resolveLead(Id activityId) {
        if (activityId == null) {
            return null;
        }
        List<Task> tasks = [
            SELECT Id, WhoId FROM Task WHERE Id = :activityId WITH SYSTEM_MODE LIMIT 1
        ];
        if (tasks.isEmpty() || tasks[0].WhoId == null) {
            return null;
        }
        if (tasks[0].WhoId.getSObjectType() != Lead.SObjectType) {
            return null;
        }
        List<Lead> leads = [
            SELECT Id, Name, Email, Status, Owner.Name
            FROM Lead
            WHERE Id = :tasks[0].WhoId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return leads.isEmpty() ? null : leads[0];
    }

    private static Id resolveOrgWideAddressId() {
        List<OrgWideEmailAddress> addresses = [
            SELECT Id FROM OrgWideEmailAddress WHERE Address = :FROM_ADDRESS WITH SYSTEM_MODE LIMIT 1
        ];
        return addresses.isEmpty() ? null : addresses[0].Id;
    }

    @TestVisible
    private static String buildBody(EmailMessage message, Lead leadRecord) {
        String leadUrl = URL.getOrgDomainUrl().toExternalForm()
            + '/lightning/r/Lead/' + leadRecord.Id + '/view';
        String sentWhen = message.MessageDate == null
            ? ''
            : message.MessageDate.format('M/d/yyyy, h:mm a');
        String subject = String.isBlank(message.Subject) ? 'your email' : message.Subject;

        return ''
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:14px;overflow:hidden;">'
            + '<tr><td style="background:#1c3155;padding:26px 30px;">'
            + '<div style="color:#ffa534;font-size:11px;font-weight:900;letter-spacing:1.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Reach Home Loans</div>'
            + '<div style="color:#ffffff;font-size:26px;font-weight:900;margin-top:8px;font-family:Arial,sans-serif;">Email Bounced</div>'
            + '</td></tr>'
            + '<tr><td style="padding:28px 30px 8px;">'
            + '<div style="color:#8290aa;font-size:11px;font-weight:900;letter-spacing:1.2px;text-transform:uppercase;font-family:Arial,sans-serif;">Lead</div>'
            + '<div style="color:#142342;font-size:22px;font-weight:900;margin-top:6px;font-family:Arial,sans-serif;">'
            + htmlEncode(leadRecord.Name) + '</div></td></tr>'
            + '<tr><td style="padding:20px 30px 0;">'
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#fdf3f3;border-left:4px solid #c9414a;border-radius:8px;">'
            + '<tr><td style="padding:20px 22px;">'
            + '<div style="color:#a03b43;font-size:11px;font-weight:900;letter-spacing:1.2px;text-transform:uppercase;font-family:Arial,sans-serif;margin-bottom:12px;">Not Delivered</div>'
            + '<div style="color:#22314f;font-size:15px;line-height:1.65;font-family:Arial,sans-serif;">'
            + 'Your email did not reach this address:</div>'
            + '<div style="color:#142342;font-size:17px;font-weight:800;line-height:1.5;margin-top:10px;font-family:Arial,sans-serif;">'
            + htmlEncode(message.ToAddress) + '</div>'
            + '</td></tr></table></td></tr>'
            + '<tr><td style="padding:18px 30px 0;">'
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">'
            + '<tr><td style="padding:6px 0;color:#8290aa;font-size:12px;font-weight:800;letter-spacing:0.6px;text-transform:uppercase;font-family:Arial,sans-serif;width:120px;">Borrower</td>'
            + '<td style="padding:6px 0;color:#142342;font-size:15px;font-weight:800;font-family:Arial,sans-serif;">'
            + htmlEncode(leadRecord.Name) + '</td></tr>'
            + '<tr><td style="padding:6px 0;color:#8290aa;font-size:12px;font-weight:800;letter-spacing:0.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Email Sent</td>'
            + '<td style="padding:6px 0;color:#142342;font-size:15px;font-weight:800;font-family:Arial,sans-serif;">'
            + htmlEncode(subject) + '</td></tr>'
            + '<tr><td style="padding:6px 0;color:#8290aa;font-size:12px;font-weight:800;letter-spacing:0.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Sent</td>'
            + '<td style="padding:6px 0;color:#142342;font-size:15px;font-weight:800;font-family:Arial,sans-serif;">'
            + sentWhen + '</td></tr>'
            + '</table></td></tr>'
            + '<tr><td style="padding:22px 30px 0;">'
            + '<div style="color:#22314f;font-size:15px;line-height:1.65;font-family:Arial,sans-serif;">'
            + 'Check the email address on the lead, correct it if needed, and send the request again. '
            + 'Until then the borrower has not received anything.'
            + '</div></td></tr>'
            + '<tr><td align="center" style="padding:26px 30px 30px;">'
            + '<a href="' + htmlEncode(leadUrl) + '" style="display:inline-block;background:#ff9824;color:#122242;font-size:15px;font-weight:900;font-family:Arial,sans-serif;text-decoration:none;padding:14px 34px;border-radius:999px;">Open Lead in Salesforce</a>'
            + '</td></tr>'
            + '<tr><td style="background:#f4f6fa;padding:18px 30px;border-top:1px solid #e2e7f0;">'
            + '<div style="color:#77839c;font-size:12px;line-height:1.6;font-family:Arial,sans-serif;">'
            + 'You are receiving this because you sent the email that bounced.'
            + '</div></td></tr></table>';
    }

    private static String htmlEncode(String value) {
        return value == null ? '' : value.escapeHtml4();
    }
}
