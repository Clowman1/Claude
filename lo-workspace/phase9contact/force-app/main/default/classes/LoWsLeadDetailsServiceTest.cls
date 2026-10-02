/**
 * LO Workspace leads: Pre-Approval Details edit and Add lead with a referring realtor, run as a real
 * outside loan officer (External Loan Officer Profile + role, permission set group External_Loan_Officer).
 *
 * Proves: the owner saves every Pre-Approval Details field in one call (Buying_Timeline__c values
 * included); a non-owner and a foreign realtor are refused; bad values are refused; Add lead requires
 * first/last name, phone, real email and loan purpose; a realtor from my partners sets the buying agent,
 * the referral source contact and Lead Source 'Realtor Referral'; the Phase 6 takeover still applies and
 * records the realtor on the taken lead.
 */
@IsTest
private class LoWsLeadDetailsServiceTest {

    @TestSetup
    static void setup() {
        User lo = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p9det' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p9.test',
            Email = 'p9det@reach-p9.test',
            LastName = 'p9det',
            Alias = 'p9det',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert lo;
            insert new PermissionSetAssignment(AssigneeId = lo.Id,
                PermissionSetGroupId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'External_Loan_Officer'].Id);
        }
        Id personRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Id consumerRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId();
        List<Account> partners = new List<Account>{
            new Account(RecordTypeId = personRt, FirstName = 'Olive', LastName = 'Ownrealtor', Is_Realtor__c = true,
                PersonEmail = 'p9d.owned@example.com', OwnerId = lo.Id),
            new Account(RecordTypeId = personRt, FirstName = 'Rita', LastName = 'Tagrealtor', Is_Realtor__c = true,
                PersonEmail = 'p9d.tagged@example.com'),
            new Account(RecordTypeId = personRt, FirstName = 'Fay', LastName = 'Foreignrealtor', Is_Realtor__c = true,
                PersonEmail = 'p9d.foreign@example.com')
        };
        insert partners;
        insert new List<Lead>{
            new Lead(RecordTypeId = consumerRt, FirstName = 'Mia', LastName = 'Mine', Company = 'n/a', Status = 'New',
                LeadSource = 'Test', OwnerId = lo.Id, Email = 'p9d.mine@example.com'),
            new Lead(RecordTypeId = consumerRt, FirstName = 'Oscar', LastName = 'Other', Company = 'n/a', Status = 'Working',
                Email = 'p9d.other@example.com'),
            new Lead(RecordTypeId = consumerRt, FirstName = 'Nora', LastName = 'Nurture', Company = 'n/a', Status = 'Nurturing',
                Email = 'p9d.nurture@example.com')
        };
        insert new LeadShare(LeadId = lead('p9d.other@example.com').Id, UserOrGroupId = lo.Id, LeadAccessLevel = 'Read', RowCause = 'Manual');
        System.runAs(lo) {
            LoWsPartnerTagService.tagAccounts(new Set<Id>{ partners[1].Id });
        }
    }

    static User lo() {
        return [SELECT Id FROM User WHERE Alias = 'p9det' LIMIT 1];
    }

    static Lead lead(String email) {
        return [SELECT Id, OwnerId, Status, LeadSource, Realtor_Buying_Agent__c, Referral_Source__c, Loan_Amount__c,
                       Buying_Timeline__c, Property_Type__c, Loan_Purpose__c, Down_Payment_Amount__c,
                       Down_Payment_Percentage__c, Estimated_Monthly_Payment__c, Purchase_Price__c, City, State,
                       Loan_Program__c, Rating, FirstName, LastName, Phone, Email
                FROM Lead WHERE Email = :email LIMIT 1];
    }

    static Account partner(String lastName) {
        return [SELECT Id, PersonContactId FROM Account WHERE LastName = :lastName LIMIT 1];
    }

    @IsTest
    static void buyingTimelineHasExactlyTheThreeValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry e : Lead.Buying_Timeline__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) values.add(e.getValue());
        }
        System.assertEquals(new List<String>{ 'In the next 3 months', '3 to 6 months', '6+ months' }, values);
        System.assertEquals(true, Lead.Buying_Timeline__c.getDescribe().isRestrictedPicklist());
    }

    @IsTest
    static void ownerSavesEveryDetailInOneCall() {
        Id leadId = lead('p9d.mine@example.com').Id;
        Account tagged = partner('Tagrealtor');
        LoWsLeadDetailsService.Details d;
        System.runAs(lo()) {
            d = ExternalLoPortalController.getPreApprovalDetails(leadId);
            System.assertEquals(true, d.canEdit);
            System.assert(d.timelines.contains('3 to 6 months'), d.timelines);
            System.assert(d.realtors.size() >= 2, 'owned + tagged partners offered');
            Map<String, Object> input = new Map<String, Object>{
                'purpose' => 'Purchase', 'program' => 'FHA', 'loanAmount' => 320000,
                'downPaymentAmount' => 20000, 'downPaymentPercent' => 5.5, 'estimatedPayment' => 2450,
                'propertyType' => d.propertyTypes[0], 'buyingTimeline' => '3 to 6 months',
                'city' => 'Orlando', 'state' => 'FL', 'purchasePrice' => 340000, 'realtorId' => tagged.Id
            };
            d = ExternalLoPortalController.savePreApprovalDetails(leadId, JSON.serialize(input));
            System.assertEquals(tagged.Id, d.realtorId);
            System.assertEquals('Rita Tagrealtor', d.realtorName);
            System.assertEquals(true, d.realtorLinkable, 'a tagged partner opens in the shell');
        }
        Lead l = lead('p9d.mine@example.com');
        System.assertEquals('Purchase', l.Loan_Purpose__c);
        System.assertEquals('FHA', l.Loan_Program__c);
        System.assertEquals(320000, l.Loan_Amount__c);
        System.assertEquals(20000, l.Down_Payment_Amount__c);
        System.assertEquals(5.5, l.Down_Payment_Percentage__c);
        System.assertEquals(2450, l.Estimated_Monthly_Payment__c);
        System.assertEquals('3 to 6 months', l.Buying_Timeline__c);
        System.assertEquals(null, l.Rating, 'Rating is never touched');
        System.assertEquals('Orlando', l.City);
        System.assertEquals(340000, l.Purchase_Price__c);
        System.assertEquals(tagged.Id, l.Realtor_Buying_Agent__c);
        System.assertEquals(tagged.PersonContactId, l.Referral_Source__c, 'attribution = the realtor contact');
        System.assertEquals('Test', l.LeadSource, 'Lead Source untouched by the edit');
        System.assertEquals('New', l.Status, 'Status untouched');
        System.assertEquals(lo().Id, l.OwnerId);

        // Clearing works too (blank / null), and keeps the lead the LO's.
        System.runAs(lo()) {
            d = ExternalLoPortalController.savePreApprovalDetails(leadId, JSON.serialize(new Map<String, Object>{
                'purpose' => 'Purchase', 'buyingTimeline' => '', 'realtorId' => null }));
            System.assertEquals(null, d.realtorId);
            System.assertEquals(null, d.buyingTimeline);
        }
        System.assertEquals(null, lead('p9d.mine@example.com').Referral_Source__c);
    }

    @IsTest
    static void nonOwnerForeignRealtorAndBadValuesAreRefused() {
        Id mine = lead('p9d.mine@example.com').Id;
        Id other = lead('p9d.other@example.com').Id;
        Id foreign = partner('Foreignrealtor').Id;
        System.runAs(lo()) {
            LoWsLeadDetailsService.Details d = ExternalLoPortalController.getPreApprovalDetails(other);
            System.assertEquals(false, d.canEdit, 'shared read-only lead');
            System.assertEquals(LoWsContactService.NOT_OWNER_NOTE, d.note);
            expectError(other, new Map<String, Object>{ 'loanAmount' => 1 }, LoWsContactService.NOT_OWNER_NOTE);
            expectError(mine, new Map<String, Object>{ 'realtorId' => foreign }, LoWsLeadDetailsService.FOREIGN_REALTOR);
            expectError(mine, new Map<String, Object>{ 'buyingTimeline' => 'Hot' }, 'valid buying timeline');
            expectError(mine, new Map<String, Object>{ 'loanAmount' => -5 }, 'cannot be negative');
            expectError(mine, new Map<String, Object>{ 'downPaymentPercent' => 150 }, 'between 0 and 100');
        }
        System.assertEquals(null, lead('p9d.other@example.com').Loan_Amount__c, 'nothing saved');
    }

    // ------------------------------------------------------------------ Add lead

    @IsTest
    static void addLeadWithMyRealtorSetsTheBuyingAgent() {
        Account owned = partner('Ownrealtor');
        ExternalLoLeadService.CreateLeadResult r;
        System.runAs(lo()) {
            System.assertEquals(2, ExternalLoPortalController.getAddLeadOptions().realtors.size(), 'owned + tagged only');
            // Same call the My Realtors row / realtor page makes with the realtor pre-filled.
            r = ExternalLoPortalController.createLoWorkspaceLead('Ann', 'Buyer', '(407) 555-0141',
                'p9d.ann@example.com', 'Purchase', owned.Id);
        }
        Lead l = lead('p9d.ann@example.com');
        System.assertEquals(r.leadId, l.Id);
        System.assertEquals('Ann', l.FirstName);
        System.assertEquals('Buyer', l.LastName);
        System.assertEquals(owned.Id, l.Realtor_Buying_Agent__c);
        System.assertEquals(owned.PersonContactId, l.Referral_Source__c);
        System.assertEquals('Realtor Referral', l.LeadSource);
        System.assertEquals(null, l.Loan_Amount__c, 'no loan amount on create');
        System.assertEquals(lo().Id, l.OwnerId);
    }

    @IsTest
    static void addLeadRequiresFieldsAndRefusesForeignRealtorAndPlaceholder() {
        Id foreign = partner('Foreignrealtor').Id;
        System.runAs(lo()) {
            expectAddError('', 'Buyer', '(407) 555-0142', 'p9d.x@example.com', 'Purchase', null, 'first and last name');
            expectAddError('Al', 'Buyer', '', 'p9d.x@example.com', 'Purchase', null, 'phone number');
            expectAddError('Al', 'Buyer', '555-12', 'p9d.x@example.com', 'Purchase', null, '10-digit');
            expectAddError('Al', 'Buyer', '(407) 555-0142', '', 'Purchase', null, 'email address');
            expectAddError('Al', 'Buyer', '(407) 555-0142', 'na@na.com', 'Purchase', null, 'real email');
            expectAddError('Al', 'Buyer', '(407) 555-0142', 'p9d.x@example.com', '', null, 'loan purpose');
            expectAddError('Al', 'Buyer', '(407) 555-0142', 'p9d.x@example.com', 'Purchase', foreign, LoWsLeadDetailsService.FOREIGN_REALTOR);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE LastName = 'Buyer']);
    }

    @IsTest
    static void addLeadStillTakesOverANurturingLeadAndRecordsTheRealtor() {
        Lead before = lead('p9d.nurture@example.com');
        Account owned = partner('Ownrealtor');
        ExternalLoLeadService.CreateLeadResult r;
        Test.startTest();
        System.runAs(lo()) {
            r = ExternalLoPortalController.createLoWorkspaceLead('Nora', 'Nurture', '(407) 555-0143',
                'P9D.Nurture@example.com', 'Refinance', owned.Id);
        }
        Test.stopTest();
        Lead after = lead('p9d.nurture@example.com');
        System.assertEquals(before.Id, r.leadId, 'Phase 6: the Nurturing lead is taken over, not duplicated');
        System.assertEquals(lo().Id, after.OwnerId);
        System.assertEquals('New', after.Status);
        System.assertEquals('Realtor Referral', after.LeadSource, 'takeover replaces the source');
        System.assertEquals(owned.Id, after.Realtor_Buying_Agent__c);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = 'p9d.nurture@example.com']);
    }

    @IsTest
    static void addLeadOnAWorkedLeadIsStillRefused() {
        System.runAs(lo()) {
            expectAddError('Oscar', 'Other', '(407) 555-0144', 'p9d.other@example.com', 'Purchase', null,
                LoWsLeadIntakeService.BLOCKED_MESSAGE);
        }
        System.assertEquals('Working', lead('p9d.other@example.com').Status);
    }

    static void expectError(Id leadId, Map<String, Object> input, String expected) {
        try {
            ExternalLoPortalController.savePreApprovalDetails(leadId, JSON.serialize(input));
            System.assert(false, 'expected: ' + expected);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains(expected), e.getMessage());
        }
    }

    static void expectAddError(String first, String last, String phone, String email, String purpose, Id realtorId, String expected) {
        try {
            ExternalLoPortalController.createLoWorkspaceLead(first, last, phone, email, purpose, realtorId);
            System.assert(false, 'expected: ' + expected);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains(expected), e.getMessage());
        }
    }
}
