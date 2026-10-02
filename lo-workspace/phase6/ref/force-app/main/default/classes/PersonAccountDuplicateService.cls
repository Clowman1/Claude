/**
 * Finds existing Person Accounts that match an email address and/or phone number.
 *
 * Every entry point that creates a Person Account calls this BEFORE inserting, so a
 * duplicate is caught at the point of entry rather than discovered in a cleanup later.
 *
 * Phone numbers are stored inconsistently in this org — "(407) 244-6554" and
 * "407-759-4300" both occur — so SOQL cannot compare them directly. We narrow with a
 * LIKE on the last four digits (highly selective: ~3 rows in 23.5k accounts) and then
 * compare fully normalized values in Apex, which makes the match exact rather than fuzzy.
 *
 * Realtors are flagged four inconsistent ways in this org (Is_Realtor__c,
 * Type__c = 'Realtor Account', Group__pc INCLUDES 'Realtor', and standard Type = 'Realtor'),
 * so isRealtor below spans all of them.
 */
public with sharing class PersonAccountDuplicateService {

    /**
     * Thrown when a matching Person Account already exists. A custom type rather than
     * AuraHandledException because Apex can only THROW AuraHandledException from an Aura or
     * VisualForce context - from a Flow, trigger or batch it fails with a LimitException
     * instead of the intended error. Aura entry points translate this for the UI.
     */
    public class DuplicateFoundException extends Exception {}


    @TestVisible
    private static final String MATCH_EMAIL = 'Email';
    @TestVisible
    private static final String MATCH_PHONE = 'Phone';
    @TestVisible
    private static final String MATCH_BOTH = 'Email and phone';

    public class Match {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String realtorGroup;
        @AuraEnabled public String brokerage;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String matchedOn;
        @AuraEnabled public Boolean isRealtor;
        @AuraEnabled public Integer loanFiles;
    }

    /**
     * @param email          email typed into the create form
     * @param phone          phone typed into the create form
     * @param accountIdToSkip an existing record to exclude (editing, not creating). May be null.
     */
    @AuraEnabled
    public static List<Match> findMatches(String email, String phone, Id accountIdToSkip) {
        List<Match> matches = matchAll(new List<String>{ email }, new List<String>{ phone }, accountIdToSkip, false)[0];
        Map<Id, Match> byId = new Map<Id, Match>();
        for (Match m : matches) {
            byId.put(m.accountId, m);
        }

        if (!byId.isEmpty()) {
            for (AggregateResult row : [
                SELECT Account__c accountId, COUNT(Id) total
                FROM Transaction__c
                WHERE Account__c IN :byId.keySet()
                GROUP BY Account__c
            ]) {
                Match m = byId.get((Id) row.get('accountId'));
                if (m != null) {
                    m.loanFiles = (Integer) row.get('total');
                }
            }
        }
        return matches;
    }

    /**
     * Bulk, org-wide version of findMatches for outside loan officers (LO Workspace), who cannot see
     * most Person Accounts (Account OWD is Private and they have no View All), so a with-sharing
     * lookup would miss nearly every duplicate. Same normalization, placeholders and matching rule
     * as findMatches. Result i holds the matches for emails[i] / phones[i]; loanFiles stays 0.
     *
     * Deliberately NOT @AuraEnabled: it reveals records the caller cannot read. Callers decide what
     * (if anything) to show and must never return the matched owner to an outside LO.
     */
    public static List<List<Match>> findMatchesAcrossOrg(List<String> emails, List<String> phones) {
        return matchAll(emails, phones, null, true);
    }

    // One query for any number of inputs, then an in-memory index, so a 200-row import costs
    // one SOQL instead of 200.
    private static List<List<Match>> matchAll(List<String> emails, List<String> phones, Id accountIdToSkip, Boolean orgWide) {
        Integer size = Math.max(emails == null ? 0 : emails.size(), phones == null ? 0 : phones.size());
        List<String> normEmails = new List<String>();
        List<String> normPhones = new List<String>();
        Set<String> emailValues = new Set<String>();
        Set<String> lastFours = new Set<String>();
        for (Integer i = 0; i < size; i++) {
            String e = normalizeEmail(emails != null && i < emails.size() ? emails[i] : null);
            String p = normalizePhone(phones != null && i < phones.size() ? phones[i] : null);
            normEmails.add(e);
            normPhones.add(p);
            if (e != null) emailValues.add(e);
            if (p != null) lastFours.add('%' + p.right(4));
        }
        List<List<Match>> results = new List<List<Match>>();
        if (emailValues.isEmpty() && lastFours.isEmpty()) {
            for (Integer i = 0; i < size; i++) results.add(new List<Match>());
            return results;
        }
        // Sentinels keep both binds non-empty, exactly like the original single-value query.
        if (emailValues.isEmpty()) emailValues.add(' none');
        if (lastFours.isEmpty()) lastFours.add(' none');
        Map<String, Object> binds = new Map<String, Object>{
            'emailValues' => new List<String>(emailValues),
            'lastFours' => new List<String>(lastFours)
        };
        String soql = CANDIDATE_SOQL + (orgWide ? 2000 : 200);
        List<Account> candidates = orgWide
            ? new OrgWideQuery().run(soql, binds)
            : Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);

        // Normalize each candidate once.
        Map<String, List<Account>> byEmail = new Map<String, List<Account>>();
        Map<String, List<Account>> byPhone = new Map<String, List<Account>>();
        for (Account c : candidates) {
            if (accountIdToSkip != null && c.Id == accountIdToSkip) continue;
            for (String v : new List<String>{ c.PersonEmail, c.Email_2__pc }) index(byEmail, normalizeEmail(v), c);
            for (String v : new List<String>{ c.PersonMobilePhone, c.Phone, c.Phone_2__c, c.PersonHomePhone, c.PersonOtherPhone }) {
                index(byPhone, normalizePhone(v), c);
            }
        }

        for (Integer i = 0; i < size; i++) {
            List<Account> emailHits = normEmails[i] == null ? null : byEmail.get(normEmails[i]);
            List<Account> phoneHits = normPhones[i] == null ? null : byPhone.get(normPhones[i]);
            Set<Id> emailIds = emailHits == null ? new Set<Id>() : new Map<Id, Account>(emailHits).keySet();
            Set<Id> phoneIds = phoneHits == null ? new Set<Id>() : new Map<Id, Account>(phoneHits).keySet();
            List<Match> matches = new List<Match>();
            // Candidate order, as before. The LIKE can catch a different area code sharing the last
            // four digits; the normalized index above drops those.
            for (Account candidate : candidates) {
                Boolean emailHit = emailIds.contains(candidate.Id);
                Boolean phoneHit = phoneIds.contains(candidate.Id);
                if (emailHit || phoneHit) matches.add(toMatch(candidate, emailHit, phoneHit));
            }
            results.add(matches);
        }
        return results;
    }

    private static void index(Map<String, List<Account>> m, String key, Account a) {
        if (key == null) return;
        if (!m.containsKey(key)) m.put(key, new List<Account>());
        List<Account> bucket = m.get(key);
        if (bucket.isEmpty() || bucket[bucket.size() - 1].Id != a.Id) bucket.add(a);
    }

    private static Match toMatch(Account candidate, Boolean emailHit, Boolean phoneHit) {
        Match m = new Match();
        m.accountId = candidate.Id;
        m.name = candidate.Name;
        m.email = candidate.PersonEmail;
        m.phone = String.isNotBlank(candidate.PersonMobilePhone) ? candidate.PersonMobilePhone : candidate.Phone;
        m.realtorGroup = candidate.Realtor_Group__c;
        m.brokerage = candidate.PersonTitle;
        m.ownerName = candidate.Owner == null ? null : candidate.Owner.Name;
        m.matchedOn = (emailHit && phoneHit) ? MATCH_BOTH : (emailHit ? MATCH_EMAIL : MATCH_PHONE);
        m.isRealtor = candidate.Is_Realtor__c == true
            || candidate.Type__c == 'Realtor Account'
            || candidate.Type == 'Realtor';
        m.loanFiles = 0;
        return m;
    }

    private static final String CANDIDATE_SOQL =
        'SELECT Id, Name, PersonEmail, Email_2__pc, Phone, Phone_2__c, '
        + 'PersonMobilePhone, PersonHomePhone, PersonOtherPhone, '
        + 'Realtor_Group__c, PersonTitle, Owner.Name, Is_Realtor__c, Type__c, Type '
        + 'FROM Account WHERE IsPersonAccount = true AND ('
        + 'PersonEmail IN :emailValues OR Email_2__pc IN :emailValues '
        + 'OR PersonMobilePhone LIKE :lastFours OR Phone LIKE :lastFours OR Phone_2__c LIKE :lastFours '
        + 'OR PersonHomePhone LIKE :lastFours OR PersonOtherPhone LIKE :lastFours) LIMIT ';

    // Inner classes do not inherit the outer sharing keyword; this one exists only to run the
    // candidate query without sharing for findMatchesAcrossOrg.
    private without sharing class OrgWideQuery {
        List<Account> run(String soql, Map<String, Object> binds) {
            return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
        }
    }

    // ---- Hard stop used by every create entry point ----

    /**
     * Throws when an existing Person Account already holds this email or phone, so the user
     * must select the existing record instead of creating a second one. Called server-side by
     * the create methods themselves, not just the UI, so the rule cannot be bypassed by a
     * caller that skips the modal.
     *
     * Note for whoever hits this on a brokerage main line: 83 mobile numbers in this org are
     * shared by differently-named agents, so a phone-only match can legitimately be a new
     * agent at an existing office. The message tells them to use that agent's direct number.
     */
    public static void blockIfDuplicate(String email, String phone) {
        List<Match> matches = findMatches(email, phone, null);
        if (matches.isEmpty()) {
            return;
        }
        throw new DuplicateFoundException(buildDuplicateMessage(matches));
    }

    @TestVisible
    private static String buildDuplicateMessage(List<Match> matches) {
        List<String> described = new List<String>();
        Boolean phoneOnly = true;
        for (Match m : matches) {
            described.add(m.name + ' (matched on ' + m.matchedOn.toLowerCase() + ')');
            if (m.matchedOn != MATCH_PHONE) {
                phoneOnly = false;
            }
        }
        String message = 'This person already exists in Salesforce: '
            + String.join(described, '; ')
            + '. Select the existing account instead of creating a new one.';
        if (phoneOnly) {
            message += ' If this is a different agent at the same office, enter that agent\'s'
                + ' own direct mobile number rather than the office line.';
        }
        return message;
    }

    // ---- Flow support: find-or-attach for the borrower path ----

    public class FindRequest {
        @InvocableVariable(label='Email' required=false)
        public String email;
        @InvocableVariable(label='Phone' required=false)
        public String phone;
    }

    public class FindResult {
        @InvocableVariable(label='Matching Person Account Id')
        public String accountId;
        @InvocableVariable(label='Found an existing Person Account')
        public Boolean found;
        @InvocableVariable(label='Matched On')
        public String matchedOn;
        @InvocableVariable(label='Number of matches')
        public Integer matchCount;
    }

    /**
     * Used by Create_Person_Account_For_Transaction so a Transaction built from a converted
     * Lead attaches to the borrower's existing Person Account from a prior deal instead of
     * creating a second one. When more than one matches, the one holding the most loan files
     * wins, then the oldest — the same keeper order used in the cleanup.
     */
    @InvocableMethod(
        label='Find Matching Person Account'
        description='Returns an existing Person Account matching this email or phone, so a Transaction can attach to it instead of creating a duplicate.'
        category='Person Account'
    )
    public static List<FindResult> findMatchingPersonAccount(List<FindRequest> requests) {
        List<FindResult> results = new List<FindResult>();
        for (FindRequest request : requests) {
            FindResult result = new FindResult();
            result.found = false;
            result.matchCount = 0;
            List<Match> matches = findMatches(request.email, request.phone, null);
            result.matchCount = matches.size();
            if (!matches.isEmpty()) {
                Match best = matches[0];
                for (Match candidate : matches) {
                    if (candidate.loanFiles > best.loanFiles) {
                        best = candidate;
                    }
                }
                result.found = true;
                result.accountId = best.accountId;
                result.matchedOn = best.matchedOn;
            }
            results.add(result);
        }
        return results;
    }

    // ---- normalization ----

    @TestVisible
    public static String normalizeEmail(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String email = value.trim().toLowerCase();
        if (!email.contains('@') || !email.contains('.')) {
            return null;
        }
        // Placeholders that appear on many unrelated records in this org.
        if (email.startsWith('tbd@') || email.startsWith('noemail') || email.startsWith('test@')
            || email.startsWith('none@') || email.startsWith('na@')) {
            return null;
        }
        return email;
    }

    @TestVisible
    public static String normalizePhone(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String digits = value.replaceAll('[^0-9]', '');
        if (digits.length() == 11 && digits.startsWith('1')) {
            digits = digits.substring(1);
        }
        if (digits.length() != 10) {
            return null;
        }
        // Placeholder numbers, and NANP numbers cannot start with 0 or 1.
        if (digits.startsWith('0') || digits.startsWith('1')) {
            return null;

        }
        Set<String> placeholders = new Set<String>{
            '0000000000','1111111111','1234567890','9999999999','5555555555',
            '2222222222','3333333333','4444444444','6666666666','7777777777','8888888888'
        };
        if (placeholders.contains(digits)) {
            return null;
        }
        return digits;
    }
}