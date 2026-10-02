public with sharing class PersonAccountRepository {
    /**
     * Resolve the Person Account record type by developer name.
     */
    public Id selectPersonAccountRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'PersonAccount'
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    /**
     * Finds an existing Person Account by normalized email.
     */
    public Account selectPersonAccountByEmail(String email) {
        if (String.isBlank(email)) {
            return null;
        }

        String normalizedEmail = email.trim();
        List<Account> accounts = [
            SELECT Id, Name, PersonEmail
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail != null
            AND PersonEmail = :normalizedEmail
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    public Account selectPersonAccountById(Id accountId) {
        if (accountId == null) {
            return null;
        }

        List<Account> accounts = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :accountId
            AND IsPersonAccount = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    /**
     * Realtor and partner accounts owned by the external LO for follow-up cadence review.
     */
    public List<Account> selectRealtorPartnersByOwner(Id ownerId) {
        if (ownerId == null) {
            return new List<Account>();
        }

        return [
            SELECT Id, Name, PersonEmail, Phone, LastActivityDate
            FROM Account
            WHERE OwnerId = :ownerId
              AND IsPersonAccount = true
              AND Group__pc IN ('Realtor', 'Realtor Prospect')
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
            LIMIT 500
        ];
    }

    public List<Account> selectPortalPartnersForUser(Id userId) {
        if (userId == null) {
            return new List<Account>();
        }
        Set<Id> partnerIds = new Set<Id>();
        for (Task taskRecord : [
            SELECT WhatId
            FROM Task
            WHERE OwnerId = :userId
              AND WhatId != null
              AND Status = 'Completed'
            LIMIT 5000
        ]) {
            partnerIds.add(taskRecord.WhatId);
        }
        Set<Id> assignedContactIds = ExternalUserAssignmentRepository.getInstance()
            .selectContactIdsByUserId(userId);

        return [
            SELECT Id, Name, PersonEmail, Phone, PersonContactId, OwnerId, Follow_Up_LO__c, Preferred_LO__c,
                   Group__pc, Company__c, BillingCity, LastActivityDate, Biz_Dev_Designation__c
            FROM Account
            WHERE IsPersonAccount = true
              AND Group__pc IN ('Realtor', 'Realtor Prospect', 'Title Agent', 'Insurance Agent')
              AND (
                  OwnerId = :userId
                  OR Follow_Up_LO__c = :userId
                  OR Preferred_LO__c = :userId
                  OR Id IN :partnerIds
                  OR PersonContactId IN :assignedContactIds
              )
            ORDER BY Name ASC
            LIMIT 500
        ];
    }

    public Account selectPortalPartnerDetail(Id accountId, Id userId) {
        if (accountId == null || userId == null) {
            return null;
        }
        List<Account> accounts = [
            SELECT Id, Name, PersonEmail, Phone, OwnerId, Follow_Up_LO__c, Preferred_LO__c,
                   Group__pc, Company__c, BillingCity, BillingState, LastActivityDate, Biz_Dev_Designation__c
            FROM Account
            WHERE Id = :accountId
              AND IsPersonAccount = true
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    public List<Account> searchSharedPartners(String searchTerm, Integer rowLimit) {
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return new List<Account>();
        }
        Integer safeLimit = rowLimit == null || rowLimit <= 0 ? 20 : Math.min(rowLimit, 50);
        String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        return [
            SELECT Id, Name, PersonEmail, Phone, PersonContactId, OwnerId, Follow_Up_LO__c, Group__pc,
                   Company__c, BillingCity, Biz_Dev_Designation__c
            FROM Account
            WHERE IsPersonAccount = true
              AND Group__pc IN ('Realtor', 'Realtor Prospect', 'Title Agent', 'Insurance Agent')
              AND (Name LIKE :term OR Company__c LIKE :term OR PersonEmail LIKE :term)
            ORDER BY Name ASC
            LIMIT :safeLimit
        ];
    }

    public List<Account> selectPartnersForImportMatch(Set<String> emails, Set<String> phones) {
        Set<String> safeEmails = emails == null ? new Set<String>() : emails;
        Set<String> safePhones = phones == null ? new Set<String>() : phones;
        if (safeEmails.isEmpty() && safePhones.isEmpty()) {
            return new List<Account>();
        }
        return new PersonAccountImportSelector().selectPartnersForImportMatch(safeEmails, safePhones);
    }

    public Map<Id, Id> selectPersonContactIds(Set<Id> accountIds) {
        Map<Id, Id> contactByAccountId = new Map<Id, Id>();
        if (accountIds == null || accountIds.isEmpty()) {
            return contactByAccountId;
        }
        for (Account accountRecord : [
            SELECT Id, PersonContactId
            FROM Account
            WHERE Id IN :accountIds
              AND PersonContactId != null
            WITH SYSTEM_MODE
        ]) {
            contactByAccountId.put(accountRecord.Id, accountRecord.PersonContactId);
        }
        return contactByAccountId;
    }
}