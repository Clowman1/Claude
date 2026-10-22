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

        // LO Workspace (Phase 6): org-wide duplicate rules. Someone else's Nurturing lead is taken
        // over; anyone else being worked, converted or someone else's client is refused.
        List<String> conflicts = null;
        List<LoWsLeadIntakeService.Verdict> verdicts = null;
        Map<Id, String> takeoverSources = new Map<Id, String>();
        Map<Id, Integer> takeoverRows = new Map<Id, Integer>();
        Map<Id, String> takeoverNames = new Map<Id, String>();
        List<String> blockedAlerts = new List<String>();
        if (LoWsPartnerTagService.isTagMode()) {
            List<String> rowEmails = new List<String>();
            List<String> rowPhones = new List<String>();
            for (List<String> row : table.rows) {
                rowEmails.add(ExternalLoCsvParser.cell(row, headerIndex, 'email'));
                rowPhones.add(ExternalLoCsvParser.cell(row, headerIndex, 'phone'));
            }
            verdicts = LoWsLeadIntakeService.decide(ownerId, rowEmails, rowPhones);
            conflicts = new List<String>();
            for (LoWsLeadIntakeService.Verdict v : verdicts) conflicts.add(v.message);
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
            String fullName = flipLastFirst(ExternalLoCsvParser.cell(row, headerIndex, 'name'));
            if (fullName == null && lastName == null && firstName != null && firstName.contains(',')) {
                fullName = flipLastFirst(firstName); // "Okafor, Grace" typed into First Name
            }
            String phone = ExternalLoCsvParser.cell(row, headerIndex, 'phone');
            String email = ExternalLoCsvParser.cell(row, headerIndex, 'email');
            String typeValue = ExternalLoCsvParser.cell(row, headerIndex, 'type');
            String purpose = ExternalLoCsvParser.cell(row, headerIndex, 'purpose');
            String city = ExternalLoCsvParser.cell(row, headerIndex, 'city');
            String notes = ExternalLoCsvParser.cell(row, headerIndex, 'notes');
            Decimal loanAmount = parseAmount(ExternalLoCsvParser.cell(row, headerIndex, 'loanamount'));
            List<String> address = parseAddress(
                ExternalLoCsvParser.cell(row, headerIndex, 'street'), city,
                ExternalLoCsvParser.cell(row, headerIndex, 'state'), ExternalLoCsvParser.cell(row, headerIndex, 'zip')
            );
            city = address[1];
            Date closingDate = parseDate(ExternalLoCsvParser.cell(row, headerIndex, 'closingdate'));
            String tags = ExternalLoCsvParser.cell(row, headerIndex, 'tags');

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
                if (conflicts[i] == LoWsLeadIntakeService.BLOCKED_MESSAGE) {
                    blockedAlerts.add('Row ' + rowNumber + ' ' + displayName + ' -> ' + verdicts[i].alert);
                }
                continue;
            }

            // A past client: Type/Stage says so, a "past client" tag, or a closing date already behind us.
            Boolean pastClient = (typeValue != null && typeValue.toLowerCase().contains('past'))
                || (tags != null && tags.toLowerCase().contains('past client'))
                || (closingDate != null && closingDate < Date.today());
            String emailKey = String.isBlank(email) ? null : email.toLowerCase();
            String phoneKey = ExternalLoPhoneNormalizer.matchKey(phone);
            Id takeoverId = verdicts == null ? null : verdicts[i].takeoverLeadId;
            Boolean matched = (emailKey != null && existingEmails.contains(emailKey))
                || (phoneKey != null && existingPhones.contains(phoneKey))
                || (takeoverId != null && takeoverSources.containsKey(takeoverId));
            if (matched) {
                if (conflicts != null) {
                    result.errors.add(outcome('e', rowNumber, displayName, 'Same person as an earlier row. Imported once.'));
                }
                continue;
            }
            if (takeoverId != null) {
                // Someone else's Nurturing lead: it becomes mine (past-client rows included, as a lead).
                takeoverSources.put(takeoverId, pastClient ? 'Past Client' : null);
                takeoverRows.put(takeoverId, rowNumber);
                takeoverNames.put(takeoverId, displayName);
                if (emailKey != null) {
                    existingEmails.add(emailKey);
                }
                if (phoneKey != null) {
                    existingPhones.add(phoneKey);
                }
                continue;
            }

            if (pastClient && conflicts != null) {
                if (verdicts[i].otherClient) {
                    // A lead may share a person with someone else's client; a second Person Account may not.
                    result.errors.add(outcome('e', rowNumber, displayName, LoWsLeadIntakeService.BLOCKED_MESSAGE));
                    continue;
                }
                // LO Workspace: a past client is a borrower Person Account I own, never a New lead.
                Account client = LoWsPartnerTagService.newPastClient(firstName, lastName, fullName, phone, email, city, notes);
                // Same "most recent" fields Set_Most_Recent_Closed_Data_on_the_Account fills when a Reach loan closes.
                client.Most_Recent_Closing_Date__c = closingDate;
                client.Most_Recent_Loan_Amount__c = loanAmount;
                client.Most_Recent_Loan_Purpose__c = loanPurpose(purpose);
                client.Purchase_Price__pc = parseAmount(ExternalLoCsvParser.cell(row, headerIndex, 'purchaseprice'));
                String loanTypeRaw = ExternalLoCsvParser.cell(row, headerIndex, 'loantype');
                client.Most_Recent_Loan_Type_1st_TD__c = loanType(loanTypeRaw);
                client.Most_Recent_Rate__c = parseRate(ExternalLoCsvParser.cell(row, headerIndex, 'rate'));
                client.Most_Recent_Term__c = parseTermMonths(ExternalLoCsvParser.cell(row, headerIndex, 'term') ?? loanTypeRaw);
                String lender = ExternalLoCsvParser.cell(row, headerIndex, 'lender');
                client.Current_Mortgage_Company__pc = lender == null ? null : lender.left(255);
                // The property they bought is home: the Mailing address, as on Reach's own closed borrowers.
                client.PersonMailingStreet = address[0];
                client.PersonMailingCity = address[1];
                client.PersonMailingState = address[2];
                client.PersonMailingPostalCode = address[3];
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

            String purposeValue = leadPurpose(purpose);
            if (String.isNotBlank(purpose) && purposeValue == null) {
                result.errors.add(outcome('e', rowNumber, displayName,
                    'Purpose "' + purpose.trim() + '" is not an option. Use ' + String.join(leadPurposeValues(), ', ') + ', or leave it blank.'));
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
            if (conflicts != null) {
                // LO Workspace, as Add lead: one Phone field stored in both, so dupes, Twilio and Zapier see it.
                leadRecord.MobilePhone = phone;
            }
            leadRecord.Email = email;
            leadRecord.Loan_Purpose__c = purposeValue;
            leadRecord.Loan_Amount__c = loanAmount;
            leadRecord.Street = address[0];
            leadRecord.City = city;
            leadRecord.State = address[2];
            leadRecord.PostalCode = address[3];
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
        LoWsLeadIntakeService.alertAdmins('CSV import', blockedAlerts);
        if (!takeoverSources.isEmpty()) {
            // Partial save: one lead that fails its takeover (validation, lock) fails only its own row.
            Map<Id, Database.SaveResult> failed = new Map<Id, Database.SaveResult>();
            Set<Id> taken = LoWsLeadIntakeService.takeOver(takeoverSources, ownerId, failed);
            for (Id leadId : takeoverSources.keySet()) {
                if (taken.contains(leadId)) {
                    result.successes.add(outcome('a', takeoverRows.get(leadId), takeoverNames.get(leadId), ROW_ADDED));
                } else if (failed.containsKey(leadId)) {
                    result.errors.add(outcome('e', takeoverRows.get(leadId), takeoverNames.get(leadId),
                        ExternalLoCsvDmlMessage.fromSaveResult(failed.get(leadId))));
                } else { // stopped being Nurturing since decide()
                    result.errors.add(outcome('e', takeoverRows.get(leadId), takeoverNames.get(leadId), LoWsLeadIntakeService.BLOCKED_MESSAGE));
                }
            }
        }
        if (records.isEmpty()) {
            result.successes.sort();
            result.errors.sort();
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
            return flipLastFirst(fullName).trim();
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

    private static final Set<String> NAME_SUFFIXES = new Set<String>{ 'jr', 'sr', 'ii', 'iii', 'iv', 'md', 'phd' };

    /** "Okafor, Grace" -> "Grace Okafor". "John Smith, Jr." is left alone. */
    @TestVisible
    static String flipLastFirst(String name) {
        if (String.isBlank(name) || name.countMatches(',') != 1) {
            return name;
        }
        String last = name.substringBefore(',').trim();
        String first = name.substringAfter(',').trim();
        if (String.isBlank(last) || String.isBlank(first) || NAME_SUFFIXES.contains(first.toLowerCase().remove('.'))) {
            return name;
        }
        return first + ' ' + last;
    }

    /**
     * [street, city, state, zip]. Separate columns win; otherwise a one-cell address
     * "123 Main St, Mesa, AZ 85201" is split on its commas.
     */
    @TestVisible
    static List<String> parseAddress(String street, String city, String state, String zip) {
        List<String> result = new List<String>{ street, city, state, zip };
        if (String.isBlank(street) || !street.contains(',')) {
            return result;
        }
        List<String> parts = new List<String>();
        for (String part : street.split(',')) {
            parts.add(part.trim());
        }
        Integer n = parts.size();
        // Last piece "AZ 85201", "AZ" or "85201".
        Matcher tail = Pattern.compile('([A-Za-z]{2})?\\s*(\\d{5}(?:-\\d{4})?)?').matcher(parts[n - 1]);
        if (String.isNotBlank(parts[n - 1]) && tail.matches()) {
            result[2] = state ?? tail.group(1)?.toUpperCase();
            result[3] = zip ?? tail.group(2);
            n--;
        }
        if (n >= 2) {
            result[1] = city ?? parts[n - 1];
            n--;
        }
        List<String> streetParts = new List<String>();
        for (Integer i = 0; i < n; i++) {
            streetParts.add(parts[i]);
        }
        result[0] = String.join(streetParts, ', ');
        return result;
    }

    // Free-text purpose -> the Most Recent Loan Purpose values Reach's own closings use.
    @TestVisible
    static String loanPurpose(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String v = raw.toLowerCase().replaceAll('[^a-z]', '');
        if (v.contains('purch')) return 'Purchase';
        if (v.contains('heloc')) return 'HELOC';
        if (v.contains('nocash') || v.contains('rate') || v.contains('term') || v.contains('irrrl') || v.contains('streamline')) return 'Refinance Rate & Term';
        if (v.contains('cash')) return 'Refinance Cash-Out';
        if (v.contains('refi')) return 'Refinance';
        return raw.trim().left(255);
    }

    // Free-text purpose -> an active Lead.Loan_Purpose__c value ("purchase", "Refi"), or null when none fits.
    @TestVisible
    static String leadPurpose(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        // Loan_Purpose__c is a multi-select: "Purchase;Refinance" maps each part; any unknown part rejects the row.
        List<String> picked = new List<String>();
        for (String part : raw.split('[;,]')) {
            if (String.isBlank(part)) {
                continue;
            }
            String one = leadPurposeOne(part);
            if (one == null) {
                return null;
            }
            if (!picked.contains(one)) {
                picked.add(one);
            }
        }
        return picked.isEmpty() ? null : String.join(picked, ';');
    }

    private static String leadPurposeOne(String raw) {
        String mapped = loanPurpose(raw);
        for (String value : leadPurposeValues()) {
            if (value.equalsIgnoreCase(raw.trim()) || value.equalsIgnoreCase(mapped)) return value;
        }
        return null;
    }

    private static List<String> leadPurposeValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry e : Lead.Loan_Purpose__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) values.add(e.getValue());
        }
        return values;
    }

    @TestVisible
    static String loanType(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String v = ' ' + raw.toLowerCase().replaceAll('[^a-z0-9]+', ' ') + ' ';
        if (v.contains(' fha ')) return 'FHA';
        if (v.contains(' va ') || v.contains(' irrrl ')) return 'VA';
        if (v.contains(' usda ') || v.contains(' rural ')) return 'USDA';
        if (v.contains('jumbo')) return 'Jumbo';
        if (v.contains('non qm') || v.contains('nonqm') || v.contains('dscr') || v.contains('bank statement')) return 'NonQM';
        if (v.contains('conv') || v.contains('fannie') || v.contains('freddie') || v.contains('conforming')) return 'Conventional';
        return 'Other';
    }

    // "6.25%", "6.250" or "0.0625" -> 6.25 (a percent field). Anything implausible is left blank.
    @TestVisible
    static Decimal parseRate(String raw) {
        Decimal rate = parseAmount(raw);
        if (rate == null || rate == 0) {
            return null;
        }
        if (rate < 1) {
            rate = rate * 100;
        }
        return rate < 20 ? rate : null;
    }

    // "360", "30", "30 yr", "30 Yr Fixed" -> 360. Reach stores the term in months.
    @TestVisible
    static Decimal parseTermMonths(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        Matcher m = Pattern.compile('(\\d+)').matcher(raw);
        if (!m.find()) {
            return null;
        }
        Integer n = Integer.valueOf(m.group(1));
        if (n >= 60 && n <= 480) return n;
        if (n >= 5 && n <= 40) return n * 12;
        return null;
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