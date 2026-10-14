// Run AFTER Manny is in the External_Loan_Officer role (stamps only resolve to role members).
// Fakes an owner/LO change so ExternalLoStampService queues its normal RestampJob per chunk.
Id u = '005Qi00000TYQgvIAH';

List<List<SObject>> chunks = new List<List<SObject>>();
List<SObject> cur = new List<SObject>();
for (Lead l : [SELECT Id, OwnerId, Loan_Partner__c FROM Lead WHERE OwnerId = :u]) {
    cur.add(l);
    if (cur.size() == 20) { chunks.add(cur); cur = new List<SObject>(); }
}
if (!cur.isEmpty()) chunks.add(cur);
chunks.add([SELECT Id, OwnerId FROM Account WHERE OwnerId = :u]);
chunks.add([SELECT Id, Loan_Officer__c, Loan_Partner__c, OwnerId FROM Transaction__c WHERE Loan_Officer__c = :u OR OwnerId = :u]);

Integer jobs = 0;
for (List<SObject> recs : chunks) {
    if (recs.isEmpty()) continue;
    Map<Id, SObject> oldMap = new Map<Id, SObject>();
    for (SObject r : recs) {
        SObject old = r.clone(true, true);
        old.put(r.getSObjectType() == Transaction__c.SObjectType ? 'Loan_Officer__c' : 'OwnerId', null);
        oldMap.put(r.Id, old);
    }
    ExternalLoStampService.restampChildrenOf(recs, oldMap);
    jobs++;
}
System.debug('Restamp jobs queued: ' + jobs);
