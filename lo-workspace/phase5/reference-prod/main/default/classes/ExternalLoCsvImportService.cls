public with sharing class ExternalLoCsvImportService {
    // ADR-0002: Lead and assignment DML use SYSTEM_MODE (community license).
    // Partner Account insert stays in user mode. Linked partners get a Manual AccountShare.
    public static final String FAMILY_CONSUMER = 'consumer';
    public static final String FAMILY_PARTNER = 'partner';
    public static final Integer MAX_ROWS = 200;
    public static final Integer MAX_CSV_CHARS = 120000;
    public static final String ROW_ADDED = 'Added to your list.';

    public static ImportResult importCsv(String family, String csvBody) {
        if (String.isBlank(csvBody)) {
            throw new DomainException('Choose a CSV file to upload.');
        }
        if (csvBody.length() > MAX_CSV_CHARS) {
            throw new DomainException('That file is too large. Export 200 rows or fewer and try again.');
        }
        if (estimatedLineCount(csvBody) > MAX_ROWS + 1) {
            throw new DomainException('Upload 200 rows or fewer at a time.');
        }
        String normalizedFamily = family == null ? '' : family.trim().toLowerCase();
        if (normalizedFamily != FAMILY_CONSUMER && normalizedFamily != FAMILY_PARTNER) {
            throw new DomainException('Choose consumer pipeline or realtor pipeline.');
        }

        ExternalLoCsvParser.Table table = ExternalLoCsvParser.parse(csvBody);
        if (table.rows.isEmpty()) {
            throw new DomainException('The file has no data rows. Check the header row and try again.');
        }
        if (table.rows.size() > MAX_ROWS) {
            throw new DomainException('Upload 200 rows or fewer at a time.');
        }

        ImportResult result = emptyResult();
        if (normalizedFamily == FAMILY_CONSUMER) {
            importConsumerRows(table, result);
        } else {
            ExternalLoPartnerCsvImporter.importRows(table, result);
        }
        foldLinksIntoSuccesses(result);
        result.userMessage = buildSummary(result);
        return result;
    }

    private static void importConsumerRows(ExternalLoCsvParser.Table table, ImportResult result) {
        Map<String, Integer> headerIndex = ExternalLoCsvParser.headerIndex(table.headers);
        Id ownerId = UserInfo.getUserId();
        LeadRepository leadRepository = LeadRepository.getInstance();
        Id recordTypeId = leadRepository.selectConsumerLeadRecordTypeId();
        if (recordTypeId == null) {
            throw new DomainException('Consumer lead record type is not configured.');
        }

        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        for (List<String> row : table.rows) {
            String email = ExternalLoCsvParser.cell(row, headerIndex, 'email');
            String phone = ExternalLoCsvParser.cell(row, headerIndex, 'phone');
            if (!String.isBlank(email)) {
                emails.add(email.trim().toLowerCase());
            }
            if (!String.isBlank(phone)) {
                phones.add(phone);
            }
        }

        Set<String> existingEmails = new Set<String>();
        Set<String> existingPhones = new Set<String>();
        for (Lead existing : leadRepository.selectPortalLeadsForImportMatch(
            ownerId,
            emails,
            ExternalLoPhoneNormalizer.soqlVariants(phones)
        )) {
            if (!String.isBlank(existing.Email)) {
                existingEmails.add(existing.Email.toLowerCase());
            }
            String phoneKey = ExternalLoPhoneNormalizer.matchKey(existing.Phone);
            if (phoneKey == null) {
                phoneKey = ExternalLoPhoneNormalizer.matchKey(existing.MobilePhone);
            }
            if (phoneKey != null) {
                existingPhones.add(phoneKey);
            }
        }

        List<Lead> toInsert = new List<Lead>();
        List<Integer> insertRowNumbers = new List<Integer>();
        List<String> insertNames = new List<String>();

        for (Integer i = 0; i < table.rows.size(); i++) {
            List<String> row = table.rows[i];
            Integer rowNumber = i + 2;
            String firstName = ExternalLoCsvParser.cell(row, headerIndex, 'firstname');
            String lastName = ExternalLoCsvParser.cell(row, headerIndex, 'lastname');
            String fullName = ExternalLoCsvParser.cell(row, headerIndex, 'name');
            String phone = ExternalLoCsvParser.cell(row, headerIndex, 'phone');
            String email = ExternalLoCsvParser.cell(row, headerIndex, 'email');
            String typeValue = ExternalLoCsvParser.cell(row, headerIndex, 'type');
            String purpose = ExternalLoCsvParser.cell(row, headerIndex, 'purpose');
            String city = ExternalLoCsvParser.cell(row, headerIndex, 'city');
            String notes = ExternalLoCsvParser.cell(row, headerIndex, 'notes');
            Decimal loanAmount = parseAmount(ExternalLoCsvParser.cell(row, headerIndex, 'loanamount'));

            String displayName = resolveName(firstName, lastName, fullName);
            if (String.isBlank(displayName)) {
                result.errors.add(outcome('e', rowNumber, 'Row ' + rowNumber, 'Add a first and last name.'));
                continue;
            }
            if (String.isBlank(phone) && String.isBlank(email)) {
                result.errors.add(outcome('e', rowNumber, displayName, 'Add a phone number or email.'));
                continue;
            }

            Boolean pastClient = typeValue != null && typeValue.toLowerCase().contains('past');
            String emailKey = String.isBlank(email) ? null : email.toLowerCase();
            String phoneKey = ExternalLoPhoneNormalizer.matchKey(phone);
            Boolean matched = (emailKey != null && existingEmails.contains(emailKey))
                || (phoneKey != null && existingPhones.contains(phoneKey));
            if (matched) {
                continue;
            }

            List<String> nameParts = displayName.trim().split('\\s+', 2);
            Lead leadRecord = new Lead();
            leadRecord.RecordTypeId = recordTypeId;
            leadRecord.FirstName = nameParts.size() > 1 ? nameParts[0] : (String.isBlank(firstName) ? displayName : firstName);
            leadRecord.LastName = nameParts.size() > 1 ? nameParts[1] : (String.isBlank(lastName) ? 'Borrower' : lastName);
            leadRecord.Company = leadRecord.LastName + ' Household';
            leadRecord.Status = 'New';
            leadRecord.OwnerId = ownerId;
            leadRecord.Phone = phone;
            leadRecord.Email = email;
            leadRecord.Loan_Purpose__c = purpose;
            leadRecord.Loan_Amount__c = loanAmount;
            leadRecord.City = city;
            leadRecord.Description = notes;
            if (pastClient) {
                leadRecord.LeadSource = 'Past Client';
            }
            toInsert.add(leadRecord);
            insertRowNumbers.add(rowNumber);
            insertNames.add(displayName);
            if (emailKey != null) {
                existingEmails.add(emailKey);
            }
            if (phoneKey != null) {
                existingPhones.add(phoneKey);
            }
        }

        if (toInsert.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saveResults = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                result.successes.add(outcome('a', insertRowNumbers[i], insertNames[i], ROW_ADDED));
            } else {
                result.errors.add(outcome(
                    'e',
                    insertRowNumbers[i],
                    insertNames[i],
                    ExternalLoCsvDmlMessage.fromSaveResult(saveResults[i])
                ));
            }
        }
    }

    public static String resolveName(String firstName, String lastName, String fullName) {
        if (!String.isBlank(fullName)) {
            return fullName.trim();
        }
        List<String> parts = new List<String>();
        if (!String.isBlank(firstName)) {
            parts.add(firstName.trim());
        }
        if (!String.isBlank(lastName)) {
            parts.add(lastName.trim());
        }
        return String.join(parts, ' ');
    }

    private static Decimal parseAmount(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String digitsOnly = raw.replaceAll('[^0-9.]', '');
        if (String.isBlank(digitsOnly) || digitsOnly == '.') {
            return null;
        }
        if (!Pattern.matches('[0-9]*\\.?[0-9]*', digitsOnly)) {
            return null;
        }
        return Decimal.valueOf(digitsOnly);
    }

    private static ImportResult emptyResult() {
        ImportResult result = new ImportResult();
        result.successes = new List<RowOutcome>();
        result.links = new List<RowOutcome>();
        result.errors = new List<RowOutcome>();
        result.successCount = 0;
        result.linkedCount = 0;
        result.errorCount = 0;
        return result;
    }

    public static RowOutcome outcome(String kind, Integer rowNumber, String name, String message) {
        RowOutcome row = new RowOutcome();
        row.rowNumber = rowNumber;
        row.rowKey = kind + '-' + String.valueOf(rowNumber);
        row.name = name;
        row.message = message;
        return row;
    }

    private static String buildSummary(ImportResult result) {
        List<String> parts = new List<String>();
        if (result.successCount > 0) {
            parts.add(result.successCount + ' added');
        }
        if (result.errorCount > 0) {
            parts.add(result.errorCount + ' need attention');
        }
        if (parts.isEmpty()) {
            return 'No new rows were added.';
        }
        return String.join(parts, '. ') + '.';
    }

    @TestVisible
    static Integer estimatedLineCount(String csvBody) {
        if (String.isBlank(csvBody)) {
            return 0;
        }
        Integer lineBreaks = csvBody.countMatches('\n');
        Integer crBreaks = csvBody.countMatches('\r');
        if (crBreaks > lineBreaks) {
            lineBreaks = crBreaks;
        }
        Boolean trailingBreak = csvBody.endsWith('\n') || csvBody.endsWith('\r');
        return lineBreaks + (trailingBreak ? 0 : 1);
    }

    /**
     * Linked rows join successes in CSV order so the Aura payload has one Added
     * list. linkedCount stays for Apex tests and is not @AuraEnabled (ADR-0006).
     */
    private static void foldLinksIntoSuccesses(ImportResult result) {
        result.linkedCount = result.links.size();
        if (!result.links.isEmpty()) {
            result.successes.addAll(result.links);
            result.links = new List<RowOutcome>();
            result.successes.sort();
        }
        result.successCount = result.successes.size();
        result.errorCount = result.errors.size();
    }

    public class ImportResult {
        @AuraEnabled public Integer successCount;
        public Integer linkedCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public String userMessage;
        @AuraEnabled public List<RowOutcome> successes;
        @AuraEnabled public List<RowOutcome> links;
        @AuraEnabled public List<RowOutcome> errors;
    }

    public class RowOutcome implements Comparable {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String rowKey;
        @AuraEnabled public String name;
        @AuraEnabled public String message;

        public Integer compareTo(Object other) {
            RowOutcome that = (RowOutcome) other;
            Integer left = rowNumber == null ? 0 : rowNumber;
            Integer right = that.rowNumber == null ? 0 : that.rowNumber;
            if (left == right) {
                return 0;
            }
            return left > right ? 1 : -1;
        }
    }
}