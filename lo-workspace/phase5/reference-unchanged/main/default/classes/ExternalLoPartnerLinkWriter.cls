/**
 * Assignment and AccountShare inserts must succeed when the external user cannot
 * see the matched Contact/Account. SYSTEM_MODE on a with-sharing class still
 * failed lookup access ("insufficient access rights on cross-reference id").
 * See ADR-0002.
 */
public without sharing class ExternalLoPartnerLinkWriter {
    public static List<Database.SaveResult> insertAssignments(List<External_User_Assignment__c> assignments) {
        if (assignments == null || assignments.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.insert(assignments, false);
    }

    public static List<Database.SaveResult> insertAccountShares(List<AccountShare> shares) {
        if (shares == null || shares.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.insert(shares, false);
    }
}