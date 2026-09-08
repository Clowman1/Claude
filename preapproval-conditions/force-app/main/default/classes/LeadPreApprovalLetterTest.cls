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
        System.assertEquals(true, html.contains('To whom it may concern:'));
        System.assertEquals(true, html.contains('Desktop Underwriter (DU) and/or Loan Prospector (LP)'));
        System.assertEquals(false, html.contains('FINANCING QUALIFICATION'),
            'The banner strapline was removed.');
        System.assertEquals(true, html.contains('/resource/Reach_Logo'), 'The real logo, not typed text.');
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
    static void finalizingStoresTheLetterAndLeavesTheStatusAlone() {
        Lead leadRecord = createLead();
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
        System.assertEquals(true, saved.Letter_Completed__c, 'A letter was produced.');
        System.assertEquals(true, result.pdfPath.contains('Lead_Pre_Approval_Letter'));
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
        System.assertEquals(
            null,
            [SELECT Pre_Approval_Letter_HTML__c FROM Lead WHERE Id = :leadRecord.Id].Pre_Approval_Letter_HTML__c,
            'A failed finalize must not leave a half-written letter behind.'
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
    // A Lead the letter is actually allowed to be issued for: already in Pre-Approval, which is
    // where logging a call puts it.
    @IsTest
    static void theLetterIsRefusedUntilTheLeadReachesPreApproval() {
        Lead leadRecord = createLead('Documents Requested');
        Boolean contextRefused = false;
        Boolean generateRefused = false;
        String message = '';

        Test.startTest();
        try {
            LeadPreApprovalLetterController.getContext(leadRecord.Id);
        } catch (Exception expected) {
            contextRefused = true;
        }
        // Asserted against the guard itself: an AuraHandledException reports only
        // "Script-thrown exception" to getMessage() in a test, though LWC does receive the real
        // text through error.body.message.
        try {
            LeadPreApprovalLetterController.ensurePreApprovalStatus(leadRecord);
        } catch (Exception expected) {
            message = expected.getMessage();
        }
        try {
            LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
                leadRecord.Id, 795000, 675750, 'Conventional', 'Single Family', null, '', null
            );
        } catch (Exception expected) {
            generateRefused = true;
        }
        Test.stopTest();

        System.assertEquals(true, contextRefused, 'Opening the modal is refused outright.');
        System.assertEquals(true, generateRefused,
            'And again on generate, in case the status changed while the modal sat open.');
        System.assertEquals(true, message.contains('log a call'),
            'The message has to tell the Loan Officer what to do about it.');
    }

    private static Lead createLead() {
        Lead leadRecord = createLead('Pre-Approval');
        return leadRecord;
    }

    private static Lead createLead(String status) {
        Lead leadRecord = new Lead(
            FirstName = 'Javine',
            LastName = 'Roman',
            Company = 'Pre-Approval Letter Test',
            Status = 'New',
            Email = 'javine.roman@example.com',
            Purchase_Price__c = 795000,
            Loan_Amount__c = 675750
        );
        insert leadRecord;
        if (status != 'New') {
            update new Lead(Id = leadRecord.Id, Status = status);
        }
        return [
            SELECT Id, FirstName, LastName, Status FROM Lead WHERE Id = :leadRecord.Id
        ];
    }
}
