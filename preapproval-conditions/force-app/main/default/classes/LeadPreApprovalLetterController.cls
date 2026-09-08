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
        @AuraEnabled public String pdfPath;
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
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
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
        String borrowerName = buildBorrowerName(leadRecord);
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
            + htmlEncode(borrowerName) + ' is pre-approved for mortgage financing.</td></tr>'
            + '<tr><td style="padding:0 0 12px 0;font-size:13px;line-height:20px;color:#33405c;">'
            + 'To whom it may concern:</td></tr>'
            + '<tr><td style="padding:0 0 20px 0;font-size:13px;line-height:20px;color:#33405c;">'
            + 'I have issued this Pre-Approval Letter to certify that the below applicant(s) is/are '
            + 'pre-approved for financing per Desktop Underwriter (DU) and/or Loan Prospector (LP).</td></tr>'

            + '<tr><td>' + buildTermsTable(leadRecord, borrowerName, ltvSuffix) + '</td></tr>'

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

    private static String buildTermsTable(Lead leadRecord, String borrowerName, String ltvSuffix) {
        List<String> rows = new List<String>();
        rows.add(termRow('APPLICANT', htmlEncode(borrowerName), false, true));
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
                    + '<span style="color:#2e7d5b;font-weight:bold;">&#10003;</span>&nbsp;&nbsp;'
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
