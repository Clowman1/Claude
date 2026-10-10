/**
 * CSV partner matching must see Person Accounts the running external user cannot read.
 * with sharing + SYSTEM_MODE still omitted other owners' records in community/standard tests,
 * so this selector is without sharing. Visibility after a match is granted via AccountShare.
 * See ADR-0002.
 */
public without sharing class PersonAccountImportSelector {
    public List<Account> selectPartnersForImportMatch(Set<String> emails, Set<String> phones) {
        Set<String> safeEmails = emails == null ? new Set<String>() : emails;
        Set<String> safePhones = phones == null ? new Set<String>() : phones;
        if (safeEmails.isEmpty() && safePhones.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, Name, PersonEmail, Phone, PersonContactId, Group__pc, Company__c,
                   BillingCity, OwnerId, Follow_Up_LO__c, Preferred_LO__c, Biz_Dev_Designation__c
            FROM Account
            WHERE IsPersonAccount = true
              AND Group__pc IN ('Realtor', 'Realtor Prospect', 'Title Agent', 'Insurance Agent')
              AND (
                  PersonEmail IN :safeEmails
                  OR Phone IN :safePhones
              )
            LIMIT 500
        ];
    }
}