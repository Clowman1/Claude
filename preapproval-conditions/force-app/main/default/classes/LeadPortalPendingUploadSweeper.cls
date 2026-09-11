/**
 * Submits borrower upload baskets that were never submitted.
 *
 * The portal only notifies the lead team when the borrower presses submit, which means a borrower
 * who uploads and closes the tab would otherwise leave documents in Salesforce that nobody is told
 * about. This sweeps those baskets up and submits them as if the borrower had pressed the button,
 * with the email saying it was automatic.
 *
 * Timing: three hours after the borrower's LAST upload, so a slow evening of uploading is not
 * interrupted mid-session, with an outer limit of twelve hours from their FIRST upload so nothing
 * can be deferred indefinitely by a trickle of files.
 *
 * The borrower is told none of this; it is a safety net, not a feature.
 */
public without sharing class LeadPortalPendingUploadSweeper implements Schedulable {

    @TestVisible
    private static final Integer QUIET_MINUTES = 180;
    @TestVisible
    private static final Integer OUTER_LIMIT_MINUTES = 720;
    // A bound rather than a guess: a sweep should never be the thing that blows a governor limit.
    private static final Integer MAX_LEADS_PER_RUN = 20;

    public void execute(SchedulableContext context) {
        sweep();
    }

    /**
     * Returns the number of baskets submitted, so a caller can tell a quiet run from a busy one.
     */
    public static Integer sweep() {
        Datetime quietBefore = Datetime.now().addMinutes(-QUIET_MINUTES);
        Datetime firstUploadBefore = Datetime.now().addMinutes(-OUTER_LIMIT_MINUTES);

        // Every pending file, oldest first. Grouping happens in Apex because the lead sits two
        // hops away: ContentVersion -> Lead_Document_Request__c -> Lead.
        List<ContentVersion> pending = [
            SELECT Id, CreatedDate, Lead_Document_Request__c, Lead_Document_Request__r.Lead__c
            FROM ContentVersion
            WHERE Portal_Upload_Pending__c = TRUE
            AND IsLatest = TRUE
            AND Lead_Document_Request__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ];
        if (pending.isEmpty()) {
            return 0;
        }

        Map<Id, Datetime> firstUploadByLeadId = new Map<Id, Datetime>();
        Map<Id, Datetime> lastUploadByLeadId = new Map<Id, Datetime>();
        for (ContentVersion version : pending) {
            Id leadId = version.Lead_Document_Request__r.Lead__c;
            if (leadId == null) {
                continue;
            }
            if (!firstUploadByLeadId.containsKey(leadId)) {
                firstUploadByLeadId.put(leadId, version.CreatedDate);
            }
            lastUploadByLeadId.put(leadId, version.CreatedDate);
        }

        Set<Id> leadIdsToSubmit = new Set<Id>();
        for (Id leadId : lastUploadByLeadId.keySet()) {
            Boolean quietLongEnough = lastUploadByLeadId.get(leadId) <= quietBefore;
            Boolean waitedLongEnough = firstUploadByLeadId.get(leadId) <= firstUploadBefore;
            if (quietLongEnough || waitedLongEnough) {
                leadIdsToSubmit.add(leadId);
            }
            if (leadIdsToSubmit.size() >= MAX_LEADS_PER_RUN) {
                break;
            }
        }
        if (leadIdsToSubmit.isEmpty()) {
            return 0;
        }

        Integer submitted = 0;
        for (Lead leadRecord : LeadDocumentRequestRepository.getInstance()
            .selectLeadsByIds(leadIdsToSubmit).values()) {
            // One basket failing must not strand the rest: a bad email address on one lead should
            // not stop another borrower's documents reaching their team.
            try {
                if (LeadDocumentPortalService.submitPendingForLeadRecord(leadRecord, true) > 0) {
                    submitted++;
                }
            } catch (Exception sweepException) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Pending upload sweep failed for lead ' + leadRecord.Id + ': ' + sweepException.getMessage()
                );
            }
        }
        return submitted;
    }
}
