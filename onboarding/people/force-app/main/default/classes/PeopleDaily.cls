// People app daily job, scheduled 9 AM: moves hires to Active on their start date, then on weekdays emails
// Bianca and Chris their own overdue / due-soon People tasks (decision 29). Nothing is sent when nothing is due.
// Schedule: System.schedule('People daily 9 AM', '0 0 9 * * ?', new PeopleDaily());
public with sharing class PeopleDaily implements Schedulable {

    // Christopher Lowman, Bianca Rodrigues.
    @TestVisible
    static final Set<Id> DIGEST_TO = new Set<Id>{ '005f2000009OtLnAAK', '0055x00000Bf9iaAAB' };

    public void execute(SchedulableContext ctx) {
        run(Date.today());
    }

    @TestVisible
    static void run(Date today) {
        List<People_Employee__c> starting = [
            SELECT Id FROM People_Employee__c WHERE Status__c IN ('Candidate', 'Pre-Start') AND Start_Date__c <= :today
        ];
        for (People_Employee__c e : starting) {
            e.Status__c = 'Active';
        }
        update starting;
        PeopleUserSync.start();
        // Renewal checklists for the year open every Oct 15 (decision 18); generateRenewals skips anyone who already has one.
        if (today.month() == 10 && today.day() == 15) {
            PeopleController.generateRenewals(today.year());
        }
        sendReminders(today);

        String dow = Datetime.newInstanceGmt(today, Time.newInstance(12, 0, 0, 0)).formatGmt('E');
        if (dow == 'Sat' || dow == 'Sun') {
            return;
        }
        String link = URL.getOrgDomainUrl().toExternalForm() + '/lightning/n/People';
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        for (User u : [SELECT Id, FirstName FROM User WHERE Id IN :DIGEST_TO AND IsActive = true]) {
            List<PeopleController.DigestItem> items = PeopleController.digestFor(u.Id, today);
            if (items.isEmpty()) {
                continue;
            }
            Integer overdue = 0;
            String rows = '';
            for (PeopleController.DigestItem d : items) {
                if (d.overdue) {
                    overdue++;
                }
                rows += '<tr><td style="padding:6px 12px 6px 0">' + d.subject.escapeHtml4() + '</td>'
                    + '<td style="padding:6px 12px 6px 0;color:#5B6472">' + d.employee.escapeHtml4() + '</td>'
                    + '<td style="padding:6px 0;white-space:nowrap;' + (d.overdue ? 'color:#92400E;font-weight:600' : 'color:#5B6472') + '">'
                    + (d.overdue ? 'Overdue · ' : '') + Datetime.newInstanceGmt(d.due, Time.newInstance(12, 0, 0, 0)).formatGmt('EEE, MMM d') + '</td></tr>';
            }
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setTargetObjectId(u.Id);
            m.setSaveAsActivity(false);
            m.setSenderDisplayName('People');
            m.setSubject('People: ' + items.size() + ' task' + (items.size() == 1 ? '' : 's') + ' due' + (overdue > 0 ? ' (' + overdue + ' overdue)' : ''));
            m.setHtmlBody('<div style="font-family:Arial,sans-serif;font-size:14px;color:#111827">'
                + '<p>Good morning ' + (u.FirstName == null ? '' : u.FirstName.escapeHtml4()) + ',</p>'
                + '<p>Your People tasks that are overdue or due in the next 5 business days:</p>'
                + '<table style="border-collapse:collapse;font-size:14px">' + rows + '</table>'
                + '<p><a href="' + link + '">Open People</a></p></div>');
            mails.add(m);
        }
        if (!mails.isEmpty()) {
            Messaging.sendEmail(mails, false);
        }
    }

    // Tasks flagged Email Reminder (the 30/90-day check-ins and benefits deadline) email their assignee
    // 7 days before and on the due date, every day of the week, on top of the weekday digest.
    @TestVisible
    static Integer sendReminders(Date today) {
        String link = URL.getOrgDomainUrl().toExternalForm() + '/lightning/n/People';
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        for (People_Task__c t : [
            SELECT Name, Due_Date__c, Assigned_To__c, Description__c, Checklist__r.Employee__r.Name
            FROM People_Task__c
            WHERE Remind__c = true AND Status__c = 'Open' AND Assigned_To__c != null AND Checklist__r.Status__c = 'Open'
                AND Checklist__r.Employee__r.Status__c NOT IN :PeopleController.GONE AND Due_Date__c IN :new Set<Date>{ today, today.addDays(7) }
        ]) {
            String dueText = t.Due_Date__c == today ? 'today' : 'on ' + Datetime.newInstanceGmt(t.Due_Date__c, Time.newInstance(12, 0, 0, 0)).formatGmt('EEEE, MMMM d');
            String who = t.Checklist__r.Employee__r.Name;
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setTargetObjectId(t.Assigned_To__c);
            m.setSaveAsActivity(false);
            m.setSenderDisplayName('People');
            m.setSubject('Reminder: ' + t.Name + ' for ' + who + ' is due ' + dueText);
            m.setHtmlBody('<div style="font-family:Arial,sans-serif;font-size:14px;color:#111827">'
                + '<p><strong>' + t.Name.escapeHtml4() + '</strong> for ' + who.escapeHtml4() + ' is due ' + dueText + '.</p>'
                + (t.Description__c == null ? '' : '<p style="color:#5B6472">' + t.Description__c.escapeHtml4() + '</p>')
                + '<p><a href="' + link + '">Open People</a></p></div>');
            mails.add(m);
        }
        if (!mails.isEmpty()) {
            Messaging.sendEmail(mails, false);
        }
        return mails.size();
    }
}
