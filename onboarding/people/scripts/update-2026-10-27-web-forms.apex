// 2026-10-27: onboarding list update from "Onboarding Checklist - Salesforce Import 1.csv".
// Row 13 (Licensing Store) and row 16 (KB Technologies) are now web forms, not emails, so the
// PH-9 / DocuSign / Send To tags come off. Updates the two templates and any still-open tasks built from them.
Map<Decimal, List<String>> rows = new Map<Decimal, List<String>>{
    130 => new List<String>{ 'Submit Licensing Store order form', 'https://orders.licensingstore.com/ - start date, position, NMLS ID, email, phone' },
    160 => new List<String>{ 'Submit KB Technologies IT request form', 'Jotform: https://form.jotform.com/240105900423138 - computer setup and firstname.lastname@reachhomeloans.com' }
};
List<People_Template_Task__c> tpls = [SELECT Id, Sort_Order__c FROM People_Template_Task__c WHERE Checklist_Type__c = 'Onboarding' AND Sort_Order__c IN :rows.keySet()];
for (People_Template_Task__c t : tpls) {
    t.Name = rows.get(t.Sort_Order__c)[0];
    t.Description__c = rows.get(t.Sort_Order__c)[1];
    t.Email_Template__c = null;
    t.Via_DocuSign__c = false;
    t.Send_To__c = null;
}
update tpls;
List<People_Task__c> open = [SELECT Id, Template_Task__r.Sort_Order__c FROM People_Task__c
    WHERE Template_Task__c IN :tpls AND Status__c = 'Open' AND Checklist__r.Status__c = 'Open'];
for (People_Task__c t : open) {
    List<String> r = rows.get(t.Template_Task__r.Sort_Order__c);
    t.Name = r[0];
    t.Description__c = r[1];
    t.Email_Template__c = null;
    t.Via_DocuSign__c = false;
    t.Send_To__c = null;
}
update open;
System.debug('UPD templates ' + tpls.size() + ', open tasks ' + open.size());
