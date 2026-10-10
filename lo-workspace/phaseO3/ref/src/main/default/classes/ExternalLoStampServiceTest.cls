@IsTest
private class ExternalLoStampServiceTest {

    static User makeUser(String alias, String profileName, String roleDeveloperName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        UserRole r = [SELECT Id FROM UserRole WHERE DeveloperName = :roleDeveloperName LIMIT 1];
        String unique = alias + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            FirstName = 'Test', LastName = alias, Alias = alias.left(8),
            Email = unique + '@example.com', Username = unique + '@example.com.lostamp',
            ProfileId = p.Id, UserRoleId = r.Id,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }

    @TestSetup
    static void setup() {
        insert new List<User>{
            makeUser('extlo1', 'External Loan Officer Profile', ExternalLoStampService.ROLE_DEVELOPER_NAME),
            makeUser('extlo2', 'External Loan Officer Profile', ExternalLoStampService.ROLE_DEVELOPER_NAME),
            makeUser('intlo1', 'Loan Officer Profile', 'Loan_Officer')
        };
    }

    static User userByAlias(String alias) {
        return [SELECT Id FROM User WHERE LastName = :alias AND Username LIKE '%lostamp' LIMIT 1];
    }

    static Lead leadOwnedBy(Id ownerId) {
        Lead l = new Lead(LastName = 'Stamp Test', Company = 'Stamp Test', OwnerId = ownerId);
        insert l;
        return l;
    }

    @IsTest
    static void childrenOfAnOutsideLosLeadAreStampedWithThem() {
        User ext = userByAlias('extlo1');
        Lead l = leadOwnedBy(ext.Id);

        Test.startTest();
        Call_Insight__c insight = new Call_Insight__c(Lead__c = l.Id);
        Enhanced_Note__c note = new Enhanced_Note__c(Lead__c = l.Id);
        Lead_Document_Request__c request = new Lead_Document_Request__c(Lead__c = l.Id);
        Borrower__c borrower = new Borrower__c(Lead__c = l.Id);
        insert new List<SObject>{ insight, note, request, borrower };
        Test.stopTest();

        System.assertEquals(ext.Id, [SELECT External_LO__c FROM Call_Insight__c WHERE Id = :insight.Id].External_LO__c);
        System.assertEquals(ext.Id, [SELECT External_LO__c FROM Enhanced_Note__c WHERE Id = :note.Id].External_LO__c);
        System.assertEquals(ext.Id, [SELECT External_LO__c FROM Lead_Document_Request__c WHERE Id = :request.Id].External_LO__c);
        System.assertEquals(ext.Id, [SELECT External_LO__c FROM Borrower__c WHERE Id = :borrower.Id].External_LO__c);
    }

    @IsTest
    static void internalOnlyRecordsStayBlank() {
        Lead l = leadOwnedBy(userByAlias('intlo1').Id);

        Test.startTest();
        Call_Insight__c insight = new Call_Insight__c(Lead__c = l.Id);
        insert insight;
        Test.stopTest();

        System.assertEquals(null, [SELECT External_LO__c FROM Call_Insight__c WHERE Id = :insight.Id].External_LO__c,
            'A lead with no outside LO must stay hidden from outside LOs');
    }

    @IsTest
    static void ownerChangeMovesTheStampToTheNewOutsideLo() {
        // The Nurturing takeover path: another LO takes the lead, and the lead's records follow it.
        User ext1 = userByAlias('extlo1');
        User ext2 = userByAlias('extlo2');
        Lead l = leadOwnedBy(ext1.Id);
        Call_Insight__c insight = new Call_Insight__c(Lead__c = l.Id);
        insert insight;

        Test.startTest();
        l.OwnerId = ext2.Id;
        update l;
        Test.stopTest();

        System.assertEquals(ext2.Id, [SELECT External_LO__c FROM Call_Insight__c WHERE Id = :insight.Id].External_LO__c);
    }

    @IsTest
    static void handingALeadToAnInternalLoClearsTheStamp() {
        Lead l = leadOwnedBy(userByAlias('extlo1').Id);
        Enhanced_Note__c note = new Enhanced_Note__c(Lead__c = l.Id);
        insert note;

        Test.startTest();
        l.OwnerId = userByAlias('intlo1').Id;
        update l;
        Test.stopTest();

        System.assertEquals(null, [SELECT External_LO__c FROM Enhanced_Note__c WHERE Id = :note.Id].External_LO__c);
    }

