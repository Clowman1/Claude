public with sharing class ExternalLoPortalConversionFacade {
    public class ConversionPreview {
        @AuraEnabled public String contextRecordKey;
        @AuraEnabled public String borrowerName;
        @AuraEnabled public String borrowerIncome;
        @AuraEnabled public String ssnMasked;
        @AuraEnabled public Boolean ssnPresent;
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public String estimatedPropertyValue;
        @AuraEnabled public String loanAmount;
        @AuraEnabled public Boolean readyToConvert;
        @AuraEnabled public List<String> missingFields;
        @AuraEnabled public Boolean alreadyConverted;
        @AuraEnabled public String convertedTransactionKey;
    }

    public class ConversionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String userMessage;
        @AuraEnabled public String transactionKey;
        @AuraEnabled public String errorCode;
    }

    private static final List<String> SSN_FIELD_CANDIDATES = new List<String>{
        'SSN__c',
        'Borrower_SSN__c',
        'Social_Security_Number__c',
        'Social_Security__c'
    };

    private static final List<String> INCOME_FIELD_CANDIDATES = new List<String>{
        'Household_Income__c',
        'Annual_Income__c',
        'Gross_Monthly_Income__c',
        'Borrower_Income__c'
    };

    @AuraEnabled
    public static ConversionPreview getConversionPreview(String contextRecordKey) {
        Id leadId = parseContextRecordKey(contextRecordKey);
        Id userId = UserInfo.getUserId();
        Lead leadRecord = LeadRepository.getInstance().selectPortalLeadForConversion(leadId, userId);
        if (leadRecord == null) {
            throw new AuraHandledException('Lead could not be found or is not visible.');
        }

        ConversionPreview preview = new ConversionPreview();
        preview.contextRecordKey = String.valueOf(leadRecord.Id);
        preview.alreadyConverted = leadRecord.IsConverted == true;
        preview.convertedTransactionKey = leadRecord.Converted_Transaction_ID__c == null
            ? null
            : String.valueOf(leadRecord.Converted_Transaction_ID__c);
        preview.borrowerName = buildBorrowerName(leadRecord);
        preview.borrowerIncome = formatIncome(readFirstPopulatedField(leadRecord, INCOME_FIELD_CANDIDATES));
        String rawSsn = readFirstPopulatedField(leadRecord, SSN_FIELD_CANDIDATES);
        preview.ssnPresent = String.isNotBlank(rawSsn);
        preview.ssnMasked = maskSsn(rawSsn);
        preview.propertyAddress = buildPropertyAddress(leadRecord);
        preview.estimatedPropertyValue = formatCurrency(firstDecimal(
            leadRecord,
            new List<String>{ 'Value_of_Property__c', 'Estimated_Property_Value__c', 'Purchase_Price__c' }
        ));
        preview.loanAmount = formatCurrency(leadRecord.Loan_Amount__c);
        preview.missingFields = buildMissingFields(preview);
        preview.readyToConvert = !preview.alreadyConverted && preview.missingFields.isEmpty();
        return preview;
    }

    @AuraEnabled
    public static ConversionResult confirmConversion(String contextRecordKey, Boolean acknowledged) {
        return confirmConversionWithReceived(contextRecordKey, acknowledged, null);
    }

    /**
     * infoReceived: missing checklist items the LO marked "Info received" (labels from missingFields).
     * A field that already has data never needs it.
     */
    @AuraEnabled
    public static ConversionResult confirmConversionWithReceived(
        String contextRecordKey, Boolean acknowledged, List<String> infoReceived
    ) {
        ConversionResult result = new ConversionResult();
        result.success = false;
        if (acknowledged != true) {
            result.errorCode = 'ACK_REQUIRED';
            result.userMessage = 'Confirm the TRID checklist before converting this lead.';
            return result;
        }

        ConversionPreview preview = getConversionPreview(contextRecordKey);
        if (preview.alreadyConverted) {
            result.errorCode = 'ALREADY_CONVERTED';
            result.userMessage = 'This lead is already converted.';
            result.transactionKey = preview.convertedTransactionKey;
            return result;
        }
        List<String> stillMissing = new List<String>();
        Set<String> received = infoReceived == null ? new Set<String>() : new Set<String>(infoReceived);
        for (String field : preview.missingFields) {
            if (!received.contains(field)) {
                stillMissing.add(field);
            }
        }
        if (!stillMissing.isEmpty()) {
            result.errorCode = 'MISSING_TRID_FIELDS';
            result.userMessage = 'Fill in or mark Info received before converting: '
                + String.join(stillMissing, ', ');
            return result;
        }

        Id leadId = parseContextRecordKey(contextRecordKey);
        try {
            ConvertLeadsInvocable.convertLeads(new List<Id>{ leadId });
            Lead convertedLead = [
                SELECT Id, IsConverted, Converted_Transaction_ID__c
                FROM Lead
                WHERE Id = :leadId
                WITH USER_MODE
                LIMIT 1
            ];
            result.success = convertedLead.IsConverted == true;
            if (result.success) {
                recordInfoReceived(leadId, preview.missingFields, received);
            }
            result.transactionKey = convertedLead.Converted_Transaction_ID__c == null
                ? null
                : String.valueOf(convertedLead.Converted_Transaction_ID__c);
            result.userMessage = result.success
                ? 'Lead converted to a transaction.'
                : 'Conversion did not complete. Contact support if this persists.';
            if (!result.success) {
                result.errorCode = 'CONVERSION_INCOMPLETE';
            }
        } catch (Exception error) {
            result.errorCode = 'CONVERSION_FAILED';
            result.userMessage = error.getMessage();
        }
        return result;
    }

    /**
     * Compliance trail: a Note on the lead naming each checklist item the LO marked Info received
     * instead of it coming over from ARIVE. Written after a successful conversion; no team email.
     */
    @TestVisible
    private static void recordInfoReceived(Id leadId, List<String> missingFields, Set<String> received) {
        List<String> confirmed = new List<String>();
        for (String field : missingFields) {
            if (received.contains(field)) {
                confirmed.add(field);
            }
        }
        if (confirmed.isEmpty()) {
            return;
        }
        String body = 'Converted by ' + UserInfo.getName() + ' on ' + System.now().format('MMM d, yyyy h:mm a')
            + '.<br>Marked Info received (not in Salesforce from ARIVE): ' + String.join(confirmed, ', ').escapeHtml4() + '.';
        LeadNoteTeamNotifier.suppressForLoggedActivity = true;
        try {
            Database.insert(new Enhanced_Note__c(
                Lead__c = leadId,
                Type__c = 'Note',
                Subject__c = 'Conversion: application info confirmed by LO',
                Body__c = body
            ), false, AccessLevel.SYSTEM_MODE);
        } finally {
            LeadNoteTeamNotifier.suppressForLoggedActivity = false;
        }
    }

    private static Id parseContextRecordKey(String contextRecordKey) {
        if (String.isBlank(contextRecordKey)) {
            return null;
        }
        return (Id) contextRecordKey;
    }

    private static String buildBorrowerName(Lead leadRecord) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(leadRecord.FirstName)) {
            parts.add(leadRecord.FirstName);
        }
        if (String.isNotBlank(leadRecord.LastName)) {
            parts.add(leadRecord.LastName);
        }
        if (!parts.isEmpty()) {
            return String.join(parts, ' ');
        }
        return leadRecord.Name;
    }

    private static String buildPropertyAddress(Lead leadRecord) {
        List<String> lines = new List<String>();
        // Subject property, not the standard Address (that is the borrower's mailing address).
        if (String.isNotBlank(leadRecord.Subject_Property_Street__c)) {
            lines.add(leadRecord.Subject_Property_Street__c);
        }
        String cityStateZip = joinNonBlank(new List<String>{
            leadRecord.Subject_Property_City__c,
            leadRecord.Property_State__c,
            leadRecord.Subject_Property_Zip__c
        }, ', ');
        if (String.isNotBlank(cityStateZip)) {
            lines.add(cityStateZip);
        }
        return joinNonBlank(lines, '\n');
    }

    private static List<String> buildMissingFields(ConversionPreview preview) {
        List<String> missing = new List<String>();
        if (String.isBlank(preview.borrowerName)) {
            missing.add('Borrower name');
        }
        if (String.isBlank(preview.borrowerIncome)) {
            missing.add('Borrower income');
        }
        // SSN is never required: ARIVE can't send it to Salesforce, and an LO converting a lead has it.
        if (String.isBlank(preview.propertyAddress)) {
            missing.add('Subject property');
        }
        if (String.isBlank(preview.estimatedPropertyValue)) {
            missing.add('Estimated property value');
        }
        if (String.isBlank(preview.loanAmount)) {
            missing.add('Loan amount');
        }
        return missing;
    }

    private static String readFirstPopulatedField(SObject record, List<String> fieldNames) {
        for (String fieldName : fieldNames) {
            if (!record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) {
                continue;
            }
            Object value = record.get(fieldName);
            if (value != null && String.isNotBlank(String.valueOf(value))) {
                return String.valueOf(value);
            }
        }
        return null;
    }

    private static Decimal firstDecimal(SObject record, List<String> fieldNames) {
        for (String fieldName : fieldNames) {
            if (!record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) {
                continue;
            }
            Object value = record.get(fieldName);
            if (value instanceof Decimal) {
                return (Decimal) value;
            }
        }
        return null;
    }

    private static String maskSsn(String rawSsn) {
        if (String.isBlank(rawSsn)) {
            return '—';
        }
        String digits = rawSsn.replaceAll('[^0-9]', '');
        if (digits.length() >= 4) {
            return '***-**-' + digits.substring(digits.length() - 4);
        }
        return 'On file';
    }

    private static String formatIncome(String rawIncome) {
        if (String.isBlank(rawIncome)) {
            return null;
        }
        try {
            Decimal amount = Decimal.valueOf(rawIncome.replaceAll('[^0-9.-]', ''));
            return formatCurrency(amount);
        } catch (Exception ignored) {
            return rawIncome;
        }
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) {
            return null;
        }
        return '$' + amount.setScale(2).format();
    }

    private static String joinNonBlank(List<String> values, String separator) {
        List<String> kept = new List<String>();
        for (String value : values) {
            if (String.isNotBlank(value)) {
                kept.add(value);
            }
        }
        return kept.isEmpty() ? null : String.join(kept, separator);
    }
}