// Phase 2 (2026-10-22): 30/90-day items count calendar days and email Bianca reminders; Salesforce user setup auto-completes on link.
List<People_Template_Task__c> rows = [SELECT Id, Name, Sort_Order__c FROM People_Template_Task__c WHERE Checklist_Type__c = 'Onboarding'];
Set<Decimal> calendar = new Set<Decimal>{ 500, 510, 520, 530 };
for (People_Template_Task__c t : rows) {
    t.Offset_Unit__c = calendar.contains(t.Sort_Order__c) ? 'Calendar Days' : 'Business Days';
    t.Remind__c = calendar.contains(t.Sort_Order__c);
    if (t.Sort_Order__c == 250) t.Auto_Complete__c = 'Salesforce user linked';
}
update rows;
for (People_Template_Task__c t : [SELECT Name, Offset_Days__c, Offset_Unit__c, Remind__c, Auto_Complete__c FROM People_Template_Task__c WHERE Remind__c = true OR Auto_Complete__c != null ORDER BY Sort_Order__c])
    System.debug('TPL ' + t.Name + ' | ' + t.Offset_Days__c + ' ' + t.Offset_Unit__c + ' | remind ' + t.Remind__c + ' | auto ' + t.Auto_Complete__c);
