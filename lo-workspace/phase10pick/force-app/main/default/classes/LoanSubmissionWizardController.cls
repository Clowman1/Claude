/**
 * Server side of the loanSubmissionWizard LWC, the guided replacement for the screen flow
 * Loan_Origination_Submission_Form (v45). Keys in the payload are the flow's own screen-field
 * names, so FORM.md maps one-to-one onto the flow XML.
 *
 * Same execution model as the flow (runInMode SystemModeWithSharing): `with sharing` for reads,
 * system-mode DML. The flow's real work happens in record-triggered automation on
 * Submission_Form__c (…_Update_Transaction, Update_Transaction_on_Submission_Form_Creation) and on
 * Submission_Form_Event__e, so submit() only has to insert the same Submission_Form__c, create the
 * same "can't find" partner Accounts, call the same DPA invocable and publish the same event.
 * Loan_Partner__c is never written (see memory submission-form-edit-window).
 */
public with sharing class LoanSubmissionWizardController {
    @TestVisible
    static final String LOCKED_MESSAGE =
        'The Submission Form is read-only once Disclosures have gone out. Contact a Processor or an Admin if it has to change.';

    static final Id PERSON_ACCOUNT_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
    static final Id BUSINESS_ACCOUNT_RT =
        Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Business_Account').getRecordTypeId();
    static final Id FORM_RT =
        Schema.SObjectType.Submission_Form__c.getRecordTypeInfosByDeveloperName().get('Loan_Origination_Submission_Form').getRecordTypeId();

    // Test hook for the edit-window rule (profile/role/username are not settable in a test).
    @TestVisible
    static String profileOverride;

    // ------------------------------------------------------------------ load

    @AuraEnabled
    public static Map<String, Object> getWizardData(Id transactionId) {
        Transaction__c t = loadTransaction(transactionId);
        Submission_Form__c prev = latestForm(transactionId);
        List<Borrower__c> borrowers = BorrowerPersonAccountService.getBorrowers(transactionId);

        Map<String, Object> v = new Map<String, Object>();
        Map<String, String> labels = new Map<String, String>();
        Account b = t.Borrower_Name__r;

        // Loan
        putId(v, labels, 'InvestorLookup', t.Lender_lookup__c, t.Lender_lookup__r?.Name);
        v.put('Channel', t.Channel__c);
        v.put('Loan_Purpose', t.Loan_Purpose__c);
        v.put('Refinance_Purpose', t.Refinance_Purpose_Picklist__c);
        v.put('Loan_Type', t.Loan_Type_1st_TD__c);
        v.put('Occupancy', t.Occupancy__c);
        v.put('New_Build_Bank_Owned', yesNo(t.New_Build_Bank_Owned__c, prev != null));
        v.put('Program_Type', t.Loan_Program_1st__c);
        v.put('Property_Type', t.Property_Type__c);
        v.put('Appraisal', t.Appraisal__c);
        if (prev != null) {
            v.put('Condo_Review_Type', prev.Condo_Review_Type__c);
            v.put('Waiving_Escrow', prev.Waiving_Escrow__c);
            v.put('DU_LP_MANUAL', prev.DU_LP_Manual__c);
        }

        // Borrowers: primary from the Transaction borrower; first Borrower__c row is the co-borrower,
        // else the Person Account co-borrower fields (the authoritative legacy source).
        v.put('Borrower_First_Name', b?.FirstName);
        v.put('Borrower_Last_Name', b?.LastName);
        if (!borrowers.isEmpty()) {
            Borrower__c co = borrowers[0];
            v.put('Co_Borrower_First_Name', co.First_Name__c);
            v.put('Co_Borrower_Last_Name', co.Last_Name__c);
            v.put('BorrowerCoPhone', co.Phone__c);
            v.put('BorrowerCoEmail', co.Email__c);
        } else if (b != null) {
            v.put('Co_Borrower_First_Name', b.First_Name_Co_Borrower__pc);
            v.put('Co_Borrower_Last_Name', b.Last_Name_Co_Borrower__pc);
            v.put('BorrowerCoPhone', b.Mobile_Co_Borrower__pc);
            v.put('BorrowerCoEmail', b.Email_Co_Borrower__pc);
        }
        if (b != null) {
            v.put('Borrower_and_Co_Borrower_are_spouses', b.Borrower_and_Co_Borrower_Spouses__pc == true);
            v.put('Borrower_Has_a_Spouse', b.Borrower_Has_Spouse__pc == true);
            v.put('Spouse_Borrower', b.Borrower_Spouse_Name__pc);
            v.put('SpousePhoneBorrower', b.Borrower_Spouse_Phone__pc);
            v.put('SpouseEmailBorrower', b.Borrower_Spouse_Email__pc);
            v.put('Co_Borrower_Has_a_Spouse', b.Co_Borrower_Has_Spouse__pc == true);
            v.put('Spouse_CoBorrower', b.Co_Borrower_Spouse_Name__pc);
            v.put('SpousePhoneCoBorrower', b.Co_Borrower_Spouse_Phone__pc);
            v.put('SpouseEmailCoBorrower', b.Co_Borrower_Spouse_Email__pc);
        }
        v.put('Speaks_Spanish_Only', prev != null && prev.Speaks_Spanish_Only__c == true);

        // Partners
        putId(v, labels, 'BuyersNameLookup', t.Realtor_Buying_Agent__c, t.Realtor_Buying_Agent__r?.Name);
        putId(v, labels, 'Buying_Agent_Assistant', t.Buying_Agent_Assistant__c, t.Buying_Agent_Assistant__r?.Name);
        putId(v, labels, 'SellersNameLookup', t.Realtor_Listing_Agent__c, t.Realtor_Listing_Agent__r?.Name);
        putId(v, labels, 'Seller_Agent_Assistant', t.Listing_Agent_TC__c, t.Listing_Agent_TC__r?.Name);
        putId(v, labels, 'NameTCLookup', t.Title_Agent__c, t.Title_Agent__r?.Name);
        if (prev != null) {
            v.put('NameHOA', prev.HOA_Name__c);
            v.put('CompanyHOA', prev.HOA_Company__c);
            v.put('PhoneHOA', prev.HOA_Phone__c);
            v.put('NameContactForEntry', prev.Appraisal_Contact_Name__c);
            v.put('PhoneContactForEntry', prev.Appraisal_Contact_Phone__c);
            v.put('EmailContactForEntry', prev.Appraisal_Contact_Email__c);
        }

        // Pricing & lock
        v.put('Expected_Cash_To_Close', t.Expected_Cash_To_Close__c);
        v.put('Rate_Buydown', yesNo(t.Rate_Buydown__c, prev != null));
        v.put('Contributor', t.Contributor__c);
        v.put('Buydown', t.Buydown__c);
        v.put('DPA_Grant', yesNo(t.DPA__c, prev != null));
        v.put('DPA_Grant_Program_Name', t.DPA_Grant_Program_Name__c);
        if (prev != null) {
            v.put('DPA_Grant_Number_of_Persons_in_Household', prev.DPA_Grant_Number_of_Persons_in_Household__c);
            v.put('DPA_Grant_Household_Income', prev.DPA_Grant_Household_Income__c);
        }
        Transaction__c second = t.Second_Mortgage__r;
        if (second != null) {
            putId(v, labels, 'InvestorLookup2nd', second.Lender_lookup__c, second.Lender_lookup__r?.Name);
            v.put('Loan_Type_2nd', second.Loan_Type_1st_TD__c);
            v.put('Rate_2nd', second.Rate_1st_TD__c);
            v.put('Loan_Amount_2nd', second.Loan_Amount_1st__c);
            v.put('Loan_Program_2nd', second.Loan_Program_1st__c);
        }
        v.put('Commitment', t.Loan_Commitment_Date__c);
        v.put('Closing', t.Closing_Date__c);
        v.put('Rate_Lock_Status', t.Rate_Lock_Status__c);
        v.put('Lock_Date', t.Rate_Lock_Exp_Date__c);

        // Notes & needs
        v.put('Needs_List', t.Conditions_Needed__c);
        if (prev != null) {
            v.put('General_Notes', prev.General_Notes_Description__c);
            v.put('Credit', prev.Credit_Description__c);
            v.put('Income_Multi', prev.Income_4506T_Multi__c);
            v.put('Assets_Multi', prev.Source_of_Funds_to_Close_Multi__c);
            v.put('Intentions_for_Current_Home', prev.Intentions_for_Current_Home__c);
        }

        List<String> prefilled = new List<String>();
        for (String key : v.keySet()) {
            Object val = v.get(key);
            if (val != null && val != false && String.isNotBlank(String.valueOf(val))) {
                prefilled.add(key);
            }
        }

        return new Map<String, Object>{
            'transactionName' => t.Name,
            'status' => t.Status__c,
            'values' => v,
            'lookupLabels' => labels,
            'prefilledKeys' => prefilled,
            'hasPreviousForm' => prev != null,
            'borrowers' => borrowers,
            'options' => options(),
            'lockedMessage' => lockedMessage(t)
        };
    }

    /** Search-as-you-type for the partner pickers. Account or Contact only, sharing respected. */
    @AuraEnabled
    public static List<Map<String, String>> searchRecords(String objectName, String term) {
        String clean = term == null ? '' : term.replaceAll('[?&|!{}\\[\\]()^~*:\\\\"\'+\\-]', ' ').trim();
        List<Map<String, String>> out = new List<Map<String, String>>();
        if (clean.length() < 2) {
            return out;
        }
        String findText = clean + '*';
        if (objectName == 'Contact') {
            for (Contact c : (List<Contact>) [
                FIND :findText IN NAME FIELDS
                RETURNING Contact(Id, Name, Email, Account.Name ORDER BY Name LIMIT 15)
            ][0]) {
                out.add(new Map<String, String>{
                    'id' => c.Id, 'name' => c.Name, 'sub' => joinNonBlank(new List<String>{ c.Account?.Name, c.Email })
                });
            }
        } else if (objectName == 'Account') {
            for (Account a : (List<Account>) [
                FIND :findText IN NAME FIELDS
                RETURNING Account(Id, Name, Type__c, Phone, PersonEmail ORDER BY Name LIMIT 15)
            ][0]) {
                out.add(new Map<String, String>{
                    'id' => a.Id, 'name' => a.Name,
                    'sub' => joinNonBlank(new List<String>{ String.valueOf(a.Type__c), a.Phone, a.PersonEmail })
                });
            }
        }
        return out;
    }

    /**
     * Partner pickers (owner decision 2026-10-05): every matching account in the org, not just the ones the
     * user can see. kind = agent (realtors), assistant (any person), title (Title Agent Accounts) or
     * investor (Type Investor). Returns name plus company / city only: no realtor phone or email.
     */
    @AuraEnabled
    public static List<Map<String, String>> searchPartners(String objectName, String kind, String term) {
        if (UserInfo.getUserType() == 'Guest') {
            return new List<Map<String, String>>();
        }
        String clean = term == null ? '' : term.trim();
        if (clean.length() < 2) {
            return new List<Map<String, String>>();
        }
        return new OrgWide().search(objectName, kind, clean);
    }

    private without sharing class OrgWide {
        void insertForm(Submission_Form__c f) {
            insert f;
        }

        Account account(Id accountId) {
            return [SELECT Name, Phone, PersonEmail FROM Account WHERE Id = :accountId];
        }

        List<Map<String, String>> search(String objectName, String kind, String clean) {
            String likeTerm = '%' + clean + '%';
            String lower = clean.toLowerCase();
            List<Map<String, String>> starts = new List<Map<String, String>>();
            List<Map<String, String>> rest = new List<Map<String, String>>();
            if (objectName == 'Contact') {
                for (Contact c : [SELECT Id, Name, Account.Name, MailingCity FROM Contact WHERE Name LIKE :likeTerm ORDER BY Name LIMIT 50]) {
                    add(c.Id, c.Name, joinNonBlank(new List<String>{ c.Account?.Name, c.MailingCity }), lower, starts, rest);
                }
            } else {
                List<Account> rows;
                if (kind == 'agent') {
                    rows = [SELECT Id, Name, Company__c, PersonMailingCity, BillingCity FROM Account
                            WHERE Name LIKE :likeTerm AND IsPersonAccount = true
                              AND (Type__c = 'Realtor Account' OR Group__pc INCLUDES ('Realtor', 'Realtor Prospect') OR Is_Realtor__c = true)
                            ORDER BY Name LIMIT 50];
                } else if (kind == 'title') {
                    rows = [SELECT Id, Name, Company__c, Phone, PersonMailingCity, BillingCity FROM Account
                            WHERE Name LIKE :likeTerm AND Type__c = 'Title Agent Account' ORDER BY Name LIMIT 50];
                } else if (kind == 'investor') {
                    rows = [SELECT Id, Name, Company__c, PersonMailingCity, BillingCity FROM Account
                            WHERE Name LIKE :likeTerm AND Type = 'Investor' ORDER BY Name LIMIT 50];
                } else {
                    rows = [SELECT Id, Name, Company__c, PersonMailingCity, BillingCity FROM Account
                            WHERE Name LIKE :likeTerm ORDER BY Name LIMIT 50];
                }
                for (Account a : rows) {
                    String city = a.PersonMailingCity ?? a.BillingCity;
                    String phone = kind == 'title' ? a.Phone : null;
                    add(a.Id, a.Name, joinNonBlank(new List<String>{ a.Company__c, city, phone }), lower, starts, rest);
                }
            }
            starts.addAll(rest);
            List<Map<String, String>> out = new List<Map<String, String>>();
            for (Integer i = 0; i < starts.size() && i < 15; i++) {
                out.add(starts[i]);
            }
            return out;
        }

        void add(Id id, String name, String sub, String lower, List<Map<String, String>> starts, List<Map<String, String>> rest) {
            Map<String, String> row = new Map<String, String>{ 'id' => id, 'name' => name, 'sub' => sub };
            if (name != null && name.toLowerCase().startsWith(lower)) {
                starts.add(row);
            } else {
                rest.add(row);
            }
        }
    }

    /** "+ Add borrower": the same Borrower__c the borrowerPanel creates (user mode, like its LDS call). */
    @AuraEnabled
    public static Borrower__c addBorrower(Id transactionId, String firstName, String lastName, String email, String phone) {
        loadTransaction(transactionId);
        if (String.isBlank(firstName) || String.isBlank(lastName)) {
            throw error('First and last name are required.');
        }
        String first = firstName.trim();
        String last = lastName.trim();
        Borrower__c row = new Borrower__c(
            Transaction__c = transactionId,
            First_Name__c = first,
            Last_Name__c = last,
            Email__c = String.isBlank(email) ? null : email.trim(),
            Phone__c = String.isBlank(phone) ? null : phone.trim(),
            Name = (first + ' ' + last).left(80)
        );
        try {
            Database.insert(row, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw error(e.getMessage());
        }
        return [
            SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Phone__c, Relationship__c, Account__c
            FROM Borrower__c WHERE Id = :row.Id
        ];
    }

    // ---------------------------------------------------------------- submit

    @AuraEnabled
    public static Id submit(Id transactionId, String payloadJson) {
        Transaction__c t = loadTransaction(transactionId);
        String locked = lockedMessage(t);
        if (locked != null) {
            throw error(locked);
        }
        Payload p = new Payload((Map<String, Object>) JSON.deserializeUntyped(payloadJson == null ? '{}' : payloadJson));
        p.applyVisibility();
        List<String> missing = p.missingRequired();
        if (!missing.isEmpty()) {
            throw error('Please complete: ' + String.join(missing, ', ') + '.');
        }

        try {
            // "Can't find my contact" partners first, so the form is inserted once with every lookup set.
            // The flow inserted the form, then created each Account and updated the form; the end state is
            // the same, but here a failed Account rolls everything back instead of being silently skipped.
            Id buyerAgent = p.cantFindBuyer ? insertPerson(p.s('First_Name_BA'), p.s('Last_Name_BA'), p.s('BuyersEmail'), p.s('BuyersCellPhone')) : p.id('BuyersNameLookup');
            Id buyerAssistant = p.cantFindBuyerAsst ? insertPerson(p.s('First_Name_BAA'), p.s('Last_Name_BAA'), p.s('EmailBAA'), p.s('PhoneBAA')) : p.id('Buying_Agent_Assistant');
            Id sellerAgent = p.cantFindSeller ? insertPerson(p.s('First_Name_SA'), p.s('Last_Name_SA'), p.s('SellersEmail'), p.s('SellersCellPhone')) : p.id('SellersNameLookup');
            Id sellerAssistant = p.id('Seller_Agent_Assistant');
            if (p.cantFindSellerAsst) {
                // Listing_Agent_TC__c is a Contact lookup: link the new Person Account's contact.
                Id acct = insertPerson(p.s('First_Name_SAA'), p.s('Last_Name_SAA'), p.s('EmailSAA'), p.s('PhoneSAA'));
                sellerAssistant = [SELECT PersonContactId FROM Account WHERE Id = :acct].PersonContactId;
            }
            Id title = p.id('NameTCLookup');
            if (p.cantFindTitle) {
                // Same as the flow in practice: name only. Its phone/email land on the form's Title_Company_*
                // fields; a Phone on a Business Account is copied to PersonMobilePhone by Account automation and fails.
                Account tc = new Account(
                    Name = p.s('CompanyTC'),
                    RecordTypeId = BUSINESS_ACCOUNT_RT,
                    Type__c = 'Title Agent Account',
                    Exclude_From_Duplicate_Check__c = true
                );
                insert tc;
                title = tc.Id;
            }

            Submission_Form__c f = p.toForm(transactionId);
            f.Buyers_Agent_Lookup__c = buyerAgent;
            f.Buying_Agent_Assistant__c = buyerAssistant;
            f.Sellers_Agent_Lookup__c = sellerAgent;
            f.Listing_Agent_TC__c = sellerAssistant;
            f.Title_Company_Name__c = title;

            // Contact for appraisal entry = seller's agent (decision Check_Contact_Same_As_Listing_Agent).
            if (p.b('Same_as_Listing_Agent')) {
                if (p.cantFindSeller) {
                    f.Appraisal_Contact_Name__c = joinName(p.s('First_Name_SA'), p.s('Last_Name_SA'));
                    f.Appraisal_Contact_Phone__c = p.s('SellersCellPhone');
                    f.Appraisal_Contact_Email__c = p.s('SellersEmail');
                } else if (sellerAgent != null) {
                    Account s = new OrgWide().account(sellerAgent);
                    f.Appraisal_Contact_Name__c = s.Name;
                    f.Appraisal_Contact_Phone__c = s.Phone;
                    f.Appraisal_Contact_Email__c = s.PersonEmail;
                }
            }

            // Picked partners may be accounts the LO can't otherwise see (org-wide pickers, owner decision
            // 2026-10-05), so the form insert must not need sharing on its lookups.
            new OrgWide().insertForm(f);
            syncCoBorrowerRow(transactionId, p);

            // Flow element Create_2nd_DPA_Transaction (MANUAL), after the record-triggered AUTO attempt.
            if (p.s('DPA_Grant') == 'Yes') {
                DpaSecondTransactionInvocable.Request r = new DpaSecondTransactionInvocable.Request();
                r.parentTransactionId = transactionId;
                r.mode = 'MANUAL';
                r.lenderId = p.id('InvestorLookup2nd');
                r.loanAmount2nd = p.d('Loan_Amount_2nd');
                r.loanType2nd = p.s('Loan_Type_2nd');
                r.loanProgram2nd = p.s('Loan_Program_2nd');
                r.rate2nd = p.d('Rate_2nd');
                DpaSecondTransactionInvocable.createSecondTransactions(new List<DpaSecondTransactionInvocable.Request>{ r });
            }

            // Flow element Create_Submission_Form_Event (PublishAfterCommit).
            EventBus.publish(new Submission_Form_Event__e(
                New_Build_Bank_Owned__c = p.s('New_Build_Bank_Owned') == 'Yes',
                Rate_Lock_Exp_Date__c = p.dt('Lock_Date'),
                Rate_Lock_Status__c = p.s('Rate_Lock_Status'),
                Transaction_Id__c = transactionId
            ));
            return f.Id;
        } catch (DmlException e) {
            throw error(e.getDmlMessage(0));
        }
    }


    /**
     * The co-borrower fields were prefilled from a Borrower__c row (CoBorrowerRowId): push the LO's edits
     * back onto that row, changed fields only, Name rebuilt the way borrowerPanel does. Never creates or
     * deletes rows, and blank names are ignored (the row keeps its required first/last name).
     */
    static void syncCoBorrowerRow(Id transactionId, Payload p) {
        Id rowId = p.id('CoBorrowerRowId');
        if (rowId == null) {
            return;
        }
        List<Borrower__c> rows = [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Phone__c
            FROM Borrower__c WHERE Id = :rowId AND Transaction__c = :transactionId AND Removed__c = FALSE
        ];
        if (rows.isEmpty()) {
            return;
        }
        Borrower__c row = rows[0];
        Borrower__c upd = new Borrower__c(Id = row.Id);
        Boolean changed = false;
        String first = p.s('Co_Borrower_First_Name');
        String last = p.s('Co_Borrower_Last_Name');
        String email = p.s('BorrowerCoEmail');
        String phone = p.s('BorrowerCoPhone');
        if (first != null && differs(first, row.First_Name__c)) {
            upd.First_Name__c = first;
            changed = true;
        }
        if (last != null && differs(last, row.Last_Name__c)) {
            upd.Last_Name__c = last;
            changed = true;
        }
        if (upd.First_Name__c != null || upd.Last_Name__c != null) {
            String f = upd.First_Name__c != null ? upd.First_Name__c : row.First_Name__c;
            String l = upd.Last_Name__c != null ? upd.Last_Name__c : row.Last_Name__c;
            List<String> parts = new List<String>();
            for (String part : new List<String>{ f, l }) {
                if (String.isNotBlank(part)) {
                    parts.add(part);
                }
            }
            upd.Name = String.join(parts, ' ').left(80);
        }
        if (differs(email, row.Email__c)) {
            upd.Email__c = email;
            changed = true;
        }
        if (!samePhone(phone, row.Phone__c)) {
            upd.Phone__c = phone;
            changed = true;
        }
        if (changed) {
            update upd;
        }
    }

    // Apex == on Strings ignores case; an LO fixing capitalisation is a real edit.
    static Boolean differs(String a, String b) {
        return a == null ? b != null : !a.equals(b);
    }

    // Phones are reformatted by the org (xxx-xxx-xxxx), so compare digits only.
    static Boolean samePhone(String a, String b) {
        String da = a == null ? '' : a.replaceAll('[^0-9]', '');
        String db = b == null ? '' : b.replaceAll('[^0-9]', '');
        return da == db;
    }

    // --------------------------------------------------------------- payload

    @TestVisible
    class Payload {
        Map<String, Object> v;
        Boolean cantFindBuyer, cantFindBuyerAsst, cantFindSeller, cantFindSellerAsst, cantFindTitle;

        Payload(Map<String, Object> raw) {
            v = raw == null ? new Map<String, Object>() : raw;
        }

        String s(String k) {
            Object o = v.get(k);
            return o == null || String.isBlank(String.valueOf(o)) ? null : String.valueOf(o).trim();
        }
        Boolean b(String k) {
            Object o = v.get(k);
            return o == true || String.valueOf(o) == 'true';
        }
        Id id(String k) {
            String raw = s(k);
            return raw == null ? null : Id.valueOf(raw);
        }
        Decimal d(String k) {
            String raw = s(k);
            return raw == null ? null : Decimal.valueOf(raw);
        }
        Date dt(String k) {
            String raw = s(k);
            return raw == null ? null : Date.valueOf(raw.left(10));
        }
        void hide(Boolean visible, List<String> keys) {
            if (!visible) {
                for (String k : keys) {
                    v.remove(k);
                }
            }
        }

        /** The flow's visibilityRule elements: a hidden field contributes no value. */
        void applyVisibility() {
            Boolean spouses = b('Borrower_and_Co_Borrower_are_spouses');
            hide(!spouses, new List<String>{ 'Borrower_Has_a_Spouse', 'Co_Borrower_Has_a_Spouse' });
            hide(b('Borrower_Has_a_Spouse'), new List<String>{ 'Spouse_Borrower', 'SpousePhoneBorrower', 'SpouseEmailBorrower' });
            hide(b('Co_Borrower_Has_a_Spouse'), new List<String>{ 'Spouse_CoBorrower', 'SpousePhoneCoBorrower', 'SpouseEmailCoBorrower' });

            cantFindBuyer = b('Cant_Find_My_Contact_Buyers');
            hide(!cantFindBuyer, new List<String>{ 'BuyersNameLookup' });
            hide(cantFindBuyer, new List<String>{ 'First_Name_BA', 'Last_Name_BA', 'BuyersCellPhone', 'BuyersEmail' });
            cantFindBuyerAsst = b('Cant_Find_BuyersAgentAssistant');
            hide(!cantFindBuyerAsst, new List<String>{ 'Buying_Agent_Assistant' });
            hide(cantFindBuyerAsst, new List<String>{ 'First_Name_BAA', 'Last_Name_BAA', 'PhoneBAA', 'EmailBAA' });
            cantFindSeller = b('Cant_Find_My_Contact_Sellers');
            hide(!cantFindSeller, new List<String>{ 'SellersNameLookup' });
            hide(cantFindSeller, new List<String>{ 'First_Name_SA', 'Last_Name_SA', 'SellersCellPhone', 'SellersEmail' });
            cantFindSellerAsst = b('Cant_Find_SellersAgentAssistant');
            hide(!cantFindSellerAsst, new List<String>{ 'Seller_Agent_Assistant' });
            hide(cantFindSellerAsst, new List<String>{ 'First_Name_SAA', 'Last_Name_SAA', 'PhoneSAA', 'EmailSAA' });
            cantFindTitle = b('Cant_Find_My_Company');
            hide(!cantFindTitle, new List<String>{ 'NameTCLookup' });
            hide(cantFindTitle, new List<String>{ 'CompanyTC', 'PhoneTC', 'EmailTC' });

            Boolean condo = s('Property_Type') == 'Condo';
            hide(condo, new List<String>{ 'NameHOA', 'CompanyHOA', 'PhoneHOA', 'Condo_Review_Type' });
            hide(!b('Same_as_Listing_Agent'), new List<String>{ 'NameContactForEntry', 'PhoneContactForEntry', 'EmailContactForEntry' });
            hide(s('Loan_Purpose') == 'Refinance', new List<String>{ 'Refinance_Purpose' });
            Boolean buydown = s('Rate_Buydown') == 'Yes';
            hide(buydown, new List<String>{ 'Contributor', 'Buydown' });
            Boolean dpa = s('DPA_Grant') == 'Yes';
            hide(dpa, new List<String>{
                'DPA_Grant_Program_Name', 'DPA_Grant_Number_of_Persons_in_Household', 'DPA_Grant_Household_Income',
                'InvestorLookup2nd', 'Loan_Type_2nd', 'Rate_2nd', 'Loan_Amount_2nd', 'Loan_Program_2nd'
            });
            hide(s('Rate_Lock_Status') == 'Locked', new List<String>{ 'Lock_Date' });
        }

        /** Required fields exactly as the flow marks them (component `required` input or isRequired). */
        List<String> missingRequired() {
            Boolean buyerSellerRequired = s('Loan_Purpose') == 'Purchase' && !b('No_Realtor');
            Map<String, String> req = new Map<String, String>{
                'InvestorLookup' => 'Investor', 'Channel' => 'Channel',
                'Borrower_First_Name' => 'Borrower First Name', 'Borrower_Last_Name' => 'Borrower Last Name',
                'Loan_Purpose' => 'Loan Purpose', 'Loan_Type' => 'Loan Type', 'Occupancy' => 'Occupancy',
                'New_Build_Bank_Owned' => 'New Build/Bank Owned?', 'Program_Type' => 'Program Type',
                'Property_Type' => 'Property Type', 'Appraisal' => 'Appraisal', 'Waiving_Escrow' => 'Waiving Escrow?',
                'Expected_Cash_To_Close' => 'Expected Cash To Close', 'Rate_Buydown' => 'Rate Buydown',
                'DPA_Grant' => 'DPA/Grant', 'Closing' => 'Closing Date', 'Rate_Lock_Status' => 'Rate Lock Status',
                'Income_Multi' => 'Income', 'Assets_Multi' => 'Assets'
            };
            if (s('Loan_Purpose') == 'Refinance') req.put('Refinance_Purpose', 'Refinance Purpose');
            if (s('Property_Type') == 'Condo') {
                req.put('Condo_Review_Type', 'Condo Review Type');
                req.put('NameHOA', 'HOA Name');
                req.put('CompanyHOA', 'HOA Company');
                req.put('PhoneHOA', 'HOA Phone');
            }
            if (buyerSellerRequired) {
                if (cantFindBuyer) {
                    req.putAll(new Map<String, String>{ 'First_Name_BA' => 'Buyer\'s Agent First Name', 'Last_Name_BA' => 'Buyer\'s Agent Last Name', 'BuyersCellPhone' => 'Buyer\'s Agent Cell Phone', 'BuyersEmail' => 'Buyer\'s Agent Email' });
                } else {
                    req.put('BuyersNameLookup', 'Buyer\'s Agent');
                }
                if (cantFindSeller) {
                    req.putAll(new Map<String, String>{ 'First_Name_SA' => 'Seller\'s Agent First Name', 'Last_Name_SA' => 'Seller\'s Agent Last Name', 'SellersCellPhone' => 'Seller\'s Agent Cell Phone', 'SellersEmail' => 'Seller\'s Agent Email' });
                } else {
                    req.put('SellersNameLookup', 'Seller\'s Agent');
                }
            }
            if (cantFindBuyerAsst) {
                req.putAll(new Map<String, String>{ 'First_Name_BAA' => 'Buyer\'s Assistant First Name', 'Last_Name_BAA' => 'Buyer\'s Assistant Last Name', 'PhoneBAA' => 'Buyer\'s Assistant Phone', 'EmailBAA' => 'Buyer\'s Assistant Email' });
            }
            if (cantFindSellerAsst) {
                req.putAll(new Map<String, String>{ 'First_Name_SAA' => 'Seller\'s Assistant First Name', 'Last_Name_SAA' => 'Seller\'s Assistant Last Name', 'PhoneSAA' => 'Seller\'s Assistant Phone', 'EmailSAA' => 'Seller\'s Assistant Email' });
            }
            if (cantFindTitle) {
                req.putAll(new Map<String, String>{ 'CompanyTC' => 'Title Company', 'PhoneTC' => 'Title Phone', 'EmailTC' => 'Title Email' });
            } else {
                req.put('NameTCLookup', 'Title Company');
            }
            if (!b('Same_as_Listing_Agent')) {
                req.putAll(new Map<String, String>{ 'NameContactForEntry' => 'Contact for Entry Name', 'PhoneContactForEntry' => 'Contact for Entry Phone', 'EmailContactForEntry' => 'Contact for Entry Email' });
            }
            if (s('Rate_Buydown') == 'Yes') {
                req.put('Contributor', 'Contributor');
                req.put('Buydown', 'Buydown');
            }
            if (s('DPA_Grant') == 'Yes') {
                req.putAll(new Map<String, String>{ 'DPA_Grant_Program_Name' => 'DPA/Grant Program Name', 'InvestorLookup2nd' => '2nd Investor', 'Loan_Type_2nd' => 'Loan Type 2nd', 'Rate_2nd' => 'Rate 2nd', 'Loan_Amount_2nd' => 'Loan Amount 2nd', 'Loan_Program_2nd' => 'Loan Program 2nd' });
            }
            if (s('Rate_Lock_Status') == 'Locked') req.put('Lock_Date', 'Lock Exp Date');

            List<String> missing = new List<String>();
            for (String k : req.keySet()) {
                if (s(k) == null) {
                    missing.add(req.get(k));
                }
            }
            return missing;
        }

        /** Assign_Values_to_Submission_Form_1..6 plus the ObjectProvided Intentions field. */
        Submission_Form__c toForm(Id transactionId) {
            Boolean spouses = b('Borrower_and_Co_Borrower_are_spouses');
            return new Submission_Form__c(
                RecordTypeId = FORM_RT,
                Transaction__c = transactionId,
                Name = 'Submission Form',
                Investor_Lookup__c = id('InvestorLookup'),
                Channel__c = s('Channel'),
                Borrower_and_Co_Borrower_Spouses__c = spouses,
                Borrower_First_Name__c = s('Borrower_First_Name'),
                Borrower_Last_Name__c = s('Borrower_Last_Name'),
                Co_Borrower_First_Name__c = s('Co_Borrower_First_Name'),
                Co_Borrower_Last_Name__c = s('Co_Borrower_Last_Name'),
                Co_Borrower_Email__c = s('BorrowerCoEmail'),
                Borrower_Has_Spouse__c = b('Borrower_Has_a_Spouse'),
                Co_Borrower_Has_Spouse__c = b('Co_Borrower_Has_a_Spouse'),
                Borrower_Spouse_Name__c = s('Spouse_Borrower'),
                Co_Borrower_Spouse_Name__c = s('Spouse_CoBorrower'),
                Co_Borrower_Phone__c = s('BorrowerCoPhone'),
                Borrower_Spouse_Phone__c = s('SpousePhoneBorrower'),
                Co_Borrower_Spouse_Phone__c = s('SpousePhoneCoBorrower'),
                Borrower_Spouse_Email__c = s('SpouseEmailBorrower'),
                Co_Borrower_Spouse_Email__c = s('SpouseEmailCoBorrower'),
                Speaks_Spanish_Only__c = b('Speaks_Spanish_Only'),
                Buyers_Phone__c = s('BuyersCellPhone'),
                Buyers_Email__c = s('BuyersEmail'),
                Sellers_Phone__c = s('SellersCellPhone'),
                Sellers_Email__c = s('SellersEmail'),
                Title_Company__c = s('CompanyTC'),
                Title_Company_Phone__c = s('PhoneTC'),
                Title_Company_Email__c = s('EmailTC'),
                HOA_Name__c = s('NameHOA'),
                HOA_Company__c = s('CompanyHOA'),
                HOA_Phone__c = s('PhoneHOA'),
                Appraisal_Contact_Name__c = s('NameContactForEntry'),
                Appraisal_Contact_Phone__c = s('PhoneContactForEntry'),
                Appraisal_Contact_Email__c = s('EmailContactForEntry'),
                Loan_Purpose__c = s('Loan_Purpose'),
                Refinance_Purpose__c = s('Refinance_Purpose'),
                Occupancy__c = s('Occupancy'),
                Loan_Program__c = s('Program_Type'),
                Property_Type__c = s('Property_Type'),
                DU_LP_Manual__c = s('DU_LP_MANUAL'),
                Condo_Review_Type__c = s('Condo_Review_Type'),
                PIW__c = s('Appraisal'),
                Waiving_Escrow__c = s('Waiving_Escrow'),
                Loan_Type__c = s('Loan_Type'),
                Contributor__c = s('Contributor'),
                Buydown__c = s('Buydown'),
                Rate_Buydown__c = s('Rate_Buydown'),
                Appraisal__c = s('Appraisal'),
                New_Build_Bank_Owned__c = s('New_Build_Bank_Owned'),
                Expected_Funds_to_Close__c = d('Expected_Cash_To_Close'),
                DPA_Grant__c = s('DPA_Grant'),
                Commitment__c = dt('Commitment'),
                Closing__c = dt('Closing'),
                Rate_lock__c = s('Rate_Lock_Status'),
                Lock_Exp_Date__c = dt('Lock_Date'),
                General_Notes_Description__c = s('General_Notes'),
                Needs_List_Description__c = s('Needs_List'),
                DPA_Grant_Program_Name__c = s('DPA_Grant_Program_Name'),
                DPA_Grant_Number_of_Persons_in_Household__c = s('DPA_Grant_Number_of_Persons_in_Household'),
                DPA_Grant_Household_Income__c = s('DPA_Grant_Household_Income'),
                Income_4506T_Multi__c = s('Income_Multi'),
                Source_of_Funds_to_Close_Multi__c = s('Assets_Multi'),
                Credit_Description__c = s('Credit'),
                Intentions_for_Current_Home__c = s('Intentions_for_Current_Home')
            );
        }
    }

    // --------------------------------------------------------------- helpers

    static Transaction__c loadTransaction(Id transactionId) {
        // with sharing: a loan the user cannot see is refused, as the flow's Get_Transaction would find nothing.
        List<Transaction__c> rows = [
            SELECT Id, Name, Status__c, Disclosures_Out_Date__c,
                Lender_lookup__c, Lender_lookup__r.Name, Channel__c, Loan_Purpose__c, Refinance_Purpose_Picklist__c,
                Loan_Type_1st_TD__c, Occupancy__c, New_Build_Bank_Owned__c, Loan_Program_1st__c, Property_Type__c,
                Appraisal__c, Expected_Cash_To_Close__c, Rate_Buydown__c, Contributor__c, Buydown__c, DPA__c,
                DPA_Grant_Program_Name__c, Loan_Commitment_Date__c, Closing_Date__c, Rate_Lock_Status__c,
                Rate_Lock_Exp_Date__c, Conditions_Needed__c,
                Realtor_Buying_Agent__c, Realtor_Buying_Agent__r.Name, Realtor_Listing_Agent__c, Realtor_Listing_Agent__r.Name,
                Title_Agent__c, Title_Agent__r.Name, Buying_Agent_Assistant__c, Buying_Agent_Assistant__r.Name,
                Listing_Agent_TC__c, Listing_Agent_TC__r.Name,
                Borrower_Name__c, Borrower_Name__r.FirstName, Borrower_Name__r.LastName,
                Borrower_Name__r.First_Name_Co_Borrower__pc, Borrower_Name__r.Last_Name_Co_Borrower__pc,
                Borrower_Name__r.Mobile_Co_Borrower__pc, Borrower_Name__r.Email_Co_Borrower__pc,
                Borrower_Name__r.Borrower_and_Co_Borrower_Spouses__pc, Borrower_Name__r.Borrower_Has_Spouse__pc,
                Borrower_Name__r.Borrower_Spouse_Name__pc, Borrower_Name__r.Borrower_Spouse_Phone__pc,
                Borrower_Name__r.Borrower_Spouse_Email__pc, Borrower_Name__r.Co_Borrower_Has_Spouse__pc,
                Borrower_Name__r.Co_Borrower_Spouse_Name__pc, Borrower_Name__r.Co_Borrower_Spouse_Phone__pc,
                Borrower_Name__r.Co_Borrower_Spouse_Email__pc,
                Second_Mortgage__c, Second_Mortgage__r.Lender_lookup__c, Second_Mortgage__r.Lender_lookup__r.Name,
                Second_Mortgage__r.Loan_Amount_1st__c, Second_Mortgage__r.Loan_Type_1st_TD__c,
                Second_Mortgage__r.Loan_Program_1st__c, Second_Mortgage__r.Rate_1st_TD__c
            FROM Transaction__c
            WHERE Id = :transactionId
        ];
        if (rows.isEmpty()) {
            throw error('You do not have access to this loan.');
        }
        return rows[0];
    }

    static Submission_Form__c latestForm(Id transactionId) {
        List<Submission_Form__c> rows = [
            SELECT Condo_Review_Type__c, Waiving_Escrow__c, DU_LP_Manual__c, Speaks_Spanish_Only__c,
                HOA_Name__c, HOA_Company__c, HOA_Phone__c, Appraisal_Contact_Name__c, Appraisal_Contact_Phone__c,
                Appraisal_Contact_Email__c, DPA_Grant_Number_of_Persons_in_Household__c, DPA_Grant_Household_Income__c,
                General_Notes_Description__c, Credit_Description__c, Income_4506T_Multi__c,
                Source_of_Funds_to_Close_Multi__c, Intentions_for_Current_Home__c
            FROM Submission_Form__c
            WHERE Transaction__c = :transactionId AND RecordTypeId = :FORM_RT
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /** Mirrors VR Submission_Form__c.Form_Not_Editable_If_Status_Inproper (the edit window). */
    @TestVisible
    static String lockedMessage(Transaction__c t) {
        User u = [SELECT Username, Profile.Name, UserRole.Name FROM User WHERE Id = :UserInfo.getUserId()];
        String profile = profileOverride != null ? profileOverride : u.Profile.Name;
        String role = profileOverride != null ? null : u.UserRole?.Name;
        if (profile == 'System Administrator') {
            return null;
        }
        if (profile == 'Loan Officer Profile (Read Only)') {
            return LOCKED_MESSAGE;
        }
        Boolean exempt = profile == 'Processor Profile' || profile == 'Processor Profile (SF)' || role == 'Processors and Closers';
        if (t.Disclosures_Out_Date__c != null && (u.Username == 'joey@reachhomeloans.com' || !exempt)) {
            return LOCKED_MESSAGE;
        }
        return null;
    }

    static Id insertPerson(String first, String last, String email, String phone) {
        Account a = new Account(
            FirstName = first,
            LastName = last,
            PersonEmail = email,
            Phone = phone,
            RecordTypeId = PERSON_ACCOUNT_RT,
            Type__c = 'Realtor Account',
            Exclude_From_Duplicate_Check__c = true
        );
        insert a;
        return a.Id;
    }

    /** Choice sets the flow used, from the same picklist fields (static choices inline). */
    static Map<String, Object> options() {
        return new Map<String, Object>{
            'Channel' => choices(new List<String>{ 'Broker', 'Correspondent' }),
            'Loan_Purpose' => picklist(Transaction__c.Loan_Purpose__c),
            'Refinance_Purpose' => picklist(Submission_Form__c.Refinance_Purpose__c),
            'Loan_Type' => picklist(Transaction__c.Loan_Type_1st_TD__c),
            'Occupancy' => picklist(Transaction__c.Occupancy__c),
            'New_Build_Bank_Owned' => picklist(Submission_Form__c.New_Build_Bank_Owned__c),
            'Program_Type' => picklist(Transaction__c.Loan_Program_1st__c),
            'Property_Type' => picklist(Transaction__c.Property_Type__c),
            'Condo_Review_Type' => choices(new List<String>{ 'Full Review', 'Limited Review', 'Non-Warrantable' }),
            'Appraisal' => choices(new List<String>{ 'Needed', 'PIW', 'ACE + PDR/PDI', 'Not Required' }),
            'YesNo' => choices(new List<String>{ 'Yes', 'No' }),
            'DU_LP_MANUAL' => picklist(Submission_Form__c.DU_LP_Manual__c),
            'Contributor' => picklist(Transaction__c.Contributor__c),
            'Buydown' => picklist(Transaction__c.Buydown__c),
            'Rate_Lock_Status' => picklist(Transaction__c.Rate_Lock_Status__c),
            'Income_Multi' => picklist(Submission_Form__c.Income_4506T_Multi__c),
            'Assets_Multi' => picklist(Submission_Form__c.Source_of_Funds_to_Close_Multi__c),
            'Intentions_for_Current_Home' => picklist(Submission_Form__c.Intentions_for_Current_Home__c)
        };
    }

    static List<Map<String, String>> picklist(Schema.SObjectField field) {
        List<Map<String, String>> out = new List<Map<String, String>>();
        for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                out.add(new Map<String, String>{ 'label' => e.getLabel(), 'value' => e.getValue() });
            }
        }
        return out;
    }

    static List<Map<String, String>> choices(List<String> values) {
        List<Map<String, String>> out = new List<Map<String, String>>();
        for (String s : values) {
            out.add(new Map<String, String>{ 'label' => s, 'value' => s });
        }
        return out;
    }

    /** Transaction checkbox -> the form's Yes/No. False only means "No" once a form has been filed. */
    static String yesNo(Boolean value, Boolean hasPrevious) {
        return value == true ? 'Yes' : (hasPrevious ? 'No' : null);
    }

    static void putId(Map<String, Object> v, Map<String, String> labels, String key, Id value, String label) {
        v.put(key, value);
        if (value != null) {
            labels.put(key, label);
        }
    }

    static String joinName(String first, String last) {
        return String.join(new List<String>{ first == null ? '' : first, last == null ? '' : last }, ' ').trim();
    }

    static String joinNonBlank(List<String> parts) {
        List<String> kept = new List<String>();
        for (String p : parts) {
            if (String.isNotBlank(p)) {
                kept.add(p);
            }
        }
        return String.join(kept, ' · ');
    }

    static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}