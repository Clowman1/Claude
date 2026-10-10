@IsTest
private class LeadRecycleServiceTest {

    /** A converted original lead (converted the way the TRID flow does it) and a live purchase loan for its borrower. */
    private static Transaction__c purchaseLoan(Decimal leadAmount, Decimal loanAmount) {
        RecordType consumer = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name LIKE '%Consumer%' LIMIT 1];
        Lead original = new Lead(
            RecordTypeId = consumer.Id,
            FirstName = 'Recycle',
            LastName = 'Borrower',
            Email = 'recycle.borrower@example.com',
            Loan_Amount__c = leadAmount,
            Pre_Approval_Date__c = Date.today().addDays(-60),
            AriveId__c = 'ARIVE-RECYCLE-1'
        );
        insert original;
        ConvertLeadsInvocable.convertLeads(new List<Id>{ original.Id });
        Id accountId = [SELECT ConvertedAccountId FROM Lead WHERE Id = :original.Id].ConvertedAccountId;

        Transaction__c t = new Transaction__c(
            Name = 'Recycle Loan',
            Borrower_Name__c = accountId,
            Loan_Officer__c = UserInfo.getUserId(),
            Loan_Purpose__c = 'Purchase',
            Status__c = 'Submitted',
            Loan_Amount_1st__c = loanAmount,
            Loan_Commitment_Date__c = Date.today().addDays(30) // validation Loan_Cmmtmnt_date_required
        );
        insert t;
        return t;
    }

    private static void cancel(Transaction__c t, String borrowerReason) {
        update new Transaction__c(
            Id = t.Id,
            Status__c = 'Cancelled',
            Withdrawn_Reason__c = 'App Withdrawn By Borrower',
            Borrower_Withdrawal_Reason__c = borrowerReason
        );
    }

    private static List<Lead> recycledFrom(Id loanId) {
        return [
            SELECT Id, Status, OwnerId, Loan_Amount__c, Pre_Approval_Date__c, AriveId__c, Arive_Status__c,
                   Converted_Transaction_ID__c, Is_Recycled__c, Recycle_Reactivated_At__c, IsConverted, ConvertedAccountId
            FROM Lead WHERE Recycled_From_Transaction__c = :loanId
        ];
    }

    @IsTest
    static void cancelledPurchaseComesBackAsAPreApprovalLead() {
        Transaction__c t = purchaseLoan(410000, 400000);
        Test.startTest();
        cancel(t, 'Chose to Purchase a Different Property');
        Test.stopTest();

        List<Lead> recycled = recycledFrom(t.Id);
        System.assertEquals(1, recycled.size(), 'One lead per cancelled loan.');
        Lead l = recycled[0];
        System.assertEquals('Pre-Approval', l.Status);
        System.assertEquals(UserInfo.getUserId(), l.OwnerId, 'Owned by the loan\'s LO.');
        System.assertEquals(410000, l.Loan_Amount__c, 'The original lead\'s amount wins.');
        System.assertEquals(Date.today().addDays(-60), l.Pre_Approval_Date__c, 'Q37: original pre-approval date kept.');
        System.assertEquals('ARIVE-RECYCLE-1', l.AriveId__c, 'The ARIVE link stays.');
        System.assertEquals(null, l.Arive_Status__c, 'Never copied: it would re-run the TRID auto-convert.');
        System.assertEquals(true, l.Is_Recycled__c);
        System.assertEquals(1, [SELECT COUNT() FROM Enhanced_Note__c WHERE Lead__c = :l.Id], 'One explanatory note.');

        // Idempotent: a later reason edit on the same cancelled loan doesn't recycle twice.
        update new Transaction__c(Id = t.Id, Borrower_Withdrawal_Reason__c = 'Costs Are Too High');
        System.assertEquals(1, recycledFrom(t.Id).size());
    }

    @IsTest
    static void lenderSwitchIsNotRecycled() {
        Transaction__c t = purchaseLoan(410000, 400000);
        Test.startTest();
        cancel(t, 'Selected an Alternative Lender');
        Test.stopTest();
        System.assertEquals(0, recycledFrom(t.Id).size());
    }

    @IsTest
    static void noAmountAnywhereGoesToNurturePreapproval() {
        Transaction__c t = purchaseLoan(null, null);
        Test.startTest();
        cancel(t, 'Costs Are Too High');
        Test.stopTest();
        List<Lead> recycled = recycledFrom(t.Id);
        System.assertEquals(1, recycled.size());
        System.assertEquals('Nurture - Preapproval', recycled[0].Status, 'Q32');
    }

    @IsTest
    static void loanAmountFallsBackToTheCancelledLoan() {
        Transaction__c t = purchaseLoan(null, 333000);
        Test.startTest();
        cancel(t, 'Other');
        Test.stopTest();
        Lead l = recycledFrom(t.Id)[0];
        System.assertEquals(333000, l.Loan_Amount__c);
        System.assertEquals('Pre-Approval', l.Status);
    }

    @IsTest
    static void reactivatedLoanMovesTheRecycledLeadToNurturing() {
        Transaction__c t = purchaseLoan(410000, 400000);
        Test.startTest();
        cancel(t, 'Chose to Purchase a Different Property');
        Test.stopTest();
        update new Transaction__c(Id = t.Id, Status__c = 'Submitted');
        Lead l = recycledFrom(t.Id)[0];
        System.assertEquals('Nurturing', l.Status, 'Q34');
        System.assertNotEquals(null, l.Recycle_Reactivated_At__c);
    }

    @IsTest
    static void recycledLeadConvertsBackIntoTheSameAccount() {
        Transaction__c t = purchaseLoan(410000, 400000);
        Test.startTest();
        cancel(t, 'Chose to Purchase a Different Property');
        Test.stopTest();
        Lead l = recycledFrom(t.Id)[0];
        Id borrower = [SELECT Borrower_Name__c FROM Transaction__c WHERE Id = :t.Id].Borrower_Name__c;

        // The standard Convert path without picking the account is refused...
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l.Id);
        lc.setConvertedStatus(Label.Consumer_Lead_Process);
        String outcome = 'converted';
        try {
            // As if the user clicked past the duplicate prompt on the Convert screen.
            Database.DMLOptions allowDupes = new Database.DMLOptions();
            allowDupes.duplicateRuleHeader.allowSave = true;
            Database.LeadConvertResult res = Database.convertLead(new List<Database.LeadConvert>{ lc }, allowDupes)[0];
            if (!res.isSuccess()) {
                outcome = res.getErrors()[0].getMessage();
            }
        } catch (Exception e) {
            outcome = e.getMessage();
        }
        System.assert(outcome.contains('cancelled loan'), 'A recycled lead may not convert into a new account: ' + outcome);

        // ...while the invocable (TRID flow / LO Workspace / Convert screen flow) uses the borrower's account.
        ConvertLeadsInvocable.convertLeads(new List<Id>{ l.Id });
        System.assertEquals(borrower, recycledFrom(t.Id)[0].ConvertedAccountId, 'Q25: no duplicate account.');
    }

    @IsTest
    static void qualifyRules() {
        Transaction__c ok = new Transaction__c(Loan_Purpose__c = 'Purchase',
            Borrower_Withdrawal_Reason__c = 'Other', Withdrawn_Reason__c = 'App Withdrawn By Borrower');
        System.assert(LeadRecycleService.qualifies(ok));
        System.assert(!LeadRecycleService.qualifies(new Transaction__c(Loan_Purpose__c = 'Refinance',
            Borrower_Withdrawal_Reason__c = 'Other')), 'Purchase only');
        System.assert(!LeadRecycleService.qualifies(new Transaction__c(Loan_Purpose__c = 'Purchase')), 'Blank reason');
        System.assert(!LeadRecycleService.qualifies(new Transaction__c(Loan_Purpose__c = 'Purchase',
            Borrower_Withdrawal_Reason__c = 'Found a More Competetive Interest Rate')));
        System.assert(!LeadRecycleService.qualifies(new Transaction__c(Loan_Purpose__c = 'Purchase',
            Borrower_Withdrawal_Reason__c = 'Other', Withdrawn_Reason__c = 'App Denied')), 'Denial');
        System.assert(!LeadRecycleService.qualifies(new Transaction__c(Loan_Purpose__c = 'Purchase',
            Loan_Type_1st_TD__c = 'DPA 2nd', Borrower_Withdrawal_Reason__c = 'Other')), 'DPA 2nd');
    }
}
