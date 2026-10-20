// Measures a Lead conversion's SOQL use through the LO Workspace / Convert pill path, then ROLLS BACK.
// Nothing is saved: the final throw fails the whole transaction (no DML, no queued jobs, no emails).
// Pick a consumer Pre-Approval/Under Contract lead with every doc request Cleared/Approved/Completed, then:
//   sed 's/LEADID/<lead id>/' measure-conversion-soql.apex > m.apex && sf apex run -o Production -f m.apex
// The result is in the error message: facadeAll=N of the 100 limit. The real button adds about 3-4 more.
Id leadId = 'LEADID';
String r = 'start=' + Limits.getQueries();
Lead cur = [SELECT Id, Status FROM Lead WHERE Id = :leadId];
if (new Set<String>{'Pre-Approval','Under Contract'}.contains(cur.Status)) {
    Database.update(new Lead(Id = leadId, Status = Label.Consumer_Lead_Process), true);
}
r += ' | statusUpdate=' + Limits.getQueries();
ConvertLeadsInvocable.convertLeads(new List<Id>{ leadId });
r += ' | convert=' + Limits.getQueries();
Id t = ExternalLoPortalConversionFacade.createTransactionForConvertedLead(leadId);
r += ' | facadeAll=' + Limits.getQueries() + ' rows=' + Limits.getQueryRows() + ' dml=' + Limits.getDmlStatements() + ' cpu=' + Limits.getCpuTime() + ' txn=' + t;
throw new HandledException('DRYRUN ' + r);
