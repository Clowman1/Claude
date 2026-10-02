public with sharing class UserRepository {
    private static UserRepository self;

    public static UserRepository getInstance() {
        if (self == null) {
            self = new UserRepository();
        }
        return self;
    }

    public User selectPortalProfile(Id userId) {
        if (userId == null) {
            return null;
        }
        try {
            return queryPortalProfile(userId, true);
        } catch (QueryException portalFlsError) {
            // Internal Home/App pages reuse Perfect Day. Portal field FLS lives on
            // External_LO_Perfect_Day_Access. Retry without those fields, then Id/Name.
            try {
                return markInternalSetupComplete(queryPortalProfile(userId, false));
            } catch (QueryException goalFlsError) {
                return markInternalSetupComplete(queryCoreProfile(userId));
            }
        }
    }

    @TestVisible
    private User queryPortalProfile(Id userId, Boolean includePortalFields) {
        List<User> users;
        if (includePortalFields) {
            users = [
                SELECT Id, Name, Business_Focus__c, External_LO_Onboarding_Complete__c,
                       ExtLO_Workdays_Per_Week__c, ExtLO_Monthly_Unit_Goal__c, ExtLO_Monthly_Volume_Goal__c,
                       ExtLO_Target_Realtor_Count__c,
                       Calls_Daily_Goal__c, Texts_Daily_Goal__c, Emails_Daily_Goal__c,
                       Meetings_Daily_Goal__c, Open_House_Daily_Goal__c
                FROM User
                WHERE Id = :userId
                WITH USER_MODE
                LIMIT 1
            ];
        } else {
            users = [
                SELECT Id, Name,
                       Calls_Daily_Goal__c, Texts_Daily_Goal__c, Emails_Daily_Goal__c,
                       Meetings_Daily_Goal__c, Open_House_Daily_Goal__c
                FROM User
                WHERE Id = :userId
                WITH USER_MODE
                LIMIT 1
            ];
        }
        return users.isEmpty() ? null : users[0];
    }

    private User queryCoreProfile(Id userId) {
        List<User> users = [
            SELECT Id, Name
            FROM User
            WHERE Id = :userId
            WITH USER_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    private User markInternalSetupComplete(User userRecord) {
        if (userRecord != null && UserInfo.getUserType() == 'Standard') {
            userRecord.External_LO_Onboarding_Complete__c = true;
        }
        return userRecord;
    }
}