public with sharing class AccountShareRepository {
    public List<AccountShare> selectManualShares(Set<Id> accountIds, Id userId) {
        if (accountIds == null || accountIds.isEmpty() || userId == null) {
            return new List<AccountShare>();
        }
        return [
            SELECT Id, AccountId, UserOrGroupId
            FROM AccountShare
            WHERE AccountId IN :accountIds
              AND UserOrGroupId = :userId
              AND RowCause = 'Manual'
            WITH SYSTEM_MODE
        ];
    }
}