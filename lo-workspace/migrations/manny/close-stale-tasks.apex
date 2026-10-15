// Closes Manny's 39 overdue auto-created tasks (ids in stale-tasks-before.json, 2026-10-14). Reopen = set Status back to Open.
List<Task> ts = [SELECT Id FROM Task WHERE Id IN ('00TQi00001DjSTXMA3','00TQi00001FZ95kMAD','00TQi00001FaEgLMAV','00TQi00001G38aeMAB','00TQi00001G2iEiMAJ','00TQi00001GciksMAB','00TQi00001HEB6WMAX','00TQi00001HF5iRMAT','00TQi00001HQdOXMA1','00TQi00001HSjCrMAL','00TQi00001HQZGBMA5','00TQi00001HS9qwMAD','00TQi00001Hu8zuMAB','00TQi00001HuVrrMAF','00TQi00001HvtgrMAB','00TQi00001I3dtnMAB','00TQi00001IGDbbMAH','00TQi00001J9DWDMA3','00TQi00001L1FdLMAV','00TQi00001PWGm3MAH','00TQi00001Pe0VuMAJ','00TQi00001XH12fMAD','00TQi00001aHs20MAC','00TQi00001aLYTDMA4','00TQi00001azu9sMAA','00TQi00001b2MBcMAM','00TQi00001b1rKuMAI','00TQi00001bzirOMAQ','00TQi00001c0nP9MAI','00TQi00001c9CrvMAE','00TQi00001cAFvlMAG','00TQi00001ckd9xMAA','00TQi00001cu73CMAQ','00TQi00001d3XRuMAM','00TQi00001dDFLiMAO','00TQi00001dcnNLMAY','00TQi00001dd48YMAQ','00TQi00001e4gfjMAA','00TQi00001edAbCMAU') AND IsClosed = false];
for (Task t : ts) t.Status = 'Completed';
List<Database.SaveResult> res = Database.update(ts, false);
Integer ok = 0;
for (Integer i = 0; i < res.size(); i++) { if (res[i].isSuccess()) ok++; else System.debug('FAIL ' + ts[i].Id + ' ' + res[i].getErrors()[0].getMessage()); }
System.debug('CLOSED ' + ok + ' of ' + ts.size());
