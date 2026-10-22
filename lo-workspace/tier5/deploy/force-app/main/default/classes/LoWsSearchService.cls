/**
 * LO Workspace header search (2026-10-21): one box that finds the running LO's OWN records by name,
 * email or phone. Never another LO's records, and no "exists elsewhere" hints.
 *
 *   Leads            Lead OwnerId = me, consumer record types, not converted (nurtured included)
 *   Loans            Transaction__c Loan_Officer__c = me (loan name / number, borrower name, email, phone)
 *   Borrowers        Person Accounts that borrow on a loan where Loan_Officer__c = me, plus past clients I imported
 *   Realtors / partners   my tags (External_User_Assignment__c User__c = me)
 *
 * with sharing AND every query filtered by ownership, so neither one alone decides what comes back.
 * Phones are stored as xxx-xxx-xxxx: a full number matches through ExternalLoPhoneNormalizer.soqlVariants,
 * 4-9 digits match the last 4 digits. 5 SOQL queries per search, 8 rows per group.
 * LO Workspace (Standard users) only; the Partner Workspace portal never shows the box.
 */
public with sharing class LoWsSearchService {

    public static final Integer MIN_LENGTH = 2;
    public static final Integer GROUP_LIMIT = 8;

    public class ResultItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        /** PORTAL_VIEWS value the shell opens the record in. */
        @AuraEnabled public String view;
    }

    public class ResultGroup {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public List<ResultItem> items = new List<ResultItem>();
    }

    @AuraEnabled
    public static List<ResultGroup> search(String term) {
        try {
            return runSearch(term);
        } catch (Exception error) {
            System.debug(LoggingLevel.ERROR, 'LoWsSearchService: ' + error.getMessage() + '\n' + error.getStackTraceString());
            throw new AuraHandledException('Search is unavailable right now. Please try again.');
        }
    }

    @TestVisible
    private static List<ResultGroup> runSearch(String term) {
        List<ResultGroup> groups = new List<ResultGroup>();
        String trimmed = term?.trim();
        if (String.isBlank(trimmed) || trimmed.length() < MIN_LENGTH || UserInfo.getUserType() != 'Standard') {
            return groups;
        }
        String digits = trimmed.replaceAll('\\D', '');
        Boolean byLast4 = digits.length() >= 4 && digits.length() < 10;
        Map<String, Object> binds = new Map<String, Object>{
            'me' => UserInfo.getUserId(),
            'likeTerm' => '%' + trimmed + '%', // bound, so no escaping needed
            'phones' => digits.length() >= 10
                ? ExternalLoPhoneNormalizer.soqlVariants(digits.right(10))
                : new Set<String>(),
            'last4' => '%' + digits.right(4),
            'leadTypes' => ExternalLOBaselineHelper.CONSUMER_LEAD_RECORD_TYPES,
            'lim' => GROUP_LIMIT
        };

        addGroup(groups, 'leads', 'Leads', searchLeads(binds, byLast4));
        addGroup(groups, 'loans', 'Loans', searchLoans(binds, byLast4));
        addGroup(groups, 'clients', 'Borrowers & past clients', searchBorrowers(binds, byLast4));
        addGroup(groups, 'partners', 'Realtors & partners', searchPartners(binds, byLast4));
        return groups;
    }

    private static List<ResultItem> searchLeads(Map<String, Object> binds, Boolean byLast4) {
        List<ResultItem> items = new List<ResultItem>();
        for (Lead l : (List<Lead>) query(
            'SELECT Id, Name, Status, Email, Phone, MobilePhone FROM Lead'
            + ' WHERE OwnerId = :me AND IsConverted = false AND RecordType.DeveloperName IN :leadTypes AND '
            + matchClause(new List<String>{ 'Name', 'Email' }, new List<String>{ 'Phone', 'MobilePhone' }, byLast4)
            + ' ORDER BY Name LIMIT :lim', binds)) {
            // Same split as the shell's nav: Nurtur* statuses live on Nurtured Leads, the rest on My Active Leads.
            Boolean nurtured = l.Status != null && l.Status.startsWithIgnoreCase('Nurtur');
            items.add(item(l.Id, l.Name, joinParts(l.Status, l.Email ?? l.MobilePhone ?? l.Phone), nurtured ? 'nurtured' : 'leads'));
        }
        return items;
    }

    private static List<ResultItem> searchLoans(Map<String, Object> binds, Boolean byLast4) {
        List<ResultItem> items = new List<ResultItem>();
        for (Transaction__c t : (List<Transaction__c>) query(
            'SELECT Id, Name, Status__c, Loan_Number__c, Borrower_Name__r.Name FROM Transaction__c'
            + ' WHERE Loan_Officer__c = :me AND '
            + matchClause(
                new List<String>{ 'Name', 'Loan_Number__c', 'Borrower_Name__r.Name', 'Borrower_Name__r.PersonEmail' },
                new List<String>{ 'Borrower_Name__r.Phone', 'Borrower_Name__r.PersonMobilePhone' }, byLast4)
            + ' ORDER BY CreatedDate DESC LIMIT :lim', binds)) {
            items.add(item(t.Id, t.Borrower_Name__r?.Name ?? t.Name, joinParts(t.Status__c, t.Loan_Number__c ?? t.Name), 'loans'));
        }
        return items;
    }

    /** Borrowers on my loans, then past clients I imported (a semi-join cannot sit inside an OR: two queries). */
    private static List<ResultItem> searchBorrowers(Map<String, Object> binds, Boolean byLast4) {
        String fields = 'SELECT Id, Name, PersonEmail, PersonMobilePhone, Phone FROM Account WHERE IsPersonAccount = true AND ';
        String match = matchClause(new List<String>{ 'Name', 'PersonEmail' }, new List<String>{ 'Phone', 'PersonMobilePhone' }, byLast4);
        List<Account> rows = (List<Account>) query(fields
            + 'Id IN (SELECT Borrower_Name__c FROM Transaction__c WHERE Loan_Officer__c = :me) AND ' + match
            + ' ORDER BY Name LIMIT :lim', binds);
        rows.addAll((List<Account>) query(fields
            + 'OwnerId = :me AND Group__pc INCLUDES (\'Client\') AND ' + match
            + ' ORDER BY Name LIMIT :lim', binds));
        List<ResultItem> items = new List<ResultItem>();
        Set<Id> seen = new Set<Id>();
        for (Account a : rows) {
            if (items.size() < GROUP_LIMIT && seen.add(a.Id)) {
                items.add(item(a.Id, a.Name, a.PersonEmail ?? a.PersonMobilePhone ?? a.Phone, 'pastClients'));
            }
        }
        return items;
    }

    private static List<ResultItem> searchPartners(Map<String, Object> binds, Boolean byLast4) {
        String acct = 'Contact__r.Account.';
        List<ResultItem> items = new List<ResultItem>();
        Set<Id> seen = new Set<Id>();
        for (External_User_Assignment__c tag : (List<External_User_Assignment__c>) query(
            'SELECT Stage__c, Contact__r.AccountId, ' + acct + 'Name, ' + acct + 'Company__c, ' + acct + 'BD_Industry__c'
            + ' FROM External_User_Assignment__c WHERE User__c = :me AND OwnerId = :me AND Contact__c != null AND '
            + matchClause(
                new List<String>{ acct + 'Name', acct + 'PersonEmail', acct + 'Company__c' },
                new List<String>{ acct + 'Phone', acct + 'PersonMobilePhone' }, byLast4)
            + ' ORDER BY ' + acct + 'Name LIMIT :lim', binds)) {
            Account a = tag.Contact__r?.Account;
            if (a == null || !seen.add(tag.Contact__r.AccountId)) {
                continue; // a merge can leave the same LO two tag rows on one account
            }
            // Same split as My Realtors / Other Contacts (ExternalLoPortalService.matchesPartnerKind).
            Boolean realtor = a.BD_Industry__c == null || a.BD_Industry__c == 'Realtor';
            items.add(item(tag.Contact__r.AccountId, a.Name, joinParts(a.Company__c, tag.Stage__c), realtor ? 'realtors' : 'otherContacts'));
        }
        return items;
    }

    // ------------------------------------------------------------------ helpers

    /** Field names are constants from this class; the term only ever reaches SOQL as a bind. */
    private static String matchClause(List<String> textFields, List<String> phoneFields, Boolean byLast4) {
        List<String> parts = new List<String>();
        for (String f : textFields) {
            parts.add(f + ' LIKE :likeTerm');
        }
        for (String f : phoneFields) {
            parts.add(f + ' IN :phones');
            if (byLast4) {
                parts.add(f + ' LIKE :last4');
            }
        }
        return '(' + String.join(parts, ' OR ') + ')';
    }

    /** SYSTEM_MODE skips FLS only; record sharing still follows this class's with sharing. */
    private static List<SObject> query(String soql, Map<String, Object> binds) {
        return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    private static void addGroup(List<ResultGroup> groups, String key, String label, List<ResultItem> items) {
        if (items.isEmpty()) {
            return;
        }
        ResultGroup g = new ResultGroup();
        g.key = key;
        g.label = label;
        g.items = items;
        groups.add(g);
    }

    private static ResultItem item(Id id, String title, String subtitle, String view) {
        ResultItem r = new ResultItem();
        r.id = id;
        r.title = title;
        r.subtitle = subtitle;
        r.view = view;
        return r;
    }

    private static String joinParts(String a, String b) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(a)) parts.add(a);
        if (String.isNotBlank(b)) parts.add(b);
        return String.join(parts, ' \u00B7 ');
    }
}
