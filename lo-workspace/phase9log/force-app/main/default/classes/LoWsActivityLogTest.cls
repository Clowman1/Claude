/**
 * Phase 9 (LO Workspace activity logging), run as a real outside loan officer (External Loan
 * Officer Profile + role, permission set group External_Loan_Officer).
 *
 * Proves: the category must match who was contacted (a consumer lead is never Realtor outreach);
 * Log communication credits the category that matches the target; the picker finds leads, partners,
 * past clients and borrowers; notes become an Enhanced_Note__c stamped for the LO; logged calls
 * show on the record; records the LO cannot open are refused.
 */
@IsTest
private class LoWsActivityLogTest {

    static final String NAME = 'Zedlogtest';

    @TestSetup
    static void setup() {
        User lo = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p9log' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p9.test',
            Email = 'p9log@reach-p9.test',
            LastName = 'p9log',
            Alias = 'p9log',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert lo;
            // The real group, like the pilot. With only External_LO_Access + External_LO_Perfect_Day_Access,
            // inserting a Lead note fails inside EnhancedNoteLeadLastNote ("Variable does not exist: tmpVar1").
            insert new PermissionSetAssignment(AssigneeId = lo.Id,
                PermissionSetGroupId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'External_Loan_Officer'].Id);
        }
        Id personRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Id consumerRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Consumer_Lead_record_type').getRecordTypeId();
        Account partner = new Account(RecordTypeId = personRt, FirstName = 'Rita', LastName = NAME + 'Realtor',
            PersonEmail = 'p9.realtor@example.com', Is_Realtor__c = true, OwnerId = lo.Id);
        Account client = new Account(RecordTypeId = personRt, FirstName = 'Cal', LastName = NAME + 'Client',
            PersonEmail = 'p9.client@example.com', Group__pc = 'Client', Type__c = 'Borrower Account', OwnerId = lo.Id);
        Account borrower = new Account(RecordTypeId = personRt, FirstName = 'Bo', LastName = NAME + 'Borrower',
            PersonEmail = 'p9.borrower@example.com');
        // Owned by the admin and never shared: the LO must not be able to log against it.
        Account stranger = new Account(RecordTypeId = personRt, FirstName = 'Sam', LastName = 'Stranger',
            PersonEmail = 'p9.stranger@example.com');
        insert new List<Account>{ partner, client, borrower, stranger };
        insert new Lead(RecordTypeId = consumerRt, FirstName = 'Lee', LastName = NAME + 'Lead', Company = 'n/a',
            Status = 'New', OwnerId = lo.Id);
        insert new Transaction__c(Name = NAME + ' Loan', Loan_Officer__c = lo.Id, Borrower_Name__c = borrower.Id);
        System.runAs(lo) {
            LoWsPartnerTagService.tagAccounts(new Set<Id>{ partner.Id });
        }
    }

    static User lo() {
        return [SELECT Id FROM User WHERE Alias = 'p9log' LIMIT 1];
    }

    static Id leadId() {
        return [SELECT Id FROM Lead WHERE LastName = :NAME + 'Lead' LIMIT 1].Id;
    }

    static Id accountId(String suffix) {
        String lastName = suffix == 'Stranger' ? 'Stranger' : NAME + suffix;
        return [SELECT Id FROM Account WHERE LastName = :lastName LIMIT 1].Id;
    }

    static ExternalLoActivityLogService.LogRequest request(String activityKey, String channel, Id recordId, String notes) {
        ExternalLoActivityLogService.LogRequest r = new ExternalLoActivityLogService.LogRequest();
        r.activityKey = activityKey;
        r.channel = channel;
        r.activityCount = 1;
        r.recordId = recordId;
        r.objectApiName = 'Lead'; // deliberately wrong for accounts: the service trusts the Id
        r.notes = notes;
        return r;
    }

    @IsTest
    static void consumerLeadCannotBeLoggedAsRealtorOutreach() {
        Id leadRecordId = leadId();
        String message;
        System.runAs(lo()) {
            try {
                ExternalLoActivityLogService.logActivity(request('realtor-outreach', 'call', leadRecordId, 'Talked about rates.'));
            } catch (DomainException e) {
                message = e.getMessage();
            }
        }
        Assert.areEqual('Realtor outreach must be logged against a realtor or partner. Pick Consumer convos for a lead.', message);
    }

    @IsTest
    static void partnerCannotBeLoggedAsConsumerAndPartnerCategoriesWork() {
        Id partnerId = accountId('Realtor');
        String message;
        Id taskId;
        System.runAs(lo()) {
            try {
                ExternalLoActivityLogService.logActivity(request('consumer-conversation', 'call', partnerId, null));
            } catch (DomainException e) {
                message = e.getMessage();
            }
            taskId = ExternalLoActivityLogService.logActivity(request('partner-meeting', 'meeting', partnerId, 'Coffee.')).taskId;
        }
        Assert.isTrue(message.startsWith('Consumer convos must be logged against a lead or borrower.'), message);
        Task logged = [SELECT WhatId, Activity_Category__c, Activity_Type__c, Type FROM Task WHERE Id = :taskId];
        Assert.areEqual(partnerId, logged.WhatId);
        Assert.areEqual('Partner_Meeting', logged.Activity_Category__c);
        Assert.areEqual('Meeting (Active Agent)', logged.Activity_Type__c);
        Assert.areEqual('Meeting', logged.Type);
        Assert.areEqual(1, [SELECT COUNT() FROM Enhanced_Note__c WHERE Account__c = :partnerId AND Type__c = 'Note']);
    }

    @IsTest
    static void consumerLogWritesNoteStampedForLoAndShowsInLoggedCalls() {
        Id leadRecordId = leadId();
        User loUser = lo();
        List<ExternalLoPortalService.ActivityEntry> calls;
        Id taskId;
        System.runAs(loUser) {
            Test.startTest();
            taskId = ExternalLoActivityLogService.logActivity(
                request('consumer-conversation', 'call', leadRecordId, 'Rates <and> timing.\nCall back Friday.')
            ).taskId;
            Test.stopTest();
            calls = ExternalLoPortalService.loggedCalls(leadRecordId);
        }
        Task logged = [SELECT Activity_Category__c, Activity_Type__c, Type FROM Task WHERE Id = :taskId];
        Assert.areEqual('Consumer_Conversation', logged.Activity_Category__c);
        Assert.areEqual('Call - Prospecting', logged.Activity_Type__c, 'A lead call is not an agent call.');
        Assert.areEqual('Call', logged.Type);

        Enhanced_Note__c note = [SELECT Subject__c, Body__c, Type__c, External_LO__c FROM Enhanced_Note__c WHERE Lead__c = :leadRecordId];
        Assert.areEqual('Call — Consumer convos', note.Subject__c);
        Assert.areEqual('Note', note.Type__c);
        Assert.isTrue(note.Body__c.contains('&lt;and&gt;') && note.Body__c.contains('<br>'), note.Body__c);
        Assert.areEqual(loUser.Id, note.External_LO__c, 'The stamp trigger must let the outside LO see their own note.');

        Assert.areEqual(1, calls.size());
        Assert.areEqual('Call', calls[0].channel);
        Assert.areEqual('Consumer convos', calls[0].outcome);
        Assert.areEqual('p9log', calls[0].author);
    }

    @IsTest
    static void logCommunicationOnConsumerLeadCreditsConsumerConvos() {
        Id leadRecordId = leadId();
        Id taskId;
        System.runAs(lo()) {
            ExternalLoCommunicationService.LogRequest r = new ExternalLoCommunicationService.LogRequest();
            r.recordId = leadRecordId;
            r.objectApiName = 'Lead';
            r.channel = 'call';
            r.outcome = 'connected';
            r.notes = 'Few questions about properties.';
            r.followUpOption = 'none';
            taskId = ExternalLoCommunicationService.logCommunication(r).taskId;
        }
        Task logged = [SELECT Activity_Category__c, Activity_Type__c, Type, CallDisposition FROM Task WHERE Id = :taskId];
        Assert.areEqual('Consumer_Conversation', logged.Activity_Category__c);
        Assert.areEqual('consumer-conversation', ExternalLoActivityRollupBuilder.activityKeyFor(logged));
        Assert.areEqual('Call - Prospecting', logged.Activity_Type__c);
        Assert.areEqual('Call', logged.Type);
        Assert.areEqual('Connected', logged.CallDisposition);
        Assert.areEqual(1, [SELECT COUNT() FROM Enhanced_Note__c WHERE Lead__c = :leadRecordId], 'One note per log.');
    }

    @IsTest
    static void logCommunicationOnPartnerAndLoanPickMatchingCategories() {
        Id partnerId = accountId('Realtor');
        Id loanId = [SELECT Id FROM Transaction__c WHERE Name = :NAME + ' Loan'].Id;
        Id partnerTask;
        Id loanTask;
        System.runAs(lo()) {
            ExternalLoCommunicationService.LogRequest r = new ExternalLoCommunicationService.LogRequest();
            r.recordId = partnerId;
            r.objectApiName = 'Account';
            r.channel = 'call';
            r.notes = 'Caught up on listings.';
            r.followUpOption = 'none';
            partnerTask = ExternalLoCommunicationService.logCommunication(r).taskId;
            r.recordId = loanId;
            r.objectApiName = 'Transaction__c';
            r.channel = 'video';
            r.notes = 'Walked the borrower through the file.';
            loanTask = ExternalLoCommunicationService.logCommunication(r).taskId;
        }
        Task partnerLog = [SELECT Activity_Category__c, Activity_Type__c FROM Task WHERE Id = :partnerTask];
        Assert.areEqual('Realtor_Outreach', partnerLog.Activity_Category__c);
        Assert.areEqual('Call - Active Agent', partnerLog.Activity_Type__c);
        Task loanLog = [SELECT Activity_Category__c, Activity_Type__c, Type FROM Task WHERE Id = :loanTask];
        Assert.areEqual('Consumer_Conversation', loanLog.Activity_Category__c, 'An open loan is a borrower conversation.');
        Assert.isNull(loanLog.Activity_Type__c, 'No agent meeting type on a borrower.');
        Assert.areEqual('Meeting', loanLog.Type);
        Assert.areEqual(1, [SELECT COUNT() FROM Enhanced_Note__c WHERE Transaction__c = :loanId]);
    }

    @IsTest
    static void pickerFindsLeadsPartnersPastClientsAndBorrowers() {
        List<ExternalLoActivityLogService.SearchHit> hits;
        System.runAs(lo()) {
            hits = ExternalLoActivityLogService.searchLoggableRecords(NAME);
        }
        Map<String, ExternalLoActivityLogService.SearchHit> bySubtitle = new Map<String, ExternalLoActivityLogService.SearchHit>();
        for (ExternalLoActivityLogService.SearchHit h : hits) {
            bySubtitle.put(h.subtitle.substringBefore(' ·'), h);
        }
        Assert.areEqual(4, hits.size(), JSON.serialize(hits));
        Assert.areEqual('consumer-conversation', bySubtitle.get('Lead').activityKey);
        Assert.areEqual('realtor-outreach', bySubtitle.get('Partner').activityKey);
        Assert.isFalse(bySubtitle.get('Partner').allowedKeys.contains('consumer-conversation'));
        Assert.areEqual('past-client-call', bySubtitle.get('Past client').activityKey);
        Assert.areEqual('Transaction__c', bySubtitle.get('Borrower').objectApiName);
        Assert.isTrue(bySubtitle.get('Borrower').allowedKeys.contains('past-client-call'));
    }

    @IsTest
    static void pastClientsAndBorrowersAreLoggableButStrangersAreNot() {
        Id clientId = accountId('Client');
        Id loanId = [SELECT Id FROM Transaction__c WHERE Name = :NAME + ' Loan'].Id;
        Id strangerId = accountId('Stranger');
        String denied;
        String clientKind;
        System.runAs(lo()) {
            clientKind = ExternalLoActivityLogService.targetKind(clientId);
            Assert.isNotNull(ExternalLoActivityLogService.logActivity(request('past-client-call', 'call', clientId, null)).taskId);
            Assert.isNotNull(ExternalLoActivityLogService.logActivity(request('past-client-call', 'call', loanId, null)).taskId);
            try {
                ExternalLoActivityLogService.logActivity(request('consumer-conversation', 'call', strangerId, null));
            } catch (Exception e) {
                denied = e.getMessage();
            }
        }
        Assert.areEqual(RecordAccessGuard.NO_ACCESS, denied);
        Assert.areEqual(ExternalLoActivityLogService.KIND_CLIENT, clientKind);
    }

    @IsTest
    static void socialPostHasNoContactNoChannelAndCreditsSocialPosts() {
        Id leadRecordId = leadId();
        String rejected;
        Id taskId;
        System.runAs(lo()) {
            try {
                ExternalLoActivityLogService.logActivity(request('social-engagement', null, leadRecordId, 'Platform: Instagram'));
            } catch (DomainException e) {
                rejected = e.getMessage();
            }
            // The modal sends no channel, but a stray one must not turn the post into a call.
            ExternalLoActivityLogService.LogRequest post = request('social-engagement', 'call', null, 'Platform: Instagram\nReel on first-time buyer tips.');
            post.activityCount = 3;
            taskId = ExternalLoActivityLogService.logActivity(post).taskId;
        }
        Assert.areEqual('Social posts are not logged against a contact. Clear the contact and pick the platform.', rejected);
        Task logged = [
            SELECT WhoId, WhatId, Type, Activity_Category__c, Activity_Type__c, Activity_Count__c, Description
            FROM Task WHERE Id = :taskId
        ];
        Assert.isNull(logged.WhoId);
        Assert.isNull(logged.WhatId);
        Assert.isNull(logged.Type, 'No channel, so never a Logged calls row.');
        Assert.areEqual('Social_Engagement', logged.Activity_Category__c);
        Assert.areEqual(ExternalLoActivityCatalog.activityTypeForCategory('Social_Engagement'), logged.Activity_Type__c);
        Assert.areEqual(3, logged.Activity_Count__c.intValue());
        Assert.isTrue(logged.Description.startsWith('Platform: Instagram'), logged.Description);
        Assert.areEqual('social-engagement', ExternalLoActivityRollupBuilder.activityKeyFor(logged));
        Assert.areEqual(0, [SELECT COUNT() FROM Enhanced_Note__c WHERE Lead__c = :leadRecordId]);
    }
}
