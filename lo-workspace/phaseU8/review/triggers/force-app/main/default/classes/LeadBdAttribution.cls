/**
 * Stamps a lead's Biz Dev with the business development rep's designation (e.g. "Biz Dev -
 * Carleton") whenever its Buying Agent or Referral Source is a partner in that rep's book.
 *
 * Runs before every insert and update, so it holds for every entry point (intake forms, LO
 * entry, webhooks, Zapier, the BD command center) and re-applies after any automation that
 * later overwrites Biz Dev.
 *
 * - A partner already designated to someone else (e.g. "Biz Dev - Olmsted") keeps that: only
 *   partners whose designation is blank, None, Reach or the rep's own value count.
 * - A human admin changing Biz Dev by hand wins: that sets BD_Attribution_Override__c and the
 *   rule leaves the lead alone until it is unchecked. The integration user is not a "human
 *   admin", so automation can never switch the rule off.
 */
public without sharing class LeadBdAttribution {

    static final Set<String> OPEN_DESIGNATIONS = new Set<String>{ null, '', 'None', 'Biz Dev - Reach' };
    static final String INTEGRATION_USERNAME = 'reach@nimbuscloudsolutions.com';

    public static void apply(List<Lead> leads, Map<Id, Lead> oldMap) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        List<Lead> candidates = new List<Lead>();
        for (Lead l : leads) {
            if (l.IsConverted) continue;
            Lead old = oldMap == null ? null : oldMap.get(l.Id);
            if (old != null && l.Biz_Dev__c != old.Biz_Dev__c && isHumanAdmin()) {
                l.BD_Attribution_Override__c = true;
            }
            if (l.BD_Attribution_Override__c) continue;
            if (l.Realtor_Buying_Agent__c == null && l.Referral_Source__c == null) continue;
            if (l.Realtor_Buying_Agent__c != null) accountIds.add(l.Realtor_Buying_Agent__c);
            if (l.Referral_Source__c != null) contactIds.add(l.Referral_Source__c);
            candidates.add(l);
        }
        if (candidates.isEmpty()) return;

        Map<Id, Id> accountByContact = new Map<Id, Id>();
        if (!contactIds.isEmpty()) {
            for (Contact c : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds AND AccountId != null]) {
                accountByContact.put(c.Id, c.AccountId);
                accountIds.add(c.AccountId);
            }
        }
        Map<Id, String> designationByAccount = new Map<Id, String>();
        Map<Id, Account> partners = new Map<Id, Account>([
            SELECT Id, PersonContactId, Biz_Dev_Designation__c, BD_Rep__r.BD_Designation__c,
                   BD_Industry__c, Is_Realtor__c, Type__c
            FROM Account WHERE Id IN :accountIds AND BD_Rep__c != null AND BD_Rep__r.IsActive = true
        ]);
        // The intake form always files the sender as Buying Agent. A non-realtor partner (a CPA,
        // an insurance agent) is a Referral Source instead.
        for (Lead l : candidates) {
            Account agent = partners.get(l.Realtor_Buying_Agent__c);
            if (l.ReferralFormSourceEmail__c != null && agent != null && !isRealtor(agent) && agent.PersonContactId != null) {
                l.Referral_Source__c = agent.PersonContactId;
                l.Realtor_Buying_Agent__c = null;
                accountByContact.put(agent.PersonContactId, agent.Id);
            }
        }
        for (Account a : partners.values()) {
            String repDesignation = a.BD_Rep__r.BD_Designation__c;
            if (String.isBlank(repDesignation)) continue;
            if (OPEN_DESIGNATIONS.contains(a.Biz_Dev_Designation__c) || a.Biz_Dev_Designation__c == repDesignation) {
                designationByAccount.put(a.Id, repDesignation);
            }
        }
        if (designationByAccount.isEmpty()) return;

        for (Lead l : candidates) {
            String target = designationByAccount.get(l.Realtor_Buying_Agent__c);
            if (target == null) target = designationByAccount.get(accountByContact.get(l.Referral_Source__c));
            if (target != null) l.Biz_Dev__c = target;
        }
    }

    static Boolean isRealtor(Account a) {
        return a.BD_Industry__c == 'Realtor' || a.Is_Realtor__c == true || a.Type__c == 'Realtor Account';
    }

    @TestVisible static Boolean adminOverrideForTest;

    static Boolean humanAdmin;

    static Boolean isHumanAdmin() {
        if (adminOverrideForTest != null) return adminOverrideForTest;
        if (humanAdmin != null) return humanAdmin;
        if (UserInfo.getUserName() == INTEGRATION_USERNAME || UserInfo.getUserType() != 'Standard') return false;
        humanAdmin = [SELECT PermissionsModifyAllData FROM Profile WHERE Id = :UserInfo.getProfileId()].PermissionsModifyAllData;
        return humanAdmin;
    }

    /** Partner accounts carry the rep's designation too, so flows that copy it agree with the rule. */
    public static String designationForNewPartner(String currentDesignation, Id repId) {
        if (!OPEN_DESIGNATIONS.contains(currentDesignation)) return currentDesignation;
        List<User> reps = [SELECT BD_Designation__c FROM User WHERE Id = :repId];
        return reps.isEmpty() || String.isBlank(reps[0].BD_Designation__c) ? currentDesignation : reps[0].BD_Designation__c;
    }
}