/**
 * LO Workspace, Phase 5: an outside loan officer's realtor / partner tags.
 *
 * A tag is one External_User_Assignment__c row per (LO, partner Person Account):
 *   User__c = the LO, Contact__c = the partner's PersonContactId, Stage__c = that LO's own stage,
 *   Granted_Share__c = this class created the LO's Manual AccountShare for the tag.
 * The row is owned by the LO and the object is Private, so no LO sees another LO's tags (managers
 * and admins see them through the role hierarchy / View All).
 *
 * A tag grants Read on the partner Account (Manual AccountShare, Read only), which is what lets the
 * LO see the partner and log calls, texts, notes and events on it. Untagging removes the tag and the
 * share only when this class created that share, so access granted any other way is never removed.
 *
 * without sharing on purpose: duplicate matching has to see every Person Account (outside LOs see
 * almost none), and the share / assignment inserts must work on records the LO cannot see yet.
 * Every public method acts only for UserInfo.getUserId(); nothing takes a user Id from the client.
 * Outside LOs are recognised by the External_LO custom permission (isTagMode); Partner Workspace
 * portal users never hold it, so the portal keeps its old behaviour.
 */
public without sharing class LoWsPartnerTagService {

    public static final String ADMIN_MESSAGE = 'This person already exists at Reach. Contact an admin.';
    public static final String DEFAULT_STAGE = 'Prospect';
    public static final List<String> STAGES = new List<String>{
        'Prospect', 'Contacted', 'Meeting Set', 'Met', 'Active Partner', 'Dormant'
    };
    // Realtor Prospects view = tags not yet Active Partner (Dormant comes after Active Partner).
    public static final Set<String> PROSPECT_STAGES = new Set<String>{ 'Prospect', 'Contacted', 'Meeting Set', 'Met' };
    // Closed-won Transaction__c.Status__c values. Lost and Cancelled are not past clients.
    public static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Funding', 'PC Review', 'Post-Closed' };

    // Same values as BdCommandCenterController.TYPE_FOR_INDUSTRY (private there).
    private static final Map<String, String> TYPE_FOR_INDUSTRY = new Map<String, String>{
        'Realtor' => 'Realtor Account', 'Title Agent' => 'Title Agent Account'
    };
    // Group__pc values the Partner Workspace views and older automation read.
    private static final Map<String, String> GROUP_FOR_INDUSTRY = new Map<String, String>{
        'Realtor' => 'Realtor', 'Title Agent' => 'Title Agent', 'Insurance Agent' => 'Insurance Agent'
    };
    private static final Set<String> PARTNER_GROUPS = new Set<String>{
        'Realtor', 'Realtor Prospect', 'Title Agent', 'Insurance Agent'
    };

    public static Boolean isTagMode() {
        // LO_Workspace_Demo: internal demo users (Brandon) get the same behaviour without the restriction rules.
        return FeatureManagement.checkPermission('External_LO') || FeatureManagement.checkPermission('LO_Workspace_Demo');
    }

    // ------------------------------------------------------------------ reads

    /** The running LO's tags keyed by partner Account Id. */
    public static Map<Id, External_User_Assignment__c> myTags(Set<Id> onlyAccountIds) {
        Id me = UserInfo.getUserId();
        Map<Id, External_User_Assignment__c> byAccount = new Map<Id, External_User_Assignment__c>();
        String q = 'SELECT Id, Stage__c, Granted_Share__c, Contact__r.AccountId FROM External_User_Assignment__c '
            + 'WHERE User__c = :me AND OwnerId = :me AND Contact__c != null';
        if (onlyAccountIds != null) {
            q += ' AND Contact__r.AccountId IN :onlyAccountIds';
        }
        for (External_User_Assignment__c t : (List<External_User_Assignment__c>) Database.query(q + ' LIMIT 2000')) {
            if (t.Contact__r?.AccountId != null) {
                byAccount.put(t.Contact__r.AccountId, t);
            }
        }
        return byAccount;
    }

    /** The running LO's closed-won loans (Loan_Officer__c = me), newest first. */
    public static List<Transaction__c> myClosedLoans() {
        Id me = UserInfo.getUserId();
        return [
            SELECT Id, Name, Status__c, Closing_Date__c, Loan_Amount_1st__c, Loan_Program_1st__c,
                   Borrower_Name__c, Borrower_Name__r.Name, Borrower_Name__r.PersonEmail,
                   Borrower_Name__r.PersonMobilePhone, Borrower_Name__r.Phone
            FROM Transaction__c
            WHERE Loan_Officer__c = :me AND Status__c IN :CLOSED_STATUSES AND Borrower_Name__c != null
            ORDER BY Closing_Date__c DESC NULLS LAST
            LIMIT 2000
        ];
    }

    // ------------------------------------------------------------------ duplicate decisions

    public class Decision {
        /** Partner-type matches, oldest first (the keeper). */
        public List<Account> partners = new List<Account>();
        /** Matched someone, but nobody taggable: refuse with ADMIN_MESSAGE. */
        public Boolean blocked = false;
    }

    /** One Decision per (emails[i], phones[i]); one duplicate query for the whole list. */
    public static List<Decision> classify(List<String> emails, List<String> phones) {
        List<List<PersonAccountDuplicateService.Match>> all =
            PersonAccountDuplicateService.findMatchesAcrossOrg(emails, phones);
        Set<Id> ids = new Set<Id>();
        for (List<PersonAccountDuplicateService.Match> ms : all) {
            for (PersonAccountDuplicateService.Match m : ms) ids.add(m.accountId);
        }
        Map<Id, Account> accounts = new Map<Id, Account>(selectPartnerFields(ids));
        List<Decision> out = new List<Decision>();
        for (List<PersonAccountDuplicateService.Match> ms : all) {
            Decision d = new Decision();
            Set<Id> matched = new Set<Id>();
            for (PersonAccountDuplicateService.Match m : ms) matched.add(m.accountId);
            // accounts is ordered by CreatedDate, so partners come out oldest first.
            for (Account a : accounts.values()) {
                if (matched.contains(a.Id) && isPartner(a)) d.partners.add(a);
            }
            d.blocked = !ms.isEmpty() && d.partners.isEmpty();
            out.add(d);
        }
        return out;
    }

    /**
     * A partner-type account is one of Fred's BD industries (BD_Industry__c set) or any of the
     * org's realtor / title / insurance flags. Borrowers, past clients and everyone else are not.
     */
    public static Boolean isPartner(Account a) {
        if (a == null) return false;
        if (a.BD_Industry__c != null || a.Is_Realtor__c == true || a.Type == 'Realtor'
            || a.Type__c == 'Realtor Account' || a.Type__c == 'Title Agent Account') {
            return true;
        }
        if (a.Group__pc != null) {
            for (String g : a.Group__pc.split(';')) {
                if (PARTNER_GROUPS.contains(g)) return true;
            }
        }
        return false;
    }

    private static List<Account> selectPartnerFields(Set<Id> ids) {
        return [
            SELECT Id, Name, OwnerId, PersonContactId, Company__c, PersonTitle, BillingCity, Group__pc,
                   BD_Industry__c, Is_Realtor__c, Type, Type__c, CreatedDate
            FROM Account
            WHERE Id IN :ids AND IsPersonAccount = true
            ORDER BY CreatedDate ASC
        ];
    }

    // ------------------------------------------------------------------ add / tag / untag / stage

    public class AddResult {
        @AuraEnabled public String status;      // created | match
        @AuraEnabled public Id accountId;
        @AuraEnabled public List<Account> matches = new List<Account>();
    }

    /**
     * Add partner from LO Workspace. Partner-type duplicate -> status 'match' (the UI offers
     * "Tag me", nothing is written). Any other duplicate -> ADMIN_MESSAGE. No duplicate -> a new
     * Person Account owned by the LO, tagged.
     */
    public static AddResult addPartner(String name, String phone, String email, String company, String market, String partnerType) {
        if (String.isBlank(name)) throw new DomainException('Enter the partner name.');
        if (String.isBlank(company)) throw new DomainException('Enter the brokerage or company.');
        if (PersonAccountDuplicateService.normalizeEmail(email) == null && PersonAccountDuplicateService.normalizePhone(phone) == null) {
            throw new DomainException('Enter a phone number or email so we can check Reach for duplicates.');
        }
        String industry = industryFor(partnerType);
        Decision d = classify(new List<String>{ email }, new List<String>{ phone })[0];
        AddResult r = new AddResult();
        if (!d.partners.isEmpty()) {
            r.status = 'match';
            // Name and company only. Never the owner or contact details of someone the LO cannot see.
            for (Account a : d.partners) {
                r.matches.add(new Account(Id = a.Id, Name = a.Name, Company__c = a.Company__c ?? a.PersonTitle));
            }
            return r;
        }
        if (d.blocked) throw new DomainException(ADMIN_MESSAGE);

        Account a = newPartner(name, phone, email, company, market, industry);
        insert a;
        tagAccounts(new Set<Id>{ a.Id });
        r.status = 'created';
        r.accountId = a.Id;
        return r;
    }

    /**
     * Tag an existing partner: "Tag me" after a duplicate hit (email/phone given) or "Link" from the
     * partner search (an account the LO can already read). Either way it must be partner-type.
     */
    public static void tagExisting(Id accountId, String email, String phone) {
        List<Account> rows = selectPartnerFields(new Set<Id>{ accountId });
        if (rows.isEmpty()) throw new DomainException('Partner record could not be found.');
        if (!isPartner(rows[0])) throw new DomainException(ADMIN_MESSAGE);
        Boolean allowed = RecordAccessGuard.readable(new Set<Id>{ accountId }).contains(accountId);
        if (!allowed && (String.isNotBlank(email) || String.isNotBlank(phone))) {
            for (Account p : classify(new List<String>{ email }, new List<String>{ phone })[0].partners) {
                if (p.Id == accountId) allowed = true;
            }
        }
        if (!allowed) throw new DomainException(RecordAccessGuard.NO_ACCESS);
        tagAccounts(new Set<Id>{ accountId });
    }

    /**
     * Tags the running LO on each account (idempotent) and returns the accounts now tagged.
     * Callers must have decided the accounts are taggable partners.
     */
    public static Set<Id> tagAccounts(Set<Id> accountIds) {
        Id me = UserInfo.getUserId();
        Set<Id> tagged = new Set<Id>();
        if (accountIds == null || accountIds.isEmpty()) return tagged;
        Map<Id, External_User_Assignment__c> existing = myTags(accountIds);
        tagged.addAll(existing.keySet());

        Set<Id> manuallyShared = new Set<Id>();
        for (AccountShare s : [
            SELECT AccountId FROM AccountShare
            WHERE AccountId IN :accountIds AND UserOrGroupId = :me AND RowCause = 'Manual'
        ]) {
            manuallyShared.add(s.AccountId);
        }

        List<Account> todo = new List<Account>();
        List<AccountShare> shares = new List<AccountShare>();
        for (Account a : [SELECT Id, OwnerId, PersonContactId FROM Account WHERE Id IN :accountIds AND PersonContactId != null]) {
            if (existing.containsKey(a.Id)) continue;
            todo.add(a);
            if (a.OwnerId != me && !manuallyShared.contains(a.Id)) {
                shares.add(new AccountShare(
                    AccountId = a.Id, UserOrGroupId = me, AccountAccessLevel = 'Read',
                    OpportunityAccessLevel = 'None', CaseAccessLevel = 'None',
                    RowCause = Schema.AccountShare.RowCause.Manual
                ));
            }
        }
        Set<Id> granted = new Set<Id>();
        Set<Id> shareFailed = new Set<Id>();
        List<Database.SaveResult> shareResults = Database.insert(shares, false);
        for (Integer i = 0; i < shareResults.size(); i++) {
            if (shareResults[i].isSuccess()) granted.add(shares[i].AccountId);
            else shareFailed.add(shares[i].AccountId);
        }

        List<External_User_Assignment__c> tags = new List<External_User_Assignment__c>();
        for (Account a : todo) {
            if (shareFailed.contains(a.Id)) continue;
            tags.add(new External_User_Assignment__c(
                User__c = me, Contact__c = a.PersonContactId,
                Unique_Key__c = String.valueOf(me) + ':' + String.valueOf(a.PersonContactId),
                Assigned_Date__c = Date.today(), Stage__c = DEFAULT_STAGE,
                Granted_Share__c = granted.contains(a.Id)
            ));
        }
        List<Database.SaveResult> tagResults = Database.insert(tags, false);
        List<AccountShare> orphanShares = new List<AccountShare>();
        for (Integer i = 0; i < tagResults.size(); i++) {
            Id accountId = accountIdFor(todo, tags[i].Contact__c);
            if (tagResults[i].isSuccess()) {
                tagged.add(accountId);
            } else if (granted.contains(accountId)) {
                // Never leave a share behind without the tag that justifies it.
                for (AccountShare s : shares) if (s.AccountId == accountId && s.Id != null) orphanShares.add(s);
            }
        }
        if (!orphanShares.isEmpty()) Database.delete(orphanShares, false);
        return tagged;
    }

    private static Id accountIdFor(List<Account> accounts, Id contactId) {
        for (Account a : accounts) if (a.PersonContactId == contactId) return a.Id;
        return null;
    }

    /** Removes the running LO's tag, and the share only if the tag created it. */
    public static void untag(Id accountId) {
        List<External_User_Assignment__c> rows = requireMyTagRows(accountId);
        Boolean granted = false;
        for (External_User_Assignment__c t : rows) granted |= t.Granted_Share__c == true;
        if (granted) {
            delete [
                SELECT Id FROM AccountShare
                WHERE AccountId = :accountId AND UserOrGroupId = :UserInfo.getUserId() AND RowCause = 'Manual'
            ];
        }
        delete rows;
    }

    public static void setStage(Id accountId, String stage) {
        if (!STAGES.contains(stage)) throw new DomainException('Unknown stage.');
        List<External_User_Assignment__c> rows = requireMyTagRows(accountId);
        for (External_User_Assignment__c t : rows) t.Stage__c = stage;
        update rows;
    }

    /**
     * Every tag row I hold on this account. Normally one, but a merge reparents both LOs' rows of
     * the losing duplicate onto the keeper, so the same LO can end up with two. Rows whose
     * Contact__c was cleared (deleted account, SetNull) never match an account and are ignored.
     */
    private static List<External_User_Assignment__c> requireMyTagRows(Id accountId) {
        Id me = UserInfo.getUserId();
        List<External_User_Assignment__c> rows = accountId == null ? new List<External_User_Assignment__c>() : [
            SELECT Id, Stage__c, Granted_Share__c FROM External_User_Assignment__c
            WHERE User__c = :me AND OwnerId = :me AND Contact__c != null AND Contact__r.AccountId = :accountId
        ];
        if (rows.isEmpty()) throw new DomainException('That partner is not on your list.');
        return rows;
    }

    // ------------------------------------------------------------------ creating partners

    /** Partner type from the UI (BD industry or the portal's Realtor/Title/Insurance) or a CSV cell. */
    public static String industryFor(String raw) {
        if (String.isBlank(raw)) return 'Realtor';
        String v = raw.trim().toLowerCase();
        for (Schema.PicklistEntry e : Account.BD_Industry__c.getDescribe().getPicklistValues()) {
            if (e.isActive() && e.getValue().toLowerCase() == v) return e.getValue();
        }
        if (v.contains('title')) return 'Title Agent';
        if (v.contains('insurance')) return 'Insurance Agent';
        if (v.contains('cpa') || v.contains('accountant')) return 'CPA';
        if (v.contains('financial') || v.contains('planner') || v.contains('advisor')) return 'Financial Planner';
        if (v.contains('attorney') || v.contains('lawyer')) return 'Attorney';
        if (v.contains('builder')) return 'Builder';
        if (v.contains('realtor') || v.contains('agent') || v.contains('prospect') || v.contains('broker')) return 'Realtor';
        return 'Other';
    }

    /** A new partner Person Account owned by the running LO (not inserted). */
    public static Account newPartner(String name, String phone, String email, String company, String market, String industry) {
        List<String> parts = name.trim().split('\\s+', 2);
        Account a = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = parts.size() > 1 ? parts[0] : null,
            LastName = parts.size() > 1 ? parts[1] : parts[0],
            PersonEmail = String.isBlank(email) ? null : email.trim(),
            PersonMobilePhone = String.isBlank(phone) ? null : phone.trim(),
            // Company__c is what the LO Workspace / portal shows; PersonTitle is what Fred's BD tools show.
            Company__c = String.isBlank(company) ? null : company.trim(),
            PersonTitle = String.isBlank(company) ? null : company.trim(),
            BillingCity = String.isBlank(market) ? null : market.trim(),
            BD_Industry__c = industry,
            Type__c = TYPE_FOR_INDUSTRY.containsKey(industry) ? TYPE_FOR_INDUSTRY.get(industry) : 'Other',
            Group__pc = GROUP_FOR_INDUSTRY.get(industry),
            OwnerId = UserInfo.getUserId()
        );
        if (industry == 'Realtor') a.Is_Realtor__c = true;
        return a;
    }

    // ------------------------------------------------------------------ consumer import

    public static final String CONFLICT_OWN_LEAD = 'Already in your list (one of your leads). Not imported again.';
    public static final String CONFLICT_OWN_CLIENT = 'Already in your list (one of your clients). Not imported again.';

    /** Past clients I imported: Person Accounts I own with Group__pc including Client. */
    public static List<Account> myClientAccounts() {
        Id me = UserInfo.getUserId();
        return [
            SELECT Id, Name, PersonEmail, PersonMobilePhone, Phone, BillingCity, CreatedDate
            FROM Account
            WHERE OwnerId = :me AND IsPersonAccount = true AND Group__pc INCLUDES ('Client')
            ORDER BY Name
            LIMIT 2000
        ];
    }

    /** A past-client (borrower) Person Account owned by the running LO (not inserted). */
    public static Account newPastClient(String firstName, String lastName, String fullName, String phone, String email, String city, String notes) {
        String first = firstName;
        String last = lastName;
        if (String.isNotBlank(fullName)) {
            List<String> parts = fullName.trim().split('\\s+', 2);
            first = parts.size() > 1 ? parts[0] : null;
            last = parts.size() > 1 ? parts[1] : parts[0];
        } else if (String.isBlank(last)) {
            // A first name alone becomes the last name (LastName is required) instead of "Borrower".
            last = first;
            first = null;
        }
        return new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = String.isBlank(first) ? null : first.trim(),
            LastName = last.trim(),
            PersonEmail = String.isBlank(email) ? null : email.trim(),
            PersonMobilePhone = String.isBlank(phone) ? null : phone.trim(),
            BillingCity = String.isBlank(city) ? null : city.trim(),
            Description = String.isBlank(notes) ? null : notes.trim(),
            Type__c = 'Borrower Account',
            Group__pc = 'Client',
            OwnerId = UserInfo.getUserId()
        );
    }
}
