// Tags Manny on every partner-type Person Account he owns (same row shape as LoWsPartnerTagService.tagAccounts).
// He owns them, so no Manual AccountShare is needed (Granted_Share__c = false). 2026-10-14.
Id u = '005Qi00000TYQgvIAH';
Set<Id> already = new Set<Id>();
for (External_User_Assignment__c t : [SELECT Contact__c FROM External_User_Assignment__c WHERE User__c = :u]) already.add(t.Contact__c);
List<External_User_Assignment__c> tags = new List<External_User_Assignment__c>();
for (Account a : [SELECT Id, Name, PersonContactId FROM Account WHERE OwnerId = :u AND IsPersonAccount = true
                  AND (Is_Realtor__c = true OR Type = 'Realtor' OR Type__c IN ('Realtor Account','Title Agent Account')
                       OR BD_Industry__c != null OR Group__pc INCLUDES ('Realtor','Realtor Prospect','Title Agent','Insurance Agent'))]) {
    if (already.contains(a.PersonContactId)) continue;
    tags.add(new External_User_Assignment__c(
        OwnerId = u, User__c = u, Contact__c = a.PersonContactId,
        Unique_Key__c = String.valueOf(u) + ':' + String.valueOf(a.PersonContactId),
        Assigned_Date__c = Date.today(), Stage__c = 'Active Partner', Granted_Share__c = false));
}
List<Database.SaveResult> res = Database.insert(tags, false);
Integer ok = 0;
for (Integer i = 0; i < res.size(); i++) {
    if (res[i].isSuccess()) ok++; else System.debug('FAIL ' + tags[i].Contact__c + ' ' + res[i].getErrors()[0].getMessage());
}
System.debug('TAGGED ' + ok + ' of ' + tags.size());
