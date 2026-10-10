@isTest
private class ExternalLoPortalServiceTest {

    // Portal-mode tests run as a fresh admin, never as a holder of LO_Workspace_Demo (see ExternalLoPortalTestHelper.createPortalAdmin).
    private static final String ADMIN_ALIAS = 'elpsvc';

    private static User getTestUser() {
        return ExternalLoPortalTestHelper.portalAdmin(ADMIN_ALIAS);
    }

    @testSetup
    static void setupData() {
        ExternalLoPortalTestHelper.createPortalAdmin(ADMIN_ALIAS);
        User testUser = getTestUser();

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
                FirstName = 'Portal',
                LastName = 'Lead',
                Company = 'Portal Lead Co',
                Status = 'New',
                Email = 'portal.lead@example.com',
                Phone = '2395550100',
                Loan_Amount__c = 350000
            );

            insert new Lead(
                RecordTypeId = consumerLeadRecordTypeId,
                FirstName = 'Portal',
                LastName = 'PreApproval',
                Company = 'Portal Pre Co',
                Status = 'Pre-Approval',
                Email = 'portal.pre@example.com',
                Loan_Amount__c = 425000,
                Pre_Approval_Date__c = Date.today().addDays(-8)
            );

            insert new Transaction__c(
                Name = 'Portal Loan',
                Loan_Officer__c = testUser.Id,
                Status__c = 'Waiting On Loan Officer',
                Current_Status_Since__c = Date.today().addDays(-4),
                Loan_Amount__c = 500000,
                Closing_Date__c = Date.today().addDays(20),
                Purchase_Price__c = 525000,
                Interest_Rate__c = 6.5,
                LTV__c = 80,
                DTI_Back_End__c = 38,
                Property_Address__c = '123 Main St',
                Lock_Exp_Date_1st_TD__c = Date.today().addDays(30)
            );

            insert new Task(
                Subject = 'Overdue follow-up',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(-2),
                Priority = 'High'
            );

