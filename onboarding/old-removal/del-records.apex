List<Account> refs = [SELECT Id FROM Account WHERE Candidate_Checklist__c != null];
for (Account a : refs) a.Candidate_Checklist__c = null;
update refs;
List<Candidate_Checklist__c> cc = [SELECT Id FROM Candidate_Checklist__c];
System.debug('DEL deleting ' + cc.size());
delete cc;
Database.emptyRecycleBin(cc);
System.debug('DEL left ' + [SELECT COUNT() FROM Candidate_Checklist__c] + ', account refs cleared ' + refs.size());
