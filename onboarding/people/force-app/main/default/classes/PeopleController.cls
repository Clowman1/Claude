// People app (2026-10-22): employee onboarding board, hire timeline and master template editor (spec: onboarding/SPEC.md).
// Callers hold People_Admin (View All / Modify All on every People object), so plain with-sharing SOQL sees everything.
// Completed By/At are only ever stamped here; the permission set makes them read-only.
public with sharing class PeopleController {

    public static final String ONBOARDING = 'Onboarding';
    static final Set<String> GONE = new Set<String>{ 'Terminated', 'Withdrawn' };

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

    // ---------- shapes ----------
    public class Card {
        @AuraEnabled public Id id;
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
        @AuraEnabled public List<Card> employees = new List<Card>();
        @AuraEnabled public List<People_Branch__c> branches;
        @AuraEnabled public List<DigestItem> digest;
        @AuraEnabled public Date today = Date.today();
    }

    public class Detail {
        @AuraEnabled public People_Employee__c employee;
        @AuraEnabled public People_Checklist__c checklist;
        @AuraEnabled public List<People_Task__c> tasks;
        @AuraEnabled public List<People_Template_Task__c> optional;
        @AuraEnabled public Boolean canViewPersonal;
        @AuraEnabled public Date today = Date.today();
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
        Map<Id, Card> cards = new Map<Id, Card>();
        for (People_Employee__c e : [
            SELECT Id, Name, Role__c, Work_Arrangement__c, Status__c, Start_Date__c, Branch__r.Name
            FROM People_Employee__c WHERE Status__c NOT IN :GONE ORDER BY Start_Date__c NULLS LAST, Name
        ]) {
            Card c = new Card();
            c.id = e.Id;
            c.name = e.Name;
            c.role = e.Role__c;
            c.arrangement = e.Work_Arrangement__c;
            c.status = e.Status__c;
            c.startDate = e.Start_Date__c;
            c.branch = e.Branch__r?.Name;
            cards.put(e.Id, c);
        }
        Set<Id> withChecklist = new Set<Id>();
        for (People_Task__c t : [
            SELECT Name, Status__c, Due_Date__c, Checklist__r.Employee__c
            FROM People_Task__c
            WHERE Checklist__r.Employee__c IN :cards.keySet() AND Checklist__r.Type__c = :ONBOARDING AND Checklist__r.Status__c = 'Open'
            ORDER BY Due_Date__c NULLS LAST, Sort_Order__c
        ]) {
            Card c = cards.get(t.Checklist__r.Employee__c);
            withChecklist.add(c.id);
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
        // ponytail: the board shows only people with an open onboarding checklist; Renewals/Offboarding views arrive in phase 3.
        for (Card c : cards.values()) {
            if (withChecklist.contains(c.id)) {
                b.employees.add(c);
            }
        }
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
            SELECT Id, Name, Due_Date__c, Checklist__r.Employee__c, Checklist__r.Employee__r.Name
            FROM People_Task__c
            WHERE Assigned_To__c = :userId AND Status__c = 'Open' AND Checklist__r.Status__c = 'Open'
                AND Checklist__r.Employee__r.Status__c NOT IN :GONE AND Due_Date__c <= :horizon
            ORDER BY Due_Date__c, Sort_Order__c LIMIT 200
        ]) {
            DigestItem d = new DigestItem();
            d.taskId = t.Id;
            d.employeeId = t.Checklist__r.Employee__c;
            d.employee = t.Checklist__r.Employee__r.Name;
            d.subject = t.Name;
            d.due = t.Due_Date__c;
            d.overdue = t.Due_Date__c < today;
            items.add(d);
        }
        return items;
    }

    // ---------- one employee ----------
    @AuraEnabled
    public static Detail getEmployee(Id employeeId) {
        Detail d = new Detail();
        d.employee = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Role__c, Work_Arrangement__c, Status__c, Start_Date__c, Manager__c, Manager__r.Name,
                Branch__c, Branch__r.Name, Work_Email__c, Personal_Email__c, NMLS_ID__c, Licensed_States__c, User__c, User__r.Name
            FROM People_Employee__c WHERE Id = :employeeId
        ];
        List<People_Checklist__c> cls = [
            SELECT Id, Name, Status__c FROM People_Checklist__c
            WHERE Employee__c = :employeeId AND Type__c = :ONBOARDING ORDER BY CreatedDate DESC LIMIT 1
        ];
        d.checklist = cls.isEmpty() ? null : cls[0];
        d.tasks = d.checklist == null ? new List<People_Task__c>() : [
            SELECT Id, Name, Phase__c, Sort_Order__c, Description__c, Due_Date__c, Status__c, Assigned_To__c, Assigned_To__r.Name, Led_By__c,
                Completed_By__r.Name, Completed_At__c, Notes__c, Email_Template__c, Via_DocuSign__c, Send_To__c, Template_Task__c
            FROM People_Task__c WHERE Checklist__c = :d.checklist.Id ORDER BY Sort_Order__c, Due_Date__c
        ];
        Set<Id> used = new Set<Id>();
        for (People_Task__c t : d.tasks) {
            used.add(t.Template_Task__c);
        }
        d.optional = new List<People_Template_Task__c>();
        for (People_Template_Task__c t : templates(ONBOARDING, true)) {
            if (!used.contains(t.Id) && applies(t, d.employee.Role__c, d.employee.Work_Arrangement__c)) {
                d.optional.add(t);
            }
        }
        d.canViewPersonal = canViewPersonal();
        return d;
    }

    @AuraEnabled
    public static Map<String, Object> previewChecklist(String role, String arrangement, Date startDate) {
        Integer n = 0, opt = 0;
        Integer firstOffset;
        for (People_Template_Task__c t : templates(ONBOARDING, null)) {
            if (!applies(t, role, arrangement)) {
                continue;
            }
            if (t.Optional__c) {
                opt++;
                continue;
            }
            n++;
            if (t.Offset_Days__c != null && (firstOffset == null || t.Offset_Days__c < firstOffset)) {
                firstOffset = t.Offset_Days__c.intValue();
            }
        }
        return new Map<String, Object>{
            'count' => n, 'optional' => opt,
            'firstDue' => firstOffset == null ? null : addBusinessDays(startDate, firstOffset)
        };
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
        People_Checklist__c cl = new People_Checklist__c(
            Name = (ONBOARDING + ' · ' + employee.Name).left(80), Employee__c = employee.Id, Type__c = ONBOARDING, Status__c = 'Open'
        );
        insert cl;
        List<People_Task__c> tasks = new List<People_Task__c>();
        for (People_Template_Task__c t : templates(ONBOARDING, false)) {
            if (applies(t, employee.Role__c, employee.Work_Arrangement__c)) {
                tasks.add(fromTemplate(t, cl.Id, employee.Start_Date__c));
            }
        }
        insert tasks;
        return employee.Id;
    }

    // Returns how many open tasks now fall before today after a start-date move (the UI warns on > 0).
    @AuraEnabled
    public static Integer saveEmployee(People_Employee__c employee) {
        People_Employee__c old = [SELECT Start_Date__c FROM People_Employee__c WHERE Id = :employee.Id];
        employee.Name = fullName(employee);
        update employee;
        if (employee.Start_Date__c == null || employee.Start_Date__c == old.Start_Date__c) {
            return 0;
        }
        List<People_Task__c> open = [
            SELECT Id, Offset_Days__c FROM People_Task__c
            WHERE Checklist__r.Employee__c = :employee.Id AND Checklist__r.Type__c = :ONBOARDING AND Status__c = 'Open' AND Offset_Days__c != null
        ];
        Integer late = 0;
        for (People_Task__c t : open) {
            t.Due_Date__c = addBusinessDays(employee.Start_Date__c, t.Offset_Days__c.intValue());
            if (t.Due_Date__c < Date.today()) {
                late++;
            }
        }
        update open;
        return late;
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
        update new People_Task__c(Id = taskId, Assigned_To__c = assignedTo, Due_Date__c = dueDate, Notes__c = notes);
    }

    @AuraEnabled
    public static void addOptionalTask(Id employeeId, Id templateId) {
        Detail d = getEmployee(employeeId);
        People_Template_Task__c t = [SELECT Id, Name, Phase__c, Sort_Order__c, Description__c, Offset_Days__c, Default_Assignee__c, Led_By__c,
                Email_Template__c, Via_DocuSign__c, Send_To__c, Exam_Section__c, Sets_Status__c
            FROM People_Template_Task__c WHERE Id = :templateId];
        insert fromTemplate(t, d.checklist.Id, d.employee.Start_Date__c);
    }

    @AuraEnabled
    public static void addCustomTask(Id employeeId, String subject, String phase, Date dueDate, Id assignedTo) {
        if (String.isBlank(subject)) {
            throw new AuraHandledException('Subject is required.');
        }
        Detail d = getEmployee(employeeId);
        insert new People_Task__c(
            Name = subject.trim().left(80), Checklist__c = d.checklist.Id, Phase__c = phase, Due_Date__c = dueDate,
            Assigned_To__c = assignedTo, Status__c = 'Open', Sort_Order__c = 99999
        );
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
                Offset_Days__c, Roles__c, Work_Arrangements__c, Optional__c, Email_Template__c, Via_DocuSign__c, Send_To__c, Exam_Section__c,
                Sets_Status__c, Active__c
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
            Description__c = t.Description__c, Offset_Days__c = t.Offset_Days__c,
            Due_Date__c = addBusinessDays(startDate, t.Offset_Days__c == null ? null : t.Offset_Days__c.intValue()),
            Assigned_To__c = t.Default_Assignee__c, Led_By__c = t.Led_By__c, Status__c = 'Open', Email_Template__c = t.Email_Template__c,
            Via_DocuSign__c = t.Via_DocuSign__c, Send_To__c = t.Send_To__c, Exam_Section__c = t.Exam_Section__c, Sets_Status__c = t.Sets_Status__c
        );
    }

    static String fullName(People_Employee__c e) {
        return ((e.First_Name__c == null ? '' : e.First_Name__c.trim()) + ' ' + (e.Last_Name__c == null ? '' : e.Last_Name__c.trim())).trim().left(80);
    }
}
