/**
 * Emails each processor a morning digest of the transactions they are assigned to whose loan
 * commitment date is today. Processors with nothing due today are not emailed at all.
 *
 * Scheduled daily at 10 AM Eastern via cron '0 0 10 * * ?'. System.schedule interprets that
 * expression in the scheduling user's time zone, so it must be scheduled by a user in
 * America/New_York (the org default).
 *
 * Declared without sharing on purpose: the digest must cover every processor's own files
 * regardless of what the user who scheduled the job can see.
 */
public without sharing class ProcessorCommitmentDigestScheduler implements Schedulable {
    private static final String SENDER_ADDRESS = 'reachus@reachhomeloans.com';

    @TestVisible
    private static final String EMAIL_SUBJECT = 'Today\'s Commitments Due';

    // Mirrors the Pipeline Command Center's definition of a file that is no longer actively
    // worked, so the digest and the Approaching Commitments tab agree on what counts as active.
    private static final Set<String> INACTIVE_STATUSES = new Set<String>{
        'Cancelled',
        'PC Review',
        'QC Review',
        'Post-Closed',
        'Lost'
    };

    public void execute(SchedulableContext context) {
        List<Messaging.SingleEmailMessage> messages = buildMessages(findCommitmentsDueToday());
        if (messages.isEmpty()) {
            return;
        }
        if (!Test.isRunningTest()) {
            Messaging.sendEmail(messages, false);
        }
    }

    // Public so the digest can be previewed or re-sent without duplicating the query.
    public static List<Transaction__c> findCommitmentsDueToday() {
        return [
            SELECT Id, Name, Status__c, Closing_Date__c, Loan_Amount_1st__c,
                Borrower_First_Name__c, Borrower_Last_Name__c,
                Processor__c, Processor__r.Email, Processor__r.FirstName, Processor__r.IsActive
            FROM Transaction__c
            WHERE Loan_Commitment_Date__c = TODAY
                AND Processor__c != NULL
                AND Status__c NOT IN :INACTIVE_STATUSES
            ORDER BY Closing_Date__c ASC NULLS LAST, Name ASC
        ];
    }

    // Public and side-effect free: builds the messages but never sends them, so callers can
    // inspect or redirect the output before anything leaves the org.
    public static List<Messaging.SingleEmailMessage> buildMessages(List<Transaction__c> transactions) {
        Map<Id, List<Transaction__c>> dueByProcessor = new Map<Id, List<Transaction__c>>();
        for (Transaction__c transactionRecord : transactions) {
            // A deactivated user cannot receive mail and a processor with no address has nowhere
            // to send, so both are skipped rather than failing the whole send.
            if (
                transactionRecord.Processor__r == null ||
                transactionRecord.Processor__r.IsActive != true ||
                String.isBlank(transactionRecord.Processor__r.Email)
            ) {
                continue;
            }
            if (!dueByProcessor.containsKey(transactionRecord.Processor__c)) {
                dueByProcessor.put(transactionRecord.Processor__c, new List<Transaction__c>());
            }
            dueByProcessor.get(transactionRecord.Processor__c).add(transactionRecord);
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        if (dueByProcessor.isEmpty()) {
            return messages;
        }

        Id senderId = resolveSenderId();
        for (Id processorId : dueByProcessor.keySet()) {
            List<Transaction__c> dueToday = dueByProcessor.get(processorId);
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ dueToday[0].Processor__r.Email });
            email.setSubject(EMAIL_SUBJECT);
            email.setHtmlBody(buildHtmlBody(dueToday));
            if (senderId != null) {
                email.setOrgWideEmailAddressId(senderId);
            }
            messages.add(email);
        }
        return messages;
    }

    private static Id resolveSenderId() {
        List<OrgWideEmailAddress> addresses = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :SENDER_ADDRESS
            LIMIT 1
        ];
        return addresses.isEmpty() ? null : addresses[0].Id;
    }

    private static String buildHtmlBody(List<Transaction__c> dueToday) {
        String firstName = String.isBlank(dueToday[0].Processor__r.FirstName)
            ? 'there'
            : dueToday[0].Processor__r.FirstName;
        String countPhrase = dueToday.size() == 1
            ? '1 commitment due today'
            : dueToday.size() + ' commitments due today';
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String cellStyle = ' style="border:1px solid #c9ced6;"';

        String html = '<div style="font-family:Arial,sans-serif;font-size:13px;color:#222222;">';
        html += '<p>Hi ' + firstName.escapeHtml4() + ',</p>';
        html += '<p>You have <strong>' + countPhrase + '</strong> (' + Date.today().format() + ').</p>';
        html += '<table cellpadding="6" cellspacing="0" style="border-collapse:collapse;border:1px solid #c9ced6;font-size:13px;">';
        html += '<tr style="background:#001c54;color:#ffffff;">';
        html += '<th align="left"' + cellStyle + '>Transaction</th>';
        html += '<th align="left"' + cellStyle + '>Borrower</th>';
        html += '<th align="left"' + cellStyle + '>Status</th>';
        html += '<th align="left"' + cellStyle + '>Closing Date</th>';
        html += '<th align="right"' + cellStyle + '>Loan Amount</th>';
        html += '</tr>';

        for (Transaction__c transactionRecord : dueToday) {
            html += '<tr>';
            html += '<td' + cellStyle + '><a href="' + baseUrl + '/' + transactionRecord.Id + '">'
                + blankIfNull(transactionRecord.Name).escapeHtml4() + '</a></td>';
            html += '<td' + cellStyle + '>' + borrowerName(transactionRecord).escapeHtml4() + '</td>';
            html += '<td' + cellStyle + '>' + blankIfNull(transactionRecord.Status__c).escapeHtml4() + '</td>';
            html += '<td' + cellStyle + '>'
                + (transactionRecord.Closing_Date__c == null ? '' : transactionRecord.Closing_Date__c.format()) + '</td>';
            html += '<td align="right"' + cellStyle + '>' + formatAmount(transactionRecord.Loan_Amount_1st__c) + '</td>';
            html += '</tr>';
        }

        html += '</table>';
        html += '</div>';
        return html;
    }

    private static String borrowerName(Transaction__c transactionRecord) {
        return (blankIfNull(transactionRecord.Borrower_First_Name__c) + ' '
            + blankIfNull(transactionRecord.Borrower_Last_Name__c)).trim();
    }

    private static String blankIfNull(String value) {
        return value == null ? '' : value;
    }

    private static String formatAmount(Decimal amount) {
        return amount == null ? '' : '$' + amount.setScale(0).format();
    }
}