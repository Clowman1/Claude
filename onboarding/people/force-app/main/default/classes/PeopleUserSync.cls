// People app (2026-10-22): links People employees to their Salesforce user by work email, completes the
// "Salesforce user linked" tasks, then copies NMLS ID and Licensed States onto the User (Employee is the master, decision 38).
// User is a setup object, so the two halves run as chained queueables to avoid mixed DML.
// Started by PeopleUserTrigger (new user / email change), employee saves, and the 9 AM PeopleDaily run.
public without sharing class PeopleUserSync implements Queueable {

    final Boolean usersStep;

    public PeopleUserSync(Boolean usersStep) {
        this.usersStep = usersStep;
    }

    public static void start() {
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new PeopleUserSync(false));
        }
    }

    public void execute(QueueableContext ctx) {
        if (usersStep) {
            syncUsers();
            return;
        }
        linkEmployees();
        if (!Test.isRunningTest()) {
            System.enqueueJob(new PeopleUserSync(true));
        }
    }

    @TestVisible
    static void linkEmployees() {
        Map<String, People_Employee__c> byEmail = new Map<String, People_Employee__c>();
        for (People_Employee__c e : [
            SELECT Id, Work_Email__c FROM People_Employee__c
            WHERE User__c = null AND Work_Email__c != null AND Status__c NOT IN :PeopleController.GONE
        ]) {
            byEmail.put(e.Work_Email__c.toLowerCase(), e);
        }
        if (byEmail.isEmpty()) {
            return;
        }
        List<People_Employee__c> linked = new List<People_Employee__c>();
        for (User u : [SELECT Id, Email FROM User WHERE Email IN :byEmail.keySet() AND IsActive = true AND UserType = 'Standard' ORDER BY CreatedDate]) {
            People_Employee__c e = byEmail.remove(u.Email.toLowerCase());
            if (e != null) {
                e.User__c = u.Id;
                linked.add(e);
            }
        }
        update linked;
        List<People_Task__c> tasks = [
            SELECT Id FROM People_Task__c
            WHERE Auto_Complete__c = 'Salesforce user linked' AND Status__c = 'Open' AND Checklist__r.Status__c = 'Open' AND Checklist__r.Employee__c IN :linked
        ];
        for (People_Task__c t : tasks) {
            t.Status__c = 'Done';
            t.Completed_By__c = UserInfo.getUserId();
            t.Completed_At__c = System.now();
            t.Notes__c = 'Auto-completed: Salesforce user linked';
        }
        update tasks;
    }

    // Copies only non-blank Employee values, so an Employee with no NMLS ID never wipes the User's.
    @TestVisible
    static void syncUsers() {
        List<User> changed = new List<User>();
        for (People_Employee__c e : [
            SELECT NMLS_ID__c, Licensed_States__c, User__c, User__r.NMLS__c, User__r.Licensed_States__c FROM People_Employee__c
            WHERE User__c != null AND Status__c NOT IN :PeopleController.GONE AND (NMLS_ID__c != null OR Licensed_States__c != null)
        ]) {
            User u = new User(Id = e.User__c);
            Boolean dirty = false;
            if (e.NMLS_ID__c != null && e.NMLS_ID__c != e.User__r.NMLS__c) {
                u.NMLS__c = e.NMLS_ID__c;
                dirty = true;
            }
            if (e.Licensed_States__c != null && e.Licensed_States__c != e.User__r.Licensed_States__c) {
                u.Licensed_States__c = e.Licensed_States__c;
                dirty = true;
            }
            if (dirty) {
                changed.add(u);
            }
        }
        Database.update(changed, false);
    }
}
