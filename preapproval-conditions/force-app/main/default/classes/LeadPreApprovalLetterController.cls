/**
 * Backs the Pre-Approval Letter quick action on the Lead.
 *
 * The Loan Officer fills in the terms, those save back to the Lead so the record and the letter can
 * never disagree, a preview is generated for free-text editing, and Finalize stores the edited HTML
 * and moves the Lead to Pre-Approval. The Visualforce page renders that stored HTML as the PDF,
 * because Apex cannot produce a PDF and a URL parameter cannot carry a whole letter.
 */
public with sharing class LeadPreApprovalLetterController {
    private static final String PRE_APPROVAL_STATUS = 'Pre-Approval';
    private static final String STATUS_GATE_MESSAGE =
        'This Lead must be in Pre-Approval status before a letter can be issued. '
        + 'Please log a call to move the status to Pre-Approval, then try again.';
    // The stored picklist value is upper case; the letter prints the cased form the template uses.
    private static final String NON_QM_VALUE = 'NON-QM';
    private static final String NON_QM_DISPLAY = 'Non-QM';
    // Falls back to the Lead Owner if this user is ever deactivated or renamed.
    private static final String DEFAULT_SIGNER_NAME = 'Brandon Brotsky';
    private static final String COMPANY_NMLS = '2266637';
    private static final String COMPANY_ADDRESS = '327 Plaza Real #215, Boca Raton, FL 33432';

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
            context.nonQmType = leadRecord.Non_QM_Type__c;
            context.docsReviewed = leadRecord.Reviewed_Documents__c;
            context.financingOptions = describeOptions(Lead.Loan_Type_1st_TD__c);
            context.propertyOptions = describeOptions(Lead.Property_Type__c);
            context.nonQmOptions = describeOptions(Lead.Non_QM_Type__c);
            context.nonQmTriggerValue = NON_QM_VALUE;
            context.signerOptions = buildSignerOptions(leadRecord);
            context.defaultSignerId = context.signerOptions.isEmpty() ? null : context.signerOptions[0].userId;
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
        Id signerId
    ) {
        try {
            ensurePreApprovalStatus(loadLead(leadId));

            Lead leadUpdate = new Lead(
                Id = leadId,
                Purchase_Price__c = purchasePrice,
                Loan_Amount__c = loanAmount,
                Loan_Type_1st_TD__c = financingType,
                Property_Type__c = propertyType,
                // Cleared when the financing is not Non-QM, so a stale sub-type cannot survive a
                // change of loan type and reappear on a later letter.
                Non_QM_Type__c = NON_QM_VALUE.equalsIgnoreCase(financingType) ? nonQmType : null,
                Reviewed_Documents__c = docsReviewed
            );
            if (purchasePrice != null && purchasePrice != 0 && loanAmount != null) {
                leadUpdate.LTV__c = (loanAmount / purchasePrice * 100).setScale(2, System.RoundingMode.HALF_UP);
            }
            // SYSTEM_MODE, as elsewhere in this codebase: who may run this is governed by access to
            // the quick action, and the class is "with sharing" so record access still applies.
            Database.update(leadUpdate, true, AccessLevel.SYSTEM_MODE);

            Lead leadRecord = loadLead(leadId);
            SignerOption signer = resolveSigner(leadRecord, signerId);
            return buildLetterHtml(leadRecord, signer, docsReviewed);
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

            FinalizeResult result = new FinalizeResult();
            result.pdfPath = '/apex/Lead_Pre_Approval_Letter?id=' + leadId;
            result.fileName = buildLetterFileName(leadId);
            result.pdfBase64 = renderLetterPdf(leadId);
            StoredLetter stored = storeLetterFile(leadId, result.fileName, result.pdfBase64);
            result.downloadUrl = stored.downloadUrl;
            result.contentDocumentId = stored.contentDocumentId;
            result.emailedTo = emailLetterToFinalizer(leadId, result.fileName, result.pdfBase64);
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
        if (leadRecord == null || leadRecord.Status != PRE_APPROVAL_STATUS) {
            throw new LetterException(STATUS_GATE_MESSAGE);
        }
    }

    // ---------- letter ----------

    @TestVisible
    private static String buildLetterHtml(Lead leadRecord, SignerOption signer, String docsReviewed) {
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

            + '<tr><td>' + buildTermsTable(leadRecord, applicantNames, ltvSuffix) + '</td></tr>'

            + '<tr><td style="padding:22px 0 6px 0;font-size:12px;font-weight:bold;color:#1b6fc4;letter-spacing:0.5px;">QUALIFICATION REVIEW</td></tr>'
            + '<tr><td style="font-size:13px;line-height:20px;color:#33405c;">'
            + 'This pre-approval is subject to the terms and conditions of the applicable loan program, '
            + 'satisfactory property review, and no material change in the applicant\'s creditworthiness '
            + 'or financial position prior to closing.</td></tr>'

            + buildDocsReviewedRows(docsReviewed)

            + '<tr><td style="padding:34px 0 0 0;font-size:13px;font-weight:bold;color:#14284b;">'
            + 'Questions regarding this pre-approval? Please contact me directly.</td></tr>'

            + '<tr><td style="padding:26px 0 0 0;">' + buildSignerBlock(signer) + '</td></tr>'
            + '</table>';
    }

    private static String buildApplicantCell(List<String> applicantNames) {
        List<String> encoded = new List<String>();
        for (String name : applicantNames) {
            encoded.add(htmlEncode(name));
        }
        return String.join(encoded, '<br />');
    }

    private static String buildTermsTable(Lead leadRecord, List<String> applicantNames, String ltvSuffix) {
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
        rows.add(termRow('PROPERTY TYPE', htmlEncode(leadRecord.Property_Type__c), false, true));

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
            + '</td>'
            + '</tr></table>';
    }

    // ---------- helpers ----------

    private static Lead loadLead(Id leadId) {
        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Name, OwnerId, Owner.Name,
                   Purchase_Price__c, Loan_Amount__c, Loan_Type_1st_TD__c, Property_Type__c,
                   Reviewed_Documents__c, Non_QM_Type__c, Status
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

    private static List<SignerOption> buildSignerOptions(Lead leadRecord) {
        Set<Id> userIds = new Set<Id>();
        if (leadRecord.OwnerId != null && leadRecord.OwnerId.getSObjectType() == Schema.User.SObjectType) {
            userIds.add(leadRecord.OwnerId);
        }

        Map<Id, User> usersById = new Map<Id, User>([
            SELECT Id, Name, Title, Phone, MobilePhone, Email, NMLS__c, Headshot_URL__c, IsActive
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
        return option;
    }

    private static SignerOption resolveSigner(Lead leadRecord, Id signerId) {
        List<SignerOption> options = buildSignerOptions(leadRecord);
        for (SignerOption option : options) {
            if (option.userId == signerId) {
                return option;
            }
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
