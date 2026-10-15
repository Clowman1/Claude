// Harold portal user 005AJ000000Ig20YAC -> new user 005Qi00000jcrB5IAI on Loan_Officer__c (2026-10-15). Owner left as-is: the
// "Re-create Transaction Share" flow can't share a loan with its own owner. Ids in before-loans.json.
List<Transaction__c> ts = [SELECT Id FROM Transaction__c WHERE Loan_Officer__c = '005AJ000000Ig20YAC'];
for (Transaction__c t : ts) t.Loan_Officer__c = '005Qi00000jcrB5IAI';
List<Database.SaveResult> res = Database.update(ts, false);
Integer ok = 0;
for (Integer i = 0; i < res.size(); i++) { if (res[i].isSuccess()) ok++; else System.debug('FAIL ' + ts[i].Id + ' ' + res[i].getErrors()[0].getMessage()); }
System.debug('MOVED ' + ok + ' of ' + ts.size());
