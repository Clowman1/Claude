List<Account> accts = [SELECT Id FROM Account WHERE RecordTypeId = '012AJ0000004K7BYAU'];
for (Account a : accts) a.RecordTypeId = '012f20000010aScAAI';
Database.SaveResult[] rs = Database.update(accts, false);
Integer ok = 0;
for (Integer i = 0; i < rs.size(); i++) { if (rs[i].isSuccess()) ok++; else System.debug('RT FAIL ' + accts[i].Id + ' ' + rs[i].getErrors()[0].getMessage()); }
System.debug('RT MOVED ' + ok + ' of ' + accts.size() + '; left on Candidate: ' + [SELECT COUNT() FROM Account WHERE RecordTypeId = '012AJ0000004K7BYAU']);
