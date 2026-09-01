@IsTest
private class LeadPreApprovalLetterTest {

    @IsTest
    static void contextCarriesTermsPicklistsAndSigners() {
        Lead leadRecord = createLead();

        Test.startTest();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);
        Test.stopTest();

        System.assertEquals('Javine Roman', context.borrowerName);
        System.assertNotEquals(0, context.financingOptions.size(), 'Financing comes from the Lead picklist.');
        System.assertNotEquals(0, context.propertyOptions.size(), 'Property type comes from the Lead picklist.');
        System.assertNotEquals(0, context.signerOptions.size(), 'There is always at least the Lead Owner to sign.');
        System.assertNotEquals(null, context.defaultSignerId);
    }

    @IsTest
    static void generatingSavesTheTermsBackToTheLead() {
        Lead leadRecord = createLead();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id,
            795000,
            675750,
            'Conventional',
            'Single Family',
            null,
            'Most recent 12 months of bank statements\nCredit history',
            context.defaultSignerId
        );
        Test.stopTest();

        Lead saved = [
            SELECT Purchase_Price__c, Loan_Amount__c, Loan_Type_1st_TD__c, Property_Type__c,
                   Reviewed_Documents__c, LTV__c
            FROM Lead WHERE Id = :leadRecord.Id
        ];

        System.assertEquals(795000, saved.Purchase_Price__c, 'The letter and the record must agree.');
        System.assertEquals(675750, saved.Loan_Amount__c);
        System.assertEquals('Conventional', saved.Loan_Type_1st_TD__c);
        System.assertEquals('Single Family', saved.Property_Type__c);
        System.assertEquals(85.00, saved.LTV__c, 'LTV is derived rather than typed.');

        System.assertEquals(true, html.contains('Javine Roman is pre-approved for mortgage financing.'));
        System.assertEquals(true, html.contains('$795,000'));
        System.assertEquals(true, html.contains('85.00% LTV'));
        System.assertEquals(true, html.contains('DOCUMENTATION REVIEWED'));
        System.assertEquals(true, html.contains('Credit history'), 'Each typed line becomes a ticked item.');
    }

    @IsTest
    static void letterOmitsTheDocsSectionWhenNothingWasReviewed() {
        Lead leadRecord = createLead();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 500000, 400000, 'FHA', 'Condo', null, '   ', context.defaultSignerId
        );
        Test.stopTest();

        System.assertEquals(false, html.contains('DOCUMENTATION REVIEWED'),
            'An empty docs box should not leave a bare heading on the letter.');
    }

    @IsTest
    static void finalizingStoresTheLetterAndMovesTheLead() {
        Lead leadRecord = createLead();
        // Pre-Approval is gated by a validation rule needing the loan amount. In the real flow the
        // terms are always saved before Finalize is reachable, so the test mirrors that order.
        update new Lead(Id = leadRecord.Id, Purchase_Price__c = 795000, Loan_Amount__c = 675750);
        String edited = '<p>Edited by the Loan Officer</p>';

        Test.startTest();
        LeadPreApprovalLetterController.FinalizeResult result =
            LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, edited);
        Test.stopTest();

        Lead saved = [
            SELECT Status, Letter_Completed__c, Pre_Approval_Letter_HTML__c
            FROM Lead WHERE Id = :leadRecord.Id
        ];

        System.assertEquals(edited, saved.Pre_Approval_Letter_HTML__c,
            'The PDF renders exactly what was on screen, edits included.');
        System.assertEquals('Pre-Approval', saved.Status);
        System.assertEquals(true, saved.Letter_Completed__c);
        System.assertEquals(true, result.pdfPath.contains('Lead_Pre_Approval_Letter'));
        System.assertEquals(true, result.statusMoved, 'A Lead with terms on it should advance.');
    }

    @IsTest
    static void finalizingRejectsAnEmptyLetter() {
        Lead leadRecord = createLead();
        Boolean rejected = false;

        Test.startTest();
        try {
            LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, '');
        } catch (Exception expected) {
            rejected = true;
        }
        Test.stopTest();

        System.assertEquals(true, rejected);
        System.assertNotEquals(
            'Pre-Approval',
            [SELECT Status FROM Lead WHERE Id = :leadRecord.Id].Status,
            'A failed finalize must not advance the Lead.'
        );
    }

    @IsTest
    static void pdfPageRendersStoredHtmlAndSaysSoWhenThereIsNone() {
        Lead leadRecord = createLead();

        Test.startTest();
        ApexPages.StandardController emptyController = new ApexPages.StandardController(leadRecord);
        String beforeFinalize = new LeadPreApprovalLetterPdfExtension(emptyController).getLetterHtml();

        LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, '<p>Final letter</p>');
        ApexPages.StandardController controller = new ApexPages.StandardController(
            [SELECT Id FROM Lead WHERE Id = :leadRecord.Id]
        );
        String afterFinalize = new LeadPreApprovalLetterPdfExtension(controller).getLetterHtml();
        Test.stopTest();

        System.assertEquals(true, beforeFinalize.contains('No pre-approval letter has been finalized'));
        System.assertEquals('<p>Final letter</p>', afterFinalize);
    }


    @IsTest
    static void nonQmPrintsItsProgrammeHyphenatedAfterTheFinancing() {
        Lead leadRecord = createLead();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 900000, 630000, 'NON-QM', 'Single Family', 'DSCR', 'Credit history',
            context.defaultSignerId
        );
        Test.stopTest();

        System.assertEquals(true, html.contains('Non-QM - DSCR'),
            'The letter prints the programme after the financing type.');
        System.assertEquals(
            'DSCR',
            [SELECT Non_QM_Type__c FROM Lead WHERE Id = :leadRecord.Id].Non_QM_Type__c
        );
    }

    @IsTest
    static void switchingAwayFromNonQmClearsTheProgramme() {
        Lead leadRecord = createLead();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);
        LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 900000, 630000, 'NON-QM', 'Single Family', 'ITIN', '', context.defaultSignerId
        );

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 900000, 630000, 'Conventional', 'Single Family', 'ITIN', '',
            context.defaultSignerId
        );
        Test.stopTest();

        System.assertEquals(
            null,
            [SELECT Non_QM_Type__c FROM Lead WHERE Id = :leadRecord.Id].Non_QM_Type__c,
            'A programme must not survive a change of financing type.'
        );
        System.assertEquals(false, html.contains('ITIN'), 'Nor appear on the letter afterwards.');
    }
    private static Lead createLead() {
        Lead leadRecord = new Lead(
            FirstName = 'Javine',
            LastName = 'Roman',
            Company = 'Pre-Approval Letter Test',
            Status = 'New',
            Email = 'javine.roman@example.com'
        );
        insert leadRecord;
        return leadRecord;
    }
}
