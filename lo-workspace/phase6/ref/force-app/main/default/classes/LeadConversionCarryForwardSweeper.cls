/**
 * Re-runs the conversion carry-forward over recently converted Leads.
 *
 * The carry-forward is triggered by a record-triggered flow when Converted_Transaction_ID__c is
 * stamped. On the Hall - 1526410724 file (converted 16 Sep 2026) that never happened: all six
 * conditions still had a null Converted_Condition__c and all 24 documents were sitting on the
 * Person Account with none on the Transaction. Invoking the service by hand carried every one of
 * them, so the service was never the problem - the trigger for it was.
 *
 * Rather than keep guessing at flow firing semantics, this sweeps a window of recent conversions
 * and simply runs the carry-forward again. It detects nothing: LeadDocumentCarryForwardService is
 * idempotent - a request that already has a Converted_Condition__c is skipped, and a document
 * already linked to the Transaction is skipped - so re-running over a Lead that carried correctly
 * costs two queries and writes nothing.
 *
 * That is the point. A borrower's documents vanishing at conversion is not something to leave
 * resting on one automation firing.
 */
public without sharing class LeadConversionCarryForwardSweeper implements Schedulable {

    // Long enough to cover a weekend plus a bank holiday, short enough that the sweep stays cheap.
    @TestVisible
    private static final Integer WINDOW_DAYS = 7;
    // A bound rather than a guess: a sweep should never be the thing that blows a governor limit.
    @TestVisible
    private static final Integer MAX_LEADS_PER_RUN = 50;

    public void execute(SchedulableContext context) {
        sweep();
    }

    /** Returns the number of Leads swept, so a caller can tell a quiet run from a busy one. */
    public static Integer sweep() {
        Date convertedOnOrAfter = Date.today().addDays(-WINDOW_DAYS);

        List<Lead> recentlyConverted = [
            SELECT Id
            FROM Lead
            WHERE IsConverted = TRUE
            AND ConvertedDate >= :convertedOnOrAfter
            AND Converted_Transaction_ID__c != NULL
            WITH SYSTEM_MODE
            ORDER BY ConvertedDate DESC
            LIMIT :MAX_LEADS_PER_RUN
        ];
        if (recentlyConverted.isEmpty()) {
            return 0;
        }

        Set<Id> leadIds = new Set<Id>();
        for (Lead leadRecord : recentlyConverted) {
            leadIds.add(leadRecord.Id);
        }

        // One Lead failing must not stop the rest being swept, so each is carried on its own.
        Integer swept = 0;
        for (Id leadId : leadIds) {
            try {
                LeadDocumentCarryForwardService.carryForward(new Set<Id>{ leadId });
                swept++;
            } catch (Exception sweepFailure) {
                System.debug(
                    LoggingLevel.WARN,
                    'Carry-forward sweep failed for Lead ' + leadId + ': ' + sweepFailure.getMessage()
                );
            }
        }
        return swept;
    }
}