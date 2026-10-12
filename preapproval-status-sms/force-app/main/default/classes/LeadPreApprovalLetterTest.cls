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
            context.defaultSignerId, null
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
        System.assertEquals(false, html.contains('do not materially change prior to closing'),
            'The QUALIFICATION REVIEW section already says this; it is not said twice.');
        System.assertEquals(false, html.contains('FINANCING QUALIFICATION'),
            'The banner strapline was removed.');
        System.assertEquals(true, html.contains('/resource/Reach_Logo'), 'The real logo, not typed text.');
        System.assertEquals(true, html.contains('$795,000'));
        System.assertEquals(true, html.contains('85.00% LTV'));
        System.assertEquals(true, html.contains('DOCUMENTATION REVIEWED'));
        System.assertEquals(true, html.contains('Credit history'), 'Each typed line becomes a ticked item.');
    }

    @IsTest
    static void exactAddressReplacesPropertyTypeOnTheLetter() {
        Lead leadRecord = createLead();
        update new Lead(Id = leadRecord.Id, Property_Type__c = 'Condo',
            Subject_Property_Street__c = '1 Main St', Subject_Property_City__c = 'Boca Raton', Subject_Property_Zip__c = '33432');
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);
        System.assert(context.propertyAddress.startsWith('1 Main St, Boca Raton'), context.propertyAddress);

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 500000, 400000, 'FHA', 'Single Family', null, '', context.defaultSignerId, '9 Ocean Dr <Unit 2>'
        );
        Test.stopTest();

        System.assert(html.contains('PROPERTY ADDRESS'));
        System.assert(html.contains('9 Ocean Dr &lt;Unit 2&gt;'), 'The typed address is escaped onto the letter.');
        System.assert(!html.contains('PROPERTY TYPE'));
        System.assertEquals('Condo', [SELECT Property_Type__c FROM Lead WHERE Id = :leadRecord.Id].Property_Type__c,
            'Choosing an address leaves the Lead property type alone.');
    }

    @IsTest
    static void letterOmitsTheDocsSectionWhenNothingWasReviewed() {
        Lead leadRecord = createLead();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 500000, 400000, 'FHA', 'Condo', null, '   ', context.defaultSignerId, null
        );
        Test.stopTest();

        System.assertEquals(false, html.contains('DOCUMENTATION REVIEWED'),
            'An empty docs box should not leave a bare heading on the letter.');
    }

    @IsTest
    static void finalizingStoresTheLetter() {
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
            context.defaultSignerId, null
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
            leadRecord.Id, 900000, 630000, 'NON-QM', 'Single Family', 'ITIN', '', context.defaultSignerId, null
        );

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 900000, 630000, 'Conventional', 'Single Family', 'ITIN', '',
            context.defaultSignerId, null
        );
        Test.stopTest();

        System.assertEquals(
            null,
            [SELECT Non_QM_Type__c FROM Lead WHERE Id = :leadRecord.Id].Non_QM_Type__c,
            'A programme must not survive a change of financing type.'
        );
        System.assertEquals(false, html.contains('ITIN'), 'Nor appear on the letter afterwards.');
    }
    // Owner rule 2026-10-12: no status is needed to issue a letter, and finalizing it is what
    // moves the Lead to Pre-Approval.
    @IsTest
    static void anEarlyLeadGetsALetterAndFinalizingMovesItToPreApproval() {
        Lead leadRecord = createLead('Documents Requested');

        Test.startTest();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);
        LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 795000, 675750, 'Conventional', 'Single Family', null, '', context.defaultSignerId, null
        );
        LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, '<p>Body</p>');
        Test.stopTest();

        System.assertEquals('Pre-Approval', [SELECT Status FROM Lead WHERE Id = :leadRecord.Id].Status);
    }

    // Co-borrowers live on Borrower__c against the Lead; the primary borrower is never one of
    // those rows, so the Lead always leads the list.
    @IsTest
    static void theLetterNamesEveryApplicantAndReadsAsASentence() {
        Lead leadRecord = createLead();
        insert new List<Borrower__c>{
            new Borrower__c(Lead__c = leadRecord.Id, First_Name__c = 'Testina', Last_Name__c = 'Testiana'),
            new Borrower__c(Lead__c = leadRecord.Id, First_Name__c = 'Testerillo', Last_Name__c = 'Testiana'),
            // Taken off the lead, so it must be off the letter too.
            new Borrower__c(Lead__c = leadRecord.Id, First_Name__c = 'Removed', Last_Name__c = 'Person', Removed__c = true)
        };
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 795000, 675750, 'Conventional', 'Single Family', null, 'Credit history',
            context.defaultSignerId, null
        );
        Test.stopTest();

        System.assertEquals(true, html.contains('Javine Roman, Testina Testiana and Testerillo Testiana'),
            'Every applicant is named, joined so it can be read aloud.');
        System.assertEquals(true, html.contains('are pre-approved for mortgage financing'),
            'Three applicants take a plural verb.');
        System.assertEquals(true, html.contains('APPLICANTS'), 'And the label follows suit.');
        System.assertEquals(false, html.contains('Removed Person'),
            'A co-borrower taken off the lead is off the letter.');
    }

    @IsTest
    static void oneApplicantStillReadsInTheSingular() {
        Lead leadRecord = createLead();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 500000, 400000, 'FHA', 'Condo', null, 'Credit history', context.defaultSignerId, null
        );
        Test.stopTest();

        System.assertEquals(true, html.contains('Javine Roman is pre-approved'));
        System.assertEquals(true, html.contains('APPLICANT<'), 'Singular label for a single applicant.');
    }

    // The PDF renderer has no glyph for the Unicode check, so the letter carries both marks and
    // each medium hides the one it cannot draw.
    @IsTest
    static void reviewedItemsCarryACheckThePdfCanDraw() {
        Lead leadRecord = createLead();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);

        Test.startTest();
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 500000, 400000, 'FHA', 'Condo', null, 'Bank statements', context.defaultSignerId, null
        );
        Test.stopTest();

        System.assertEquals(true, html.contains('/resource/Reviewed_Check'),
            'An image, not a glyph: the PDF fonts hold no check mark, so a character just vanishes.');
    }

    // The PDF bytes travel back with the finalize call so the browser can save the file without
    // opening a tab. getContentAsPDF does not work under test, so what is checked here is the
    // naming and the fallback that keeps a letter reachable when rendering fails.
    @IsTest
    static void finalizingNamesTheFileAndKeepsAFallbackRoute() {
        Lead leadRecord = createLead();

        Test.startTest();
        LeadPreApprovalLetterController.FinalizeResult result =
            LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, '<p>Final letter</p>');
        Test.stopTest();

        System.assertEquals(
            'Pre-Approval Letter - Javine_Roman.pdf',
            result.fileName,
            'The borrower is named in the file, so a downloads folder stays legible.'
        );
        System.assertEquals(
            true,
            result.pdfPath.contains('Lead_Pre_Approval_Letter'),
            'The page link stays as the fallback when the bytes cannot be produced.'
        );
    }

    // The emailed copy is what makes this work on a phone, so its wording is pinned here.
    @IsTest
    static void theEmailedCopyNamesTheBorrowerAndLinksTheLead() {
        Lead leadRecord = createLead();

        Test.startTest();
        String body = LeadPreApprovalLetterController.buildLetterEmailBody(leadRecord.Id, 'Javine Roman');
        Test.stopTest();

        System.assertEquals(true, body.contains('Javine Roman'), 'It says whose letter it is.');
        System.assertEquals(true, body.contains('Pre-Approval Letter'));
        System.assertEquals(
            true,
            body.contains('/lightning/r/Lead/' + leadRecord.Id),
            'And links back to the Lead it came from.'
        );
    }

    // Delivery is a second call because the PDF page cannot see the finalize save until it has
    // committed. Under test the render returns nothing, so what is checked is that the call
    // survives that and still hands back a usable name and fallback link.
    @IsTest
    static void deliveryRunsAfterFinalizeAndSkipsTheEmailOnDesktop() {
        Lead leadRecord = createLead();
        LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, '<p>Final letter</p>');

        Test.startTest();
        LeadPreApprovalLetterController.FinalizeResult delivered =
            LeadPreApprovalLetterController.deliverFinalizedLetter(leadRecord.Id, false);
        Test.stopTest();

        System.assertEquals('Pre-Approval Letter - Javine_Roman.pdf', delivered.fileName);
        System.assertEquals(
            null,
            delivered.emailedTo,
            'A desktop saves the file itself, so no copy is emailed.'
        );
        System.assertEquals(
            true,
            delivered.pdfPath.contains('Lead_Pre_Approval_Letter'),
            'The page link remains as the last resort.'
        );
        System.assertEquals(
            '<p>Final letter</p>',
            [SELECT Pre_Approval_Letter_HTML__c FROM Lead WHERE Id = :leadRecord.Id].Pre_Approval_Letter_HTML__c,
            'And the letter itself was saved by the first call.'
        );
    }

    // ---------- outside LOs (External_LO): their own signature card only ----------

    @IsTest
    static void outsideLoIsOfferedOnlyTheirOwnCardWithNmlsAndStates() {
        User lo = newOutsideLo();
        Lead leadRecord = createLeadOwnedBy(lo);
        LeadPreApprovalLetterController.LetterContext context;
        String html;

        Test.startTest();
        System.runAs(lo) {
            context = LeadPreApprovalLetterController.getContext(leadRecord.Id);
            html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
                leadRecord.Id, 500000, 400000, 'FHA', 'Condo', null, '', context.defaultSignerId, null
            );
        }
        Test.stopTest();

        System.assertEquals(1, context.signerOptions.size(), 'No Brandon default and no Lead Owner option.');
        System.assertEquals(lo.Id, context.signerOptions[0].userId);
        System.assertEquals(lo.Id, context.defaultSignerId);
        System.assertEquals('FL, GA', context.signerOptions[0].licensedStates);
        System.assert(html.contains('NMLS #998877'), 'The LO\'s own NMLS is on the card.');
        System.assert(html.contains('Licensed in FL, GA'), 'Licensed states print when filled.');
        System.assert(html.contains('Company NMLS #2266637'), 'The company NMLS stays.');
        System.assert(!html.contains('BRANDON BROTSKY'), 'No one else signs an outside LO\'s letter.');
        System.assert(html.contains(LeadPreApprovalLetterController.SIGNER_START)
            && html.contains(LeadPreApprovalLetterController.SIGNER_END));
    }

    @IsTest
    static void outsideLoCannotAskForAnotherSigner() {
        User lo = newOutsideLo();
        Lead leadRecord = createLeadOwnedBy(lo);
        Id adminId = UserInfo.getUserId();
        Boolean refused = false;

        Test.startTest();
        System.runAs(lo) {
            try {
                // Brandon (or any other user) is refused; the same call with the LO's own Id succeeds above.
                LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
                    leadRecord.Id, 500000, 400000, 'FHA', 'Condo', null, '', adminId, null
                );
            } catch (Exception expected) {
                refused = true;
            }
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'Enforced on the server, not only in the picker.');
    }

    @IsTest
    static void outsideLoFinalizePutsTheirOwnCardBackWhateverWasTyped() {
        User lo = newOutsideLo();
        Lead leadRecord = createLeadOwnedBy(lo);
        String tampered = '<p>Letter body</p>'
            + LeadPreApprovalLetterController.SIGNER_START
            + '<div>BRANDON BROTSKY NMLS #1</div>'
            + LeadPreApprovalLetterController.SIGNER_END
            + '<p>tail</p>';
        String missingMessage = '';

        Test.startTest();
        System.runAs(lo) {
            LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, tampered);
            // Asserted against the helper: AuraHandledException hides its text from getMessage() in tests.
            try {
                LeadPreApprovalLetterController.restoreOwnSignerCard('<p>card deleted</p>');
            } catch (Exception expected) {
                missingMessage = expected.getMessage();
            }
        }
        Test.stopTest();

        String stored = [SELECT Pre_Approval_Letter_HTML__c FROM Lead WHERE Id = :leadRecord.Id].Pre_Approval_Letter_HTML__c;
        System.assert(!stored.contains('BRANDON BROTSKY'), 'The typed-in card is replaced.');
        System.assert(stored.contains('NMLS #998877') && stored.contains('Licensed in FL, GA'));
        System.assert(stored.startsWith('<p>Letter body</p>') && stored.endsWith('<p>tail</p>'),
            'Everything outside the card is kept as edited.');
        System.assertEquals(LeadPreApprovalLetterController.SIGNER_REMOVED_MESSAGE, missingMessage);
    }

    // With the full External_Loan_Officer group (muting set included) the LO cannot edit the
    // letter field or their own NMLS directly, yet finalize still saves - it writes in system mode.
    @IsTest
    static void outsideLoInTheFullGroupCannotEditTheFieldButFinalizeStillSaves() {
        User lo = newOutsideLo();
        PermissionSetGroup psg = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'External_Loan_Officer'];
        Test.calculatePermissionSetGroup(psg.Id);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = lo.Id, PermissionSetGroupId = psg.Id);
        }
        Lead leadRecord = createLeadOwnedBy(lo);
        Boolean letterFieldEditable;
        Boolean letterFieldReadable;
        Boolean nmlsEditable;
        Boolean nmlsReadable;

        Test.startTest();
        System.runAs(lo) {
            letterFieldEditable = Schema.SObjectType.Lead.fields.Pre_Approval_Letter_HTML__c.isUpdateable();
            letterFieldReadable = Schema.SObjectType.Lead.fields.Pre_Approval_Letter_HTML__c.isAccessible();
            nmlsEditable = Schema.SObjectType.User.fields.NMLS__c.isUpdateable();
            nmlsReadable = Schema.SObjectType.User.fields.NMLS__c.isAccessible();
            LeadPreApprovalLetterController.finalizeLetter(
                leadRecord.Id,
                '<p>Body</p>' + LeadPreApprovalLetterController.SIGNER_START
                    + LeadPreApprovalLetterController.SIGNER_END
            );
        }
        Test.stopTest();

        System.assertEquals(false, letterFieldEditable, 'Muted: no direct edit of the stored letter.');
        System.assertEquals(true, letterFieldReadable, 'Read stays.');
        System.assertEquals(false, nmlsEditable, 'Outside LOs cannot change their own NMLS.');
        System.assertEquals(true, nmlsReadable);
        String stored = [SELECT Pre_Approval_Letter_HTML__c FROM Lead WHERE Id = :leadRecord.Id].Pre_Approval_Letter_HTML__c;
        System.assert(stored.contains('NMLS #998877'), 'Finalize saved the letter with their own card.');
    }

    @IsTest
    static void internalLettersCarryNoMarkersAndAreNotRewritten() {
        Lead leadRecord = createLead();
        String edited = '<p>Anything the internal LO typed</p>';

        Test.startTest();
        LeadPreApprovalLetterController.LetterContext context =
            LeadPreApprovalLetterController.getContext(leadRecord.Id);
        String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 500000, 400000, 'FHA', 'Condo', null, '', context.defaultSignerId, null
        );
        LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, edited);
        Test.stopTest();

        System.assert(!html.contains(LeadPreApprovalLetterController.SIGNER_START));
        System.assertEquals(edited,
            [SELECT Pre_Approval_Letter_HTML__c FROM Lead WHERE Id = :leadRecord.Id].Pre_Approval_Letter_HTML__c);
    }

    // Owner rule 2026-10-12: the buyer's agent is texted again for a letter at a new purchase price,
    // not for a re-issue at the same one.
    @IsTest
    static void onlyANewPurchasePriceReArmsTheAgentText() {
        Lead leadRecord = createLead();
        update new Lead(Id = leadRecord.Id, Letter_Completed__c = true, CommSent_Pre_Approval__c = true);
        Id signer = LeadPreApprovalLetterController.getContext(leadRecord.Id).defaultSignerId;

        Test.startTest();
        LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 795000, 675750, 'Conventional', 'Single Family', null, '', signer, null
        );
        Boolean afterSamePrice = [SELECT CommSent_Pre_Approval__c FROM Lead WHERE Id = :leadRecord.Id].CommSent_Pre_Approval__c;
        LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
            leadRecord.Id, 810000, 688500, 'Conventional', 'Single Family', null, '', signer, null
        );
        Boolean afterNewPrice = [SELECT CommSent_Pre_Approval__c FROM Lead WHERE Id = :leadRecord.Id].CommSent_Pre_Approval__c;
        LeadPreApprovalLetterController.finalizeLetter(leadRecord.Id, '<p>New price</p>');
        Test.stopTest();

        System.assertEquals(true, afterSamePrice, 'Same price: no new text.');
        System.assertEquals(false, afterNewPrice, 'New price: the text is due again.');
        System.assertEquals(true, [SELECT Letter_Completed__c FROM Lead WHERE Id = :leadRecord.Id].Letter_Completed__c);
    }

    // Owner rule 2026-10-12: outside LOs too - no status gate, and finalize moves an early Lead to
    // Pre-Approval but never drags a later one back.
    @IsTest
    static void outsideLosLetterAtAnyStatusAndLaterLeadsKeepTheirStatus() {
        User lo = newOutsideLo();
        Lead early = createLead('Nurturing');
        Lead later = createLead('Under Contract');
        update new List<Lead>{ new Lead(Id = early.Id, OwnerId = lo.Id), new Lead(Id = later.Id, OwnerId = lo.Id) };
        String earlyReason;
        String laterReason;

        Test.startTest();
        System.runAs(lo) {
            earlyReason = LeadPreApprovalLetterController.getLetterBlockedReason(early.Id);
            laterReason = LeadPreApprovalLetterController.getLetterBlockedReason(later.Id);
            LeadPreApprovalLetterController.LetterContext context =
                LeadPreApprovalLetterController.getContext(early.Id);
            String html = LeadPreApprovalLetterController.saveDetailsAndBuildLetter(
                early.Id, 500000, 400000, 'FHA', 'Condo', null, '', context.defaultSignerId, null
            );
            LeadPreApprovalLetterController.finalizeLetter(early.Id, html);
            LeadPreApprovalLetterController.deliverFinalizedLetter(early.Id, false);
        }
        LeadPreApprovalLetterController.finalizeLetter(later.Id, '<p>Later</p>');
        Test.stopTest();

        System.assertEquals(null, earlyReason, 'No status gate.');
        System.assertEquals(null, laterReason);
        Map<Id, Lead> saved = new Map<Id, Lead>([
            SELECT Status, Pre_Approval_Letter_HTML__c FROM Lead WHERE Id IN :new List<Id>{ early.Id, later.Id }
        ]);
        System.assertEquals('Pre-Approval', saved.get(early.Id).Status);
        System.assertEquals('Under Contract', saved.get(later.Id).Status, 'Never moved backwards.');
        System.assertEquals('<p>Later</p>', saved.get(later.Id).Pre_Approval_Letter_HTML__c);
    }

    @IsTest
    static void convertedLeadsAreRefusedWithTheirOwnMessage() {
        // A converted Lead cannot be updated, so the letter (which saves its terms to the Lead) is refused.
        Lead converted = (Lead) JSON.deserialize(
            '{"attributes":{"type":"Lead"},"IsConverted":true,"Status":"Submitted For Disclosures"}', Lead.class);
        System.assertEquals(LeadPreApprovalLetterController.CONVERTED_MESSAGE,
            LeadPreApprovalLetterController.letterBlockedReason(converted));
    }

    // Outside LOs letter their own leads (Lead OWD is Private).
    private static Lead createLeadOwnedBy(User lo) {
        Lead leadRecord = createLead();
        update new Lead(Id = leadRecord.Id, OwnerId = lo.Id);
        return leadRecord;
    }

    private static User newOutsideLo() {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User lo = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p7.lo' + suffix + '@reach-p7.test',
            Email = 'p7.lo@reach-p7.test',
            FirstName = 'Pat',
            LastName = 'Outside',
            Alias = 'p7lo',
            NMLS__c = '998877',
            Licensed_States__c = 'FL;GA',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert lo;
            insert new PermissionSetAssignment(
                AssigneeId = lo.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'External_LO_Access'].Id
            );
        }
        return lo;
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