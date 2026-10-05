@isTest
private class ExternalLoPortalCoverageTest {

    private static User getTestUser() {
        return ExternalLoPortalTestHelper.currentUser();
    }

    @testSetup
    static void setupData() {
        insert new AesKey__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            AesKey__c = '12345678901234567890123456789012'
        );
        ExternalLoPortalTestHelper.grantPortalAccess(UserInfo.getUserId());
        User testUser = ExternalLoPortalTestHelper.currentUser();

        System.runAs(testUser) {
            Id consumerLeadRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                  AND DeveloperName = 'Consumer_Lead_record_type'
                LIMIT 1
            ].Id;

            insert new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                FirstName = 'Coverage',
                LastName = 'Lead',
                Company = 'Coverage Co',
                Status = 'New',
                Email = 'coverage.lead@example.com',
                Phone = '2395550600',
                Loan_Amount__c = 200000,
                Loan_Purpose__c = 'Purchase',
                Loan_Program__c = 'Conventional',
                City = 'Naples',
                State = 'FL'
            );

            insert new Transaction__c(
                Name = 'Coverage Loan',
                Loan_Officer__c = testUser.Id,
                Status__c = 'Waiting On Loan Officer',
                Current_Status_Since__c = Date.today().addDays(-4),
                Loan_Amount__c = 400000
            );

            Id personAccountRecordTypeId = new PersonAccountRepository().selectPersonAccountRecordTypeId();
            if (personAccountRecordTypeId != null) {
                insert new Account(
                    RecordTypeId = personAccountRecordTypeId,
                    FirstName = 'Coverage',
                    LastName = 'Realtor',
                    PersonEmail = 'coverage.realtor@example.com',
                    Phone = '2395550700',
                    Group__pc = 'Realtor',
                    Company__c = 'Coverage Realty',
                    OwnerId = testUser.Id,
                    Follow_Up_LO__c = testUser.Id,
                    BillingCity = 'Fort Myers'
                );
            }
        }
    }

    @isTest
    static void leadService_validatesAndCreates() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Boolean blankName = false;
            Boolean missingContact = false;
            Boolean missingAmount = false;
            try {
                ExternalLoLeadService.CreateLeadRequest blank = new ExternalLoLeadService.CreateLeadRequest();
                ExternalLoLeadService.createLead(blank);
            } catch (DomainException expectedError) {
                blankName = expectedError.getMessage().contains('borrower name');
            }
            try {
                ExternalLoLeadService.CreateLeadRequest noContact = new ExternalLoLeadService.CreateLeadRequest();
                noContact.name = 'No Contact';
                noContact.loanAmount = 100000;
                ExternalLoLeadService.createLead(noContact);
            } catch (DomainException expectedError) {
                missingContact = expectedError.getMessage().contains('phone');
            }
            try {
                ExternalLoLeadService.CreateLeadRequest noAmount = new ExternalLoLeadService.CreateLeadRequest();
                noAmount.name = 'No Amount';
                noAmount.email = 'no.amount@example.com';
                ExternalLoLeadService.createLead(noAmount);
            } catch (DomainException expectedError) {
                missingAmount = expectedError.getMessage().contains('loan amount');
            }

            ExternalLoLeadService.CreateLeadRequest request = new ExternalLoLeadService.CreateLeadRequest();
            request.name = 'Solo';
            request.email = 'solo.borrower@example.com';
            request.purpose = 'Refinance';
            request.loanAmount = 180000;
            request.loanProgram = 'FHA';
            request.leadSource = 'Self generated';
            request.market = 'Cape Coral';
            request.notes = 'Coverage create';
            request.forceCreate = true;
            ExternalLoLeadService.CreateLeadResult result = ExternalLoLeadService.createLead(request);

            Boolean duplicateBlocked = false;
            try {
                ExternalLoLeadService.CreateLeadRequest duplicate = new ExternalLoLeadService.CreateLeadRequest();
                duplicate.name = 'Coverage Lead';
                duplicate.phone = '2395550600';
                duplicate.email = 'coverage.lead@example.com';
                duplicate.loanAmount = 200000;
                ExternalLoLeadService.createLead(duplicate);
            } catch (DomainException expectedError) {
                duplicateBlocked = expectedError.getMessage().contains('duplicate');
            }

            System.assert(blankName);
            System.assert(missingContact);
            System.assert(missingAmount);
            System.assertNotEquals(null, result.leadId);
            System.assert(duplicateBlocked);
        }
    }

    @isTest
    static void partnerService_validatesSearchAndHouseLock() {
        User testUser = getTestUser();
        List<Account> partners = [
            SELECT Id FROM Account WHERE OwnerId = :testUser.Id AND IsPersonAccount = true LIMIT 1
        ];

        System.runAs(testUser) {
            Boolean blankName = false;
            Boolean blankCompany = false;
            Boolean missingPartner = false;
            try {
                ExternalLoPartnerService.createPartner(new ExternalLoPartnerService.CreatePartnerRequest());
            } catch (DomainException expectedError) {
                blankName = expectedError.getMessage().contains('partner name');
            }
            try {
                ExternalLoPartnerService.CreatePartnerRequest noCompany = new ExternalLoPartnerService.CreatePartnerRequest();
                noCompany.name = 'No Company';
                ExternalLoPartnerService.createPartner(noCompany);
            } catch (DomainException expectedError) {
                blankCompany = expectedError.getMessage().contains('brokerage');
            }
            try {
                ExternalLoPartnerService.linkPartner(null);
            } catch (DomainException expectedError) {
                missingPartner = true;
            }

            List<ExternalLoPortalService.PartnerRow> emptySearch = ExternalLoPartnerService.searchPartners('x');
            Account houseLocked = new Account(Biz_Dev_Designation__c = 'Biz Dev - Reach');
            Account bondarevskyLocked = new Account(Biz_Dev_Designation__c = 'Biz Dev - Bondarevsky');
            Account owned = new Account(
                OwnerId = UserInfo.getUserId(),
                Follow_Up_LO__c = UserInfo.getUserId(),
                Preferred_LO__c = UserInfo.getUserId()
            );

            System.assert(blankName);
            System.assert(blankCompany);
            System.assert(missingPartner);
            System.assertEquals(0, emptySearch.size());
            System.assertEquals(false, ExternalLoPortalService.isHouseLocked(null, UserInfo.getUserId()));
            System.assertEquals(false, ExternalLoPortalService.isHouseLocked(owned, UserInfo.getUserId()));
            System.assertEquals(true, ExternalLoPortalService.isHouseLocked(houseLocked, UserInfo.getUserId()));
            System.assertEquals(true, ExternalLoPortalService.isHouseLocked(bondarevskyLocked, UserInfo.getUserId()));

            if (!partners.isEmpty()) {
                ExternalLoPortalController.getPartnerDetail(partners[0].Id);
                ExternalLoPortalController.linkPartner(partners[0].Id);
            }
        }
    }

    @isTest
    static void communicationService_validatesAndLogsChannels() {
        User testUser = getTestUser();
        Lead leadRecord = [
            SELECT Id FROM Lead WHERE OwnerId = :testUser.Id AND Status = 'New' LIMIT 1
        ];
        Transaction__c loanRecord = [
            SELECT Id FROM Transaction__c WHERE Loan_Officer__c = :testUser.Id LIMIT 1
        ];

        System.runAs(testUser) {
            Boolean missingRecord = false;
            Boolean missingObject = false;
            Boolean badObject = false;
            Boolean missingChannel = false;
            Boolean shortNote = false;
            try {
                ExternalLoCommunicationService.logCommunication(new ExternalLoCommunicationService.LogRequest());
            } catch (DomainException expectedError) {
                missingRecord = true;
            }
            ExternalLoCommunicationService.LogRequest noObject = new ExternalLoCommunicationService.LogRequest();
            noObject.recordId = leadRecord.Id;
            try {
                ExternalLoCommunicationService.logCommunication(noObject);
            } catch (DomainException expectedError) {
                missingObject = true;
            }
            noObject.objectApiName = 'Task';
            noObject.channel = 'call';
            noObject.notes = 'Too';
            try {
                ExternalLoCommunicationService.logCommunication(noObject);
            } catch (DomainException expectedError) {
                badObject = expectedError.getMessage().contains('lead or partner');
            }
            ExternalLoCommunicationService.LogRequest noChannel = new ExternalLoCommunicationService.LogRequest();
            noChannel.recordId = leadRecord.Id;
            noChannel.objectApiName = 'Lead';
            noChannel.notes = 'Long enough note';
            try {
                ExternalLoCommunicationService.logCommunication(noChannel);
            } catch (DomainException expectedError) {
                missingChannel = true;
            }
            noChannel.channel = 'call';
            noChannel.notes = 'ab';
            try {
                ExternalLoCommunicationService.logCommunication(noChannel);
            } catch (DomainException expectedError) {
                shortNote = true;
            }

            ExternalLoCommunicationService.LogRequest textRequest = new ExternalLoCommunicationService.LogRequest();
            textRequest.recordId = leadRecord.Id;
            textRequest.objectApiName = 'Lead';
            textRequest.channel = 'text';
            textRequest.outcome = 'sent';
            textRequest.notes = 'Texted the borrower about documents.';
            textRequest.followUpOption = '3-days';
            ExternalLoCommunicationService.LogResult textResult = ExternalLoCommunicationService.logCommunication(textRequest);

            ExternalLoCommunicationService.LogRequest videoRequest = new ExternalLoCommunicationService.LogRequest();
            videoRequest.recordId = loanRecord.Id;
            videoRequest.objectApiName = 'Transaction__c';
            videoRequest.channel = 'video';
            videoRequest.notes = 'Video review of loan status with borrower.';
            videoRequest.followUpOption = 'next-week';
            ExternalLoCommunicationService.LogResult videoResult = ExternalLoCommunicationService.logCommunication(videoRequest);

            ExternalLoCommunicationService.LogRequest inPerson = new ExternalLoCommunicationService.LogRequest();
            inPerson.recordId = leadRecord.Id;
            inPerson.objectApiName = 'Lead';
            inPerson.channel = 'in-person';
            inPerson.notes = 'Met the borrower at the office.';
            inPerson.followUpOption = 'none';
            ExternalLoCommunicationService.logCommunication(inPerson);

            System.assert(missingRecord);
            System.assert(missingObject);
            System.assert(badObject);
            System.assert(missingChannel);
            System.assert(shortNote);
            System.assertNotEquals(null, textResult.taskId);
            System.assertNotEquals(null, textResult.followUpEventId);
            System.assertNotEquals(null, videoResult.followUpEventId);
        }
    }

    @isTest
    static void portalFiltersAndRecordSets_coverRemainingBranches() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExternalLoPortalService.getLeads('uncontacted', 'Coverage');
            ExternalLoPortalService.getLeads('working', null);
            ExternalLoPortalService.getLeads('nurture', 'zzz-no-match');
            ExternalLoPortalService.getRealtors('7', null);
            ExternalLoPortalService.getRealtors('due', 'zzz');
            ExternalLoPortalService.getLoans('processing', null);
            ExternalLoPortalService.getLoans('ctc', 'Coverage');
            ExternalLoPortalService.getRecordSet('unknown-key');
            ExternalLoPortalService.getRecordSet('goal-week-texts');
            ExternalLoPortalService.getRecordSet('goal-month-emails');
            ExternalLoPortalService.getRecordSet('goal-today-meetings');
            ExternalLoPortalService.getRecordSet('goal-today-openHouses');
            ExternalLoPortalService.getRecordSet('goal-x');
            ExternalLoPortalService.getNavBadges();
            ExternalLoPortalController.findLeadDuplicates('Coverage', '2395550600', 'coverage.lead@example.com');
            Test.stopTest();

            System.assertNotEquals(null, ExternalLoPortalService.getRecordSet('activities-remaining'));
        }
    }

    @isTest
    static void repositories_nullGuardsAndPartnerSearch() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            LeadRepository leadRepository = LeadRepository.getInstance();
            TaskRepository taskRepository = new TaskRepository();
            PersonAccountRepository personAccountRepository = new PersonAccountRepository();
            LoanRepository loanRepository = LoanRepository.getInstance();

            System.assertEquals(null, leadRepository.selectForRealtorConvert(null));
            System.assertEquals(0, leadRepository.selectSmsOptOutByIds(null).size());
            System.assertEquals(0, leadRepository.selectByEmailsForEmailOptOut(null).size());
            System.assertEquals(0, leadRepository.selectConvertedByIds(null).size());
            System.assertEquals(0, leadRepository.selectNewLeadsToContact(null, null).size());
            System.assertEquals(0, leadRepository.selectPreApprovalsToReview(null).size());
            System.assertEquals(null, leadRepository.selectForPerfectDayDefer(null, null));
            System.assertEquals(0, leadRepository.selectLeadIdsWithFutureEvents(null).size());
            System.assertEquals(0, leadRepository.selectPortalLeadsByOwner(null).size());
            System.assertEquals(0, leadRepository.selectPortalLeadsByPartner(null, null).size());
            System.assertEquals(null, leadRepository.selectPortalLeadDetail(null, null));
            System.assertEquals(0, leadRepository.selectDuplicateLeads(null, null, null, null).size());
            System.assertEquals(0, leadRepository.selectPortalPreApprovalsByOwner(null).size());
            System.assertEquals(0, taskRepository.selectCompletedActivitiesByOwnerForDateRange(null, null, null).size());
            System.assertEquals(0, taskRepository.selectOpenOverdueByOwner(null).size());
            System.assertEquals(0, taskRepository.countOpenOverdueByOwner(null));
            System.assertEquals(0, taskRepository.selectLastActivityDatetimeByWhatIds(null, null).size());
            System.assertEquals(null, taskRepository.selectById(null));
            System.assertEquals(0, taskRepository.selectCompletedActivitiesForRecord(null, null, null).size());
            System.assertEquals(0, taskRepository.selectOpenTasksForLead(null, null).size());
            System.assertEquals(0, taskRepository.selectOpenTasksDueByOwner(null, null).size());
            System.assertEquals(null, personAccountRepository.selectPersonAccountByEmail(null));
            System.assertEquals(null, personAccountRepository.selectPersonAccountById(null));
            System.assertEquals(0, personAccountRepository.selectRealtorPartnersByOwner(null).size());
            System.assertEquals(0, personAccountRepository.selectPortalPartnersForUser(null).size());
            System.assertEquals(null, personAccountRepository.selectPortalPartnerDetail(null, null));
            System.assertEquals(0, personAccountRepository.searchSharedPartners('x', 0).size());
            System.assertEquals(0, personAccountRepository.selectPartnersForImportMatch(null, null).size());
            System.assertEquals(0, new PersonAccountImportSelector().selectPartnersForImportMatch(null, null).size());
            System.assertEquals(0, leadRepository.selectPortalLeadsForImportMatch(null, null, null).size());
            System.assertNotEquals(null, leadRepository.selectConsumerLeadRecordTypeId());
            System.assertEquals(0, loanRepository.selectPortalLoansByUser(null).size());
            System.assertEquals(null, loanRepository.selectPortalLoanDetail(null, null));
            personAccountRepository.selectPersonAccountByEmail('coverage.realtor@example.com');
        }
    }

    @isTest
    static void initializeDocumentRequestDataForOwnedLead() {
        User testUser = getTestUser();
        Lead ownedLead = [
            SELECT Id, Name, Email
            FROM Lead
            WHERE Email = 'coverage.lead@example.com'
            LIMIT 1
        ];
        ownedLead.OwnerId = testUser.Id;
        update ownedLead;

        System.runAs(testUser) {
            Test.startTest();
            LeadDocumentRequestService.LeadDocumentRequestData data =
                LeadDocumentRequestController.initializeData(ownedLead.Id);
            Test.stopTest();

            System.assertEquals(ownedLead.Name, data.leadName);
            System.assertEquals('coverage.lead@example.com', data.borrowerEmail);
        }
    }

    @isTest
    static void createPartnerTypes_andControllerErrors() {
        User testUser = getTestUser();
        if (new PersonAccountRepository().selectPersonAccountRecordTypeId() == null) {
            return;
        }

        System.runAs(testUser) {
            ExternalLoPartnerService.CreatePartnerRequest titleRequest = new ExternalLoPartnerService.CreatePartnerRequest();
            titleRequest.name = 'Title Coverage';
            titleRequest.company = 'Coverage Title';
            titleRequest.partnerType = 'Title';
            titleRequest.email = 'title.coverage' + DateTime.now().getTime() + '@example.com';
            titleRequest.phone = '2395550800';
            titleRequest.market = 'Estero';
            ExternalLoPartnerService.CreatePartnerResult titleResult = ExternalLoPartnerService.createPartner(titleRequest);

            Boolean matchingBlocked = false;
            try {
                ExternalLoPartnerService.CreatePartnerRequest duplicate = new ExternalLoPartnerService.CreatePartnerRequest();
                duplicate.name = 'Coverage Realtor';
                duplicate.company = 'Coverage Realty';
                ExternalLoPartnerService.createPartner(duplicate);
            } catch (DomainException expectedError) {
                matchingBlocked = true;
            }

            System.assertNotEquals(null, titleResult.accountId);
            System.assert(matchingBlocked);
        }
    }

    @isTest
    static void portalController_exposesConversionAndCocEntryPoints() {
        User testUser = getTestUser();
        Lead ownedLead = [
            SELECT Id
            FROM Lead
            WHERE Email = 'coverage.lead@example.com'
            LIMIT 1
        ];
        ownedLead.Street = '100 Main';
        ownedLead.City = 'Naples';
        ownedLead.State = 'FL';
        ownedLead.PostalCode = '34102';
        ownedLead.Loan_Amount__c = 400000;
        ownedLead.Value_of_Property__c = 450000;
        ownedLead.Household_Income__c = 110000;
        ownedLead.OwnerId = testUser.Id;
        update ownedLead;

        System.runAs(testUser) {
            Test.startTest();
            List<ExternalLoPortalCocFacade.CocReasonOption> reasons =
                ExternalLoPortalCocFacade.getReasonOptions();
            ExternalLoPortalConversionFacade.ConversionPreview preview =
                ExternalLoPortalConversionFacade.getConversionPreview(String.valueOf(ownedLead.Id));
            ExternalLoPortalConversionFacade.ConversionResult blocked =
                ExternalLoPortalConversionFacade.confirmConversion(String.valueOf(ownedLead.Id), false);
            Test.stopTest();

            System.assert(!reasons.isEmpty());
            System.assertNotEquals(null, preview.borrowerName);
            System.assertEquals(false, blocked.success);
        }
    }

    @isTest
    static void portalService_getLoanDetail_includesConditionSnapshot() {
        User testUser = getTestUser();
        Transaction__c loanRecord = [
            SELECT Id
            FROM Transaction__c
            WHERE Name = 'Coverage Loan'
            LIMIT 1
        ];
        insert new Condition__c(
            Name = 'Portal snapshot',
            Transaction__c = loanRecord.Id,
            Status__c = 'New',
            Type__c = 'Loan Officer',
            Description__c = 'Coverage condition'
        );

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoPortalService.LoanDetail detail =
                ExternalLoPortalService.getLoanDetail(loanRecord.Id);
            Test.stopTest();
            System.assert(detail.conditionRows.size() >= 1);
        }
    }

}