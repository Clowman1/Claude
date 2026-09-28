public with sharing class ExternalLoPartnerCsvImporter {
    public static void importRows(ExternalLoCsvParser.Table table, ExternalLoCsvImportService.ImportResult result) {
        Map<String, Integer> headerIndex = ExternalLoCsvParser.headerIndex(table.headers);
        Id userId = UserInfo.getUserId();
        PersonAccountRepository personAccountRepository = new PersonAccountRepository();
        Id recordTypeId = personAccountRepository.selectPersonAccountRecordTypeId();
        if (recordTypeId == null) {
            throw new DomainException('Person Account record type is not configured.');
        }

        List<RowDraft> drafts = new List<RowDraft>();
        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        for (Integer i = 0; i < table.rows.size(); i++) {
            List<String> row = table.rows[i];
            RowDraft draft = new RowDraft();
            draft.rowNumber = i + 2;
            draft.firstName = ExternalLoCsvParser.cell(row, headerIndex, 'firstname');
            draft.lastName = ExternalLoCsvParser.cell(row, headerIndex, 'lastname');
            draft.fullName = ExternalLoCsvParser.cell(row, headerIndex, 'name');
            draft.phone = ExternalLoCsvParser.cell(row, headerIndex, 'phone');
            draft.email = ExternalLoCsvParser.cell(row, headerIndex, 'email');
            draft.company = ExternalLoCsvParser.cell(row, headerIndex, 'company');
            draft.market = ExternalLoCsvParser.cell(row, headerIndex, 'market');
            draft.partnerType = ExternalLoCsvParser.cell(row, headerIndex, 'partnertype');
            draft.displayName = ExternalLoCsvImportService.resolveName(
                draft.firstName,
                draft.lastName,
                draft.fullName
            );
            if (String.isBlank(draft.displayName)) {
                result.errors.add(ExternalLoCsvImportService.outcome(
                    'e',
                    draft.rowNumber,
                    'Row ' + draft.rowNumber,
                    'Add a first and last name.'
                ));
                continue;
            }
            if (String.isBlank(draft.company)) {
                result.errors.add(ExternalLoCsvImportService.outcome(
                    'e',
                    draft.rowNumber,
                    draft.displayName,
                    'Add the brokerage or company.'
                ));
                continue;
            }
            drafts.add(draft);
            if (!String.isBlank(draft.email)) {
                emails.add(draft.email);
            }
            if (!String.isBlank(draft.phone)) {
                phones.add(draft.phone);
            }
        }

        Map<String, Account> matchesByEmail = new Map<String, Account>();
        Map<String, Account> matchesByPhone = new Map<String, Account>();
        for (Account accountRecord : new PersonAccountImportSelector().selectPartnersForImportMatch(
            emails,
            ExternalLoPhoneNormalizer.soqlVariants(phones)
        )) {
            if (!String.isBlank(accountRecord.PersonEmail)) {
                matchesByEmail.put(accountRecord.PersonEmail.toLowerCase(), accountRecord);
            }
            String phoneKey = ExternalLoPhoneNormalizer.matchKey(accountRecord.Phone);
            if (phoneKey != null) {
                matchesByPhone.put(phoneKey, accountRecord);
            }
        }

        List<Account> toInsert = new List<Account>();
        List<RowDraft> createDrafts = new List<RowDraft>();
        List<RowDraft> linkDrafts = new List<RowDraft>();
        List<RowDraft> inFileCreateDuplicates = new List<RowDraft>();
        Map<String, RowDraft> pendingCreatesByEmail = new Map<String, RowDraft>();
        Map<String, RowDraft> pendingCreatesByPhone = new Map<String, RowDraft>();
        Set<Id> matchedContactIds = new Set<Id>();

        for (RowDraft draft : drafts) {
            Account match = findPartnerMatch(draft, matchesByEmail, matchesByPhone);
            if (match != null) {
                if (ExternalLoPortalService.isHouseLocked(match, userId)) {
                    result.errors.add(ExternalLoCsvImportService.outcome(
                        'e',
                        draft.rowNumber,
                        draft.displayName,
                        'This partner is managed by the Reach house team.'
                    ));
                    continue;
                }
                draft.matchedAccount = match;
                linkDrafts.add(draft);
                if (match.PersonContactId != null) {
                    matchedContactIds.add(match.PersonContactId);
                }
                registerMatchKeys(draft, match, matchesByEmail, matchesByPhone);
            } else {
                RowDraft pendingCreate = findPendingCreate(draft, pendingCreatesByEmail, pendingCreatesByPhone);
                if (pendingCreate != null) {
                    draft.inFileCreateSource = pendingCreate;
                    draft.isInFileDuplicate = true;
                    inFileCreateDuplicates.add(draft);
                    continue;
                }
                Account partner = new Account();
                partner.RecordTypeId = recordTypeId;
                List<String> nameParts = draft.displayName.trim().split('\\s+', 2);
                partner.FirstName = nameParts[0];
                partner.LastName = nameParts.size() > 1 ? nameParts[1] : 'Partner';
                partner.PersonEmail = draft.email;
                partner.Phone = draft.phone;
                partner.Company__c = draft.company;
                partner.BillingCity = draft.market;
                partner.Group__pc = mapPartnerGroup(draft.partnerType);
                partner.OwnerId = userId;
                partner.Follow_Up_LO__c = userId;
                toInsert.add(partner);
                createDrafts.add(draft);
                registerPendingCreate(draft, pendingCreatesByEmail, pendingCreatesByPhone);
            }
        }

        if (!toInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(toInsert, false);
            Set<Id> createdIds = new Set<Id>();
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    createdIds.add(saveResults[i].getId());
                    createDrafts[i].createdAccountId = saveResults[i].getId();
                    result.successes.add(ExternalLoCsvImportService.outcome(
                        'a',
                        createDrafts[i].rowNumber,
                        createDrafts[i].displayName,
                        ExternalLoCsvImportService.ROW_ADDED
                    ));
                } else {
                    result.errors.add(ExternalLoCsvImportService.outcome(
                        'e',
                        createDrafts[i].rowNumber,
                        createDrafts[i].displayName,
                        ExternalLoCsvDmlMessage.fromSaveResult(saveResults[i])
                    ));
                }
            }
            Map<Id, Id> contactByAccountId = personAccountRepository.selectPersonContactIds(createdIds);
            for (RowDraft draft : createDrafts) {
                if (draft.createdAccountId != null && contactByAccountId.containsKey(draft.createdAccountId)) {
                    matchedContactIds.add(contactByAccountId.get(draft.createdAccountId));
                    draft.personContactId = contactByAccountId.get(draft.createdAccountId);
                }
            }
            for (RowDraft draft : inFileCreateDuplicates) {
                RowDraft source = draft.inFileCreateSource;
                if (source == null || source.createdAccountId == null) {
                    result.errors.add(ExternalLoCsvImportService.outcome(
                        'e',
                        draft.rowNumber,
                        draft.displayName,
                        'That partner could not be added.'
                    ));
                    continue;
                }
                draft.createdAccountId = source.createdAccountId;
                draft.personContactId = source.personContactId;
                createDrafts.add(draft);
            }
        }

        for (RowDraft draft : linkDrafts) {
            draft.personContactId = draft.matchedAccount?.PersonContactId;
            if (draft.personContactId == null) {
                result.errors.add(ExternalLoCsvImportService.outcome(
                    'e',
                    draft.rowNumber,
                    draft.displayName,
                    'That partner could not be linked. Ask an admin for help.'
                ));
            }
        }

        insertAssignmentsAndShares(userId, linkDrafts, createDrafts, matchedContactIds, result);
    }

    private static void insertAssignmentsAndShares(
        Id userId,
        List<RowDraft> linkDrafts,
        List<RowDraft> createDrafts,
        Set<Id> matchedContactIds,
        ExternalLoCsvImportService.ImportResult result
    ) {
        List<External_User_Assignment__c> assignments = new List<External_User_Assignment__c>();
        List<RowDraft> insertedDrafts = new List<RowDraft>();
        Set<String> existingKeys = ExternalUserAssignmentRepository.getInstance()
            .selectUniqueKeys(userId, matchedContactIds);
        Set<String> pendingKeys = new Set<String>();
        List<RowDraft> assignmentDrafts = new List<RowDraft>();
        assignmentDrafts.addAll(linkDrafts);
        assignmentDrafts.addAll(createDrafts);
        for (RowDraft draft : assignmentDrafts) {
            if (draft.personContactId == null) {
                continue;
            }
            String uniqueKey = String.valueOf(userId) + ':' + String.valueOf(draft.personContactId);
            if (existingKeys.contains(uniqueKey.toLowerCase()) || pendingKeys.contains(uniqueKey.toLowerCase())) {
                if (draft.matchedAccount != null || draft.isInFileDuplicate == true) {
                    result.links.add(ExternalLoCsvImportService.outcome(
                        'a',
                        draft.rowNumber,
                        draft.displayName,
                        ExternalLoCsvImportService.ROW_ADDED
                    ));
                }
                continue;
            }
            pendingKeys.add(uniqueKey.toLowerCase());
            assignments.add(new External_User_Assignment__c(
                User__c = userId,
                Contact__c = draft.personContactId,
                Unique_Key__c = uniqueKey,
                Assigned_Date__c = Date.today()
            ));
            insertedDrafts.add(draft);
        }

        List<RowDraft> shareDrafts = new List<RowDraft>();
        if (!assignments.isEmpty()) {
            List<Database.SaveResult> saveResults = ExternalLoPartnerLinkWriter.insertAssignments(assignments);
            for (Integer i = 0; i < saveResults.size(); i++) {
                RowDraft draft = insertedDrafts[i];
                if (saveResults[i].isSuccess()) {
                    if (draft.matchedAccount != null) {
                        if (draft.matchedAccount.OwnerId != userId) {
                            shareDrafts.add(draft);
                        } else {
                            result.links.add(ExternalLoCsvImportService.outcome(
                                'a',
                                draft.rowNumber,
                                draft.displayName,
                                ExternalLoCsvImportService.ROW_ADDED
                            ));
                        }
                    }
                } else {
                    result.errors.add(ExternalLoCsvImportService.outcome(
                        'e',
                        draft.rowNumber,
                        draft.displayName,
                    ExternalLoCsvDmlMessage.fromSaveResult(saveResults[i])
                    ));
                }
            }
        }
        shareLinkedAccounts(userId, shareDrafts, result);
    }

    private static void shareLinkedAccounts(
        Id userId,
        List<RowDraft> shareDrafts,
        ExternalLoCsvImportService.ImportResult result
    ) {
        if (userId == null || shareDrafts == null || shareDrafts.isEmpty()) {
            return;
        }
        Set<Id> accountIds = new Set<Id>();
        for (RowDraft draft : shareDrafts) {
            if (draft.matchedAccount != null) {
                accountIds.add(draft.matchedAccount.Id);
            }
        }
        Set<Id> alreadyShared = new Set<Id>();
        for (AccountShare existing : new AccountShareRepository().selectManualShares(accountIds, userId)) {
            alreadyShared.add(existing.AccountId);
        }
        List<AccountShare> toInsert = new List<AccountShare>();
        List<RowDraft> pendingShareDrafts = new List<RowDraft>();
        for (RowDraft draft : shareDrafts) {
            if (draft.matchedAccount == null) {
                continue;
            }
            if (alreadyShared.contains(draft.matchedAccount.Id)) {
                result.links.add(ExternalLoCsvImportService.outcome(
                    'a',
                    draft.rowNumber,
                    draft.displayName,
                    ExternalLoCsvImportService.ROW_ADDED
                ));
                continue;
            }
            toInsert.add(new AccountShare(
                AccountId = draft.matchedAccount.Id,
                UserOrGroupId = userId,
                AccountAccessLevel = 'Read',
                OpportunityAccessLevel = 'None',
                CaseAccessLevel = 'None',
                RowCause = Schema.AccountShare.RowCause.Manual
            ));
            pendingShareDrafts.add(draft);
        }
        if (toInsert.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saveResults = ExternalLoPartnerLinkWriter.insertAccountShares(toInsert);
        for (Integer i = 0; i < saveResults.size(); i++) {
            RowDraft draft = pendingShareDrafts[i];
            if (saveResults[i].isSuccess()) {
                result.links.add(ExternalLoCsvImportService.outcome(
                    'a',
                    draft.rowNumber,
                    draft.displayName,
                    ExternalLoCsvImportService.ROW_ADDED
                ));
            } else {
                result.errors.add(ExternalLoCsvImportService.outcome(
                    'e',
                    draft.rowNumber,
                    draft.displayName,
                    'We could not share this partner with you. Ask an admin for help.'
                ));
            }
        }
    }

    @TestVisible
    private static String userSafeDmlMessage(Database.SaveResult saveResult) {
        return ExternalLoCsvDmlMessage.fromSaveResult(saveResult);
    }

    private static void registerMatchKeys(
        RowDraft draft,
        Account match,
        Map<String, Account> matchesByEmail,
        Map<String, Account> matchesByPhone
    ) {
        if (!String.isBlank(draft.email)) {
            matchesByEmail.put(draft.email.toLowerCase(), match);
        }
        String phoneKey = ExternalLoPhoneNormalizer.matchKey(draft.phone);
        if (phoneKey != null) {
            matchesByPhone.put(phoneKey, match);
        }
    }

    private static RowDraft findPendingCreate(
        RowDraft draft,
        Map<String, RowDraft> pendingCreatesByEmail,
        Map<String, RowDraft> pendingCreatesByPhone
    ) {
        if (!String.isBlank(draft.email) && pendingCreatesByEmail.containsKey(draft.email.toLowerCase())) {
            return pendingCreatesByEmail.get(draft.email.toLowerCase());
        }
        String phoneKey = ExternalLoPhoneNormalizer.matchKey(draft.phone);
        if (phoneKey != null && pendingCreatesByPhone.containsKey(phoneKey)) {
            return pendingCreatesByPhone.get(phoneKey);
        }
        return null;
    }

    private static void registerPendingCreate(
        RowDraft draft,
        Map<String, RowDraft> pendingCreatesByEmail,
        Map<String, RowDraft> pendingCreatesByPhone
    ) {
        if (!String.isBlank(draft.email)) {
            pendingCreatesByEmail.put(draft.email.toLowerCase(), draft);
        }
        String phoneKey = ExternalLoPhoneNormalizer.matchKey(draft.phone);
        if (phoneKey != null) {
            pendingCreatesByPhone.put(phoneKey, draft);
        }
    }

    private static Account findPartnerMatch(
        RowDraft draft,
        Map<String, Account> matchesByEmail,
        Map<String, Account> matchesByPhone
    ) {
        if (!String.isBlank(draft.email) && matchesByEmail.containsKey(draft.email.toLowerCase())) {
            return matchesByEmail.get(draft.email.toLowerCase());
        }
        String phoneKey = ExternalLoPhoneNormalizer.matchKey(draft.phone);
        if (phoneKey != null && matchesByPhone.containsKey(phoneKey)) {
            return matchesByPhone.get(phoneKey);
        }
        return null;
    }

    @TestVisible
    private static String mapPartnerGroup(String partnerType) {
        if (partnerType == null) {
            return 'Realtor';
        }
        String normalized = partnerType.trim().toLowerCase();
        if (normalized.contains('title')) {
            return 'Title Agent';
        }
        if (normalized.contains('insurance')) {
            return 'Insurance Agent';
        }
        if (normalized.contains('prospect')) {
            return 'Realtor Prospect';
        }
        return 'Realtor';
    }

    private class RowDraft {
        public Integer rowNumber;
        public String firstName;
        public String lastName;
        public String fullName;
        public String displayName;
        public String phone;
        public String email;
        public String company;
        public String market;
        public String partnerType;
        public Account matchedAccount;
        public Id createdAccountId;
        public Id personContactId;
        public RowDraft inFileCreateSource;
        public Boolean isInFileDuplicate;
    }
}