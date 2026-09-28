@isTest
public class ExternalLoPortalTestHelper {

    public static User currentUser() {
        return [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId()];
    }

    /**
     * Isolated portal subject for onboarding tests. Do not read/write the
     * running admin — their User row is shared across the org.
     */
    public static User createOnboardingSubject() {
        User subject = createCommunityOrStandardImporter();
        grantPortalAccess(subject.Id);
        return subject;
    }

    public static User createStandardUser(String alias) {
        Profile profileRecord = [
            SELECT Id
            FROM Profile
            WHERE Name IN ('Standard User', 'Minimum Access - Salesforce')
            ORDER BY Name DESC
            LIMIT 1
        ];
        User userRecord = buildUser(alias, profileRecord.Id);
        insert userRecord;
        return userRecord;
    }

    public static User createCommunityOrStandardImporter() {
        List<Profile> communityProfiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Customer Community Plus User'
            LIMIT 1
        ];
        if (!communityProfiles.isEmpty()) {
            try {
                return createCommunityUser(communityProfiles[0].Id);
            } catch (DmlException error) {
                // License, role, or person-account-only orgs still need a sharing test.
            }
        }
        return createStandardUser('cimp');
    }

    public static User createCommunityUser(Id profileId) {
        User thisUser = currentUser();
        Contact portalContact;
        System.runAs(thisUser) {
            Account household = new Account(Name = 'Ext LO Import Test ' + String.valueOf(Crypto.getRandomInteger()));
            insert household;
            portalContact = new Contact(
                FirstName = 'Portal',
                LastName = 'Importer',
                AccountId = household.Id,
                Email = 'portal.importer.' + String.valueOf(Crypto.getRandomInteger()) + '@example.com'
            );
            insert portalContact;
        }
        User portalUser = buildUser('cimp', profileId);
        portalUser.ContactId = portalContact.Id;
        insert portalUser;
        return portalUser;
    }

    private static User buildUser(String alias, Id profileId) {
        String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            FirstName = 'Ext',
            LastName = alias,
            Alias = alias.left(8),
            Email = alias + '.' + unique + '@example.com',
            Username = alias + '.' + unique + '@example.com',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Headshot_URL__c = 'image.jpg',
            NMLS__c = '1866656'
        );
    }

    public static void grantPortalAccess(Id userId) {
        if (userId == null) {
            return;
        }
        Set<String> permissionSetNames = new Set<String>{
            'External_LO_Perfect_Day_Access',
            'Lead_Access',
            'All_Leads',
            'Account_Follow_Up_Access'
        };
        Map<Id, PermissionSet> permissionSets = new Map<Id, PermissionSet>([
            SELECT Id FROM PermissionSet WHERE Name IN :permissionSetNames
        ]);
        if (permissionSets.isEmpty()) {
            return;
        }

        Set<Id> alreadyAssigned = new Set<Id>();
        for (PermissionSetAssignment assignment : [
            SELECT PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
              AND PermissionSetId IN :permissionSets.keySet()
        ]) {
            alreadyAssigned.add(assignment.PermissionSetId);
        }

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (Id permissionSetId : permissionSets.keySet()) {
            if (!alreadyAssigned.contains(permissionSetId)) {
                assignments.add(new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetId = permissionSetId
                ));
            }
        }
        if (!assignments.isEmpty()) {
            insert assignments;
        }
    }

    public static Id requirePersonAccountRecordTypeId() {
        Id recordTypeId = new PersonAccountRepository().selectPersonAccountRecordTypeId();
        System.assertNotEquals(
            null,
            recordTypeId,
            'Person Account record type is required for partner import tests.'
        );
        return recordTypeId;
    }

    public static void insertAfterSetupDml(SObject record) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert record;
        }
    }
}