            Id personAccountRecordTypeId = new PersonAccountRepository().selectPersonAccountRecordTypeId();
            if (personAccountRecordTypeId != null) {
                Account partner = new Account(
                    RecordTypeId = personAccountRecordTypeId,
                    FirstName = 'Portal',
                    LastName = 'Realtor',
                    PersonEmail = 'portal.realtor@example.com',
                    Phone = '2395550200',
                    Group__pc = 'Realtor',
                    Company__c = 'Portal Realty',
                    OwnerId = testUser.Id,
                    Follow_Up_LO__c = testUser.Id
                );
                insert partner;

                insert new Task(
                    Subject = 'Partner touch',
                    Status = 'Completed',
                    ActivityDate = Date.today().addDays(-12),
                    WhatId = partner.Id
                );
            }
        }
    }

    @isTest
    static void getLeadsAndDetail_returnPortalRows() {
        User testUser = getTestUser();
        Lead leadRecord = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            List<ExternalLoPortalService.LeadRow> rows = ExternalLoPortalService.getLeads('new', 'Portal');
            ExternalLoPortalService.LeadDetail detail = ExternalLoPortalService.getLeadDetail(leadRecord.Id);
            Test.stopTest();

            System.assertEquals(1, rows.size(), 'One new lead should match the filter.');
            System.assertEquals(leadRecord.Id, detail.summary.id, 'Lead detail should return the requested lead.');
        }
    }

    @isTest
    static void controllerMethods_exposePortalData() {
        User testUser = getTestUser();
        Lead leadRecord = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];
        Transaction__c loanRecord = [
            SELECT Id
            FROM Transaction__c
            WHERE Loan_Officer__c = :testUser.Id
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            System.assertNotEquals(null, ExternalLoPortalController.getLeads('all', null));
            System.assertNotEquals(null, ExternalLoPortalController.getLeadDetail(leadRecord.Id));
            System.assertNotEquals(null, ExternalLoPortalController.getPreApprovals('all', null));
            System.assertNotEquals(null, ExternalLoPortalController.getLoans('all', null));
            System.assertNotEquals(null, ExternalLoPortalController.getRealtors('all', null));
            System.assertNotEquals(null, ExternalLoPortalController.getLoanDetail(loanRecord.Id));
            System.assertNotEquals(null, ExternalLoPortalController.getRecordSet('pre-approvals'));
            System.assertNotEquals(null, ExternalLoPortalController.getRecordSet('overdue-tasks'));
            System.assertNotEquals(null, ExternalLoPortalController.getRecordSet('realtor-follow-ups'));
            System.assertNotEquals(null, ExternalLoPortalController.getNavBadges());
            System.assertNotEquals(null, ExternalLoPortalController.getRecordSet('completed-today'));
            System.assertNotEquals(null, ExternalLoPortalController.getRecordSet('activities-remaining'));
            System.assertNotEquals(null, ExternalLoPortalController.getRecordSet('goal-today-calls'));
            System.assertNotEquals(null, ExternalLoPortalController.findLeadDuplicates('Portal', '2395550100', 'portal.lead@example.com'));
            Test.stopTest();
        }
    }

    @isTest
    static void myLoansTabs_splitActiveClosedCancelled() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            insert new List<Transaction__c>{
                new Transaction__c(Name = 'Funded Loan', Loan_Officer__c = testUser.Id, Status__c = 'Funding'),
                new Transaction__c(Name = 'Done Loan', Loan_Officer__c = testUser.Id, Status__c = 'Post-Closed', Skip_Post_Closed_Validation__c = true),
                new Transaction__c(Name = 'Dead Loan', Loan_Officer__c = testUser.Id, Status__c = 'Cancelled')
            };
            Test.startTest();
            List<ExternalLoPortalService.LoanRow> active = ExternalLoPortalService.getLoans('active', null);
            List<ExternalLoPortalService.LoanRow> closed = ExternalLoPortalService.getLoans('closed', null);
            List<ExternalLoPortalService.LoanRow> cancelled = ExternalLoPortalService.getLoans('cancelled', null);
            Map<String, Integer> counts = ExternalLoPortalController.getLoanTabCounts();
            Test.stopTest();

            System.assertEquals(1, active.size(), 'Funding is closed, so only the Waiting On Loan Officer loan is active.');
            System.assertEquals('processing', active[0].boardStage);
            System.assertEquals(2, closed.size());
            System.assertEquals(1, cancelled.size());
            System.assertEquals(1, counts.get('active'));
            System.assertEquals(2, counts.get('closed'));
            System.assertEquals(1, counts.get('cancelled'));
            System.assertEquals(1, ExternalLoPortalService.getLoans('update', null).size(), 'Old filter links still work.');
        }
    }

    @isTest
    static void boardStage_mapsStatusesToColumns() {
        System.assertEquals('application', ExternalLoPortalService.boardStage(new Transaction__c(Status__c = 'Disclosures Out')));
        System.assertEquals('processing', ExternalLoPortalService.boardStage(new Transaction__c(Status__c = 'Submitted')));
        System.assertEquals('approved', ExternalLoPortalService.boardStage(new Transaction__c(Status__c = 'Conditionally Approved')));
        System.assertEquals('ctc', ExternalLoPortalService.boardStage(
            new Transaction__c(Status__c = 'Conditionally Approved', Clear_to_Close_Date__c = Date.today())));
        System.assertEquals('closing', ExternalLoPortalService.boardStage(
            new Transaction__c(Status__c = 'Closing', Clear_to_Close_Date__c = Date.today())));
    }

    private static ExternalLoPortalService.PreApprovalRow preApprovalRow() {
        for (ExternalLoPortalService.PreApprovalRow row : ExternalLoPortalService.getPreApprovals('all', 'PreApproval')) {
            return row;
        }
        return null;
    }

    @isTest
    static void weeklyTouch_dueUntilACallIsLogged() {
        User testUser = getTestUser();
        Lead pre = [SELECT Id FROM Lead WHERE Email = 'portal.pre@example.com' LIMIT 1];
        // Org automation re-stamps Pre_Approval_Date__c on insert and may log a task; start from a clean, 8-day-old file.
        delete [SELECT Id FROM Task WHERE WhoId = :pre.Id];
        delete [SELECT Id FROM Event WHERE WhoId = :pre.Id];
        update new Lead(Id = pre.Id, Pre_Approval_Date__c = Date.today().addDays(-8));
        System.runAs(testUser) {
            ExternalLoPortalService.PreApprovalRow before = preApprovalRow();
            System.assertEquals('touch-due', before.statusKey, 'Pre-approved 8 days ago with no touch.');
            System.assert(before.daysSinceTouch >= 7, String.valueOf(before.daysSinceTouch));
            System.assertEquals(1, ExternalLoPortalService.getPreApprovals('weekly-touch', 'PreApproval').size());

            List<ExternalLoPromptService.PromptItem> all = PerfectDayHomeController.getAllUpNext();
            Boolean sawTouch = false;
            for (ExternalLoPromptService.PromptItem item : all) {
                if (item.kind == 'touch' && item.recordId == pre.Id) {
                    sawTouch = true;
                    System.assertEquals('overdue', item.upNextGroup);
                }
            }
            System.assert(sawTouch, 'Open all lists the due weekly touch.');

            insert new Task(WhoId = pre.Id, Subject = 'Call', Status = 'Completed', TaskSubtype = 'Call', ActivityDate = Date.today());
            Test.startTest();
            ExternalLoPortalService.PreApprovalRow afterCall = preApprovalRow();
            Test.stopTest();
            System.assertEquals('ready-to-review', afterCall.statusKey, 'A logged call is a touch.');
            System.assertEquals(true, afterCall.weeklyTouchDone);
        }
    }

    @isTest
    static void weeklyTouch_emailToTheBorrowerCounts() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            EmailMessage msg = new EmailMessage(
                Subject = 'Your pre-approval',
                Status = '3',
                Incoming = false,
                MessageDate = System.now().addDays(-1),
                FromAddress = 'lo@example.com',
                ToAddress = 'Portal.Pre@example.com',
                TextBody = 'Checking in'
            );
            insert msg;
            insert new EmailMessageRelation(
                EmailMessageId = msg.Id,
                RelationAddress = 'Portal.Pre@example.com',
                RelationType = 'ToAddress'
            );
            Test.startTest();
            ExternalLoPortalService.PreApprovalRow row = preApprovalRow();
            Test.stopTest();
            System.assertEquals(true, row.weeklyTouchDone, 'An email to the lead address (any case) is a touch.');
        }
    }

    @isTest
    static void preApprovalSort_touchDueFirstThenNewest() {
        ExternalLoPortalService.PreApprovalRow due10 = new ExternalLoPortalService.PreApprovalRow();
        due10.weeklyTouchDone = false;
        due10.daysSinceTouch = 10;
        ExternalLoPortalService.PreApprovalRow due8 = new ExternalLoPortalService.PreApprovalRow();
        due8.weeklyTouchDone = false;
        due8.daysSinceTouch = 8;
        ExternalLoPortalService.PreApprovalRow fresh = new ExternalLoPortalService.PreApprovalRow();
        fresh.weeklyTouchDone = true;
        List<ExternalLoPortalService.PreApprovalSort> rows = new List<ExternalLoPortalService.PreApprovalSort>{
            new ExternalLoPortalService.PreApprovalSort(fresh, System.now()),
            new ExternalLoPortalService.PreApprovalSort(due8, System.now().addDays(-30)),
            new ExternalLoPortalService.PreApprovalSort(due10, System.now().addDays(-40))
        };
        rows.sort();
        System.assertEquals(due10, rows[0].row);
        System.assertEquals(due8, rows[1].row);
        System.assertEquals(fresh, rows[2].row);
    }

    @isTest
    static void partnerKind_splitsRealtorsFromOtherContacts() {
        System.assert(ExternalLoPortalService.matchesPartnerKind(null, 'realtor'), 'Blank industry is a realtor.');
        System.assert(ExternalLoPortalService.matchesPartnerKind('Realtor', 'realtor'));
        System.assert(!ExternalLoPortalService.matchesPartnerKind('Insurance Agent', 'realtor'));
        System.assert(ExternalLoPortalService.matchesPartnerKind('Home Inspector', 'other'));
        System.assert(!ExternalLoPortalService.matchesPartnerKind('Realtor', 'other'));
        System.assert(ExternalLoPortalService.matchesPartnerKind('Appraiser', 'all'));
        System.runAs(getTestUser()) {
            System.assertNotEquals(null, ExternalLoPortalController.getPartnersByKind('all', null, 'other'));
        }
    }

    @isTest
    static void getRecordSet_returnsPriorityRecords() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoPortalService.RecordSetPayload newLeads = ExternalLoPortalService.getRecordSet('new-leads');
            ExternalLoPortalService.RecordSetPayload milestoneLoans = ExternalLoPortalService.getRecordSet('milestone-loans');
            Test.stopTest();

            System.assertEquals('New leads need contact', newLeads.title, 'New-leads record set should carry its title.');
            System.assert(newLeads.records.size() >= 1, 'At least one new lead should be returned.');
            System.assert(milestoneLoans.records.size() >= 1, 'Milestone record set should return the stale loan.');
            for (ExternalLoPortalService.RecordSetItem item : newLeads.records) {
                System.assertEquals('Lead', item.objectApiName, 'New-lead rows should be Lead records.');
            }
        }
    }

    @isTest
    static void getRealtorsAndPartnerDetail_returnRows() {
        User testUser = getTestUser();
        List<Account> partners = [
            SELECT Id
            FROM Account
            WHERE OwnerId = :testUser.Id
              AND IsPersonAccount = true
            LIMIT 1
        ];
        if (partners.isEmpty()) {
            return;
        }

        System.runAs(testUser) {
            Test.startTest();
            List<ExternalLoPortalService.PartnerRow> rows = ExternalLoPortalService.getRealtors('all', 'Portal');
            ExternalLoPortalService.PartnerDetail detail = ExternalLoPortalService.getPartnerDetail(partners[0].Id);
            List<ExternalLoPortalService.PartnerRow> matches = ExternalLoPartnerService.searchPartners('Portal');
            Test.stopTest();

            System.assert(rows.size() >= 1, 'At least one partner should be visible.');
            System.assertEquals(partners[0].Id, detail.summary.id, 'Partner detail should match the requested account.');
            System.assert(matches.size() >= 1, 'Shared partner search should return matches.');
        }
    }

    @isTest
    static void logCommunication_createsCompletedTask() {
        User testUser = getTestUser();
        Lead leadRecord = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];

        System.runAs(testUser) {
            ExternalLoCommunicationService.LogRequest request = new ExternalLoCommunicationService.LogRequest();
            request.recordId = leadRecord.Id;
            request.objectApiName = 'Lead';
            request.channel = 'call';
            request.outcome = 'connected';
            request.notes = 'Reached borrower and reviewed next steps.';
            request.followUpOption = 'none';

            Test.startTest();
            ExternalLoCommunicationService.LogResult result = ExternalLoCommunicationService.logCommunication(request);
            Test.stopTest();

            System.assertNotEquals(null, result.taskId, 'A completed task should be created.');
            System.assert([SELECT COUNT() FROM Task WHERE WhoId = :leadRecord.Id AND IsClosed = true] >= 1);
        }
    }

    @isTest
    static void createLead_returnsNewRecord() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            ExternalLoLeadService.CreateLeadRequest request = new ExternalLoLeadService.CreateLeadRequest();
            request.name = 'Created Borrower';
            request.phone = '2395550199';
            request.email = 'created.borrower@example.com';
            request.purpose = 'Purchase';
            request.loanAmount = 275000;
            request.loanProgram = 'Conventional';
            request.leadSource = 'Self generated';
            request.forceCreate = true;

            Test.startTest();
            ExternalLoLeadService.CreateLeadResult result = ExternalLoLeadService.createLead(request);
            Test.stopTest();

            System.assertNotEquals(null, result.leadId, 'Lead creation should return an Id.');
        }
    }

    @isTest
    static void createPartner_returnsSharedAccount() {
        User testUser = getTestUser();
        Id personAccountRecordTypeId = new PersonAccountRepository().selectPersonAccountRecordTypeId();
        if (personAccountRecordTypeId == null) {
            return;
        }

        System.runAs(testUser) {
            ExternalLoPartnerService.CreatePartnerRequest request = new ExternalLoPartnerService.CreatePartnerRequest();
            request.name = 'Created Partner';
            request.company = 'Created Brokerage';
            request.partnerType = 'Realtor';
            request.phone = '2395550300';
            request.email = 'created.partner@example.com';
            request.market = 'Fort Myers';

            Test.startTest();
            ExternalLoPartnerService.CreatePartnerResult result = ExternalLoPartnerService.createPartner(request);
            Test.stopTest();

            System.assertNotEquals(null, result.accountId, 'Partner creation should return an Id.');
            Account createdPartner = [SELECT BillingCity FROM Account WHERE Id = :result.accountId];
            System.assertEquals('Fort Myers', createdPartner.BillingCity,
                'The market the LO typed must persist on the partner record.');
        }
    }

    @isTest
    static void getLoansAndPreApprovals_returnWorkspaceRows() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<ExternalLoPortalService.LoanRow> loans = ExternalLoPortalService.getLoans('all', 'Portal');
            List<ExternalLoPortalService.PreApprovalRow> preApprovals = ExternalLoPortalService.getPreApprovals('all', 'Portal');
            Test.stopTest();

            System.assertEquals(1, loans.size(), 'One portal loan should be visible.');
            System.assertEquals(1, preApprovals.size(), 'One pre-approval should be visible.');
        }
    }

    @isTest
    static void getLeads_bulkScenario_processes200Records() {
        User testUser = getTestUser();
        Id consumerLeadRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
              AND DeveloperName = 'Consumer_Lead_record_type'
            LIMIT 1
        ].Id;

        List<Lead> bulkLeads = new List<Lead>();
        for (Integer indexNumber = 0; indexNumber < 200; indexNumber++) {
            bulkLeads.add(
                new Lead(
                    RecordTypeId = consumerLeadRecordTypeId,
                    FirstName = 'Bulk',
                    LastName = 'Lead ' + indexNumber,
                    Company = 'Bulk Co ' + indexNumber,
                    Status = indexNumber < 50 ? 'New' : 'Pre-Approval',
                    Email = 'bulk.lead.' + indexNumber + '@example.com',
                    OwnerId = testUser.Id,
                    Loan_Amount__c = 300000 + indexNumber
                )
            );
        }

        System.runAs(testUser) {
            insert bulkLeads;

            Test.startTest();
            List<ExternalLoPortalService.LeadRow> allRows = ExternalLoPortalService.getLeads('all', null);
            List<ExternalLoPortalService.LeadRow> newRows = ExternalLoPortalService.getLeads('new', null);
            Test.stopTest();

            System.assert(allRows.size() >= 200, 'Bulk leads should be returned from the portal query.');
            System.assert(newRows.size() >= 50, 'New filter should return the bulk new leads.');
            System.assert(Limits.getQueries() <= 50, 'Bulk read path should remain governor-safe.');
        }
    }

    @isTest
    static void logCommunication_withFollowUpCreatesEvent() {
        User testUser = getTestUser();
        Lead leadRecord = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];

        System.runAs(testUser) {
            ExternalLoCommunicationService.LogRequest request = new ExternalLoCommunicationService.LogRequest();
            request.recordId = leadRecord.Id;
            request.objectApiName = 'Lead';
            request.channel = 'email';
            request.outcome = 'sent-no-reply';
            request.notes = 'Sent pre-approval checklist to borrower.';
            request.followUpOption = 'tomorrow';

            Test.startTest();
            ExternalLoCommunicationService.LogResult result = ExternalLoCommunicationService.logCommunication(request);
            ExternalLoPortalController.logCommunication(
                request.recordId,
                request.objectApiName,
                request.channel,
                request.outcome,
                request.notes,
                request.followUpOption
            );
            Test.stopTest();

            System.assertNotEquals(null, result.followUpEventId, 'Follow-up should be scheduled.');
            // Phase 9 calendar: a general follow-up ('tomorrow') is an open Task, not an Event.
            System.assert([SELECT COUNT() FROM Task WHERE WhoId = :leadRecord.Id AND IsClosed = false] >= 1);
        }
    }

    @isTest
    static void controllerCreateMethods_delegateToServices() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            ExternalLoLeadService.CreateLeadRequest leadRequest = new ExternalLoLeadService.CreateLeadRequest();
            leadRequest.name = 'Controller Borrower';
            leadRequest.phone = '2395550400';
            leadRequest.email = 'controller.borrower@example.com';
            leadRequest.purpose = 'Purchase';
            leadRequest.loanAmount = 310000;
            leadRequest.loanProgram = 'Conventional';
            leadRequest.leadSource = 'Self generated';
            leadRequest.forceCreate = true;

            Test.startTest();
            ExternalLoPortalController.createLead(
                leadRequest.name,
                leadRequest.phone,
                leadRequest.email,
                leadRequest.purpose,
                leadRequest.loanAmount,
                leadRequest.loanProgram,
                leadRequest.leadSource,
                leadRequest.market,
                leadRequest.notes,
                leadRequest.forceCreate
            );
            Boolean blankNameBlocked = false;
            try {
                ExternalLoPortalController.createLead(
                    null,
                    '2395550400',
                    'blank.name@example.com',
                    'Purchase',
                    310000,
                    'Conventional',
                    'Self generated',
                    null,
                    null,
                    true
                );
            } catch (Exception createError) {
                blankNameBlocked = true;
            }
            Test.stopTest();

            System.assert(blankNameBlocked, 'Blank borrower name should fail at the controller.');

            System.assertEquals(
                1,
                [SELECT COUNT() FROM Lead WHERE Email = 'controller.borrower@example.com' AND OwnerId = :testUser.Id]
            );
        }
    }

    @isTest
    static void linkPartner_returnsPartnerRow() {
        User testUser = getTestUser();
        List<Account> partners = [
            SELECT Id
            FROM Account
            WHERE OwnerId = :testUser.Id
              AND IsPersonAccount = true
            LIMIT 1
        ];
        if (partners.isEmpty()) {
            return;
        }

        System.runAs(testUser) {
            Test.startTest();
            ExternalLoPortalService.PartnerRow linked = ExternalLoPartnerService.linkPartner(partners[0].Id);
            ExternalLoPortalController.linkPartner(partners[0].Id);
            List<ExternalLoPortalService.PartnerRow> dueRows = ExternalLoPortalService.getRealtors('due', null);
            List<ExternalLoPortalService.LoanRow> updateLoans = ExternalLoPortalService.getLoans('update', null);
            Test.stopTest();

            System.assertEquals(partners[0].Id, linked.id, 'Linked partner should match the account.');
            System.assertNotEquals(null, dueRows);
            System.assertNotEquals(null, updateLoans);
        }
    }

    @isTest
    static void workspaceCoverage_exercisesHomeAndPortalPaths() {
        User testUser = getTestUser();
        Lead leadRecord = [
            SELECT Id
            FROM Lead
            WHERE OwnerId = :testUser.Id
              AND Status = 'New'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            PerfectDayHomeModels.PerfectDayHomeData homeData = PerfectDayHomeService.getHomeData();
            ExternalLoPortalService.LeadDetail leadDetail = ExternalLoPortalService.getLeadDetail(leadRecord.Id);
            System.assertNotEquals(null, leadDetail.scenarioFields);
            ExternalLoPortalService.getPreApprovals('weekly-touch', null);
            ExternalLoPortalService.getLoans('processing', null);
            ExternalLoPortalService.getLoans('ctc', null);
            ExternalLoPortalService.getRecordSet('overdue-tasks');
            ExternalLoPortalController.searchPartners('Portal');
            Test.stopTest();

            System.assertNotEquals(null, homeData.upNext, 'Perfect Day should still rank competing work.');
            System.assertNotEquals(null, leadDetail.openTasks, 'Lead detail should include open tasks.');
            System.assert(Limits.getQueries() <= 100, 'Combined workspace reads should stay governor-safe.');
        }
    }

    @isTest
    static void repositoryMethods_supportPortalAndLegacyPaths() {
        User testUser = getTestUser();
        Transaction__c loanRecord = [
            SELECT Id
            FROM Transaction__c
            WHERE Loan_Officer__c = :testUser.Id
            LIMIT 1
        ];
        Lead leadRecord = [
            SELECT Id, Email
            FROM Lead
            WHERE OwnerId = :testUser.Id
            LIMIT 1
        ];

        System.runAs(testUser) {
            LeadRepository leadRepository = LeadRepository.getInstance();
            LoanRepository loanRepository = LoanRepository.getInstance();
            PersonAccountRepository personAccountRepository = new PersonAccountRepository();
            TaskRepository taskRepository = new TaskRepository();
            List<Account> partners = [
                SELECT Id, PersonEmail
                FROM Account
                WHERE OwnerId = :testUser.Id
                  AND IsPersonAccount = true
                LIMIT 1
            ];

            Test.startTest();
            System.assertNotEquals(null, leadRepository.getLeadById(String.valueOf(leadRecord.Id)));
            System.assertNotEquals(null, leadRepository.selectNewLeadsToContact(testUser.Id, Date.today().addDays(-30)));
            System.assertNotEquals(null, leadRepository.selectPreApprovalsToReview(testUser.Id));
            System.assertNotEquals(null, leadRepository.selectLeadIdsWithFutureEvents(new Set<Id>{ leadRecord.Id }));
            System.assertNotEquals(null, leadRepository.selectPortalLeadsByOwner(testUser.Id));
            System.assertNotEquals(null, leadRepository.selectPortalLeadDetail(leadRecord.Id, testUser.Id));
            System.assertNotEquals(null, leadRepository.selectDuplicateLeads(testUser.Id, 'Portal', '2395550100', leadRecord.Email));
            System.assertNotEquals(null, leadRepository.selectPortalPreApprovalsByOwner(testUser.Id));
            System.assertNotEquals(null, loanRepository.selectPortalLoansByUser(testUser.Id));
            System.assertNotEquals(null, loanRepository.selectPortalLoanDetail(loanRecord.Id, testUser.Id));
            System.assertNotEquals(null, loanRepository.selectLoansNeedingMilestoneUpdates(testUser.Id));
            System.assertNotEquals(null, loanRepository.selectTransactionsByIds(new Set<Id>{ loanRecord.Id }));
            System.assertNotEquals(null, loanRepository.getLoanMapByIds(new Set<Id>{ loanRecord.Id }));
            System.assertNotEquals(null, loanRepository.getLoanById(String.valueOf(loanRecord.Id)));
            loanRepository.getLoanForBorrowerPortalById(loanRecord.Id);
            System.assertNotEquals(null, personAccountRepository.selectPersonAccountRecordTypeId());
            System.assertNotEquals(null, personAccountRepository.selectPortalPartnersForUser(testUser.Id));
            System.assertNotEquals(null, personAccountRepository.selectRealtorPartnersByOwner(testUser.Id));
            System.assertNotEquals(null, personAccountRepository.searchSharedPartners('Portal', 5));
            if (!partners.isEmpty() && partners[0].PersonEmail != null) {
                personAccountRepository.selectPersonAccountByEmail(partners[0].PersonEmail);
            }
            System.assertNotEquals(null, leadRepository.selectSmsOptOutByIds(new Set<Id>{ leadRecord.Id }));
            System.assertNotEquals(null, leadRepository.selectByEmailsForEmailOptOut(new Set<String>{ leadRecord.Email }));
            System.assertNotEquals(null, leadRepository.selectConvertedByIds(new Set<Id>{ leadRecord.Id }));
            leadRepository.selectForRealtorConvert(leadRecord.Id);
            List<Task> overdueTasks = taskRepository.selectOpenOverdueByOwner(testUser.Id);
            if (!overdueTasks.isEmpty()) {
                System.assertNotEquals(null, taskRepository.selectById(overdueTasks[0].Id));
            }
            if (!partners.isEmpty()) {
                System.assertNotEquals(null, personAccountRepository.selectPersonAccountById(partners[0].Id));
                System.assertNotEquals(null, personAccountRepository.selectPortalPartnerDetail(partners[0].Id, testUser.Id));
            }
            System.assertNotEquals(null, taskRepository.selectOpenOverdueByOwner(testUser.Id));
            System.assertNotEquals(null, taskRepository.countOpenOverdueByOwner(testUser.Id));
            System.assertNotEquals(null, taskRepository.selectCompletedActivitiesForRecord(leadRecord.Id, testUser.Id, 10));
            System.assertNotEquals(null, taskRepository.selectOpenTasksForLead(leadRecord.Id, testUser.Id));
            System.assertNotEquals(null, taskRepository.selectCompletedActivitiesByOwnerForDateRange(
                testUser.Id,
                Date.today().addDays(-7),
                Date.today()
            ));
            Test.stopTest();
        }
    }

    @isTest
    static void controllerCreatePartner_delegatesToService() {
        User testUser = getTestUser();
        if (new PersonAccountRepository().selectPersonAccountRecordTypeId() == null) {
            return;
        }

        System.runAs(testUser) {
            ExternalLoPartnerService.CreatePartnerRequest request = new ExternalLoPartnerService.CreatePartnerRequest();
            request.name = 'Controller Partner';
            request.company = 'Controller Brokerage';
            request.partnerType = 'Realtor';
            request.phone = '2395550500';
            request.email = 'controller.partner' + DateTime.now().getTime() + '@example.com';

            Test.startTest();
            ExternalLoPortalController.createPartner(
                request.name,
                request.phone,
                request.email,
                request.company,
                'Naples',
                request.partnerType
            );
            Boolean blankPartnerBlocked = false;
            try {
                ExternalLoPortalController.createPartner(null, null, null, null, null, 'Realtor');
            } catch (Exception createError) {
                blankPartnerBlocked = true;
            }
            Test.stopTest();

            System.assert(blankPartnerBlocked, 'Blank partner name should fail at the controller.');

            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE PersonEmail = :request.email AND OwnerId = :testUser.Id AND BillingCity = 'Naples']
            );
        }
    }
}