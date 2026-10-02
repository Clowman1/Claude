@IsTest
private class LeadLoanPartnerShareTriggerHandlerTest {
    private static final String STANDARD_USER_PROFILE = 'Standard User';

    @IsTest
    static void testCreatesAndReplacesLeadLoanPartnerEditShares() {
        User ownerUser = createUser('ownerlp');
        User firstLoanPartner = createUser('lpfirst');
        User secondLoanPartner = createUser('lpsecond');
        insert new List<User>{ ownerUser, firstLoanPartner, secondLoanPartner };

        Lead leadRecord = new Lead(
            LastName = 'Lead Share Test',
            Company = 'Reach',
            OwnerId = ownerUser.Id
        );
        insert leadRecord;

        leadRecord.Loan_Partner__c = firstLoanPartner.Id;
        update leadRecord;

        List<LeadShare> firstShares = [
            SELECT Id, UserOrGroupId, LeadAccessLevel, RowCause
            FROM LeadShare
            WHERE LeadId = :leadRecord.Id
            AND UserOrGroupId = :firstLoanPartner.Id
            AND RowCause = 'Manual'
        ];
        System.assertEquals(1, firstShares.size(), 'Lead should be shared to the assigned Loan Partner.');
        System.assertEquals('Edit', firstShares[0].LeadAccessLevel, 'Loan Partner share should allow Edit access.');

        leadRecord.Loan_Partner__c = secondLoanPartner.Id;
        update leadRecord;

        Integer oldShareCount = [
            SELECT COUNT()
            FROM LeadShare
            WHERE LeadId = :leadRecord.Id
            AND UserOrGroupId = :firstLoanPartner.Id
            AND RowCause = 'Manual'
        ];
        Integer newShareCount = [
            SELECT COUNT()
            FROM LeadShare
            WHERE LeadId = :leadRecord.Id
            AND UserOrGroupId = :secondLoanPartner.Id
            AND RowCause = 'Manual'
            AND LeadAccessLevel = 'Edit'
        ];
        System.assertEquals(0, oldShareCount, 'Old Loan Partner share should be removed when the field changes.');
        System.assertEquals(1, newShareCount, 'New Loan Partner should receive Edit access.');
    }

    private static Integer editShareCount(Id leadId, Id userId) {
        return [
            SELECT COUNT()
            FROM LeadShare
            WHERE LeadId = :leadId
            AND UserOrGroupId = :userId
            AND RowCause = 'Manual'
            AND LeadAccessLevel = 'Edit'
        ];
    }

    @IsTest
    static void otherLeadTeamMemberGetsTheSameEditShareAsTheLoanPartner() {
        User ownerUser = createUser('ownerot');
        User loanPartner = createUser('otlp');
        User otherMember = createUser('otother');
        insert new List<User>{ ownerUser, loanPartner, otherMember };

        Lead leadRecord = new Lead(LastName = 'Other Share Test', Company = 'Reach', OwnerId = ownerUser.Id);
        insert leadRecord;

        Test.startTest();
        leadRecord.Loan_Partner__c = loanPartner.Id;
        leadRecord.Other_Lead_Team_Member__c = otherMember.Id;
        update leadRecord;
        Test.stopTest();

        // Both team members must be shared on the SAME lead -- syncLeadShares keys by Lead Id,
        // so this is what proves the two passes do not overwrite one another.
        System.assertEquals(
            1, editShareCount(leadRecord.Id, otherMember.Id),
            'Other Lead Team Member should receive a Manual/Edit share.'
        );
        System.assertEquals(
            1, editShareCount(leadRecord.Id, loanPartner.Id),
            'Loan Partner share must survive alongside the Other share.'
        );
    }

    @IsTest
    static void replacingOtherLeadTeamMemberMovesTheShare() {
        User ownerUser = createUser('ownerrp');
        User firstOther = createUser('rpfirst');
        User secondOther = createUser('rpsecond');
        insert new List<User>{ ownerUser, firstOther, secondOther };

        Lead leadRecord = new Lead(LastName = 'Other Swap Test', Company = 'Reach', OwnerId = ownerUser.Id);
        insert leadRecord;

        leadRecord.Other_Lead_Team_Member__c = firstOther.Id;
        update leadRecord;
        System.assertEquals(1, editShareCount(leadRecord.Id, firstOther.Id), 'First Other should have access.');

        Test.startTest();
        leadRecord.Other_Lead_Team_Member__c = secondOther.Id;
        update leadRecord;
        Test.stopTest();

        System.assertEquals(
            0, editShareCount(leadRecord.Id, firstOther.Id),
            'Access should be revoked when the person is removed from the field.'
        );
        System.assertEquals(
            1, editShareCount(leadRecord.Id, secondOther.Id),
            'The replacement should receive access.'
        );
    }

    @IsTest
    static void clearingOtherLeadTeamMemberRevokesAccess() {
        User ownerUser = createUser('ownercl');
        User otherMember = createUser('clother');
        insert new List<User>{ ownerUser, otherMember };

        Lead leadRecord = new Lead(LastName = 'Other Clear Test', Company = 'Reach', OwnerId = ownerUser.Id);
        insert leadRecord;
        leadRecord.Other_Lead_Team_Member__c = otherMember.Id;
        update leadRecord;
        System.assertEquals(1, editShareCount(leadRecord.Id, otherMember.Id), 'Access granted first.');

        Test.startTest();
        leadRecord.Other_Lead_Team_Member__c = null;
        update leadRecord;
        Test.stopTest();

        System.assertEquals(
            0, editShareCount(leadRecord.Id, otherMember.Id),
            'Clearing the field should remove the share.'
        );
    }

    @IsTest
    static void otherShareSurvivesAnOwnerChange() {
        User ownerUser = createUser('ownerA');
        User nextOwner = createUser('ownerB');
        User otherMember = createUser('ocother');
        insert new List<User>{ ownerUser, nextOwner, otherMember };

        Lead leadRecord = new Lead(LastName = 'Other Owner Test', Company = 'Reach', OwnerId = ownerUser.Id);
        insert leadRecord;
        leadRecord.Other_Lead_Team_Member__c = otherMember.Id;
        update leadRecord;

        Test.startTest();
        // Salesforce deletes Manual shares on owner change; the handler must put this one back.
        leadRecord.OwnerId = nextOwner.Id;
        update leadRecord;
        Test.stopTest();

        System.assertEquals(
            1, editShareCount(leadRecord.Id, otherMember.Id),
            'Other Lead Team Member should keep access after the lead changes owner.'
        );
    }

    @IsTest
    static void ownerIsNotSharedWithThemselves() {
        User ownerUser = createUser('ownerslf');
        insert ownerUser;

        Lead leadRecord = new Lead(LastName = 'Owner Self Test', Company = 'Reach', OwnerId = ownerUser.Id);
        insert leadRecord;

        Test.startTest();
        leadRecord.Other_Lead_Team_Member__c = ownerUser.Id;
        update leadRecord;
        Test.stopTest();

        System.assertEquals(
            0, editShareCount(leadRecord.Id, ownerUser.Id),
            'The owner already has full access; sharing a record with its own owner is rejected.'
        );
    }

    private static User createUser(String key) {
        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE Name = :STANDARD_USER_PROFILE
            LIMIT 1
        ];

        String uniqueKey = key + String.valueOf(DateTime.now().getTime());
        return new User(
            Alias = key.substring(0, Math.min(8, key.length())),
            Email = uniqueKey + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = key,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/New_York',
            UserName = uniqueKey + '@example.com'
        );
    }
}