@IsTest
private class LeadBdAttributionTest {
    static final String CARLETON = 'Biz Dev - Carleton';

    static User rep() {
        User me = [SELECT ProfileId, TimeZoneSidKey, LocaleSidKey, EmailEncodingKey, LanguageLocaleKey FROM User WHERE Id = :UserInfo.getUserId()];
        User u = new User(
            FirstName = 'Bd', LastName = 'Attrib', Alias = 'bdattr', Email = 'bdattr@example.com',
            Username = 'bdattr.' + Datetime.now().getTime() + '@reach-bd-test.com', ProfileId = me.ProfileId,
            TimeZoneSidKey = me.TimeZoneSidKey, LocaleSidKey = me.LocaleSidKey, EmailEncodingKey = me.EmailEncodingKey,
            LanguageLocaleKey = me.LanguageLocaleKey, BD_Designation__c = CARLETON
        );
        insert u;
        return u;
    }

    static Account partner(Id repId, String last, String designation) {
        Account a = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = 'Partner', LastName = last, BD_Rep__c = repId, Biz_Dev_Designation__c = designation
        );
        insert a;
        return [SELECT Id, PersonContactId FROM Account WHERE Id = :a.Id];
    }

    static Lead newLead(String last) {
        return new Lead(FirstName = 'Bo', LastName = last, Company = 'Bo ' + last, Biz_Dev__c = 'Biz Dev - Reach');
    }

    @IsTest
    static void referralSourceAndBuyingAgentStampTheRepDesignation() {
        User r = rep();
        Account mine = partner(r.Id, 'Mine', null);
        Account joes = partner(r.Id, 'Joes', 'Biz Dev - Olmsted');
        LeadBdAttribution.adminOverrideForTest = false;

        Lead viaReferral = newLead('Ref');
        viaReferral.Referral_Source__c = mine.PersonContactId;
        Lead viaAgent = newLead('Agent');
        viaAgent.Realtor_Buying_Agent__c = mine.Id;
        Lead joesRealtor = newLead('Joe');
        joesRealtor.Realtor_Buying_Agent__c = joes.Id;
        Lead unrelated = newLead('None');
        insert new List<Lead>{ viaReferral, viaAgent, joesRealtor, unrelated };

        Map<Id, Lead> got = new Map<Id, Lead>([SELECT Biz_Dev__c FROM Lead WHERE Id IN :new List<Id>{ viaReferral.Id, viaAgent.Id, joesRealtor.Id, unrelated.Id }]);
        System.assertEquals(CARLETON, got.get(viaReferral.Id).Biz_Dev__c);
        System.assertEquals(CARLETON, got.get(viaAgent.Id).Biz_Dev__c);
        System.assertNotEquals(CARLETON, got.get(joesRealtor.Id).Biz_Dev__c, 'an existing designation wins');
        System.assertNotEquals(CARLETON, got.get(unrelated.Id).Biz_Dev__c);

        // Attaching the partner to an existing lead later stamps it too.
        unrelated.Referral_Source__c = mine.PersonContactId;
        update unrelated;
        System.assertEquals(CARLETON, [SELECT Biz_Dev__c FROM Lead WHERE Id = :unrelated.Id].Biz_Dev__c);

        // A non-admin (or automation) changing it back is corrected on save.
        viaReferral.Biz_Dev__c = 'Biz Dev - Reach';
        update viaReferral;
        System.assertEquals(CARLETON, [SELECT Biz_Dev__c FROM Lead WHERE Id = :viaReferral.Id].Biz_Dev__c);
    }

    @IsTest
    static void humanAdminChangeSticks() {
        User r = rep();
        Account mine = partner(r.Id, 'Adm', null);
        Lead l = newLead('Admin');
        l.Referral_Source__c = mine.PersonContactId;
        insert l;

        LeadBdAttribution.adminOverrideForTest = true;
        l.Biz_Dev__c = 'Biz Dev - Olmsted';
        update l;
        Lead after = [SELECT Biz_Dev__c, BD_Attribution_Override__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Biz Dev - Olmsted', after.Biz_Dev__c);
        System.assertEquals(true, after.BD_Attribution_Override__c);

        // Later non-admin saves leave the admin's choice alone.
        LeadBdAttribution.adminOverrideForTest = false;
        update new Lead(Id = l.Id, Description = 'touched');
        System.assertEquals('Biz Dev - Olmsted', [SELECT Biz_Dev__c FROM Lead WHERE Id = :l.Id].Biz_Dev__c);
    }

    @IsTest
    static void intakeFormNonRealtorBecomesReferralSource() {
        User r = rep();
        Account cpa = partner(r.Id, 'Cpa', null);
        update new Account(Id = cpa.Id, BD_Industry__c = 'CPA');
        Account realtor = partner(r.Id, 'Realtor', null);
        update new Account(Id = realtor.Id, BD_Industry__c = 'Realtor');

        Lead fromCpa = newLead('FromCpa');
        fromCpa.ReferralFormSourceEmail__c = 'cpa@example.com';
        fromCpa.Realtor_Buying_Agent__c = cpa.Id;
        Lead fromRealtor = newLead('FromRealtor');
        fromRealtor.ReferralFormSourceEmail__c = 'realtor@example.com';
        fromRealtor.Realtor_Buying_Agent__c = realtor.Id;
        insert new List<Lead>{ fromCpa, fromRealtor };

        Lead c = [SELECT Realtor_Buying_Agent__c, Referral_Source__c, Biz_Dev__c FROM Lead WHERE Id = :fromCpa.Id];
        System.assertEquals(null, c.Realtor_Buying_Agent__c);
        System.assertEquals(cpa.PersonContactId, c.Referral_Source__c);
        System.assertEquals(CARLETON, c.Biz_Dev__c);
        Lead re = [SELECT Realtor_Buying_Agent__c, Biz_Dev__c FROM Lead WHERE Id = :fromRealtor.Id];
        System.assertEquals(realtor.Id, re.Realtor_Buying_Agent__c, 'realtors stay the Buying Agent');
        System.assertEquals(CARLETON, re.Biz_Dev__c);
    }

    @IsTest
    static void newPartnerDesignation() {
        User r = rep();
        System.assertEquals(CARLETON, LeadBdAttribution.designationForNewPartner(null, r.Id));
        System.assertEquals(CARLETON, LeadBdAttribution.designationForNewPartner('Biz Dev - Reach', r.Id));
        System.assertEquals('Biz Dev - Olmsted', LeadBdAttribution.designationForNewPartner('Biz Dev - Olmsted', r.Id));
        System.assertEquals('Biz Dev - Reach', LeadBdAttribution.designationForNewPartner('Biz Dev - Reach', UserInfo.getUserId()));
    }
}
