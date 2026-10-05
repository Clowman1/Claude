@IsTest
private class LoanSubmissionWizardControllerTest {
    static Id personRt() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
    }

    @TestSetup
    static void setup() {
        Account borrower = new Account(
            FirstName = 'Pat', LastName = 'Primary', RecordTypeId = personRt(),
            First_Name_Co_Borrower__pc = 'Legacy', Last_Name_Co_Borrower__pc = 'CoBorrower',
            Borrower_Has_Spouse__pc = true, Borrower_Spouse_Name__pc = 'Sam Spouse'
        );
        Account lender = new Account(Name = 'Wizard Test Lender', Type = 'Investor');
        Account title = new Account(Name = 'Wizard Test Title');
        insert new List<Account>{ borrower, lender, title };

        Transaction__c t = new Transaction__c(
            Name = 'Wizard Test Loan',
            Borrower_Name__c = borrower.Id,
            Account__c = borrower.Id,
            Lien_Position__c = '1st',
            Lender_lookup__c = lender.Id,
            Title_Agent__c = title.Id,
            Loan_Amount_1st__c = 300000,
            Loan_Type_1st_TD__c = 'Conventional',
            Loan_Program_1st__c = 'Conventional Fixed',
            Loan_Purpose__c = 'Purchase',
            Occupancy__c = 'Primary Residence',
            Property_Type__c = 'Single Family',
            Rate_1st_TD__c = 6.5,
            Rate_Lock_Status__c = 'Locked',
            Rate_Lock_Exp_Date__c = Date.today().addDays(30),
            Closing_Date__c = Date.today().addDays(40),
            Conditions_Needed__c = 'Pay stubs',
            Status__c = 'TRID Application'
        );
        insert t;
        insert new Borrower__c(
            Transaction__c = t.Id, First_Name__c = 'Casey', Last_Name__c = 'Co', Email__c = 'casey@example.com',
            Name = 'Casey Co'
        );
    }

    static Transaction__c loan() {
        return [SELECT Id, Lender_lookup__c, Title_Agent__c, Loan_Partner__c FROM Transaction__c WHERE Name = 'Wizard Test Loan' LIMIT 1];
    }

    /** A complete, valid payload keyed by the flow's screen-field names. */
    static Map<String, Object> payload(Transaction__c t) {
        return new Map<String, Object>{
            'InvestorLookup' => t.Lender_lookup__c, 'Channel' => 'Broker',
            'Borrower_First_Name' => 'Pat', 'Borrower_Last_Name' => 'Primary',
            'Co_Borrower_First_Name' => 'Casey', 'Co_Borrower_Last_Name' => 'Co', 'BorrowerCoEmail' => 'casey@example.com',
            'Borrower_and_Co_Borrower_are_spouses' => false, 'Borrower_Has_a_Spouse' => true, 'Spouse_Borrower' => 'Sam Spouse',
            'Loan_Purpose' => 'Purchase', 'Loan_Type' => 'Conventional', 'Occupancy' => 'Primary Residence',
            'New_Build_Bank_Owned' => 'No', 'Program_Type' => 'Conventional Fixed', 'Property_Type' => 'Single Family',
            'Appraisal' => 'Needed', 'Waiving_Escrow' => 'No', 'Expected_Cash_To_Close' => 25000,
            'No_Realtor' => true, 'NameTCLookup' => t.Title_Agent__c, 'Same_as_Listing_Agent' => false,
            'NameContactForEntry' => 'Entry Person', 'PhoneContactForEntry' => '4075551212', 'EmailContactForEntry' => 'entry@example.com',
            'Rate_Buydown' => 'No', 'DPA_Grant' => 'No', 'Closing' => String.valueOf(Date.today().addDays(45)),
            'Rate_Lock_Status' => 'Locked', 'Lock_Date' => String.valueOf(Date.today().addDays(35)),
            'Income_Multi' => '2 years', 'Assets_Multi' => 'Checking/Savings', 'Needs_List' => 'Bank statements',
            // hidden by the flow's visibility rules, must not be saved:
            'Refinance_Purpose' => 'Rate & Term', 'Contributor' => 'Seller Paid', 'NameHOA' => 'Should vanish'
        };
    }

    @IsTest
    static void prefillLoadsTransactionAccountAndBorrowers() {
        Transaction__c t = loan();
        Test.startTest();
        Map<String, Object> data = LoanSubmissionWizardController.getWizardData(t.Id);
        Test.stopTest();

        Map<String, Object> v = (Map<String, Object>) data.get('values');
        Assert.areEqual(t.Lender_lookup__c, v.get('InvestorLookup'));
        Assert.areEqual('Pat', v.get('Borrower_First_Name'));
        Assert.areEqual('Purchase', v.get('Loan_Purpose'));
        Assert.areEqual('Locked', v.get('Rate_Lock_Status'));
        Assert.areEqual('Pay stubs', v.get('Needs_List'));
        Assert.areEqual(true, v.get('Borrower_Has_a_Spouse'), 'spouse flags come from the Person Account');
        Assert.areEqual('Casey', v.get('Co_Borrower_First_Name'), 'first Borrower__c row is the co-borrower');
        Assert.isNull(v.get('DPA_Grant'), 'no filed form yet, so an unticked checkbox is not a "No"');
        Assert.areEqual(1, ((List<Borrower__c>) data.get('borrowers')).size());
        Assert.isTrue(((List<String>) data.get('prefilledKeys')).contains('Program_Type'));
        Assert.isNull(data.get('lockedMessage'));
        Assert.areEqual('Wizard Test Lender', ((Map<String, String>) data.get('lookupLabels')).get('InvestorLookup'));
    }

    @IsTest
    static void submitCreatesFormAndNeverWritesLoanPartner() {
        Transaction__c t = loan();
        Id partnerBefore = t.Loan_Partner__c;

        Test.startTest();
        Id formId = LoanSubmissionWizardController.submit(t.Id, JSON.serialize(payload(t)));
        Test.stopTest();

        Submission_Form__c f = [
            SELECT Transaction__c, RecordType.DeveloperName, Channel__c, Investor_Lookup__c, Title_Company_Name__c,
                Borrower_Has_Spouse__c, Borrower_Spouse_Name__c, Lock_Exp_Date__c, Rate_lock__c, PIW__c, Appraisal__c,
                Expected_Funds_to_Close__c, Refinance_Purpose__c, Contributor__c, HOA_Name__c, Appraisal_Contact_Name__c,
                Needs_List_Description__c, Loan_Partner__c
            FROM Submission_Form__c WHERE Id = :formId
        ];
        Assert.areEqual('Loan_Origination_Submission_Form', f.RecordType.DeveloperName);
        Assert.areEqual('Broker', f.Channel__c);
        Assert.areEqual(t.Title_Agent__c, f.Title_Company_Name__c);
        Assert.isTrue(f.Borrower_Has_Spouse__c);
        Assert.areEqual('Needed', f.PIW__c, 'flow writes Appraisal to both PIW__c and Appraisal__c');
        Assert.areEqual(25000, f.Expected_Funds_to_Close__c);
        Assert.areEqual(Date.today().addDays(35), f.Lock_Exp_Date__c);
        Assert.isNull(f.Refinance_Purpose__c, 'hidden (not a Refinance)');
        Assert.isNull(f.Contributor__c, 'hidden (no rate buydown)');
        Assert.isNull(f.HOA_Name__c, 'hidden (not a Condo)');
        Assert.areEqual('Entry Person', f.Appraisal_Contact_Name__c);
        Assert.isNull(f.Loan_Partner__c);

        Transaction__c after = [SELECT Loan_Partner__c, Channel__c, Conditions_Needed__c FROM Transaction__c WHERE Id = :t.Id];
        Assert.areEqual(partnerBefore, after.Loan_Partner__c, 'the form must never write Loan Partner');
        Assert.areEqual('Bank statements', after.Conditions_Needed__c, 'record-triggered flow copied the form');
    }

    @IsTest
    static void cantFindCreatesPartnersAndLinksThem() {
        Transaction__c t = loan();
        Map<String, Object> p = payload(t);
        p.put('No_Realtor', false);
        p.putAll(new Map<String, Object>{
            'Cant_Find_My_Contact_Buyers' => true, 'First_Name_BA' => 'Bea', 'Last_Name_BA' => 'Buyer',
            'BuyersCellPhone' => '4075550001', 'BuyersEmail' => 'bea@example.com',
            'Cant_Find_BuyersAgentAssistant' => true, 'First_Name_BAA' => 'Ann', 'Last_Name_BAA' => 'Assist',
            'PhoneBAA' => '4075550002', 'EmailBAA' => 'ann@example.com',
            'Cant_Find_My_Contact_Sellers' => true, 'First_Name_SA' => 'Sid', 'Last_Name_SA' => 'Seller',
            'SellersCellPhone' => '4075550003', 'SellersEmail' => 'sid@example.com',
            'Cant_Find_SellersAgentAssistant' => true, 'First_Name_SAA' => 'Tia', 'Last_Name_SAA' => 'Tc',
            'PhoneSAA' => '4075550004', 'EmailSAA' => 'tia@example.com',
            'Cant_Find_My_Company' => true, 'CompanyTC' => 'Brand New Title', 'PhoneTC' => '4075550005', 'EmailTC' => 'tc@example.com',
            'Same_as_Listing_Agent' => true
        });

        Test.startTest();
        Id formId = LoanSubmissionWizardController.submit(t.Id, JSON.serialize(p));
        Test.stopTest();

        Submission_Form__c f = [
            SELECT Buyers_Agent_Lookup__r.LastName, Buyers_Agent_Lookup__r.Type__c, Buying_Agent_Assistant__r.LastName,
                Sellers_Agent_Lookup__r.LastName, Listing_Agent_TC__r.LastName, Title_Company_Name__r.Name,
                Title_Company_Name__r.Type__c, Title_Company_Email__c, Appraisal_Contact_Name__c, Appraisal_Contact_Email__c
            FROM Submission_Form__c WHERE Id = :formId
        ];
        Assert.areEqual('Buyer', f.Buyers_Agent_Lookup__r.LastName);
        Assert.areEqual('Realtor Account', f.Buyers_Agent_Lookup__r.Type__c);
        Assert.areEqual('Assist', f.Buying_Agent_Assistant__r.LastName);
        Assert.areEqual('Seller', f.Sellers_Agent_Lookup__r.LastName);
        Assert.areEqual('Tc', f.Listing_Agent_TC__r.LastName, 'assistant linked through its Person Contact');
        Assert.areEqual('Brand New Title', f.Title_Company_Name__r.Name);
        Assert.areEqual('Title Agent Account', f.Title_Company_Name__r.Type__c);
        Assert.areEqual('tc@example.com', f.Title_Company_Email__c);
        Assert.areEqual('Sid Seller', f.Appraisal_Contact_Name__c, 'same as seller\'s agent');
        Assert.areEqual('sid@example.com', f.Appraisal_Contact_Email__c);
        Assert.areEqual(5, [SELECT COUNT() FROM Account WHERE Exclude_From_Duplicate_Check__c = true AND CreatedDate = TODAY AND (Type__c = 'Realtor Account' OR Type__c = 'Title Agent Account')]);
    }

    @IsTest
    static void sameAsSellerLookupCopiesTheAccount() {
        Transaction__c t = loan();
        Account seller = new Account(FirstName = 'Lia', LastName = 'Listing', RecordTypeId = personRt(), PersonEmail = 'lia@example.com');
        insert seller;
        Map<String, Object> p = payload(t);
        p.put('SellersNameLookup', seller.Id);
        p.put('Same_as_Listing_Agent', true);

        Id formId = LoanSubmissionWizardController.submit(t.Id, JSON.serialize(p));
        Submission_Form__c f = [SELECT Appraisal_Contact_Name__c, Appraisal_Contact_Email__c FROM Submission_Form__c WHERE Id = :formId];
        Assert.areEqual('Lia Listing', f.Appraisal_Contact_Name__c);
        Assert.areEqual('lia@example.com', f.Appraisal_Contact_Email__c);
    }

    @IsTest
    static void editWindowLocksLoanOfficersAfterDisclosuresOut() {
        Transaction__c t = loan();
        update new Transaction__c(Id = t.Id, Disclosures_Out_Date__c = System.now(), CommSent_Disclosures_Out__c = true);

        LoanSubmissionWizardController.profileOverride = 'Loan Officer Profile';
        Assert.areEqual(LoanSubmissionWizardController.LOCKED_MESSAGE, LoanSubmissionWizardController.getWizardData(t.Id).get('lockedMessage'));
        try {
            LoanSubmissionWizardController.submit(t.Id, JSON.serialize(payload(t)));
            Assert.fail('a Loan Officer must not submit after Disclosures Out');
        } catch (AuraHandledException e) {
            Assert.areEqual(LoanSubmissionWizardController.LOCKED_MESSAGE, e.getMessage());
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Submission_Form__c WHERE Transaction__c = :t.Id]);

        LoanSubmissionWizardController.profileOverride = 'Processor Profile (SF)';
        Assert.isNotNull(LoanSubmissionWizardController.submit(t.Id, JSON.serialize(payload(t))), 'processors edit at any stage');

        LoanSubmissionWizardController.profileOverride = 'Loan Officer Profile (Read Only)';
        Assert.isNotNull(LoanSubmissionWizardController.getWizardData(t.Id).get('lockedMessage'));
    }

    @IsTest
    static void missingRequiredFieldsAreRefused() {
        Transaction__c t = loan();
        Map<String, Object> p = payload(t);
        p.remove('Closing');
        p.remove('Refinance_Purpose');
        p.put('Loan_Purpose', 'Refinance');
        p.put('DPA_Grant', 'Yes');
        try {
            LoanSubmissionWizardController.submit(t.Id, JSON.serialize(p));
            Assert.fail('expected a validation error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Closing Date'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('Refinance Purpose'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('Loan Amount 2nd'), e.getMessage());
        }
    }

    @IsTest
    static void dpaCreatesTheSecondTransaction() {
        Transaction__c t = loan();
        Map<String, Object> p = payload(t);
        p.putAll(new Map<String, Object>{
            'DPA_Grant' => 'Yes', 'DPA_Grant_Program_Name' => 'Hometown Heroes',
            'InvestorLookup2nd' => t.Lender_lookup__c, 'Loan_Type_2nd' => 'DPA 2nd', 'Rate_2nd' => 0,
            'Loan_Amount_2nd' => 10000, 'Loan_Program_2nd' => 'Closed-End Second'
        });
        Test.startTest();
        LoanSubmissionWizardController.submit(t.Id, JSON.serialize(p));
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Transaction__c WHERE First_Mortgage__c = :t.Id]);
    }

    @IsTest
    static void addBorrowerAndSearch() {
        Transaction__c t = loan();
        Borrower__c row = LoanSubmissionWizardController.addBorrower(t.Id, ' Drew ', 'Third', 'drew@example.com', null);
        Assert.areEqual('Drew Third', row.Name);
        Assert.areEqual(2, BorrowerPersonAccountService.getBorrowers(t.Id).size());
        try {
            LoanSubmissionWizardController.addBorrower(t.Id, '', 'Nobody', null, null);
            Assert.fail('names are required');
        } catch (AuraHandledException e) {
            Assert.areEqual('First and last name are required.', e.getMessage());
        }

        Account title = [SELECT Id FROM Account WHERE Name = 'Wizard Test Title'];
        Test.setFixedSearchResults(new List<Id>{ title.Id });
        List<Map<String, String>> hits = LoanSubmissionWizardController.searchRecords('Account', 'Wizard');
        Assert.areEqual(1, hits.size());
        Assert.areEqual(title.Id, hits[0].get('id'));
        Assert.areEqual(0, LoanSubmissionWizardController.searchRecords('Account', 'W').size(), 'two characters minimum');
        Assert.areEqual(0, LoanSubmissionWizardController.searchRecords('Contact', 'Wizard').size());
    }

    @IsTest
    static void submitWritesCoBorrowerEditsBackToTheRow() {
        Transaction__c t = loan();
        Borrower__c row = [SELECT Id, Phone__c FROM Borrower__c WHERE Transaction__c = :t.Id];
        Map<String, Object> p = payload(t);
        p.putAll(new Map<String, Object>{
            'CoBorrowerRowId' => row.Id, 'Co_Borrower_First_Name' => 'casey', 'Co_Borrower_Last_Name' => 'Co',
            'BorrowerCoEmail' => 'casey.new@example.com', 'BorrowerCoPhone' => '4075559999'
        });

        Test.startTest();
        LoanSubmissionWizardController.submit(t.Id, JSON.serialize(p));
        Test.stopTest();

        Borrower__c after = [SELECT Name, First_Name__c, Last_Name__c, Email__c, Phone__c FROM Borrower__c WHERE Id = :row.Id];
        Assert.areEqual('casey', after.First_Name__c, 'case-only edit is still an edit');
        Assert.areEqual('Co', after.Last_Name__c);
        Assert.areEqual('casey Co', after.Name, 'borrowerPanel naming rule');
        Assert.areEqual('casey.new@example.com', after.Email__c);
        Assert.areEqual('4075559999', after.Phone__c.replaceAll('[^0-9]', ''));
        Assert.areEqual(1, [SELECT COUNT() FROM Borrower__c WHERE Transaction__c = :t.Id], 'submit never creates or deletes rows');
    }

    @IsTest
    static void unchangedCoBorrowerLeavesTheRowAlone() {
        Transaction__c t = loan();
        Borrower__c row = [SELECT Id, LastModifiedDate, SystemModstamp FROM Borrower__c WHERE Transaction__c = :t.Id];
        Map<String, Object> p = payload(t);
        p.put('CoBorrowerRowId', row.Id);
        p.put('Co_Borrower_Last_Name', null); // blank name is ignored, not written
        LoanSubmissionWizardController.submit(t.Id, JSON.serialize(p));
        Borrower__c after = [SELECT Name, Last_Name__c FROM Borrower__c WHERE Id = :row.Id];
        Assert.areEqual('Co', after.Last_Name__c);
        Assert.areEqual('Casey Co', after.Name);
    }

    @IsTest
    static void pickersSearchTheWholeOrgForAnOutsideLo() {
        Account titleCo = new Account(
            Name = 'Zebra Title Partners', Type__c = 'Title Agent Account',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Business_Account').getRecordTypeId()
        );
        Account realtor = new Account(
            FirstName = 'Zelda', LastName = 'Zimmer', Type__c = 'Realtor Account', PersonEmail = 'zelda@example.com',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId()
        );
        insert new List<Account>{ titleCo, realtor };
        User lo = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p10pick' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p10.test',
            Email = 'p10pick@reach-p10.test', LastName = 'p10pick', Alias = 'p10pick',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert lo;
        }
        System.runAs(lo) {
            List<Map<String, String>> titles = LoanSubmissionWizardController.searchPartners('Account', 'title', 'Zebra');
            System.assertEquals(1, titles.size(), 'Title companies the LO does not own are found.');
            System.assertEquals(titleCo.Id, titles[0].get('id'));
            List<Map<String, String>> agents = LoanSubmissionWizardController.searchPartners('Account', 'agent', 'Zelda');
            System.assertEquals(1, agents.size());
            System.assert(!String.valueOf(agents[0].get('sub')).contains('zelda@example.com'), 'No realtor email.');
            System.assertEquals(0, LoanSubmissionWizardController.searchPartners('Account', 'title', 'Zelda').size(), 'Title kind only returns title companies.');
            System.assertEquals(0, LoanSubmissionWizardController.searchPartners('Account', 'agent', 'Z').size(), 'Two letters minimum.');
        }
    }
}