    @IsTest
    static void theLoanOutranksTheLeadAndCoversLoanOnlyObjects() {
        User ext1 = userByAlias('extlo1');
        User ext2 = userByAlias('extlo2');
        Lead l = leadOwnedBy(ext2.Id);
        Transaction__c loan = new Transaction__c(Name = 'Stamp Loan', Status__c = TestDataFactory.getOpportunityStageName(), Loan_Officer__c = ext1.Id);
        insert loan;

        Test.startTest();
        Call_Insight__c insight = new Call_Insight__c(Lead__c = l.Id, Transaction__c = loan.Id);
        Checklist__c checklist = new Checklist__c(Transaction__c = loan.Id);
        Appraisal_Order__c appraisal = new Appraisal_Order__c(Loan__c = loan.Id);
        insert new List<SObject>{ insight, checklist, appraisal };
        Test.stopTest();

        System.assertEquals(ext1.Id, [SELECT External_LO__c FROM Call_Insight__c WHERE Id = :insight.Id].External_LO__c,
            'The loan is the more specific parent');
        System.assertEquals(ext1.Id, [SELECT External_LO__c FROM Checklist__c WHERE Id = :checklist.Id].External_LO__c);
        System.assertEquals(ext1.Id, [SELECT External_LO__c FROM Appraisal_Order__c WHERE Id = :appraisal.Id].External_LO__c);
    }

    @IsTest
    static void zoomRecordingsFollowTheirMeeting() {
        User ext1 = userByAlias('extlo1');
        User ext2 = userByAlias('extlo2');
        Lead l = leadOwnedBy(ext1.Id);
        Zoom_Meeting__c meeting = new Zoom_Meeting__c(Lead__c = l.Id);
        insert meeting;
        Zoom_Recording__c recording = new Zoom_Recording__c(Zoom_Meeting__c = meeting.Id);
        insert recording;
        System.assertEquals(ext1.Id, [SELECT External_LO__c FROM Zoom_Recording__c WHERE Id = :recording.Id].External_LO__c);

        Test.startTest();
        l.OwnerId = ext2.Id;
        update l;
        Test.stopTest();

        System.assertEquals(ext2.Id, [SELECT External_LO__c FROM Zoom_Meeting__c WHERE Id = :meeting.Id].External_LO__c);
        System.assertEquals(ext2.Id, [SELECT External_LO__c FROM Zoom_Recording__c WHERE Id = :recording.Id].External_LO__c);
    }

    @IsTest
    static void accountOwnedByAnOutsideLoStampsItsRecords() {
        User ext = userByAlias('extlo1');
        Account a = new Account(Name = 'Stamp Partner Co', OwnerId = ext.Id);
        insert a;

        Test.startTest();
        Enhanced_Note__c note = new Enhanced_Note__c(Account__c = a.Id);
        insert note;
        Test.stopTest();

        System.assertEquals(ext.Id, [SELECT External_LO__c FROM Enhanced_Note__c WHERE Id = :note.Id].External_LO__c);
    }

    @IsTest
    static void accountOwnerChangeMovesTheStamp() {
        User ext1 = userByAlias('extlo1');
        User ext2 = userByAlias('extlo2');
        Account a = new Account(Name = 'Stamp Partner Co', OwnerId = ext1.Id);
        insert a;
        Enhanced_Note__c note = new Enhanced_Note__c(Account__c = a.Id);
        insert note;

        Test.startTest();
        a.OwnerId = ext2.Id;
        update a;
        Test.stopTest();

        System.assertEquals(ext2.Id, [SELECT External_LO__c FROM Enhanced_Note__c WHERE Id = :note.Id].External_LO__c);
    }

    @IsTest
    static void nothingHappensWhenNoOutsideLoIsInvolved() {
        Lead l = leadOwnedBy(userByAlias('intlo1').Id);
        Integer jobsBefore = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'];

        Test.startTest();
        l.OwnerId = UserInfo.getUserId();
        update l;
        Test.stopTest();

        System.assertEquals(jobsBefore, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'],
            'Internal-only owner changes must not enqueue a restamp');
    }
}