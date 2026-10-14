/**
 * Admin-run: tags an LO on every partner-type Person Account they own, for moving an existing
 * internal LO into LO Workspace (lo-workspace/onboarding/RUNBOOK.md). LoWsPartnerTagService only
 * tags for the running user, and the tag fields have no FLS, so anonymous Apex can't do this.
 * Same row shape as LoWsPartnerTagService.tagAccounts; the LO owns the accounts, so no share.
 *
 *   LoWsPartnerTagBackfill.tagOwnedPartners('005...', 'Active Partner');
 */
public without sharing class LoWsPartnerTagBackfill {

    public static Integer tagOwnedPartners(Id loId, String stage) {
        if (!LoWsPartnerTagService.STAGES.contains(stage)) {
            throw new IllegalArgumentException('Unknown stage: ' + stage);
        }
        Set<Id> already = new Set<Id>();
        for (External_User_Assignment__c t : [SELECT Contact__c FROM External_User_Assignment__c WHERE User__c = :loId]) {
            already.add(t.Contact__c);
        }
        List<External_User_Assignment__c> tags = new List<External_User_Assignment__c>();
        for (Account a : [
            SELECT Id, PersonContactId, BD_Industry__c, Is_Realtor__c, Type, Type__c, Group__pc
            FROM Account WHERE OwnerId = :loId AND IsPersonAccount = true
        ]) {
            if (!LoWsPartnerTagService.isPartner(a) || already.contains(a.PersonContactId)) continue;
            tags.add(new External_User_Assignment__c(
                OwnerId = loId, User__c = loId, Contact__c = a.PersonContactId,
                Unique_Key__c = String.valueOf(loId) + ':' + String.valueOf(a.PersonContactId),
                Assigned_Date__c = Date.today(), Stage__c = stage, Granted_Share__c = false
            ));
        }
        insert tags;
        return tags.size();
    }
}
