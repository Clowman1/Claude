// Harold portal user -> new user 005Qi00000jcrB5IAI: accounts, open tasks, future events (2026-10-15). Ids in before-*.json.
Id oldU = '005AJ000000Ig20YAC', newU = '005Qi00000jcrB5IAI';
List<SObject> recs = new List<SObject>();
for (Account a : [SELECT Id FROM Account WHERE OwnerId = :oldU]) { a.OwnerId = newU; recs.add(a); }
Integer nAcc = recs.size();
for (Task t : [SELECT Id FROM Task WHERE OwnerId = :oldU AND IsClosed = false]) { t.OwnerId = newU; recs.add(t); }
for (Event e : [SELECT Id FROM Event WHERE OwnerId = :oldU AND StartDateTime >= TODAY]) { e.OwnerId = newU; recs.add(e); }
List<Database.SaveResult> res = Database.update(recs, false);
Integer ok = 0;
for (Integer i = 0; i < res.size(); i++) { if (res[i].isSuccess()) ok++; else System.debug('FAIL ' + recs[i].Id + ' ' + res[i].getErrors()[0].getMessage()); }
System.debug('MOVED ' + ok + ' of ' + recs.size() + ' (accounts ' + nAcc + ')');
