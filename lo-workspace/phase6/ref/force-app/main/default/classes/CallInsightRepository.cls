/**
 * Canonical Call_Insight__c reads. Org-wide: ingest health and admin status must see all insights.
 */
public without sharing class CallInsightRepository {
    public static Datetime selectLatestCreatedDate() {
        List<Call_Insight__c> rows = [
            SELECT CreatedDate
            FROM Call_Insight__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].CreatedDate;
    }
}