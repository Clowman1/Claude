/**
 * Backs the Pre-Approval Letter quick action on the Lead.
 *
 * The Loan Officer fills in the terms, those save back to the Lead so the record and the letter can
 * never disagree, a preview is generated for free-text editing, and Finalize stores the edited HTML
 * and moves the Lead to Pre-Approval. The Visualforce page renders that stored HTML as the PDF,
 * because Apex cannot produce a PDF and a URL parameter cannot carry a whole letter.
 */
public with sharing class LeadPreApprovalLetterController {
    // The ONE list of Lead Statuses a letter may be issued at: Pre-Approval and every status after it
    // (owner rule, 2026-10-09). Ambiguous statuses are deliberately left out; see lo-workspace/phaseO4a/O4a.md.
    @TestVisible private static final Set<String> LETTER_STATUSES = new Set<String>{
        'Pre-Approval',
        'Nurture - Preapproval',
        'Nurture-Pre-Approval', // legacy spelling still on ~600 leads
        'Active',
        'Under Contract',
        'Submitted For Disclosures'
    };
    private static final String STATUS_GATE_MESSAGE =
        'Pre-approval letters unlock once this Lead reaches Pre-Approval. '
        + 'Please log a call to move the status to Pre-Approval, then try again.';
    // LO Workspace LOs move the status themselves from the lead header (decision 48.1).
    @TestVisible private static final String LO_WORKSPACE_STATUS_GATE_MESSAGE =
        'Pre-approval letters unlock once this lead reaches Pre-Approval. '
        + 'Move the lead to Pre-Approval once you\'ve reviewed credit and documents.';
    // A converted Lead cannot be updated, and the letter saves its terms to the Lead.
    @TestVisible private static final String CONVERTED_MESSAGE =
        'This lead has already been converted to a loan, so a new pre-approval letter cannot be issued from it.';
    // The stored picklist value is upper case; the letter prints the cased form the template uses.
    private static final String NON_QM_VALUE = 'NON-QM';
    private static final String NON_QM_DISPLAY = 'Non-QM';
    // Falls back to the Lead Owner if this user is ever deactivated or renamed.
    private static final String DEFAULT_SIGNER_NAME = 'Brandon Brotsky';
    private static final String COMPANY_NMLS = '2266637';
    private static final String COMPANY_ADDRESS = '327 Plaza Real #215, Boca Raton, FL 33432';
    // Outside LOs (LO Workspace) may sign only with their own card. Enforced here, not in the picker.
    private static final String EXTERNAL_LO_PERMISSION = 'External_LO';
    // Brandon's demo of LO Workspace: unrestricted, but his own card is the default.
    private static final String DEMO_PERMISSION = 'LO_Workspace_Demo';
    // Invisible markers around an outside LO's card, so finalize can put the real card back
    // whatever was typed into the editable preview.
    @TestVisible private static final String SIGNER_START = '<!--rhl-signer-start-->';
    @TestVisible private static final String SIGNER_END = '<!--rhl-signer-end-->';
    @TestVisible private static final String SIGNER_REMOVED_MESSAGE =
        'The signature card was removed from the letter. Go Back and generate the letter again.';
    @TestVisible private static final String OWN_CARD_ONLY_MESSAGE =
        'You can only sign a pre-approval letter with your own signature card.';

    public class LetterException extends Exception {}

    public class SignerOption {
        @AuraEnabled public Id userId;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String nmls;
        @AuraEnabled public String photoUrl;
        // "FL, GA, TX" from User.Licensed_States__c; blank leaves the card as it always was.
        @AuraEnabled public String licensedStates;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class LetterContext {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String borrowerName;
        @AuraEnabled public Decimal purchasePrice;
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public String financingType;
        @AuraEnabled public String propertyType;
        // Prefill for the Exact Address option, from the Lead's subject property fields.
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public String nonQmType;
        @AuraEnabled public String docsReviewed;
        @AuraEnabled public List<PicklistOption> financingOptions;
        @AuraEnabled public List<PicklistOption> propertyOptions;
        @AuraEnabled public List<PicklistOption> nonQmOptions;
        @AuraEnabled public String nonQmTriggerValue;
        @AuraEnabled public List<SignerOption> signerOptions;
        @AuraEnabled public Id defaultSignerId;
    }

    @AuraEnabled
    public static LetterContext getContext(Id leadId) {
        try {
            Lead leadRecord = loadLead(leadId);
            ensurePreApprovalStatus(leadRecord);

            LetterContext context = new LetterContext();
            context.leadId = leadRecord.Id;
            context.borrowerName = buildBorrowerName(leadRecord);
            context.purchasePrice = leadRecord.Purchase_Price__c;
            context.loanAmount = leadRecord.Loan_Amount__c;
            context.financingType = leadRecord.Loan_Type_1st_TD__c;
            context.propertyType = leadRecord.Property_Type__c;
            context.propertyAddress = buildSubjectAddress(leadRecord);
            context.nonQmType = leadRecord.Non_QM_Type__c;
            context.docsReviewed = leadRecord.Reviewed_Documents__c;
            context.financingOptions = describeOptions(Lead.Loan_Type_1st_TD__c);
            context.propertyOptions = describeOptions(Lead.Property_Type__c);
            context.nonQmOptions = describeOptions(Lead.Non_QM_Type__c);
            context.nonQmTriggerValue = NON_QM_VALUE;
            context.signerOptions = buildSignerOptions(leadRecord);
            context.defaultSignerId = context.signerOptions.isEmpty() ? null : context.signerOptions[0].userId;
            if (FeatureManagement.checkPermission(DEMO_PERMISSION)) {
                for (SignerOption option : context.signerOptions) {
                    if (option.userId == UserInfo.getUserId()) {
                        context.defaultSignerId = option.userId;
                    }
                }
            }
            return context;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * the letter is generated from what is now on the record, so a letter can never quote a number
     * the Lead does not hold.
     */
    @AuraEnabled
    public static String saveDetailsAndBuildLetter(
        Id leadId,
        Decimal purchasePrice,
        Decimal loanAmount,
        String financingType,
        String propertyType,
        String nonQmType,
        String docsReviewed,
        Id signerId,
        String propertyAddress
    ) {
        try {
            ensurePreApprovalStatus(loadLead(leadId));

            Lead leadUpdate = new Lead(
                Id = leadId,
                Purchase_Price__c = purchasePrice,
                Loan_Amount__c = loanAmount,
                Loan_Type_1st_TD__c = financingType,
                // Cleared when the financing is not Non-QM, so a stale sub-type cannot survive a
                // change of loan type and reappear on a later letter.
                Non_QM_Type__c = NON_QM_VALUE.equalsIgnoreCase(financingType) ? nonQmType : null,
                Reviewed_Documents__c = docsReviewed
            );
            // An exact address replaces the property type on the letter; the Lead's type is left as is.
            if (String.isBlank(propertyAddress)) {
                leadUpdate.Property_Type__c = propertyType;
            }
            if (purchasePrice != null && purchasePrice != 0 && loanAmount != null) {
                leadUpdate.LTV__c = (loanAmount / purchasePrice * 100).setScale(2, System.RoundingMode.HALF_UP);
            }
            // SYSTEM_MODE, as elsewhere in this codebase: who may run this is governed by access to
            // the quick action, and the class is "with sharing" so record access still applies.
            Database.update(leadUpdate, true, AccessLevel.SYSTEM_MODE);

            Lead leadRecord = loadLead(leadId);
            SignerOption signer = resolveSigner(leadRecord, signerId);
            return buildLetterHtml(leadRecord, signer, docsReviewed, propertyAddress);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class FinalizeResult {
        // Fallback route to the same letter if the bytes cannot be produced.
        @AuraEnabled public String pdfPath;
        // The PDF itself, so the browser saves it straight to disk rather than opening a tab
        // and leaving the Loan Officer to download it from there.
        @AuraEnabled public String pdfBase64;
        @AuraEnabled public String fileName;
        // A real URL serving the same file as an attachment. iOS ignores a blob download, so
        // an iPhone is sent here instead and Safari saves it through its download manager.
        @AuraEnabled public String downloadUrl;
        // The stored file. The Salesforce mobile app is a webview that will not follow a
        // download URL, but it does open its own file preview, which carries a save action.
        @AuraEnabled public Id contentDocumentId;
        // Where the copy was emailed, or null if it could not be sent. A phone cannot be made
        // to save a file from a webview, but it can always open an attachment in Mail.
        @AuraEnabled public String emailedTo;
    }

    /**
     * Stores the letter exactly as edited. The Lead status is deliberately left alone: reaching
     * Pre-Approval is the Loan Officer's decision, recorded by logging a call, and the letter is
     * only reachable once they have already made it.
     */
    @AuraEnabled
    public static FinalizeResult finalizeLetter(Id leadId, String letterHtml) {
        try {
            if (String.isBlank(letterHtml)) {
                throw new LetterException('The letter is empty, so there is nothing to finalize.');
            }
            // Re-checked at finalize too: the status may have moved while the modal sat open.
            ensurePreApprovalStatus(loadLead(leadId));
            if (isExternalLo()) {
                letterHtml = restoreOwnSignerCard(letterHtml);
            }

            Database.update(
                new Lead(Id = leadId, Pre_Approval_Letter_HTML__c = letterHtml),
                true,
                AccessLevel.SYSTEM_MODE
            );

            // Letter_Completed__c still records that a letter was produced; only the status move
            // is gone.
            Database.update(
                new Lead(Id = leadId, Letter_Completed__c = true),
                true,
                AccessLevel.SYSTEM_MODE
            );

            // Rendering happens in deliverFinalizedLetter, a separate call: getContentAsPDF renders
            // the page in its own request, which cannot see this save until it has committed.
            FinalizeResult result = new FinalizeResult();
            result.pdfPath = '/apex/Lead_Pre_Approval_Letter?id=' + leadId;
            result.fileName = buildLetterFileName(leadId);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Renders, stores and - only when the client asks - emails the letter, once the finalize save
     * has committed.
     *
     * This cannot live inside finalizeLetter. getContentAsPDF renders the Visualforce page in a
     * separate request that cannot see uncommitted DML, so calling it in the same transaction as
     * the save produced a PDF of the "no letter has been finalized" fallback rather than the
     * letter.
     *
     * emailCopy comes from the client because only it knows the device: a desktop saves the file
     * directly and does not need a copy in its inbox, while a phone cannot save anything at all.
     */
    @AuraEnabled
    public static FinalizeResult deliverFinalizedLetter(Id leadId, Boolean emailCopy) {
        try {
            ensurePreApprovalStatus(loadLead(leadId));
            FinalizeResult result = new FinalizeResult();
            result.pdfPath = '/apex/Lead_Pre_Approval_Letter?id=' + leadId;
            result.fileName = buildLetterFileName(leadId);
            result.pdfBase64 = renderLetterPdf(leadId);

            StoredLetter stored = storeLetterFile(leadId, result.fileName, result.pdfBase64);
            result.downloadUrl = stored.downloadUrl;
            result.contentDocumentId = stored.contentDocumentId;

            if (emailCopy == true) {
                result.emailedTo = emailLetterToFinalizer(leadId, result.fileName, result.pdfBase64);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Renders the stored letter to PDF bytes so the LWC can hand them straight to the browser.
     *
     * Returns null rather than throwing: the letter is saved by this point, and a rendering
     * problem should leave the Loan Officer with the page link rather than an error over work
     * that actually succeeded.
     */
    private static String renderLetterPdf(Id leadId) {
        if (Test.isRunningTest()) {
            // getContentAsPDF returns nothing useful under test.
            return null;
        }
        try {
            PageReference letterPage = Page.Lead_Pre_Approval_Letter;
            letterPage.getParameters().put('id', leadId);
            Blob pdf = letterPage.getContentAsPDF();
            return pdf == null ? null : EncodingUtil.base64Encode(pdf);
        } catch (Exception renderException) {
            System.debug(
                LoggingLevel.ERROR,
                'Could not render the pre-approval letter PDF for ' + leadId + ': '
                    + renderException.getMessage()
            );
            return null;
        }
    }

    /**
     * Keeps the issued letter on the Lead as a file and returns a URL that downloads it.
     *
     * Two reasons. A phone cannot save a blob, so it needs a real URL that arrives with
     * attachment headers; and the letter that actually went out is worth keeping, since the
     * stored HTML can be re-rendered but the issued PDF is the thing the realtor holds.
     *
     * Returns null on any failure: the letter is already saved, and losing the download is
     * better than failing the finalize over it.
     */
    /**
     * Emails the finalized letter to whoever pressed the button, with the PDF attached.
     *
     * This is the one delivery route that works on every device: a phone cannot be made to
     * write a file from inside a webview, but it can always open an attachment in Mail and
     * save or forward it from there.
     *
     * Returns the address it went to, or null. The letter is saved either way, so a mail
     * problem must not fail the finalize - but the caller is told, rather than the toast
     * promising an email that never left.
     */
    private static String emailLetterToFinalizer(Id leadId, String fileName, String pdfBase64) {
        if (String.isBlank(pdfBase64)) {
            return null;
        }
        String recipient = UserInfo.getUserEmail();
        if (String.isBlank(recipient)) {
            return null;
        }

        try {
            List<Lead> leads = [
                SELECT Id, Name, FirstName, LastName FROM Lead WHERE Id = :leadId WITH SYSTEM_MODE LIMIT 1
            ];
            String borrower = leads.isEmpty() ? 'the borrower' : buildBorrowerName(leads[0]);

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(fileName);
            attachment.setContentType('application/pdf');
            attachment.setBody(EncodingUtil.base64Decode(pdfBase64));

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ recipient });
            email.setSubject('Pre-Approval Letter - ' + borrower);
            email.setHtmlBody(buildLetterEmailBody(leadId, borrower));
            email.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
            email.setSaveAsActivity(false);

            Id orgWideId = resolveOrgWideAddressId();
            if (orgWideId != null) {
                email.setOrgWideEmailAddressId(orgWideId);
            }

            if (!Test.isRunningTest()) {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            }
            return recipient;
        } catch (Exception emailException) {
            System.debug(
                LoggingLevel.ERROR,
                'Could not email the pre-approval letter for ' + leadId + ': '
                    + emailException.getMessage()
            );
            return null;
        }
    }

    private static Id resolveOrgWideAddressId() {
        List<OrgWideEmailAddress> addresses = [
            SELECT Id FROM OrgWideEmailAddress WHERE Address = 'reachus@reachhomeloans.com'
            WITH SYSTEM_MODE LIMIT 1
        ];
        return addresses.isEmpty() ? null : addresses[0].Id;
    }

    @TestVisible
    private static String buildLetterEmailBody(Id leadId, String borrower) {
        String leadUrl = URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/Lead/' + leadId + '/view';
        return ''
            + '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:14px;overflow:hidden;">'
            + '<tr><td style="background:#1c3155;padding:26px 30px;">'
            + '<div style="color:#ffa534;font-size:11px;font-weight:900;letter-spacing:1.6px;text-transform:uppercase;font-family:Arial,sans-serif;">Reach Home Loans</div>'
            + '<div style="color:#ffffff;font-size:26px;font-weight:900;margin-top:8px;font-family:Arial,sans-serif;">Pre-Approval Letter</div>'
            + '</td></tr>'
            + '<tr><td style="padding:28px 30px 0;">'
            + '<div style="color:#22314f;font-size:15px;line-height:1.65;font-family:Arial,sans-serif;">'
            + 'Your pre-approval letter for <strong>' + htmlEncode(borrower)
            + '</strong> is attached, ready to send on or save to your phone.</div></td></tr>'
            + '<tr><td align="center" style="padding:26px 30px 30px;">'
            + '<a href="' + htmlEncode(leadUrl) + '" style="display:inline-block;background:#ff9824;color:#122242;font-size:15px;font-weight:900;font-family:Arial,sans-serif;text-decoration:none;padding:14px 34px;border-radius:999px;">Open the Lead</a>'
            + '</td></tr>'
            + '<tr><td style="background:#f4f6fa;padding:18px 30px;border-top:1px solid #e2e7f0;">'
            + '<div style="color:#77839c;font-size:12px;line-height:1.6;font-family:Arial,sans-serif;">'
            + 'You are receiving this because you finalized this letter. A copy is also kept on the Lead.'
            + '</div></td></tr></table>';
    }

    private class StoredLetter {
        String downloadUrl;
        Id contentDocumentId;
    }

    private static StoredLetter storeLetterFile(Id leadId, String fileName, String pdfBase64) {
        StoredLetter stored = new StoredLetter();
        if (String.isBlank(pdfBase64)) {
            return stored;
        }
        try {
            ContentVersion version = new ContentVersion(
                Title = fileName.removeEnd('.pdf'),
                PathOnClient = fileName,
                VersionData = EncodingUtil.base64Decode(pdfBase64),
                Origin = 'H'
            );
            Database.insert(version, true, AccessLevel.SYSTEM_MODE);

            stored.contentDocumentId = [
                SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id WITH SYSTEM_MODE
            ].ContentDocumentId;
            Database.insert(
                new ContentDocumentLink(
                    ContentDocumentId = stored.contentDocumentId,
                    LinkedEntityId = leadId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ),
                true,
                AccessLevel.SYSTEM_MODE
            );

            stored.downloadUrl = '/sfc/servlet.shepherd/version/download/' + version.Id;
            return stored;
        } catch (Exception storeException) {
            System.debug(
                LoggingLevel.ERROR,
                'Could not store the pre-approval letter file for ' + leadId + ': '
                    + storeException.getMessage()
            );
            return stored;
        }
    }

    // Names the download after the borrower so a downloads folder stays legible.
    @TestVisible
    private static String buildLetterFileName(Id leadId) {
        List<Lead> leads = [
            SELECT FirstName, LastName, Name FROM Lead WHERE Id = :leadId WITH SYSTEM_MODE LIMIT 1
        ];
        String borrower = leads.isEmpty() ? 'Borrower' : buildBorrowerName(leads[0]);
        String safeBorrower = borrower.replaceAll('[^a-zA-Z0-9]+', '_').removeEnd('_');
        return 'Pre-Approval Letter - ' + safeBorrower + '.pdf';
    }

    @TestVisible
    private static void ensurePreApprovalStatus(Lead leadRecord) {
        String reason = letterBlockedReason(leadRecord);
        if (reason != null) {
            throw new LetterException(reason);
        }
    }

    /** Null when a letter may be issued for this Lead, otherwise the direction to show. */
    @TestVisible
    private static String letterBlockedReason(Lead leadRecord) {
        if (leadRecord != null && leadRecord.isSet('IsConverted') && leadRecord.IsConverted) {
            return CONVERTED_MESSAGE;
        }
        if (leadRecord == null || !LETTER_STATUSES.contains(leadRecord.Status)) {
            return isExternalLo() ? LO_WORKSPACE_STATUS_GATE_MESSAGE : STATUS_GATE_MESSAGE;
        }
        return null;
    }

    /** LO Workspace button guard: the same rule, asked before the modal opens. */
    @AuraEnabled
    public static String getLetterBlockedReason(Id leadId) {
        try {
            return letterBlockedReason(loadLead(leadId));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ---------- letter ----------

    @TestVisible
    private static String buildLetterHtml(Lead leadRecord, SignerOption signer, String docsReviewed, String propertyAddress) {
        List<String> applicantNames = buildApplicantNames(leadRecord);
        String borrowerName = joinApplicantNames(applicantNames);
        Boolean isJointApplication = applicantNames.size() > 1;
        String today = Datetime.now().format('MMMM d, yyyy').toUpperCase();
        String ltvSuffix = '';
        if (leadRecord.Purchase_Price__c != null && leadRecord.Purchase_Price__c != 0 && leadRecord.Loan_Amount__c != null) {
            Decimal ltv = (leadRecord.Loan_Amount__c / leadRecord.Purchase_Price__c * 100)
                .setScale(2, System.RoundingMode.HALF_UP);
            // String.valueOf rather than format(): format() drops the trailing zeros, so 85.00 would
            // print as 85 and the letter would read "85% LTV" against a 85.00% record.
            ltvSuffix = '&nbsp;&nbsp;(' + String.valueOf(ltv) + '% LTV)';
        }

        // Tables and inline styles throughout: the Visualforce PDF renderer supports neither
        // flexbox nor grid, so the preview has to be built the way the PDF needs it.
        return ''
            + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="font-family:Helvetica,Arial,sans-serif;color:#1b2f5c;">'
            + '<tr><td style="padding:0 0 26px 0;">'
            + '<img src="/resource/Reach_Logo" alt="Reach Home Loans" width="190" />'
            + '</td></tr>'

            + '<tr><td style="background:#e8f1fb;padding:20px 24px;">'
            + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>'
            + '<td style="font-size:21px;font-weight:bold;color:#14284b;">PRE-APPROVAL LETTER</td>'
            + '<td align="right" style="font-size:11px;font-weight:bold;color:#5a6b86;letter-spacing:1px;vertical-align:top;">' + today + '</td>'
            + '</tr></table></td></tr>'

            + '<tr><td style="padding:26px 0 10px 0;font-size:19px;font-weight:bold;color:#14284b;">'
            + htmlEncode(borrowerName)
            + (isJointApplication ? ' are' : ' is') + ' pre-approved for mortgage financing.</td></tr>'
            + '<tr><td style="padding:0 0 12px 0;font-size:13px;line-height:20px;color:#33405c;">'
            + 'To whom it may concern:</td></tr>'
            + '<tr><td style="padding:0 0 20px 0;font-size:13px;line-height:20px;color:#33405c;">'
            + 'I have issued this Pre-Approval Letter to certify that the below applicant(s) is/are '
            + 'pre-approved for financing per Desktop Underwriter (DU) and/or Loan Prospector (LP).</td></tr>'

            + '<tr><td>' + buildTermsTable(leadRecord, applicantNames, ltvSuffix, propertyAddress) + '</td></tr>'

            + '<tr><td style="padding:22px 0 6px 0;font-size:12px;font-weight:bold;color:#1b6fc4;letter-spacing:0.5px;">QUALIFICATION REVIEW</td></tr>'
            + '<tr><td style="font-size:13px;line-height:20px;color:#33405c;">'
            + 'This pre-approval is subject to the terms and conditions of the applicable loan program, '
            + 'satisfactory property review, and no material change in the applicant\'s creditworthiness '
            + 'or financial position prior to closing.</td></tr>'

            + buildDocsReviewedRows(docsReviewed)

            + '<tr><td style="padding:34px 0 0 0;font-size:13px;font-weight:bold;color:#14284b;">'
            + 'Questions regarding this pre-approval? Please contact me directly.</td></tr>'

            + '<tr><td style="padding:26px 0 0 0;">' + buildSignerCard(signer) + '</td></tr>'
            + '</table>';
    }

    private static String buildApplicantCell(List<String> applicantNames) {
        List<String> encoded = new List<String>();
        for (String name : applicantNames) {
            encoded.add(htmlEncode(name));
        }
        return String.join(encoded, '<br />');
    }

    private static String buildTermsTable(Lead leadRecord, List<String> applicantNames, String ltvSuffix, String propertyAddress) {
        List<String> rows = new List<String>();
        rows.add(termRow(
            applicantNames.size() > 1 ? 'APPLICANTS' : 'APPLICANT',
            buildApplicantCell(applicantNames),
            false,
            true
        ));
        rows.add(termRow('PURCHASE PRICE', formatCurrency(leadRecord.Purchase_Price__c), true, false));
        rows.add(termRow('LOAN AMOUNT', formatCurrency(leadRecord.Loan_Amount__c) + ltvSuffix, true, true));
        rows.add(termRow('FINANCING', htmlEncode(buildFinancingLabel(leadRecord)), false, false));
        rows.add(String.isBlank(propertyAddress)
            ? termRow('PROPERTY TYPE', htmlEncode(leadRecord.Property_Type__c), false, true)
            : termRow('PROPERTY ADDRESS', htmlEncode(propertyAddress.trim()), false, true));

        return '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="font-size:13px;">'
            + String.join(rows, '')
            + '</table>';
    }

    // Non-QM prints with its programme hyphenated after it, as in "Non-QM - Bank Statement".
    @TestVisible
    private static String buildFinancingLabel(Lead leadRecord) {
        String financing = leadRecord.Loan_Type_1st_TD__c;
        if (String.isBlank(financing)) {
            return '';
        }
        if (!NON_QM_VALUE.equalsIgnoreCase(financing)) {
            return financing;
        }
        return String.isBlank(leadRecord.Non_QM_Type__c)
            ? NON_QM_DISPLAY
            : NON_QM_DISPLAY + ' - ' + leadRecord.Non_QM_Type__c;
    }

    private static String termRow(String label, String value, Boolean emphasise, Boolean shaded) {
        String background = shaded ? 'background:#f4f7fb;' : '';
        String valueWeight = emphasise ? 'font-weight:bold;' : '';
        return '<tr>'
            + '<td width="30%" style="' + background + 'padding:11px 14px;font-size:11px;font-weight:bold;color:#5a6b86;letter-spacing:0.6px;">'
            + label + '</td>'
            + '<td style="' + background + 'padding:11px 14px;color:#14284b;' + valueWeight + '">'
            + (String.isBlank(value) ? '&mdash;' : value) + '</td>'
            + '</tr>';
    }

    // Free text, one item per line, rendered as a ticked list the way the template shows it.
    private static String buildDocsReviewedRows(String docsReviewed) {
        if (String.isBlank(docsReviewed)) {
            return '';
        }

        List<String> items = new List<String>();
        for (String line : docsReviewed.split('\n')) {
            String trimmed = line.trim();
            if (String.isNotBlank(trimmed)) {
                items.add(
                    '<tr><td style="padding:5px 0;font-size:13px;color:#33405c;">'
                    + '<img src="/resource/Reviewed_Check" alt="Reviewed" width="11" height="11" />'
                    + '&nbsp;&nbsp;'
                    + htmlEncode(trimmed) + '</td></tr>'
                );
            }
        }
        if (items.isEmpty()) {
            return '';
        }

        return '<tr><td style="padding:22px 0 6px 0;font-size:12px;font-weight:bold;color:#1b6fc4;letter-spacing:0.5px;">DOCUMENTATION REVIEWED</td></tr>'
            + '<tr><td><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">'
            + String.join(items, '')
            + '</table></td></tr>';
    }

    // Internal letters are byte-for-byte what they were; only an outside LO's card carries markers.
    private static String buildSignerCard(SignerOption signer) {
        String block = buildSignerBlock(signer);
        return isExternalLo() ? SIGNER_START + block + SIGNER_END : block;
    }

    /**
     * Swaps whatever sits between the markers for the outside LO's own card, rebuilt from their
     * User record, so no edit to the preview can put someone else's name, NMLS or photo there.
     */
    @TestVisible
    private static String restoreOwnSignerCard(String letterHtml) {
        Integer startAt = letterHtml.indexOf(SIGNER_START);
        Integer endAt = startAt < 0 ? -1 : letterHtml.indexOf(SIGNER_END, startAt);
        if (endAt < 0 || letterHtml.indexOf(SIGNER_START, startAt + 1) >= 0) {
            throw new LetterException(SIGNER_REMOVED_MESSAGE);
        }
        List<SignerOption> own = ownSignerOption();
        if (own.isEmpty()) {
            throw new LetterException(OWN_CARD_ONLY_MESSAGE);
        }
        return letterHtml.left(startAt)
            + buildSignerCard(own[0])
            + letterHtml.substring(endAt + SIGNER_END.length());
    }

    private static Boolean isExternalLo() {
        return FeatureManagement.checkPermission(EXTERNAL_LO_PERMISSION);
    }

    private static String buildSignerBlock(SignerOption signer) {
        if (signer == null) {
            return '';
        }

        String photoCell = String.isBlank(signer.photoUrl)
            ? ''
            : '<td width="90" style="padding:16px 16px 16px 20px;vertical-align:middle;">'
                + '<img src="' + htmlEncode(signer.photoUrl) + '" width="74" height="74" alt="' + htmlEncode(signer.name) + '" />'
                + '</td>';

        List<String> contactBits = new List<String>();
        if (String.isNotBlank(signer.phone)) {
            contactBits.add(htmlEncode(signer.phone));
        }
        if (String.isNotBlank(signer.email)) {
            contactBits.add(htmlEncode(signer.email));
        }

        return '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#14284b;color:#ffffff;">'
            + '<tr>'
            + photoCell
            + '<td style="padding:16px 12px;vertical-align:middle;">'
            + '<div style="font-size:15px;font-weight:bold;letter-spacing:0.5px;">' + htmlEncode(signer.name).toUpperCase() + '</div>'
            + (String.isBlank(signer.title) ? '' : '<div style="font-size:12px;color:#c3d2e8;padding-top:3px;">' + htmlEncode(signer.title) + '</div>')
            + (contactBits.isEmpty() ? '' : '<div style="font-size:12px;color:#e4ecf7;padding-top:5px;">' + String.join(contactBits, '&nbsp;&nbsp;|&nbsp;&nbsp;') + '</div>')
            + '<div style="font-size:12px;color:#e4ecf7;padding-top:3px;">' + COMPANY_ADDRESS + '</div>'
            + '</td>'
            + '<td align="right" style="padding:16px 20px;vertical-align:bottom;font-size:11px;color:#c3d2e8;">'
            + 'Company NMLS #' + COMPANY_NMLS
            + (String.isBlank(signer.nmls) ? '' : '<div style="padding-top:3px;">NMLS #' + htmlEncode(signer.nmls) + '</div>')
            + (String.isBlank(signer.licensedStates) ? '' : '<div style="padding-top:3px;">Licensed in ' + htmlEncode(signer.licensedStates) + '</div>')
            + '</td>'
            + '</tr></table>';
    }

    // ---------- helpers ----------

    private static Lead loadLead(Id leadId) {
        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Name, OwnerId, Owner.Name,
                   Purchase_Price__c, Loan_Amount__c, Loan_Type_1st_TD__c, Property_Type__c,
                   Reviewed_Documents__c, Non_QM_Type__c, Status, IsConverted,
                   Subject_Property_Street__c, Subject_Property_City__c, Property_State__c, Subject_Property_Zip__c
            FROM Lead
            WHERE Id = :leadId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            throw new LetterException('Unable to load this Lead.');
        }
        return leads[0];
    }

    // The running user's own card, and nothing else.
    private static List<SignerOption> ownSignerOption() {
        List<SignerOption> options = new List<SignerOption>();
        for (User candidate : [
            SELECT Id, Name, Title, Phone, MobilePhone, Email, NMLS__c, Licensed_States__c, Headshot_URL__c
            FROM User
            WHERE Id = :UserInfo.getUserId() AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            options.add(toSignerOption(candidate));
        }
        return options;
    }

    private static List<SignerOption> buildSignerOptions(Lead leadRecord) {
        // Outside LOs: no Brandon default, no Lead Owner option - their own card only.
        if (isExternalLo()) {
            return ownSignerOption();
        }

        Set<Id> userIds = new Set<Id>();
        if (leadRecord.OwnerId != null && leadRecord.OwnerId.getSObjectType() == Schema.User.SObjectType) {
            userIds.add(leadRecord.OwnerId);
        }

        Map<Id, User> usersById = new Map<Id, User>([
            SELECT Id, Name, Title, Phone, MobilePhone, Email, NMLS__c, Licensed_States__c, Headshot_URL__c, IsActive
            FROM User
            WHERE (Name = :DEFAULT_SIGNER_NAME OR Id IN :userIds) AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]);

        // Brandon first so he is the default; the Lead Owner is the alternative.
        List<SignerOption> options = new List<SignerOption>();
        for (User candidate : usersById.values()) {
            if (candidate.Name == DEFAULT_SIGNER_NAME) {
                options.add(toSignerOption(candidate));
            }
        }
        for (User candidate : usersById.values()) {
            if (candidate.Name != DEFAULT_SIGNER_NAME) {
                options.add(toSignerOption(candidate));
            }
        }
        return options;
    }

    private static SignerOption toSignerOption(User userRecord) {
        SignerOption option = new SignerOption();
        option.userId = userRecord.Id;
        option.name = userRecord.Name;
        option.label = userRecord.Name + (String.isBlank(userRecord.Title) ? '' : ' — ' + userRecord.Title);
        option.title = userRecord.Title;
        option.phone = String.isNotBlank(userRecord.MobilePhone) ? userRecord.MobilePhone : userRecord.Phone;
        option.email = userRecord.Email;
        option.nmls = userRecord.NMLS__c;
        option.photoUrl = userRecord.Headshot_URL__c;
        option.licensedStates = String.isBlank(userRecord.Licensed_States__c)
            ? null
            : userRecord.Licensed_States__c.replace(';', ', ');
        return option;
    }

    private static SignerOption resolveSigner(Lead leadRecord, Id signerId) {
        List<SignerOption> options = buildSignerOptions(leadRecord);
        for (SignerOption option : options) {
            if (option.userId == signerId) {
                return option;
            }
        }
        // An outside LO asking for anyone else's card is refused, not quietly re-signed.
        if (isExternalLo() && signerId != null) {
            throw new LetterException(OWN_CARD_ONLY_MESSAGE);
        }
        return options.isEmpty() ? null : options[0];
    }

    private static List<PicklistOption> describeOptions(Schema.SObjectField field) {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    // "1 Main St, Boca Raton, FL 33432", skipping whatever is blank; null when there is no street.
    @TestVisible
    private static String buildSubjectAddress(Lead leadRecord) {
        if (String.isBlank(leadRecord.Subject_Property_Street__c)) {
            return null;
        }
        List<String> parts = new List<String>{ leadRecord.Subject_Property_Street__c };
        if (String.isNotBlank(leadRecord.Subject_Property_City__c)) {
            parts.add(leadRecord.Subject_Property_City__c);
        }
        String stateZip = ((leadRecord.Property_State__c == null ? '' : leadRecord.Property_State__c) + ' '
            + (leadRecord.Subject_Property_Zip__c == null ? '' : leadRecord.Subject_Property_Zip__c)).trim();
        if (String.isNotBlank(stateZip)) {
            parts.add(stateZip);
        }
        return String.join(parts, ', ');
    }

    private static String buildBorrowerName(Lead leadRecord) {
        String fullName = ((leadRecord.FirstName == null ? '' : leadRecord.FirstName + ' ')
            + (leadRecord.LastName == null ? '' : leadRecord.LastName)).trim();
        return String.isBlank(fullName) ? leadRecord.Name : fullName;
    }

    /**
     * Everyone the letter is issued for: the Lead, then any co-borrowers added to it.
     *
     * The primary borrower is never a Borrower__c row - that object holds the additional
     * borrowers only - so the Lead always leads the list. Removed ones are excluded: taking a
     * co-borrower off the lead has to take them off the letter too.
     */
    @TestVisible
    private static List<String> buildApplicantNames(Lead leadRecord) {
        List<String> names = new List<String>{ buildBorrowerName(leadRecord) };
        if (!Schema.getGlobalDescribe().containsKey('Borrower__c')) {
            return names;
        }

        Id leadId = leadRecord.Id;
        for (SObject coBorrower : Database.query(
            'SELECT First_Name__c, Last_Name__c FROM Borrower__c' +
            ' WHERE Lead__c = :leadId AND Removed__c = FALSE' +
            ' WITH SYSTEM_MODE ORDER BY CreatedDate'
        )) {
            String coName = (
                (coBorrower.get('First_Name__c') == null ? '' : (String) coBorrower.get('First_Name__c') + ' ')
                + (coBorrower.get('Last_Name__c') == null ? '' : (String) coBorrower.get('Last_Name__c'))
            ).trim();
            if (String.isNotBlank(coName)) {
                names.add(coName);
            }
        }
        return names;
    }

    // "A", "A and B", "A, B and C" - read aloud by a realtor, so it has to be a sentence.
    @TestVisible
    private static String joinApplicantNames(List<String> names) {
        if (names == null || names.isEmpty()) {
            return '';
        }
        if (names.size() == 1) {
            return names[0];
        }
        List<String> allButLast = new List<String>(names);
        String last = allButLast.remove(allButLast.size() - 1);
        return String.join(allButLast, ', ') + ' and ' + last;
    }

    private static String formatCurrency(Decimal value) {
        if (value == null) {
            return '';
        }
        return '$' + value.setScale(0, System.RoundingMode.HALF_UP).format();
    }

    private static String htmlEncode(String value) {
        return String.isBlank(value) ? '' : value.escapeHtml4();
    }
}