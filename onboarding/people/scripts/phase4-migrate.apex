// Phase 4 (2026-10-22) data migration. Safe to re-run: every step skips what is already there.
// 1. One license per state already on each employee (Active, Sponsored; Pending for Candidates/Pre-Start).
// 2. Annual Compliance template gains Fair Lending, GLBA privacy, IT security (P4-12/19); "Confirm {STATE}" renews the license.
// 3. Open 2026 checklists: renamed "Annual Compliance 2026 · …", the 3 new items added, per-state tasks tagged with their state.
Id bianca = '0055x00000Bf9iaAAB';

// 1
Integer lic = 0;
for (People_Employee__c e : [SELECT Id, Name, Status__c, Licensed_States__c, (SELECT State__c FROM Licenses__r) FROM People_Employee__c WHERE Licensed_States__c != null]) {
    Integer before = e.Licenses__r.size();
    PeopleHrController.licensesFromStates(e.Id, e.Name, e.Licensed_States__c, new Set<String>{ 'Candidate', 'Pre-Start' }.contains(e.Status__c) ? 'Pending' : 'Active');
    lic += [SELECT COUNT() FROM People_License__c WHERE Employee__c = :e.Id] - before;
}

// 2
Set<String> have = new Set<String>();
for (People_Template_Task__c t : [SELECT Name FROM People_Template_Task__c WHERE Checklist_Type__c = 'Renewal']) have.add(t.Name);
List<People_Template_Task__c> add = new List<People_Template_Task__c>();
Map<String, Integer> fresh = new Map<String, Integer>{ 'Annual Fair Lending training' => 42, 'Annual GLBA privacy training' => 44, 'Annual IT security training' => 46 };
for (String n : fresh.keySet()) {
    if (!have.contains(n)) {
        add.add(new People_Template_Task__c(Name = n, Checklist_Type__c = 'Renewal', Phase__c = 'Renewal', Offset_Days__c = -30, Offset_Unit__c = 'Calendar Days',
            Default_Assignee__c = bianca, Exam_Section__c = 'Regulatory', Remind__c = true, Active__c = true, Sort_Order__c = fresh.get(n),
            Description__c = 'Collect the certificate; add its link in the notes.'));
    }
}
insert add;
List<People_Template_Task__c> approve = [SELECT Id FROM People_Template_Task__c WHERE Checklist_Type__c = 'Renewal' AND Name LIKE 'Confirm {STATE}%' AND Renews_License__c = false];
for (People_Template_Task__c t : approve) t.Renews_License__c = true;
update approve;

// 3
List<People_Template_Task__c> newTpls = [SELECT Id, Name, Phase__c, Sort_Order__c, Description__c, Offset_Days__c, Offset_Unit__c, Default_Assignee__c, Exam_Section__c, Remind__c
    FROM People_Template_Task__c WHERE Checklist_Type__c = 'Renewal' AND Name IN :fresh.keySet()];
List<People_Checklist__c> cls = [SELECT Id, Name, Anchor_Date__c, (SELECT Template_Task__c FROM Tasks__r) FROM People_Checklist__c WHERE Type__c = 'Renewal' AND Renewal_Year__c = 2026 AND Status__c = 'Open'];
List<People_Task__c> tasks = new List<People_Task__c>();
for (People_Checklist__c c : cls) {
    c.Name = c.Name.replace('Renewal 2026', 'Annual Compliance 2026').left(80);
    Set<Id> used = new Set<Id>();
    for (People_Task__c t : c.Tasks__r) used.add(t.Template_Task__c);
    for (People_Template_Task__c t : newTpls) {
        if (used.contains(t.Id)) continue;
        Date due = c.Anchor_Date__c.addDays(t.Offset_Days__c.intValue());
        tasks.add(new People_Task__c(Name = t.Name, Checklist__c = c.Id, Template_Task__c = t.Id, Phase__c = t.Phase__c, Sort_Order__c = t.Sort_Order__c,
            Description__c = t.Description__c, Offset_Days__c = t.Offset_Days__c, Offset_Unit__c = t.Offset_Unit__c, Due_Date__c = due,
            Assigned_To__c = t.Default_Assignee__c, Status__c = 'Open', Exam_Section__c = t.Exam_Section__c, Remind__c = t.Remind__c));
    }
}
update cls;
insert tasks;
Pattern p = Pattern.compile('^(?:Submit|Confirm) ([A-Z]{2}) (?:license )?renewal.*');
List<People_Task__c> perState = new List<People_Task__c>();
for (People_Task__c t : [SELECT Id, Name FROM People_Task__c WHERE Checklist__r.Type__c = 'Renewal' AND License_State__c = null AND (Name LIKE 'Submit %' OR Name LIKE 'Confirm %')]) {
    Matcher m = p.matcher(t.Name);
    if (m.matches()) perState.add(new People_Task__c(Id = t.Id, License_State__c = m.group(1), Renews_License__c = t.Name.startsWith('Confirm')));
}
update perState;
System.debug('MIG licenses +' + lic + ', templates +' + add.size() + ', checklists renamed ' + cls.size() + ', tasks +' + tasks.size() + ', per-state tagged ' + perState.size());
