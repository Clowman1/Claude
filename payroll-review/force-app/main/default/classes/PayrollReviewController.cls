// Payroll Review (2026-10-14): monthly payroll shown to each LO on the Command Center and in the
// LO Workspace Volume drawer until the 11th. Records are owned by whoever loads them (Private OWD),
// so every employee-facing method is scoped to UserInfo.getUserId() and runs without sharing.
public without sharing class PayrollReviewController {

    // Feedback goes to Christopher Lowman and Bianca Rodrigues.
    @TestVisible
    static final Set<Id> FEEDBACK_RECIPIENTS = new Set<Id>{ '005f2000009OtLnAAK', '0055x00000Bf9iaAAB' };

    public static final String NOT_REVIEWED = 'Not Reviewed';

    // The caller's open review (closing date not yet passed), newest pay date first; null if none.
    @AuraEnabled
    public static Payroll_Review__c getMine() {
        List<Payroll_Review__c> reviews = [
            SELECT Id, Period__c, Pay_Date__c, Review_Closes__c, Total__c, Status__c, Reviewed_On__c,
                (SELECT Section__c, Loan__c, Loan_Amount__c, Biz_Dev__c, Rate__c, Commission__c
                 FROM Lines__r ORDER BY Sort_Order__c)
            FROM Payroll_Review__c
            WHERE Employee__c = :UserInfo.getUserId() AND Review_Closes__c >= :Date.today()
            ORDER BY Pay_Date__c DESC
            LIMIT 1
        ];
        return reviews.isEmpty() ? null : reviews[0];
    }

    @AuraEnabled
    public static void markReviewed(Id reviewId) {
        Payroll_Review__c review = mine(reviewId);
        if (review.Status__c == NOT_REVIEWED) {
            update new Payroll_Review__c(Id = review.Id, Status__c = 'Reviewed', Reviewed_On__c = System.now());
        }
    }

    @AuraEnabled
    public static void submitFeedback(Id reviewId, String message) {
        if (String.isBlank(message)) {
            throw new AuraHandledException('Please describe the issue.');
        }
        Payroll_Review__c review = mine(reviewId);
        String stamp = System.now().format('MMM d, yyyy h:mm a', 'America/New_York') + ' ET';
        String log = (String.isBlank(review.Feedback__c) ? '' : review.Feedback__c + '\n\n') + stamp + '\n' + message.trim();
        update new Payroll_Review__c(
            Id = review.Id, Status__c = 'Disputed', Reviewed_On__c = System.now(),
            Feedback__c = log.right(32768), Resolved__c = false
        );

        List<String> to = new List<String>();
        for (User u : [SELECT Email FROM User WHERE Id IN :FEEDBACK_RECIPIENTS AND IsActive = true]) {
            to.add(u.Email);
        }
        if (to.isEmpty()) {
            return;
        }
        String name = UserInfo.getName();
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(to);
        mail.setReplyTo(UserInfo.getUserEmail());
        mail.setSenderDisplayName(name);
        mail.setSaveAsActivity(false);
        mail.setSubject('Payroll feedback — ' + name + ' — ' + review.Period__c);
        mail.setPlainTextBody(
            name + ' reported an issue with their ' + review.Period__c + ' payroll:\n\n' + message.trim() +
            '\n\nPaid total shown: $' + review.Total__c.format() +
            '\nReview: ' + Url.getOrgDomainUrl().toExternalForm() + '/' + review.Id
        );
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }

    static Payroll_Review__c mine(Id reviewId) {
        List<Payroll_Review__c> reviews = [
            SELECT Id, Period__c, Total__c, Status__c, Feedback__c
            FROM Payroll_Review__c
            WHERE Id = :reviewId AND Employee__c = :UserInfo.getUserId() AND Review_Closes__c >= :Date.today()
        ];
        if (reviews.isEmpty()) {
            throw new AuraHandledException('This payroll review is closed.');
        }
        return reviews[0];
    }

    // ---------- Monthly load (run by an admin as anonymous Apex; see LOADING.md) ----------

    public class Person {
        public String name;
        public Decimal total;
        public List<Line> lines;
    }

    public class Line {
        public String section;
        public String loan;
        public Decimal loanAmount;
        public String bizDev;
        public String rate;
        public Decimal commission;
    }

    // Replaces each person's review for the period and resets it to Not Reviewed, so a corrected
    // reload pops up again. Throws (loading nothing) if any name does not match exactly one active user.
    public static List<Payroll_Review__c> load(String period, Date payDate, Date reviewCloses, String peopleJson) {
        List<Person> people = (List<Person>) JSON.deserialize(peopleJson, List<Person>.class);
        Set<String> names = new Set<String>();
        for (Person p : people) {
            names.add(p.name);
        }
        Map<String, List<Id>> idsByName = new Map<String, List<Id>>();
        for (User u : [SELECT Id, Name FROM User WHERE Name IN :names AND IsActive = true]) {
            if (!idsByName.containsKey(u.Name)) {
                idsByName.put(u.Name, new List<Id>());
            }
            idsByName.get(u.Name).add(u.Id);
        }
        List<String> bad = new List<String>();
        for (String n : names) {
            if (!idsByName.containsKey(n) || idsByName.get(n).size() != 1) {
                bad.add(n);
            }
        }
        if (!bad.isEmpty()) {
            throw new IllegalArgumentException('No single active user named: ' + String.join(bad, ', '));
        }

        Set<Id> userIds = new Set<Id>();
        for (List<Id> ids : idsByName.values()) {
            userIds.addAll(ids);
        }
        // Reuse an existing review (keeps its Feedback__c history) but replace its lines.
        Map<Id, Id> existingByUser = new Map<Id, Id>();
        for (Payroll_Review__c r : [SELECT Id, Employee__c FROM Payroll_Review__c WHERE Period__c = :period AND Employee__c IN :userIds]) {
            existingByUser.put(r.Employee__c, r.Id);
        }
        delete [SELECT Id FROM Payroll_Review_Line__c WHERE Payroll_Review__c IN :existingByUser.values()];

        List<Payroll_Review__c> reviews = new List<Payroll_Review__c>();
        for (Person p : people) {
            Id userId = idsByName.get(p.name)[0];
            reviews.add(new Payroll_Review__c(
                Id = existingByUser.get(userId), Name = (p.name + ' — ' + period).left(80), Employee__c = userId,
                Period__c = period, Pay_Date__c = payDate, Review_Closes__c = reviewCloses,
                Total__c = p.total, Status__c = NOT_REVIEWED, Reviewed_On__c = null
            ));
        }
        upsert reviews;

        List<Payroll_Review_Line__c> lines = new List<Payroll_Review_Line__c>();
        for (Integer i = 0; i < people.size(); i++) {
            Integer idx = 0;
            for (Line l : people[i].lines) {
                lines.add(new Payroll_Review_Line__c(
                    Name = String.isBlank(l.loan) ? '—' : l.loan.left(80), Payroll_Review__c = reviews[i].Id,
                    Section__c = l.section, Loan__c = l.loan, Loan_Amount__c = l.loanAmount,
                    Biz_Dev__c = l.bizDev, Rate__c = l.rate, Commission__c = l.commission, Sort_Order__c = idx++
                ));
            }
        }
        insert lines;
        return reviews;
    }
}
