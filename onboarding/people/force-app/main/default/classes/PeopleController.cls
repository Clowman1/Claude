// People app (2026-10-22): employee onboarding board, hire timeline and master template editor (spec: onboarding/SPEC.md).
// Callers hold People_Admin (View All / Modify All on every People object), so plain with-sharing SOQL sees everything.
// Completed By/At are only ever stamped here; the permission set makes them read-only.
public with sharing class PeopleController {

    public static final String ONBOARDING = 'Onboarding';
    public static final String OFFBOARDING = 'Offboarding';
    public static final String RENEWAL = 'Renewal';
    public static final String BRANCH = 'Branch';
    public static final Set<String> GONE = new Set<String>{ 'Terminated', 'Withdrawn' };

    // Compliance sign-off (decision 24): Bianca Rodrigues, with Christopher Lowman as backup.
    @TestVisible
    static Set<Id> signers = new Set<Id>{ '0055x00000Bf9iaAAB', '005f2000009OtLnAAK' };
    public static final String ATTESTATION = 'I attest that every item on this checklist was completed as recorded.';

    // ---------- business days ----------
    // Company holidays are attached to the TRID business hours only (Default has none), and TRID counts
    // Saturday as a business day, so weekends are skipped here and TRID answers only "is it a holiday".
    static Id tridId;
    static Boolean tridLoaded = false;
    static Map<Date, Boolean> workdays = new Map<Date, Boolean>();

    @TestVisible
    static Boolean isWorkday(Date d) {
        if (workdays.containsKey(d)) {
            return workdays.get(d);
        }
        Datetime noon = Datetime.newInstanceGmt(d, Time.newInstance(12, 0, 0, 0));
        String dow = noon.formatGmt('E');
        Boolean ok = dow != 'Sat' && dow != 'Sun';
        if (ok) {
            if (!tridLoaded) {
                List<BusinessHours> bh = [SELECT Id FROM BusinessHours WHERE Name = 'TRID' AND IsActive = true LIMIT 1];
                tridId = bh.isEmpty() ? null : bh[0].Id;
                tridLoaded = true;
            }
            ok = tridId == null || BusinessHours.isWithin(tridId, noon);
        }
        workdays.put(d, ok);
        return ok;
    }

    @TestVisible
    static Date addBusinessDays(Date start, Integer n) {
        if (start == null || n == null) {
            return null;
        }
        Date d = start;
        Integer step = n < 0 ? -1 : 1;
        for (Integer left = Math.abs(n); left > 0;) {
            d = d.addDays(step);
            if (isWorkday(d)) {
                left--;
            }
        }
        return d;
    }

    // Calendar-day offsets (the 30/90-day items) count straight days, then roll forward off a weekend or holiday.
    @TestVisible
    static Date dueDate(Date start, Decimal offset, String unit) {
        if (start == null || offset == null) {
            return null;
        }
        if (unit != 'Calendar Days') {
            return addBusinessDays(start, offset.intValue());
        }
        Date d = start.addDays(offset.intValue());
        while (!isWorkday(d)) {
            d = d.addDays(1);
        }
        return d;
    }

    // ---------- shapes ----------
    // One open checklist on the board. id is the employee or branch the checklist belongs to.
    public class Card {
        @AuraEnabled public Id id;
        @AuraEnabled public Id checklistId;
        @AuraEnabled public String type;
        @AuraEnabled public Decimal year;
        @AuraEnabled public Date anchorDate;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public String arrangement;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public String branch;
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer done = 0;
        @AuraEnabled public Integer overdue = 0;
        @AuraEnabled public String nextSubject;
        @AuraEnabled public Date nextDue;
    }

    public class DigestItem {
        @AuraEnabled public Id taskId;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employee;
        @AuraEnabled public String subject;
        @AuraEnabled public Date due;
        @AuraEnabled public Boolean overdue;
    }

    public class Board {
        @AuraEnabled public List<Card> cards = new List<Card>();
        @AuraEnabled public List<People_Employee__c> staff;
        @AuraEnabled public List<People_Branch__c> branches;
        @AuraEnabled public List<DigestItem> digest;
        @AuraEnabled public Integer renewalYear = Date.today().year();
        @AuraEnabled public Integer renewalEligible;
        @AuraEnabled public Date today = Date.today();
    }

    // The People page for one employee or one branch, showing one of its checklists.
    public class Detail {
        @AuraEnabled public People_Employee__c employee;
        @AuraEnabled public People_Branch__c branch;
        @AuraEnabled public List<People_Checklist__c> checklists;
        @AuraEnabled public People_Checklist__c checklist;
        @AuraEnabled public Integer openLeads;
        @AuraEnabled public Integer openTransactions;
        @AuraEnabled public List<People_Task__c> tasks;
        @AuraEnabled public List<People_Template_Task__c> optional;
        @AuraEnabled public Boolean canViewPersonal;
        @AuraEnabled public Boolean canSignOff;
        @AuraEnabled public String attestation;
        @AuraEnabled public Date today = Date.today();
    }

    public class EmailDraft {
        @AuraEnabled public String to;
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // ---------- board ----------
    @AuraEnabled
    public static Board getBoard() {
        Board b = new Board();
        for (People_Checklist__c cl : [
            SELECT Id, Type__c, Renewal_Year__c, Anchor_Date__c, Employee__c, Employee__r.Name, Employee__r.Role__c, Employee__r.Work_Arrangement__c,
                Employee__r.Status__c, Employee__r.Start_Date__c, Employee__r.Branch__r.Name, Branch__c, Branch__r.Name, Branch__r.State__c, Branch__r.Status__c,
                (SELECT Name, Status__c, Due_Date__c FROM Tasks__r ORDER BY Due_Date__c NULLS LAST, Sort_Order__c)
            FROM People_Checklist__c
            WHERE Status__c = 'Open' AND (Employee__c = null OR Employee__r.Status__c NOT IN :GONE)
            ORDER BY Anchor_Date__c NULLS LAST, Name
        ]) {
            Card c = new Card();
            c.checklistId = cl.Id;
            c.type = cl.Type__c;
            c.year = cl.Renewal_Year__c;
            c.anchorDate = cl.Anchor_Date__c;
            if (cl.Employee__c != null) {
                c.id = cl.Employee__c;
                c.name = cl.Employee__r.Name;
                c.role = cl.Employee__r.Role__c;
                c.arrangement = cl.Employee__r.Work_Arrangement__c;
                c.status = cl.Employee__r.Status__c;
                c.startDate = cl.Employee__r.Start_Date__c;
                c.branch = cl.Employee__r.Branch__r?.Name;
            } else {
                c.id = cl.Branch__c;
                c.name = cl.Branch__r?.Name;
                c.role = cl.Branch__r?.State__c;
                c.status = cl.Branch__r?.Status__c;
            }
            for (People_Task__c t : cl.Tasks__r) {
                c.total++;
                if (t.Status__c != 'Open') {
                    c.done++;
                    continue;
                }
                if (t.Due_Date__c != null && t.Due_Date__c < b.today) {
                    c.overdue++;
                }
                if (c.nextSubject == null) {
                    c.nextSubject = t.Name;
                    c.nextDue = t.Due_Date__c;
                }
            }
            b.cards.add(c);
        }
        b.staff = [
            SELECT Id, Name, Role__c, Work_Arrangement__c, Status__c, Start_Date__c, NMLS_ID__c, Licensed_States__c, Manager__r.Name, Branch__r.Name,
                User__c, Termination_Date__c
            FROM People_Employee__c WHERE Status__c NOT IN :GONE ORDER BY Name
        ];
        b.renewalEligible = renewalTargets(b.renewalYear).size();
        b.branches = [
            SELECT Id, Name, State__c, Status__c, Target_Open_Date__c, Branch_Manager__r.Name, (SELECT Name FROM Employees__r WHERE Status__c NOT IN :GONE)
            FROM People_Branch__c WHERE Status__c != 'Closed' ORDER BY Name
        ];
        b.digest = digestFor(UserInfo.getUserId(), b.today);
        return b;
    }

    // Open tasks assigned to the user that are overdue or due within the next 5 business days. Also feeds the 9 AM email.
    public static List<DigestItem> digestFor(Id userId, Date today) {
        List<DigestItem> items = new List<DigestItem>();
        Date horizon = addBusinessDays(today, 5);
        for (People_Task__c t : [
            SELECT Id, Name, Due_Date__c, Checklist__r.Employee__c, Checklist__r.Employee__r.Name, Checklist__r.Branch__c, Checklist__r.Branch__r.Name
            FROM People_Task__c
            WHERE Assigned_To__c = :userId AND Status__c = 'Open' AND Checklist__r.Status__c = 'Open'
                AND (Checklist__r.Employee__c = null OR Checklist__r.Employee__r.Status__c NOT IN :GONE) AND Due_Date__c <= :horizon
            ORDER BY Due_Date__c, Sort_Order__c LIMIT 200
        ]) {
            DigestItem d = new DigestItem();
            d.taskId = t.Id;
            // employeeId/employee name whichever record owns the checklist: an employee, or a branch.
            d.employeeId = t.Checklist__r.Employee__c != null ? t.Checklist__r.Employee__c : t.Checklist__r.Branch__c;
            d.employee = t.Checklist__r.Employee__c != null ? t.Checklist__r.Employee__r.Name : t.Checklist__r.Branch__r?.Name;
            d.subject = t.Name;
            d.due = t.Due_Date__c;
            d.overdue = t.Due_Date__c < today;
            items.add(d);
        }
        return items;
    }

    // ---------- one employee or branch ----------
    // Kept for callers that only know the employee: shows the open onboarding checklist (else the newest).
    @AuraEnabled
    public static Detail getEmployee(Id employeeId) {
        return getDetail(employeeId, null);
    }

    // recordId is a People_Employee__c or a People_Branch__c; checklistId picks one of its checklists (null = the
    // first open one by Onboarding, Offboarding, Renewal, Branch order, else the newest).
    @AuraEnabled
    public static Detail getDetail(Id recordId, Id checklistId) {
        Detail d = new Detail();
        Boolean isBranch = recordId.getSObjectType() == People_Branch__c.SObjectType;
        if (isBranch) {
            d.branch = [
                SELECT Id, Name, State__c, Address__c, Branch_NMLS_ID__c, Branch_Manager__c, Branch_Manager__r.Name, Target_Open_Date__c, Status__c,
                    (SELECT Id, Name, Role__c, Status__c FROM Employees__r ORDER BY Name)
                FROM People_Branch__c WHERE Id = :recordId
            ];
        } else {
            d.employee = [
                SELECT Id, Name, First_Name__c, Last_Name__c, Role__c, Work_Arrangement__c, Status__c, Start_Date__c, Manager__c, Manager__r.Name,
                    Branch__c, Branch__r.Name, Work_Email__c, Personal_Email__c, NMLS_ID__c, Licensed_States__c, User__c, User__r.Name,
                    Termination_Date__c, Termination_Reason__c
                FROM People_Employee__c WHERE Id = :recordId
            ];
        }
        d.checklists = [
            SELECT Id, Name, Type__c, Status__c, Renewal_Year__c, Anchor_Date__c, Signed_Off_By__r.Name, Signed_Off_At__c, Exam_PDF_Id__c
            FROM People_Checklist__c WHERE Employee__c = :recordId OR Branch__c = :recordId ORDER BY CreatedDate DESC
        ];
        d.checklist = pickChecklist(d.checklists, checklistId);
        d.tasks = d.checklist == null ? new List<People_Task__c>() : [
            SELECT Id, Name, Phase__c, Sort_Order__c, Description__c, Due_Date__c, Status__c, Assigned_To__c, Assigned_To__r.Name, Led_By__c,
                Completed_By__r.Name, Completed_At__c, Notes__c, Email_Template__c, Via_DocuSign__c, Send_To__c, Template_Task__c, Remind__c
            FROM People_Task__c WHERE Checklist__c = :d.checklist.Id ORDER BY Sort_Order__c, Due_Date__c
        ];
        Set<Id> used = new Set<Id>();
        for (People_Task__c t : d.tasks) {
            used.add(t.Template_Task__c);
        }
        d.optional = new List<People_Template_Task__c>();
        if (d.checklist != null) {
            for (People_Template_Task__c t : templates(d.checklist.Type__c, true)) {
                if (!used.contains(t.Id) && (isBranch || applies(t, d.employee.Role__c, d.employee.Work_Arrangement__c))) {
                    d.optional.add(t);
                }
            }
        }
        // What an offboarding has to hand over: unconverted Leads they own and active Transactions they are LO on.
        if (d.employee?.User__c != null) {
            Id u = d.employee.User__c;
            d.openLeads = [SELECT COUNT() FROM Lead WHERE OwnerId = :u AND IsConverted = false];
            d.openTransactions = [SELECT COUNT() FROM Transaction__c WHERE Loan_Officer__c = :u AND Status__c NOT IN ('Post-Closed', 'Cancelled', 'Lost')];
        }
        d.canViewPersonal = !isBranch && canViewPersonal();
        d.canSignOff = signers.contains(UserInfo.getUserId());
        d.attestation = ATTESTATION;
        return d;
    }

    static People_Checklist__c pickChecklist(List<People_Checklist__c> cls, Id checklistId) {
        for (People_Checklist__c c : cls) {
            if (c.Id == checklistId) {
                return c;
            }
        }
        for (String type : new List<String>{ ONBOARDING, OFFBOARDING, RENEWAL, BRANCH }) {
            for (People_Checklist__c c : cls) {
                if (c.Type__c == type && c.Status__c == 'Open') {
                    return c;
                }
            }
        }
        return cls.isEmpty() ? null : cls[0];
    }

    @AuraEnabled
    public static Map<String, Object> previewChecklist(String role, String arrangement, Date startDate) {
        Integer n = 0, opt = 0;
        Date firstDue;
        for (People_Template_Task__c t : templates(ONBOARDING, null)) {
            if (!applies(t, role, arrangement)) {
                continue;
            }
            if (t.Optional__c) {
                opt++;
                continue;
            }
            n++;
            Date due = dueDate(startDate, t.Offset_Days__c, t.Offset_Unit__c);
            if (due != null && (firstDue == null || due < firstDue)) {
                firstDue = due;
            }
        }
        return new Map<String, Object>{ 'count' => n, 'optional' => opt, 'firstDue' => firstDue };
    }

    @AuraEnabled
    public static Id createEmployee(People_Employee__c employee) {
        if (String.isBlank(employee.First_Name__c) || String.isBlank(employee.Last_Name__c) || employee.Start_Date__c == null
                || String.isBlank(employee.Role__c) || String.isBlank(employee.Work_Arrangement__c)) {
            throw new AuraHandledException('First name, last name, role, work arrangement and start date are required.');
        }
        employee.Id = null;
        employee.Name = fullName(employee);
        if (String.isBlank(employee.Status__c)) {
            employee.Status__c = 'Candidate';
        }
        insert employee;
        generate(ONBOARDING, employee, null, employee.Start_Date__c, null);
        PeopleUserSync.start();
        return employee.Id;
    }

    // Creates one checklist of the given type for an employee or a branch, with every matching active template task.
    // Renewal tasks marked One Per Licensed State repeat once per state, with {STATE} in the subject replaced.
    @TestVisible
    static Id generate(String type, People_Employee__c emp, People_Branch__c br, Date anchor, Integer year) {
        String who = emp != null ? emp.Name : br.Name;
        People_Checklist__c cl = new People_Checklist__c(
            Name = (type + (year == null ? '' : ' ' + year) + ' · ' + who).left(80), Type__c = type, Status__c = 'Open',
            Employee__c = emp?.Id, Branch__c = br?.Id, Anchor_Date__c = anchor, Renewal_Year__c = year
        );
        insert cl;
        List<People_Task__c> tasks = new List<People_Task__c>();
        // For renewals, licensing follows the NMLS ID, not the job: a President or Manager with an NMLS ID renews like an LO.
        String role = emp == null ? null : type == RENEWAL ? (emp.NMLS_ID__c != null ? 'Loan Officer' : 'Unlicensed') : emp.Role__c;
        for (People_Template_Task__c t : templates(type, false)) {
            if (emp != null && !applies(t, role, emp.Work_Arrangement__c)) {
                continue;
            }
            if (!t.Per_State__c) {
                tasks.add(fromTemplate(t, cl.Id, anchor));
                continue;
            }
            for (String st : emp?.Licensed_States__c == null ? new List<String>() : emp.Licensed_States__c.split(';')) {
                People_Task__c task = fromTemplate(t, cl.Id, anchor);
                task.Name = t.Name.replace('{STATE}', st).left(80);
                tasks.add(task);
            }
        }
        insert tasks;
        return cl.Id;
    }

    // Returns how many open tasks now fall before today after a start-date or last-day move (the UI warns on > 0).
    @AuraEnabled
    public static Integer saveEmployee(People_Employee__c employee) {
        employee.Name = fullName(employee);
        update employee;
        PeopleUserSync.start();
        Integer late = 0;
        if (employee.Start_Date__c != null) {
            late += moveAnchor(employee.Id, ONBOARDING, employee.Start_Date__c);
        }
        if (employee.Termination_Date__c != null) {
            late += moveAnchor(employee.Id, OFFBOARDING, employee.Termination_Date__c);
        }
        return late;
    }

    // Re-dates the open tasks of the record's open checklist of this type when its anchor date changed.
    static Integer moveAnchor(Id recordId, String type, Date anchor) {
        List<People_Checklist__c> cls = [
            SELECT Id, Anchor_Date__c FROM People_Checklist__c
            WHERE (Employee__c = :recordId OR Branch__c = :recordId) AND Type__c = :type AND Status__c = 'Open'
        ];
        Integer late = 0;
        for (People_Checklist__c cl : cls) {
            if (cl.Anchor_Date__c == anchor) {
                continue;
            }
            List<People_Task__c> open = [
                SELECT Id, Offset_Days__c, Offset_Unit__c FROM People_Task__c
                WHERE Checklist__c = :cl.Id AND Status__c = 'Open' AND Offset_Days__c != null
            ];
            for (People_Task__c t : open) {
                t.Due_Date__c = dueDate(anchor, t.Offset_Days__c, t.Offset_Unit__c);
                if (t.Due_Date__c < Date.today()) {
                    late++;
                }
            }
            update open;
            update new People_Checklist__c(Id = cl.Id, Anchor_Date__c = anchor);
        }
        return late;
    }

    // ---------- offboarding, renewals, branches (phase 3) ----------
    @AuraEnabled
    public static Id offboard(Id employeeId, Date lastDay, String reason) {
        if (lastDay == null) {
            throw new AuraHandledException('Last day is required.');
        }
        People_Employee__c e = [
            SELECT Id, Name, Role__c, Work_Arrangement__c, Licensed_States__c, Status__c FROM People_Employee__c WHERE Id = :employeeId
        ];
        if (GONE.contains(e.Status__c)) {
            throw new AuraHandledException(e.Name + ' is already ' + e.Status__c + '.');
        }
        if ([SELECT COUNT() FROM People_Checklist__c WHERE Employee__c = :employeeId AND Type__c = :OFFBOARDING AND Status__c = 'Open'] > 0) {
            throw new AuraHandledException(e.Name + ' already has an open offboarding checklist.');
        }
        update new People_Employee__c(Id = e.Id, Status__c = 'Offboarding', Termination_Date__c = lastDay, Termination_Reason__c = reason);
        return generate(OFFBOARDING, e, null, lastDay, null);
    }

    // Active and Pre-Start employees with no renewal checklist for the year yet.
    static List<People_Employee__c> renewalTargets(Integer year) {
        return [
            SELECT Id, Name, Role__c, Work_Arrangement__c, Licensed_States__c, NMLS_ID__c FROM People_Employee__c
            WHERE Status__c IN ('Active', 'Pre-Start')
                AND Id NOT IN (SELECT Employee__c FROM People_Checklist__c WHERE Type__c = :RENEWAL AND Renewal_Year__c = :year AND Employee__c != null)
            ORDER BY Name
        ];
    }

    // Renewal due dates count from Dec 31 of the year (the NMLS renewal deadline). Safe to run twice: done employees are skipped.
    // ponytail: two DML per employee; fine for a staff of dozens, bulkify past ~70 employees.
    @AuraEnabled
    public static Integer generateRenewals(Integer year) {
        Integer n = 0;
        for (People_Employee__c e : renewalTargets(year)) {
            generate(RENEWAL, e, null, Date.newInstance(year, 12, 31), year);
            n++;
        }
        return n;
    }

    // Insert or update a branch. Its branch checklist starts once it has a target open date, and later
    // target-date moves re-date the open tasks.
    @AuraEnabled
    public static Id saveBranch(People_Branch__c rec) {
        if (String.isBlank(rec.Name)) {
            throw new AuraHandledException('Branch name is required.');
        }
        if (String.isBlank(rec.Status__c)) {
            rec.Status__c = 'Planning';
        }
        upsert rec;
        if (rec.Target_Open_Date__c != null) {
            if ([SELECT COUNT() FROM People_Checklist__c WHERE Branch__c = :rec.Id AND Type__c = :BRANCH] == 0) {
                generate(BRANCH, null, rec, rec.Target_Open_Date__c, null);
            } else {
                moveAnchor(rec.Id, BRANCH, rec.Target_Open_Date__c);
            }
        }
        return rec.Id;
    }

    @AuraEnabled
    public static void withdraw(Id employeeId) {
        update new People_Employee__c(Id = employeeId, Status__c = 'Withdrawn');
        List<People_Task__c> open = [SELECT Id FROM People_Task__c WHERE Checklist__r.Employee__c = :employeeId AND Status__c = 'Open'];
        for (People_Task__c t : open) {
            t.Status__c = 'N/A';
            t.Completed_By__c = UserInfo.getUserId();
            t.Completed_At__c = System.now();
        }
        update open;
        List<People_Checklist__c> cls = [SELECT Id FROM People_Checklist__c WHERE Employee__c = :employeeId AND Status__c = 'Open'];
        for (People_Checklist__c c : cls) {
            c.Status__c = 'Closed';
        }
        update cls;
    }

    // ---------- tasks ----------
    @AuraEnabled
    public static void setTaskStatus(Id taskId, String status) {
        People_Task__c t = [
            SELECT Id, Sets_Status__c, Checklist__r.Status__c, Checklist__r.Employee__c, Checklist__r.Employee__r.Status__c
            FROM People_Task__c WHERE Id = :taskId
        ];
        if (t.Checklist__r.Status__c != 'Open') {
            throw new AuraHandledException('This checklist is closed and can no longer change.');
        }
        Boolean closing = status == 'Done' || status == 'N/A';
        update new People_Task__c(
            Id = t.Id, Status__c = closing ? status : 'Open',
            Completed_By__c = closing ? UserInfo.getUserId() : null,
            Completed_At__c = closing ? System.now() : null
        );
        if (status == 'Done' && t.Sets_Status__c != null && t.Checklist__r.Employee__r?.Status__c == 'Candidate') {
            update new People_Employee__c(Id = t.Checklist__r.Employee__c, Status__c = t.Sets_Status__c);
        }
    }

    @AuraEnabled
    public static void updateTask(Id taskId, Id assignedTo, Date dueDate, String notes) {
        requireOpen([SELECT Checklist__r.Status__c FROM People_Task__c WHERE Id = :taskId].Checklist__r.Status__c);
        update new People_Task__c(Id = taskId, Assigned_To__c = assignedTo, Due_Date__c = dueDate, Notes__c = notes);
    }

    @AuraEnabled
    public static void addOptionalTask(Id checklistId, Id templateId) {
        People_Checklist__c cl = [SELECT Id, Type__c, Status__c, Anchor_Date__c FROM People_Checklist__c WHERE Id = :checklistId];
        requireOpen(cl.Status__c);
        for (People_Template_Task__c t : getTemplates(cl.Type__c)) {
            if (t.Id == templateId) {
                insert fromTemplate(t, cl.Id, cl.Anchor_Date__c);
            }
        }
    }

    @AuraEnabled
    public static void addCustomTask(Id checklistId, String subject, String phase, Date dueDate, Id assignedTo) {
        if (String.isBlank(subject)) {
            throw new AuraHandledException('Subject is required.');
        }
        requireOpen([SELECT Status__c FROM People_Checklist__c WHERE Id = :checklistId].Status__c);
        insert new People_Task__c(
            Name = subject.trim().left(80), Checklist__c = checklistId, Phase__c = phase, Due_Date__c = dueDate,
            Assigned_To__c = assignedTo, Status__c = 'Open', Sort_Order__c = 99999
        );
    }

    static void requireOpen(String checklistStatus) {
        if (checklistStatus != 'Open') {
            throw new AuraHandledException('This checklist is closed and can no longer change.');
        }
    }

    // ---------- email (Bianca's templates, decision 16) ----------
    // A task's Email_Template__c "PH-3" maps to the classic template People_PH_3 in the People Onboarding folder.
    // {{SEND_DATE_PLUS_2}} in a template becomes the send date + 2 business days (the Paychex deadline).
    @AuraEnabled
    public static EmailDraft getEmailDraft(Id taskId) {
        People_Task__c t = [
            SELECT Email_Template__c, Send_To__c, Checklist__r.Status__c, Checklist__r.Employee__c, Checklist__r.Employee__r.Personal_Email__c
            FROM People_Task__c WHERE Id = :taskId
        ];
        requireOpen(t.Checklist__r.Status__c);
        String dev = 'People_' + String.valueOf(t.Email_Template__c).replaceAll('[^A-Za-z0-9]+', '_');
        List<EmailTemplate> tpl = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :dev AND IsActive = true LIMIT 1];
        if (tpl.isEmpty()) {
            throw new AuraHandledException('No Salesforce email template named ' + dev + '.');
        }
        Messaging.SingleEmailMessage m = Messaging.renderStoredEmailTemplate(tpl[0].Id, null, t.Checklist__r.Employee__c);
        String due = Datetime.newInstanceGmt(addBusinessDays(Date.today(), 2), Time.newInstance(12, 0, 0, 0)).formatGmt('EEEE, MMMM d');
        EmailDraft d = new EmailDraft();
        d.to = t.Send_To__c != null && t.Send_To__c.contains('@') ? t.Send_To__c : t.Checklist__r.Employee__r.Personal_Email__c;
        d.subject = m.getSubject();
        d.body = (m.getHtmlBody() != null ? m.getHtmlBody() : m.getPlainTextBody().escapeHtml4().replace('\n', '<br>')).replace('{{SEND_DATE_PLUS_2}}', due)
            + signatureCard();
        return d;
    }

    // The sender's signature card (User.Email_Signature__c, built by UserTriggerHandler from EmailSignatureTemplate__mdt).
    // A card still holding $$placeholders$$ (OverrideEmailSignature__c off) is not usable, so fall back to name + company.
    @TestVisible
    static String signatureCard() {
        User u = [SELECT Name, Email_Signature__c FROM User WHERE Id = :UserInfo.getUserId()];
        if (String.isNotBlank(u.Email_Signature__c) && !u.Email_Signature__c.contains('$$')) {
            return '<br>' + u.Email_Signature__c;
        }
        return '<p>' + u.Name.escapeHtml4() + '<br>Reach Home Loans</p>';
    }

    // Sends as the clicking user (decision 32), then completes the task with the stamp and a note of who it went to.
    @AuraEnabled
    public static void sendTaskEmail(Id taskId, String toAddress, String subject, String body) {
        People_Task__c t = [SELECT Id, Notes__c, Status__c, Checklist__r.Status__c FROM People_Task__c WHERE Id = :taskId];
        requireOpen(t.Checklist__r.Status__c);
        List<String> to = new List<String>();
        for (String a : (toAddress == null ? '' : toAddress).split('[,;\\s]+')) {
            if (Pattern.matches('[^@\\s]+@[^@\\s]+\\.[^@\\s]+', a)) {
                to.add(a);
            }
        }
        if (to.isEmpty() || String.isBlank(subject) || String.isBlank(body)) {
            throw new AuraHandledException('A valid To address, a subject and a message are required.');
        }
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(to);
        m.setSubject(subject);
        m.setHtmlBody(body);
        m.setSaveAsActivity(false);
        Messaging.SendEmailResult r = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false)[0];
        if (!r.isSuccess()) {
            throw new AuraHandledException('Email not sent: ' + r.getErrors()[0].getMessage());
        }
        String stamp = 'Emailed to ' + String.join(to, ', ') + ' · ' + System.now().format('MMM d, yyyy h:mm a', 'America/New_York') + ' ET';
        update new People_Task__c(
            Id = t.Id, Status__c = 'Done', Completed_By__c = UserInfo.getUserId(), Completed_At__c = System.now(),
            Notes__c = (String.isBlank(t.Notes__c) ? '' : t.Notes__c + '\n') + stamp
        );
    }

    // ---------- compliance sign-off + exam PDF (decisions 13, 24, 25) ----------
    @AuraEnabled
    public static void signOff(Id checklistId) {
        if (!signers.contains(UserInfo.getUserId())) {
            throw new AuraHandledException('Only Bianca Rodrigues or Christopher Lowman can sign off.');
        }
        People_Checklist__c c = [
            SELECT Id, Status__c, Type__c, Employee__c, (SELECT Id FROM Tasks__r WHERE Status__c = 'Open') FROM People_Checklist__c WHERE Id = :checklistId
        ];
        requireOpen(c.Status__c);
        if (!c.Tasks__r.isEmpty()) {
            throw new AuraHandledException(c.Tasks__r.size() + ' task(s) are still open.');
        }
        update new People_Checklist__c(Id = c.Id, Status__c = 'Signed Off', Signed_Off_By__c = UserInfo.getUserId(), Signed_Off_At__c = System.now());
        // A signed-off offboarding is the end of employment (decision 42).
        if (c.Type__c == OFFBOARDING && c.Employee__c != null) {
            update new People_Employee__c(Id = c.Employee__c, Status__c = 'Terminated');
        }
    }

    // Renders the exam PDF and files it on the employee. Separate call from signOff: rendering a page counts as a callout,
    // which cannot follow DML in the same transaction.
    @AuraEnabled
    public static Id saveExamPdf(Id checklistId) {
        People_Checklist__c c = [
            SELECT Id, Status__c, Type__c, Renewal_Year__c, Employee__c, Employee__r.Name, Branch__c, Branch__r.Name FROM People_Checklist__c WHERE Id = :checklistId
        ];
        if (c.Status__c != 'Signed Off') {
            throw new AuraHandledException('Sign off first; the filed PDF is the signed record.');
        }
        PageReference p = Page.PeopleExamPdf;
        p.getParameters().put('id', checklistId);
        Blob pdf = Test.isRunningTest() ? Blob.valueOf('pdf') : p.getContentAsPDF();
        String kind = c.Type__c + (c.Renewal_Year__c == null ? '' : ' ' + c.Renewal_Year__c.intValue());
        ContentVersion v = new ContentVersion(
            Title = kind + ' checklist - ' + (c.Employee__c != null ? c.Employee__r.Name : c.Branch__r.Name) + ' - signed ' + Date.today().format(),
            PathOnClient = kind.toLowerCase().replace(' ', '-') + '-checklist.pdf', VersionData = pdf,
            FirstPublishLocationId = c.Employee__c != null ? c.Employee__c : c.Branch__c
        );
        insert v;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;
        update new People_Checklist__c(Id = c.Id, Exam_PDF_Id__c = docId);
        return docId;
    }

    // ---------- encrypted personal fields ----------
    static Boolean canViewPersonal() {
        return [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.PermissionsViewEncryptedData = true
        ] > 0;
    }

    // Apex sees encrypted fields in clear text whatever the user's permissions, hence the explicit check.
    @AuraEnabled
    public static People_Employee__c getPersonal(Id employeeId) {
        if (!canViewPersonal()) {
            throw new AuraHandledException('You do not have access to personal details.');
        }
        return [SELECT Id, Date_of_Birth__c, Home_Address__c, Personal_Phone__c, Emergency_Contact__c FROM People_Employee__c WHERE Id = :employeeId];
    }

    @AuraEnabled
    public static void savePersonal(People_Employee__c personal) {
        if (!canViewPersonal()) {
            throw new AuraHandledException('You do not have access to personal details.');
        }
        update new People_Employee__c(
            Id = personal.Id, Date_of_Birth__c = personal.Date_of_Birth__c, Home_Address__c = personal.Home_Address__c,
            Personal_Phone__c = personal.Personal_Phone__c, Emergency_Contact__c = personal.Emergency_Contact__c
        );
    }

    // ---------- templates ----------
    @AuraEnabled
    public static List<People_Template_Task__c> getTemplates(String checklistType) {
        return [
            SELECT Id, Name, Checklist_Type__c, Sort_Order__c, Phase__c, Description__c, Default_Assignee__c, Default_Assignee__r.Name, Led_By__c,
                Offset_Days__c, Offset_Unit__c, Roles__c, Work_Arrangements__c, Optional__c, Email_Template__c, Via_DocuSign__c, Send_To__c,
                Exam_Section__c, Sets_Status__c, Remind__c, Auto_Complete__c, Per_State__c, Active__c
            FROM People_Template_Task__c WHERE Checklist_Type__c = :checklistType ORDER BY Sort_Order__c, Name
        ];
    }

    @AuraEnabled
    public static Id saveTemplate(People_Template_Task__c template) {
        if (String.isBlank(template.Name)) {
            throw new AuraHandledException('Subject is required.');
        }
        if (template.Id == null && template.Sort_Order__c == null) {
            List<AggregateResult> mx = [SELECT MAX(Sort_Order__c) m FROM People_Template_Task__c WHERE Checklist_Type__c = :template.Checklist_Type__c];
            Decimal top = (Decimal) mx[0].get('m');
            template.Sort_Order__c = (top == null ? 0 : top) + 10;
        }
        upsert template;
        return template.Id;
    }

    @AuraEnabled
    public static void reorderTemplates(List<Id> orderedIds) {
        List<People_Template_Task__c> rows = new List<People_Template_Task__c>();
        for (Integer i = 0; i < orderedIds.size(); i++) {
            rows.add(new People_Template_Task__c(Id = orderedIds[i], Sort_Order__c = (i + 1) * 10));
        }
        update rows;
    }

    // The People_Admin users: the only people tasks can be assigned to (decision 2).
    @AuraEnabled(cacheable=true)
    public static List<Option> getAssignees() {
        List<Option> out = new List<Option>();
        for (PermissionSetAssignment a : [
            SELECT AssigneeId, Assignee.Name FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'People_Admin' AND Assignee.IsActive = true ORDER BY Assignee.Name
        ]) {
            out.add(new Option(a.Assignee.Name, a.AssigneeId));
        }
        return out;
    }

    // ---------- helpers ----------
    // optional: true = optional only, false = required only, null = both.
    static List<People_Template_Task__c> templates(String checklistType, Boolean optional) {
        List<People_Template_Task__c> out = new List<People_Template_Task__c>();
        for (People_Template_Task__c t : getTemplates(checklistType)) {
            if (t.Active__c && (optional == null || t.Optional__c == optional)) {
                out.add(t);
            }
        }
        return out;
    }

    @TestVisible
    static Boolean applies(People_Template_Task__c t, String role, String arrangement) {
        return (String.isBlank(t.Roles__c) || t.Roles__c.split(';').contains(role))
            && (String.isBlank(t.Work_Arrangements__c) || t.Work_Arrangements__c.split(';').contains(arrangement));
    }

    static People_Task__c fromTemplate(People_Template_Task__c t, Id checklistId, Date startDate) {
        return new People_Task__c(
            Name = t.Name, Checklist__c = checklistId, Template_Task__c = t.Id, Phase__c = t.Phase__c, Sort_Order__c = t.Sort_Order__c,
            Description__c = t.Description__c, Offset_Days__c = t.Offset_Days__c, Offset_Unit__c = t.Offset_Unit__c,
            Due_Date__c = dueDate(startDate, t.Offset_Days__c, t.Offset_Unit__c),
            Assigned_To__c = t.Default_Assignee__c, Led_By__c = t.Led_By__c, Status__c = 'Open', Email_Template__c = t.Email_Template__c,
            Via_DocuSign__c = t.Via_DocuSign__c, Send_To__c = t.Send_To__c, Exam_Section__c = t.Exam_Section__c, Sets_Status__c = t.Sets_Status__c,
            Remind__c = t.Remind__c, Auto_Complete__c = t.Auto_Complete__c
        );
    }

    static String fullName(People_Employee__c e) {
        return ((e.First_Name__c == null ? '' : e.First_Name__c.trim()) + ' ' + (e.Last_Name__c == null ? '' : e.Last_Name__c.trim())).trim().left(80);
    }
}
