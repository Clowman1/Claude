// People app P4 (2026-10-22): HR for every employee. Job fields, compensation history, per-state licenses, adding
// people who are already employed (many never log in to Salesforce), the Compliance tab and missing-data highlights.
// Spec: onboarding/SPEC.md P4. Callers hold People_Admin, like PeopleController.
public with sharing class PeopleHrController {

    static final Set<String> LIVE = new Set<String>{ 'Active', 'Pending' };

    public class Hr {
        @AuraEnabled public List<People_Compensation__c> compensation;
        @AuraEnabled public List<People_License__c> licenses;
        @AuraEnabled public List<String> missing;
    }

    public class Cell {
        @AuraEnabled public String status; // done | open | overdue | na
        @AuraEnabled public String detail;
    }

    public class Row {
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public List<Cell> cells = new List<Cell>();
    }

    public class Compliance {
        @AuraEnabled public Integer year;
        @AuraEnabled public List<String> columns = new List<String>();
        @AuraEnabled public List<Row> rows = new List<Row>();
        @AuraEnabled public List<People_License__c> expiring;
        @AuraEnabled public Map<Id, List<String>> missing;
        @AuraEnabled public Map<Id, String> names = new Map<Id, String>();
    }

    // ---------- one employee ----------
    @AuraEnabled
    public static Hr getHr(Id employeeId) {
        Hr h = new Hr();
        h.compensation = [
            SELECT Id, Name, Effective_Date__c, Pay_Type__c, Base_Amount__c, Base_Per__c, LO_Comp_Bps__c, Per_Loan_Flat__c, Bonus_Plan__c, Notes__c
            FROM People_Compensation__c WHERE Employee__c = :employeeId ORDER BY Effective_Date__c DESC NULLS LAST, CreatedDate DESC
        ];
        h.licenses = licensesOf(new Set<Id>{ employeeId });
        h.missing = missingFor(new Set<Id>{ employeeId }).get(employeeId);
        return h;
    }

    @AuraEnabled
    public static void saveComp(People_Compensation__c rec) {
        if (rec.Effective_Date__c == null || String.isBlank(rec.Pay_Type__c)) {
            throw new AuraHandledException('Effective date and pay type are required.');
        }
        upsert rec;
    }

    @AuraEnabled
    public static void deleteComp(Id compId) {
        delete [SELECT Id FROM People_Compensation__c WHERE Id = :compId];
    }

    // One license per state per employee; saving keeps the employee's Licensed States (and so the User's) in step.
    @AuraEnabled
    public static void saveLicense(People_License__c rec) {
        if (String.isBlank(rec.State__c) || String.isBlank(rec.Status__c)) {
            throw new AuraHandledException('State and status are required.');
        }
        Id empId = rec.Employee__c != null ? rec.Employee__c : [SELECT Employee__c FROM People_License__c WHERE Id = :rec.Id].Employee__c;
        if ([SELECT COUNT() FROM People_License__c WHERE Employee__c = :empId AND State__c = :rec.State__c AND Id != :rec.Id] > 0) {
            throw new AuraHandledException('There is already a ' + rec.State__c + ' license for this employee.');
        }
        rec.Name = (rec.State__c + ' · ' + [SELECT Name FROM People_Employee__c WHERE Id = :empId].Name).left(80);
        if (rec.Id == null) {
            rec.Employee__c = empId;
        }
        upsert rec;
        syncStates(new Set<Id>{ empId });
    }

    // Licensed States = the employee's Active and Pending licenses, A-Z. PeopleUserSync copies it to the User.
    public static void syncStates(Set<Id> employeeIds) {
        Map<Id, List<String>> states = new Map<Id, List<String>>();
        for (Id e : employeeIds) {
            states.put(e, new List<String>());
        }
        for (People_License__c l : [SELECT Employee__c, State__c FROM People_License__c WHERE Employee__c IN :employeeIds AND Status__c IN :LIVE ORDER BY State__c]) {
            states.get(l.Employee__c).add(l.State__c);
        }
        List<People_Employee__c> rows = new List<People_Employee__c>();
        for (Id e : employeeIds) {
            rows.add(new People_Employee__c(Id = e, Licensed_States__c = states.get(e).isEmpty() ? null : String.join(states.get(e), ';')));
        }
        update rows;
        PeopleUserSync.start();
    }

    // Creates licenses for states not on file yet, for a new hire (Pending) or a loaded / existing employee (Active).
    public static void licensesFromStates(Id employeeId, String employeeName, String statesValue, String status) {
        if (String.isBlank(statesValue)) {
            return;
        }
        Set<String> have = new Set<String>();
        for (People_License__c l : [SELECT State__c FROM People_License__c WHERE Employee__c = :employeeId]) {
            have.add(l.State__c);
        }
        List<People_License__c> fresh = new List<People_License__c>();
        for (String st : statesValue.split(';')) {
            if (!have.contains(st)) {
                fresh.add(new People_License__c(Employee__c = employeeId, State__c = st, Status__c = status, Name = (st + ' · ' + employeeName).left(80),
                    Sponsorship__c = status == 'Active' ? 'Sponsored' : 'Pending'));
            }
        }
        insert fresh;
    }

    // "Confirm {STATE} renewal approved" (Renews License) done: that license renewed today, valid through Dec 31 next year.
    public static void markRenewed(Id employeeId, String state) {
        List<People_License__c> ls = [SELECT Id FROM People_License__c WHERE Employee__c = :employeeId AND State__c = :state LIMIT 1];
        if (!ls.isEmpty()) {
            update new People_License__c(Id = ls[0].Id, Last_Renewed__c = Date.today(), Expiration_Date__c = Date.newInstance(Date.today().year() + 1, 12, 31), Status__c = 'Active');
        }
    }

    // ---------- existing employees (P4-0, P4-9) ----------
    @AuraEnabled
    public static Id addExistingEmployee(People_Employee__c employee) {
        if (String.isBlank(employee.First_Name__c) || String.isBlank(employee.Last_Name__c) || String.isBlank(employee.Role__c)) {
            throw new AuraHandledException('First name, last name and role are required.');
        }
        employee.Id = null;
        employee.Name = (employee.First_Name__c.trim() + ' ' + employee.Last_Name__c.trim()).left(80);
        employee.Status__c = 'Active';
        insert employee;
        licensesFromStates(employee.Id, employee.Name, employee.Licensed_States__c, 'Active');
        // Joining during renewal season (from Oct 15) opens their Annual Compliance straight away.
        Date today = Date.today();
        if (today >= Date.newInstance(today.year(), 10, 15)) {
            PeopleController.generateRenewals(today.year());
        }
        PeopleUserSync.start();
        return employee.Id;
    }

    // ---------- missing data (P4-20) ----------
    @AuraEnabled
    public static Map<Id, List<String>> getMissing() {
        return missingFor(null);
    }

    // employeeIds null = every current employee. Only employees with something missing are in the map.
    public static Map<Id, List<String>> missingFor(Set<Id> employeeIds) {
        List<People_Employee__c> emps = employeeIds == null
            ? [SELECT Id, Hire_Date__c, Department__c, Employment_Type__c, Emergency_Contact__c, NMLS_ID__c FROM People_Employee__c WHERE Status__c NOT IN :PeopleController.GONE]
            : [SELECT Id, Hire_Date__c, Department__c, Employment_Type__c, Emergency_Contact__c, NMLS_ID__c FROM People_Employee__c WHERE Id IN :employeeIds];
        Map<Id, List<People_License__c>> lic = new Map<Id, List<People_License__c>>();
        for (People_License__c l : licensesOf(new Map<Id, People_Employee__c>(emps).keySet())) {
            if (!lic.containsKey(l.Employee__c)) {
                lic.put(l.Employee__c, new List<People_License__c>());
            }
            lic.get(l.Employee__c).add(l);
        }
        Map<Id, List<String>> out = new Map<Id, List<String>>();
        for (People_Employee__c e : emps) {
            List<String> m = new List<String>();
            if (e.Hire_Date__c == null) m.add('Hire date');
            if (e.Department__c == null) m.add('Department');
            if (e.Employment_Type__c == null) m.add('Employment type');
            if (String.isBlank(e.Emergency_Contact__c)) m.add('Emergency contact');
            if (e.NMLS_ID__c != null) {
                for (People_License__c l : lic.containsKey(e.Id) ? lic.get(e.Id) : new List<People_License__c>()) {
                    if (!LIVE.contains(l.Status__c)) continue;
                    if (String.isBlank(l.License_Number__c)) m.add(l.State__c + ' license number');
                    if (l.Expiration_Date__c == null) m.add(l.State__c + ' license expiration');
                }
            }
            if (!m.isEmpty()) {
                out.put(e.Id, m);
            }
        }
        return out;
    }

    static List<People_License__c> licensesOf(Set<Id> employeeIds) {
        return [
            SELECT Id, Name, Employee__c, Employee__r.Name, State__c, License_Number__c, Status__c, Issue_Date__c, Expiration_Date__c, Sponsorship__c, Last_Renewed__c
            FROM People_License__c WHERE Employee__c IN :employeeIds ORDER BY State__c
        ];
    }

    // ---------- Compliance tab (P4-7) ----------
    // One column per Annual Compliance template item; per-state items fold into one column whose cell lists each state.
    @AuraEnabled
    public static Compliance getCompliance() {
        Compliance c = new Compliance();
        List<AggregateResult> yr = [SELECT MAX(Renewal_Year__c) y FROM People_Checklist__c WHERE Type__c = :PeopleController.RENEWAL];
        c.year = yr[0].get('y') == null ? Date.today().year() : ((Decimal) yr[0].get('y')).intValue();
        Date today = Date.today();
        Map<Id, Integer> colOf = new Map<Id, Integer>();
        for (People_Template_Task__c t : PeopleController.getTemplates(PeopleController.RENEWAL)) {
            if (t.Active__c && !t.Optional__c) { // optional items are rare one-offs, not exam columns
                colOf.put(t.Id, c.columns.size());
                c.columns.add(t.Name.replace('{STATE} ', '').replace(' {STATE}', ''));
            }
        }
        for (People_Checklist__c cl : [
            SELECT Employee__c, Employee__r.Name, Employee__r.Role__c,
                (SELECT Status__c, Due_Date__c, Template_Task__c, License_State__c FROM Tasks__r)
            FROM People_Checklist__c
            WHERE Type__c = :PeopleController.RENEWAL AND Renewal_Year__c = :c.year AND Employee__c != null AND Employee__r.Status__c NOT IN :PeopleController.GONE
            ORDER BY Employee__r.Name
        ]) {
            Row r = new Row();
            r.employeeId = cl.Employee__c;
            r.name = cl.Employee__r.Name;
            r.role = cl.Employee__r.Role__c;
            List<List<People_Task__c>> byCol = new List<List<People_Task__c>>();
            for (Integer i = 0; i < c.columns.size(); i++) {
                byCol.add(new List<People_Task__c>());
            }
            for (People_Task__c t : cl.Tasks__r) {
                if (colOf.containsKey(t.Template_Task__c)) {
                    byCol[colOf.get(t.Template_Task__c)].add(t);
                }
            }
            for (List<People_Task__c> ts : byCol) {
                r.cells.add(cellFor(ts, today));
            }
            c.rows.add(r);
        }
        c.expiring = [
            SELECT Id, Employee__c, Employee__r.Name, State__c, License_Number__c, Status__c, Expiration_Date__c
            FROM People_License__c
            WHERE Status__c IN :LIVE AND Expiration_Date__c <= :today.addDays(60) AND Employee__r.Status__c NOT IN :PeopleController.GONE
            ORDER BY Expiration_Date__c
        ];
        c.missing = missingFor(null);
        for (People_Employee__c e : [SELECT Id, Name FROM People_Employee__c WHERE Id IN :c.missing.keySet()]) {
            c.names.put(e.Id, e.Name);
        }
        return c;
    }

    @TestVisible
    static Cell cellFor(List<People_Task__c> ts, Date today) {
        Cell cell = new Cell();
        if (ts.isEmpty()) {
            cell.status = 'na';
            return cell;
        }
        Integer open = 0, late = 0;
        List<String> states = new List<String>();
        for (People_Task__c t : ts) {
            Boolean isOpen = t.Status__c == 'Open';
            if (isOpen) open++;
            if (isOpen && t.Due_Date__c != null && t.Due_Date__c < today) late++;
            if (t.License_State__c != null) states.add(t.License_State__c + (isOpen ? '' : ' ✓'));
        }
        cell.status = late > 0 ? 'overdue' : open > 0 ? 'open' : 'done';
        states.sort();
        cell.detail = states.isEmpty() ? null : String.join(states, ', ');
        return cell;
    }
}
