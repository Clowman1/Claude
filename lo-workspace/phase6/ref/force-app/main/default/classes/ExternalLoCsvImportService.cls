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
        } else if (LoWsPartnerTagService.isTagMode()) {
            importTaggedPartnerRows(table, result);
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

        // LO Workspace: org-wide duplicate rules (someone else's lead or client is refused).
        List<String> conflicts = null;
        if (LoWsPartnerTagService.isTagMode()) {
            List<String> rowEmails = new List<String>();
            List<String> rowPhones = new List<String>();
            for (List<String> row : table.rows) {
                rowEmails.add(ExternalLoCsvParser.cell(row, headerIndex, 'email'));
                rowPhones.add(ExternalLoCsvParser.cell(row, headerIndex, 'phone'));
            }
            conflicts = LoWsPartnerTagService.consumerConflicts(rowEmails, rowPhones);
        }

        List<Lead> toInsert = new List<Lead>();
        List<Integer> insertRowNumbers = new List<Integer>();
        List<String> insertNames = new List<String>();
        List<Account> clients = new List<Account>();
        List<Integer> clientRowNumbers = new List<Integer>();
        List<String> clientNames = new List<String>();

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

            if (conflicts != null && conflicts[i] != null) {
                result.errors.add(outcome('e', rowNumber, displayName, conflicts[i]));
                continue;
            }

            Boolean pastClient = typeValue != null && typeValue.toLowerCase().contains('past');
            String emailKey = String.isBlank(email) ? null : email.toLowerCase();
            String phoneKey = ExternalLoPhoneNormalizer.matchKey(phone);
            Boolean matched = (emailKey != null && existingEmails.contains(emailKey))
                || (phoneKey != null && existingPhones.contains(phoneKey));
            if (matched) {
                if (conflicts != null) {
                    result.errors.add(outcome('e', rowNumber, displayName, 'Same person as an earlier row. Imported once.'));
                }
                continue;
            }

            if (pastClient && conflicts != null) {
                // LO Workspace: a past client is a borrower Person Account I own, never a New lead.
                Account client = LoWsPartnerTagService.newPastClient(firstName, lastName, fullName, phone, email, city, notes);
                // Same "most recent" fields Set_Most_Recent_Closed_Data_on_the_Account fills when a Reach loan closes.
                client.Most_Recent_Closing_Date__c = parseDate(ExternalLoCsvParser.cell(row, headerIndex, 'closingdate'));
                client.Most_Recent_Loan_Amount__c = loanAmount;
                client.Most_Recent_Loan_Purpose__c = String.isBlank(purpose) ? null : purpose.trim();
                client.Purchase_Price__pc = parseAmount(ExternalLoCsvParser.cell(row, headerIndex, 'purchaseprice'));
                clients.add(client);
                clientRowNumbers.add(rowNumber);
                clientNames.add(displayName);
                if (emailKey != null) {
                    existingEmails.add(emailKey);
                }
                if (phoneKey != null) {
                    existingPhones.add(phoneKey);
                }
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

        // Leads first, then past-client Person Accounts: two type chunks in one partial-success insert.
        List<SObject> records = new List<SObject>();
        records.addAll(toInsert);
        records.addAll(clients);
        insertRowNumbers.addAll(clientRowNumbers);
        insertNames.addAll(clientNames);
        if (records.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saveResults = Database.insert(records, false, AccessLevel.SYSTEM_MODE);
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
        // Lead and client rows were inserted as two groups; report them in file order.
        result.successes.sort();
        result.errors.sort();
    }

    /**
     * LO Workspace partner rows, same rule as Add partner: an existing partner-type match is tagged
     * (no new record), any other existing person is refused with the admin message, otherwise a
     * new partner is created and tagged. One duplicate query for the whole file.
     */
    private static void importTaggedPartnerRows(ExternalLoCsvParser.Table table, ImportResult result) {
        Map<String, Integer> headerIndex = ExternalLoCsvParser.headerIndex(table.headers);
        List<Integer> rowNumbers = new List<Integer>();
        List<String> names = new List<String>();
        List<String> emails = new List<String>();
        List<String> phones = new List<String>();
        List<List<String>> kept = new List<List<String>>();
        Map<String, Integer> firstRowByKey = new Map<String, Integer>();
        for (Integer i = 0; i < table.rows.size(); i++) {
            List<String> row = table.rows[i];
            Integer rowNumber = i + 2;
            String name = resolveName(
                ExternalLoCsvParser.cell(row, headerIndex, 'firstname'),
                ExternalLoCsvParser.cell(row, headerIndex, 'lastname'),
                ExternalLoCsvParser.cell(row, headerIndex, 'name')
            );
            String email = ExternalLoCsvParser.cell(row, headerIndex, 'email');
            String phone = ExternalLoCsvParser.cell(row, headerIndex, 'phone');
            String emailKey = PersonAccountDuplicateService.normalizeEmail(email);
            String phoneKey = PersonAccountDuplicateService.normalizePhone(phone);
            if (String.isBlank(name)) {
                result.errors.add(outcome('e', rowNumber, 'Row ' + rowNumber, 'Add a first and last name.'));
                continue;
            }
            if (ExternalLoCsvParser.cell(row, headerIndex, 'company') == null) {
                result.errors.add(outcome('e', rowNumber, name, 'Add the brokerage or company.'));
                continue;
            }
            if (emailKey == null && phoneKey == null) {
                result.errors.add(outcome('e', rowNumber, name, 'Add a phone number or email so we can check Reach for duplicates.'));
                continue;
            }
            Integer earlier = firstRowByKey.get(emailKey) ?? firstRowByKey.get(phoneKey);
            if (earlier != null) {
                result.errors.add(outcome('e', rowNumber, name, 'Same person as row ' + earlier + '. Imported once.'));
                continue;
            }
            if (emailKey != null) firstRowByKey.put(emailKey, rowNumber);
            if (phoneKey != null) firstRowByKey.put(phoneKey, rowNumber);
            rowNumbers.add(rowNumber);
            names.add(name);
            emails.add(email);
            phones.add(phone);
            kept.add(row);
        }
        if (kept.isEmpty()) {
            return;
        }

        List<LoWsPartnerTagService.Decision> decisions = LoWsPartnerTagService.classify(emails, phones);
        Set<Id> alreadyMine = LoWsPartnerTagService.myTags(null).keySet();
        Map<Integer, Id> existingByIndex = new Map<Integer, Id>();
        List<Account> toInsert = new List<Account>();
        List<Integer> insertIndex = new List<Integer>();
        for (Integer k = 0; k < kept.size(); k++) {
            LoWsPartnerTagService.Decision d = decisions[k];
            if (!d.partners.isEmpty()) {
                existingByIndex.put(k, d.partners[0].Id);
            } else if (d.blocked) {
                result.errors.add(outcome('e', rowNumbers[k], names[k], LoWsPartnerTagService.ADMIN_MESSAGE));
            } else {
                List<String> row = kept[k];
                toInsert.add(LoWsPartnerTagService.newPartner(
                    names[k], phones[k], emails[k],
                    ExternalLoCsvParser.cell(row, headerIndex, 'company'),
                    ExternalLoCsvParser.cell(row, headerIndex, 'market'),
                    LoWsPartnerTagService.industryFor(ExternalLoCsvParser.cell(row, headerIndex, 'partnertype'))
                ));
                insertIndex.add(k);
            }
        }

        Map<Integer, Id> createdByIndex = new Map<Integer, Id>();
        List<Database.SaveResult> saved = Database.insert(toInsert, false);
        for (Integer j = 0; j < saved.size(); j++) {
            Integer k = insertIndex[j];
            if (saved[j].isSuccess()) {
                createdByIndex.put(k, saved[j].getId());
            } else {
                result.errors.add(outcome('e', rowNumbers[k], names[k], ExternalLoCsvDmlMessage.fromSaveResult(saved[j])));
            }
        }

        Set<Id> toTag = new Set<Id>(existingByIndex.values());
        toTag.addAll(createdByIndex.values());
        Set<Id> tagged = LoWsPartnerTagService.tagAccounts(toTag);
        for (Integer k = 0; k < kept.size(); k++) {
            Id accountId = existingByIndex.get(k) ?? createdByIndex.get(k);
            if (accountId == null) {
                continue;
            }
            if (!tagged.contains(accountId)) {
                result.errors.add(outcome('e', rowNumbers[k], names[k], 'That partner could not be added to your list. Ask an admin for help.'));
            } else if (createdByIndex.containsKey(k)) {
                result.successes.add(outcome('a', rowNumbers[k], names[k], ROW_ADDED));
            } else if (alreadyMine.contains(accountId)) {
                result.successes.add(outcome('a', rowNumbers[k], names[k], 'Already on your list.'));
            } else {
                result.successes.add(outcome('a', rowNumbers[k], names[k], 'Already at Reach. ' + ROW_ADDED));
            }
        }
        result.successes.sort();
        result.errors.sort();
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

    // Accepts 2024-05-31, 5/31/2024 and 5/31/24. Anything else is left blank rather than failing the row.
    @TestVisible
    private static Date parseDate(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String value = raw.trim();
        try {
            Matcher iso = Pattern.compile('(\\d{4})-(\\d{1,2})-(\\d{1,2}).*').matcher(value);
            if (iso.matches()) {
                return Date.newInstance(Integer.valueOf(iso.group(1)), Integer.valueOf(iso.group(2)), Integer.valueOf(iso.group(3)));
            }
            Matcher us = Pattern.compile('(\\d{1,2})[/-](\\d{1,2})[/-](\\d{2}|\\d{4})').matcher(value);
            if (us.matches()) {
                Integer year = Integer.valueOf(us.group(3));
                if (year < 100) {
                    year += 2000;
                }
                Integer month = Integer.valueOf(us.group(1));
                Integer day = Integer.valueOf(us.group(2));
                if (month < 1 || month > 12 || day < 1 || day > Date.daysInMonth(year, month)) {
                    return null;
                }
                return Date.newInstance(year, month, day);
            }
        } catch (Exception e) {
            return null;
        }
        return null;
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
        // Newlines inside quoted cells are not rows. Count only the unquoted text: the even pieces
        // between double quotes (an escaped "" toggles twice, so it is neutral).
        String unquoted = '';
        List<String> pieces = csvBody.split('"', -1);
        for (Integer i = 0; i < pieces.size(); i += 2) {
            unquoted += pieces[i];
        }
        Integer lineBreaks = unquoted.countMatches('\n');
        Integer crBreaks = unquoted.countMatches('\r');
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