@IsTest
public class IntakeFormControllerTests {

    @IsTest static void test() {
        RecordType personAccountRecordType = [SELECT Id FROM RecordType WHERE Name = 'Person Account'];
        Account acc = new Account();
        acc.LastName = 'Test';
        acc.PersonEmail = 'test@gmail.com';
        acc.RecordTypeId = personAccountRecordType.Id;
        insert acc;
        
        Test.startTest();
        IntakeFormController.getLoanOfficers('test@gmail.com');
        Test.stopTest();
    }

    @IsTest static void assignedLoanOfficerLeadsTheList() {
        User assignedOfficer = buildUser('Rhett', 'Delaney');
        User otherOfficer = buildUser('Aaron', 'Alphabetical');
        insert new List<User>{ assignedOfficer, otherOfficer };

        // The assignment names the officer who sorts second, so promotion is observable.
        Account realtor = buildRealtor('promote@example.com', 'Rhett Delaney');
        linkOfficers(realtor.Id, new List<User>{ assignedOfficer, otherOfficer }, true);

        Test.startTest();
        List<User> officers = IntakeFormController.getLoanOfficers('promote@example.com');
        Test.stopTest();

        System.assertEquals(2, officers.size());
        System.assertEquals(assignedOfficer.Id, officers[0].Id, 'The assigned LO must be the first tile.');
        System.assertEquals(otherOfficer.Id, officers[1].Id, 'Remaining officers keep alphabetical order.');
    }

    // "Zach Fritz" is stored on the Account while the User record reads "Zachary Fritz".
    @IsTest static void assignedLoanOfficerMatchesShortenedFirstName() {
        User zachary = buildUser('Zachary', 'Fritz');
        User adam = buildUser('Adam', 'Anderson');
        insert new List<User>{ zachary, adam };

        Account realtor = buildRealtor('nickname@example.com', 'Zach Fritz');
        linkOfficers(realtor.Id, new List<User>{ zachary, adam }, true);

        Test.startTest();
        List<User> officers = IntakeFormController.getLoanOfficers('nickname@example.com');
        Test.stopTest();

        System.assertEquals(zachary.Id, officers[0].Id, 'A shortened first name must still match the assigned LO.');
    }

    @IsTest static void unmatchedAssignmentLeavesOrderAlone() {
        User first = buildUser('Aaron', 'Aaronson');
        User second = buildUser('Zoe', 'Zimmerman');
        insert new List<User>{ first, second };

        // A valid assignment whose officer is not selectable here, so alphabetical order must survive.
        Account realtor = buildRealtor('unmatched@example.com', 'Zach Fritz');
        linkOfficers(realtor.Id, new List<User>{ first, second }, true);

        Test.startTest();
        List<User> officers = IntakeFormController.getLoanOfficers('unmatched@example.com');
        Test.stopTest();

        System.assertEquals(2, officers.size());
        System.assertEquals(first.Id, officers[0].Id, 'An unmatched assignment must not reorder the list.');
    }

    @IsTest static void inactiveLinksAndUnknownRealtorsReturnNothing() {
        User officer = buildUser('Inactive', 'Linkerson');
        insert officer;
        Account realtor = buildRealtor('inactive@example.com', 'Joe Olmsted');
        linkOfficers(realtor.Id, new List<User>{ officer }, false);

        Test.startTest();
        List<User> suppressed = IntakeFormController.getLoanOfficers('inactive@example.com');
        List<User> unknown = IntakeFormController.getLoanOfficers('nobody@example.com');
        Test.stopTest();

        System.assertEquals(0, suppressed.size(), 'Inactive links must not be selectable.');
        System.assertEquals(0, unknown.size(), 'An unknown realtor email returns no officers.');
    }

    // The designation rule is keyed to a real username, so this queries the live user on purpose.
    // If Zach Fritz is ever deactivated this test fails, which is the intended signal that the
    // hardcoded BIZ_DEV_DESIGNATION_DEFAULT_LO entry has gone stale.
    @IsTest static void bondarevskyDesignationReturnsOnlyTheDesignatedOfficer() {
        List<User> zachFritz = [
            SELECT Id FROM User WHERE Username = 'zfritz@reachhomeloans.com' AND IsActive = true LIMIT 1
        ];
        System.assertEquals(1, zachFritz.size(), 'The designated LO for Biz Dev - Bondarevsky must exist and be active.');

        // Card two unrelated officers, so a passing result proves the cards were bypassed rather
        // than merely reordered.
        User firstCarded = buildUser('Aaron', 'Carded');
        User secondCarded = buildUser('Betty', 'Carded');
        insert new List<User>{ firstCarded, secondCarded };

        Account realtor = buildRealtor('bondarevsky@example.com', null);
        realtor.Biz_Dev_Designation__c = 'Biz Dev - Bondarevsky';
        update realtor;
        linkOfficers(realtor.Id, new List<User>{ firstCarded, secondCarded }, true);

        Test.startTest();
        List<User> officers = IntakeFormController.getLoanOfficers('bondarevsky@example.com');
        Test.stopTest();

        System.assertEquals(1, officers.size(), 'A Bondarevsky realtor gets exactly one tile.');
        System.assertEquals(zachFritz[0].Id, officers[0].Id, 'That one tile must be the designated LO.');
    }

    @IsTest static void unmappedDesignationKeepsTheNormalCardList() {
        User firstCarded = buildUser('Aaron', 'Normal');
        User secondCarded = buildUser('Betty', 'Normal');
        insert new List<User>{ firstCarded, secondCarded };

        Account realtor = buildRealtor('unmapped@example.com', null);
        realtor.Biz_Dev_Designation__c = 'Biz Dev - Reach';
        update realtor;
        linkOfficers(realtor.Id, new List<User>{ firstCarded, secondCarded }, true);

        Test.startTest();
        List<User> officers = IntakeFormController.getLoanOfficers('unmapped@example.com');
        Test.stopTest();

        System.assertEquals(2, officers.size(), 'A designation with no rule must fall through to the card list.');
    }

    private static Account buildRealtor(String email, String assignedLoanOfficerName) {
        RecordType personAccountRecordType = [SELECT Id FROM RecordType WHERE Name = 'Person Account'];
        Account realtor = new Account(
            LastName = 'Realtor',
            PersonEmail = email,
            RecordTypeId = personAccountRecordType.Id,
            Nickley_Realtor_LO__c = assignedLoanOfficerName
        );
        insert realtor;
        return realtor;
    }

    private static void linkOfficers(Id accountId, List<User> officers, Boolean active) {
        List<User_To_Account__c> links = new List<User_To_Account__c>();
        for (User officer : officers) {
            links.add(new User_To_Account__c(Account__c = accountId, User__c = officer.Id, Active__c = active));
        }
        insert links;
    }

    private static User buildUser(String firstName, String lastName) {
        Profile profileRecord = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String uniqueToken = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = (firstName.left(1) + lastName).left(8),
            Email = uniqueToken + '@example.com',
            Username = uniqueToken + '@example.com',
            CommunityNickname = ('u' + uniqueToken).left(40),
            ProfileId = profileRecord.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}