@IsTest
private class LeadInfluencerAttributionTest {
    @TestSetup
    static void setup() {
        insert new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = 'Maria', LastName = 'Influence', PersonEmail = 'maria.influence.test@example.com',
            Type__c = 'Influencer Partner', Influencer_Stage__c = 'Active',
            Influencer_Partner_Code__c = 'MARIA-TEST', Influencer_Assigned_LO__c = UserInfo.getUserId()
        );
    }

    static Lead formLead(String code, String spanish) {
        return new Lead(FirstName = 'Bo', LastName = 'Rower', Company = 'Bo Rower', Phone = '5615550101',
            Influencer_Partner_Code__c = code, Spanish_Speaker_Intake_Form__c = spanish);
    }

    @IsTest
    static void stampsBothAttributionsAndRoutesToAssignedLo() {
        Account p = [SELECT PersonContactId FROM Account WHERE Influencer_Partner_Code__c = 'MARIA-TEST'];
        Test.startTest();
        Lead l = formLead(' maria-test ', 'No');
        insert l;
        Test.stopTest();
        l = [SELECT LeadSource, Referral_Source__c, Realtor_Buying_Agent__c, OwnerId FROM Lead WHERE Id = :l.Id];
        Assert.areEqual('Influencer Partners', l.LeadSource);
        Assert.areEqual(p.PersonContactId, l.Referral_Source__c);
        Assert.isNull(l.Realtor_Buying_Agent__c);
        Assert.areEqual(UserInfo.getUserId(), l.OwnerId);
    }

    @IsTest
    static void alertGoesToLoAndProgramManager() {
        String manager = [SELECT Email FROM User WHERE Username = :LeadInfluencerAttribution.PROGRAM_MANAGER_USERNAME].Email;
        Test.startTest();
        insert formLead('MARIA-TEST', 'No');
        Set<String> to = new Set<String>(LeadInfluencerAttribution.sentForTest[0].getToAddresses());
        Test.stopTest();
        Assert.isTrue(to.contains(UserInfo.getUserEmail()), 'assigned LO gets the alert');
        Assert.isTrue(to.contains(manager), 'program manager gets the alert');
    }

    @IsTest
    static void queueLeadStillAlertsProgramManager() {
        update new Account(Id = [SELECT Id FROM Account WHERE Influencer_Partner_Code__c = 'MARIA-TEST'].Id, Influencer_Assigned_LO__c = null);
        String manager = [SELECT Email FROM User WHERE Username = :LeadInfluencerAttribution.PROGRAM_MANAGER_USERNAME].Email;
        Test.startTest();
        insert formLead('MARIA-TEST', 'No');
        Assert.areEqual(new List<String>{ manager }, LeadInfluencerAttribution.sentForTest[0].getToAddresses());
        Test.stopTest();
    }

    @IsTest
    static void spanishSpeakerRuleWins() {
        Lead l = formLead('MARIA-TEST', 'Yes');
        Test.startTest();
        insert l;
        Test.stopTest();
        Assert.areEqual(LeadInfluencerAttribution.SPANISH_OWNER_ID, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId);
    }

    @IsTest
    static void unknownCodeIsLeftAlone() {
        Lead l = formLead('NOBODY-X', 'No');
        l.LeadSource = 'Website';
        insert l;
        l = [SELECT LeadSource, Referral_Source__c FROM Lead WHERE Id = :l.Id];
        Assert.areEqual('Website', l.LeadSource);
        Assert.isNull(l.Referral_Source__c);
    }

    @IsTest
    static void intakeFormLooksUpPartner() {
        Map<String, Object> partner = IntakeFormController.getInfluencerPartner('MARIA-TEST');
        Assert.areEqual('Maria Influence', partner.get('partnerName'));
        Assert.areEqual(1, ((List<User>) partner.get('loanOfficers')).size());
        Assert.isNull(IntakeFormController.getInfluencerPartner('NOBODY-X'));
        Assert.isNull(IntakeFormController.getInfluencerPartner(' '));
    }
}
