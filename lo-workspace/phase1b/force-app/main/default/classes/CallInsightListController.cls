public without sharing class CallInsightListController {

    /**
     * @param source 'Zoom' returns only Zoom-sourced insights; anything else (including
     *        null) returns everything that is not Zoom. Existing RingSense rows predate
     *        Source__c and are null, so the RingSense side deliberately matches "not Zoom"
     *        rather than "= RingSense" — that avoids backfilling 20,000+ records.
     */
    @AuraEnabled
    public static List<Call_Insight__c> getCallInsights(String recordId, String source) {
        // Phase 1b: this class stays without sharing (Call_Insight__c is Private to Partner
        // Workspace users), so the parent record the browser names must be one the user can open.
        RecordAccessGuard.requireRead((Id) recordId);

        String whereLocator;
        if (recordId.startsWith('00Q')) {
            whereLocator = 'WHERE Lead__c = :recordId ';
        } else if (recordId.startsWith('001')) {
            whereLocator = 'WHERE Account__c = :recordId ';
        } else {
            whereLocator = 'WHERE Transaction__c = :recordId ';
        }

        String sourceFilter = 'Zoom'.equalsIgnoreCase(source)
            ? 'AND Source__c = \'Zoom\' '
            : 'AND (Source__c != \'Zoom\' OR Source__c = NULL) ';

        return (List<Call_Insight__c>) Database.query(
            'SELECT Id, Name,  Salesforce_User__r.FirstName, Salesforce_User__r.LastName, CreatedDate, AI_Score__c, Direction__c, Duration__c, Title__c, ' +
            'Summary__c, Transcript__c, HighLights__c, Next_Steps__c, Bulleted_Summary__c, Source__c, Zoom_Meeting__c, ' +
            'Salesforce_User__c, Salesforce_User__r.Name, Recording_Start_DateTime__c ' +
            'FROM Call_Insight__c ' +
             whereLocator + sourceFilter +
            'ORDER BY Recording_Start_DateTime__c DESC NULLS LAST'
        );
    }

    /**
     * Playable Zoom files for the given meetings, for the Recording tab.
     *
     * A separate call rather than part of getCallInsights: Zoom_Recording__c is a sibling
     * of Call_Insight__c — both hang off Zoom_Meeting__c — so it cannot come back in one
     * subquery, and reshaping the main result would disturb the RingSense tab that shares
     * that method.
     *
     * Files with no Play_URL__c are excluded: TIMELINE files in particular arrive without
     * one and would render as dead links.
     */
    @AuraEnabled
    public static List<Zoom_Recording__c> getZoomRecordings(List<Id> zoomMeetingIds) {
        if (zoomMeetingIds == null || zoomMeetingIds.isEmpty()) {
            return new List<Zoom_Recording__c>();
        }
        // Phase 1b: only meetings with a call insight on a Lead/Account/Transaction the user can
        // open. The component passes exactly those meetings, so nothing it shows today is lost.
        Set<Id> allowedMeetingIds = visibleMeetingIds(zoomMeetingIds);
        return [
            SELECT Id, Zoom_Meeting__c, File_Type__c, Play_URL__c, Play_Passcode__c,
                   Recording_Start__c, Duration_Seconds__c, Status__c
            FROM Zoom_Recording__c
            WHERE Zoom_Meeting__c IN :allowedMeetingIds
              AND Play_URL__c != NULL
              AND Status__c = 'Available'
            ORDER BY File_Type__c
        ];
    }

    private static Set<Id> visibleMeetingIds(List<Id> zoomMeetingIds) {
        List<Call_Insight__c> insights = [
            SELECT Zoom_Meeting__c, Lead__c, Account__c, Transaction__c
            FROM Call_Insight__c
            WHERE Zoom_Meeting__c IN :zoomMeetingIds
        ];
        Set<Id> parentIds = new Set<Id>();
        for (Call_Insight__c insight : insights) {
            parentIds.addAll(new Set<Id>{ insight.Lead__c, insight.Account__c, insight.Transaction__c });
        }
        Set<Id> readableParents = RecordAccessGuard.readable(parentIds);
        Set<Id> meetingIds = new Set<Id>();
        for (Call_Insight__c insight : insights) {
            if (readableParents.contains(insight.Lead__c)
                || readableParents.contains(insight.Account__c)
                || readableParents.contains(insight.Transaction__c)) {
                meetingIds.add(insight.Zoom_Meeting__c);
            }
        }
        return meetingIds;
    }
}