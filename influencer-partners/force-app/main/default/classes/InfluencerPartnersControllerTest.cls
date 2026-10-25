@IsTest
private class InfluencerPartnersControllerTest {
    // The custom permission only applies inside runAs once the assignment exists.
    static User me() {
        Id ps = [SELECT Id FROM PermissionSet WHERE Name = 'Influencer_Partners'].Id;
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :ps] == 0) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps);
        }
        return new User(Id = UserInfo.getUserId());
    }

    static InfluencerPartnersController.PartnerInput input(String first, String last, String email) {
        InfluencerPartnersController.PartnerInput i = new InfluencerPartnersController.PartnerInput();
        i.firstName = first;
        i.lastName = last;
        i.email = email;
        i.phone = '5615550' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 1000)).leftPad(3, '0');
        i.channel = 'YouTube';
        i.channelUrl = 'https://youtube.com/@test';
        i.audience = 120000;
        i.loId = UserInfo.getUserId();
        return i;
    }

    @IsTest
    static void pipelineLifecycle() {
        System.runAs(me()) {
            Id id = InfluencerPartnersController.createPartner(input('Maria', 'Gomez', 'maria.gomez.ip.test@example.com'));
            Account a = [SELECT Influencer_Stage__c, Influencer_Partner_Code__c, Type__c FROM Account WHERE Id = :id];
            Assert.areEqual('Target', a.Influencer_Stage__c);
            Assert.areEqual('MARIA-G', a.Influencer_Partner_Code__c);
            Assert.areEqual('Influencer Partner', a.Type__c);
            Id second = InfluencerPartnersController.createPartner(input('Maria', 'Garcia', 'maria.garcia.ip.test@example.com'));
            Assert.areEqual('MARIA-G2', [SELECT Influencer_Partner_Code__c FROM Account WHERE Id = :second].Influencer_Partner_Code__c);

            InfluencerPartnersController.logTouch(id, 'Call', 'Intro call');
            InfluencerPartnersController.logTouch(id, 'Note', 'Niche: first-time buyers');
            InfluencerPartnersController.Home h = InfluencerPartnersController.getHome();
            Assert.areEqual(2, h.partners.size());
            Assert.areEqual('Contacted', [SELECT Influencer_Stage__c FROM Account WHERE Id = :id].Influencer_Stage__c);

            try {
                InfluencerPartnersController.setStage(id, 'Lost', null);
                Assert.fail('Lost needs a reason');
            } catch (AuraHandledException e) {}
            InfluencerPartnersController.setStage(id, 'Lost', 'No response');
            a = [SELECT Influencer_Lost_From_Stage__c, Influencer_Lost_Date__c FROM Account WHERE Id = :id];
            Assert.areEqual('Contacted', a.Influencer_Lost_From_Stage__c);
            Assert.areEqual(Date.today(), a.Influencer_Lost_Date__c);
            InfluencerPartnersController.reopen(id);
            Assert.areEqual('Contacted', [SELECT Influencer_Stage__c FROM Account WHERE Id = :id].Influencer_Stage__c);
            InfluencerPartnersController.setStage(id, 'Active', null);

            InfluencerPartnersController.PartnerInput edit = input('Maria', 'Gomez', 'maria.gomez.ip.test@example.com');
            edit.id = id;
            edit.code = 'mariag-yt';
            edit.monthlyFee = 500;
            edit.agreementDate = Date.today().addMonths(-2);
            InfluencerPartnersController.savePartner(edit);
            Assert.areEqual('MARIAG-YT', [SELECT Influencer_Partner_Code__c FROM Account WHERE Id = :id].Influencer_Partner_Code__c);

            Test.startTest();
            Id leadId = InfluencerPartnersController.createLead(id, 'Bo', 'Rower', '5615550199', null, 'Saw the video');
            Test.stopTest();
            Lead l = [SELECT LeadSource, OwnerId FROM Lead WHERE Id = :leadId];
            Assert.areEqual('Influencer Partners', l.LeadSource);
            Assert.areEqual(UserInfo.getUserId(), l.OwnerId);

            edit.code = 'CHANGED';
            try {
                InfluencerPartnersController.savePartner(edit);
                Assert.fail('code locks after the first lead');
            } catch (AuraHandledException e) {}

            InfluencerPartnersController.Detail d = InfluencerPartnersController.getPartner(id);
            Assert.areEqual(1, d.leads.size());
            Assert.areEqual(1, d.results.leads);
            Assert.areEqual(1500, d.results.cost);
            Assert.isFalse(d.timeline.isEmpty());

            Assert.areEqual(1, InfluencerPartnersController.getLeads().size());
            InfluencerPartnersController.getLoans();
            for (String r : new List<String>{ 'MONTH', 'QUARTER', 'YTD', 'ALL' }) {
                InfluencerPartnersController.Results res = InfluencerPartnersController.getResults(r);
                Assert.areEqual(1, res.total.leads);
            }
        }
    }

    @IsTest
    static void loansCountTowardTheirPartner() {
        System.runAs(me()) {
            Id id = InfluencerPartnersController.createPartner(input('Lena', 'Loans', 'lena.loans.ip.test@example.com'));
            Account a = [SELECT PersonContactId FROM Account WHERE Id = :id];
            insert new Transaction__c(Name = 'IP Test Loan', Lead_Source__c = 'Influencer Partners', Referral_Source__c = a.PersonContactId,
                Status__c = 'Post-Closed', Post_Closed_Date__c = Date.today(), Loan_Amount_1st__c = 300000);
            InfluencerPartnersController.Results res = InfluencerPartnersController.getResults('ALL');
            Assert.areEqual(1, res.total.closed);
            Assert.areEqual(300000, res.total.volume);
            Assert.areEqual(1, InfluencerPartnersController.getLoans().size());
            Assert.areEqual(1, InfluencerPartnersController.getHome().partners[0].closed);
        }
    }

    @IsTest
    static void existingPersonIsLinkedNotDuplicated() {
        Account borrower = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = 'Paula', LastName = 'Past', PersonEmail = 'paula.past.ip.test@example.com', Type__c = 'Borrower Account'
        );
        insert borrower;
        System.runAs(me()) {
            List<InfluencerPartnersController.Duplicate> dupes = InfluencerPartnersController.findDuplicates('paula.past.ip.test@example.com', null);
            Assert.areEqual(1, dupes.size());
            Assert.isFalse(dupes[0].alreadyPartner);
            InfluencerPartnersController.addExisting(borrower.Id, input('Paula', 'Past', null));
            InfluencerPartnersController.setStage(borrower.Id, 'Active', null);
            Account a = [SELECT Influencer_Stage__c, Type__c, Influencer_Partner_Code__c FROM Account WHERE Id = :borrower.Id];
            Assert.areEqual('Active', a.Influencer_Stage__c);
            Assert.areEqual('Borrower Account', a.Type__c);
            Assert.areEqual('PAULA-P', a.Influencer_Partner_Code__c);
        }
    }

    @IsTest
    static void costAndRangeMath() {
        Account a = new Account(Influencer_Monthly_Fee__c = 100, Influencer_Agreement_Signed__c = Date.newInstance(2026, 1, 20),
            Influencer_Stage__c = 'Lost', Influencer_Lost_Date__c = Date.newInstance(2026, 3, 2));
        Assert.areEqual(300, InfluencerPartnersController.cost(a, null));
        Assert.areEqual(200, InfluencerPartnersController.cost(a, Date.newInstance(2026, 2, 1)));
        Assert.areEqual(0, InfluencerPartnersController.cost(a, Date.newInstance(2026, 4, 1)));
        Assert.isNull(InfluencerPartnersController.rangeStart('ALL'));
        Assert.areEqual(Date.today().toStartOfMonth(), InfluencerPartnersController.rangeStart('MONTH'));
        Assert.areEqual(1, InfluencerPartnersController.rangeStart('QUARTER').day());
        Assert.areEqual(Date.newInstance(Date.today().year(), 1, 1), InfluencerPartnersController.rangeStart('YTD'));
    }
}
