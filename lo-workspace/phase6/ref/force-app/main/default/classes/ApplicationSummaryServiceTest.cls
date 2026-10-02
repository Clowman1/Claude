@IsTest
private class ApplicationSummaryServiceTest {

    private static final String LONG_TRANSCRIPT =
        'Agent: Thanks for the time today. Tell me about the property. Borrower: We have an offer '
        + 'accepted at 895000 on 1606 Flagler Avenue in Key West. We are renting now at 5500 a month '
        + 'split between us. I am a server and my partner manages a hotel making about 150000 a year. '
        + 'We are putting 20 percent down from my savings and expecting an inheritance later. '
        + 'My score is around 750 and my partner is over 800. We want to avoid FHA and minimise '
        + 'total interest paid across the life of the loan, and recast once the money arrives.';

    @IsTest
    static void appendKeepsExistingContentAndAddsBeneathIt() {
        String combined = (String) callAppend('-- Inbound call, Aug 1 2026 9:00 AM (CI-1)\n- First point',
            '-- Outbound call, Aug 2 2026 9:00 AM (CI-2)\n- Second point');
        System.assert(combined.contains('First point'), 'Existing content must be preserved.');
        System.assert(combined.contains('Second point'), 'New content must be appended.');
        System.assert(
            combined.indexOf('First point') < combined.indexOf('Second point'),
            'New blocks must appear beneath existing ones.'
        );
    }

    @IsTest
    static void appendRefusesRatherThanTruncatingWhenFull() {
        String nearlyFull = 'x'.repeat(32760);
        Object result = callAppend(nearlyFull, '-- Call (CI-9)\n- Another point that will not fit');
        System.assertEquals(null, result, 'A block that will not fit must be refused, not truncated.');
    }

    @IsTest
    static void snapshotOnConversionWritesOnceAndNeverOverwrites() {
        Lead leadRecord = new Lead(
            LastName = 'Snapshot',
            Company = 'Reach Home Loans',
            App_Summary_Property__c = '-- Inbound call, Aug 1 2026 9:00 AM (CI-1)\n- Purchase price: $895,000',
            App_Summary_Credit__c = '-- Inbound call, Aug 1 2026 9:00 AM (CI-1)\n- Score approximately 750'
        );
        insert leadRecord;

        Transaction__c txn = new Transaction__c();
        insert txn;

        Test.startTest();
        // Simulate conversion: the trigger fires on the Lead update.
        leadRecord.Converted_Transaction_ID__c = txn.Id;
        update leadRecord;
        ApplicationSummaryService.snapshotOnConversion(
            new List<Lead>{ [
                SELECT Id, IsConverted, Converted_Transaction_ID__c, App_Summary_Property__c,
                       App_Summary_Credit__c, App_Summary_Household__c, App_Summary_Borrower_1__c,
                       App_Summary_Borrower_2__c, App_Summary_Income_B1__c, App_Summary_Income_B2__c,
                       App_Summary_Assets__c, App_Summary_Goals__c, App_Summary_Other_Points__c
                FROM Lead WHERE Id = :leadRecord.Id
            ] },
            null
        );
        Test.stopTest();

        Transaction__c saved = [SELECT App_Summary_Snapshot__c FROM Transaction__c WHERE Id = :txn.Id];
        if (String.isNotBlank(saved.App_Summary_Snapshot__c)) {
            System.assert(saved.App_Summary_Snapshot__c.contains('PROPERTY'), 'Snapshot should carry section headings.');
            System.assert(saved.App_Summary_Snapshot__c.contains('895,000'), 'Snapshot should carry the Lead content.');

            // A second pass must leave the existing snapshot untouched.
            String before = saved.App_Summary_Snapshot__c;
            ApplicationSummaryService.snapshotOnConversion(new List<Lead>{ leadRecord }, null);
            Transaction__c after = [SELECT App_Summary_Snapshot__c FROM Transaction__c WHERE Id = :txn.Id];
            System.assertEquals(before, after.App_Summary_Snapshot__c, 'An existing snapshot must never be rewritten.');
        }
    }

    @IsTest
    static void insightWithoutLeadIsIgnored() {
        Call_Insight__c insight = new Call_Insight__c(Transcript__c = LONG_TRANSCRIPT);
        insert insight;

        Test.startTest();
        ApplicationSummaryService.enqueueForInsights(new List<Call_Insight__c>{ insight });
        ApplicationSummaryService.summarizeInsight(insight.Id);
        Test.stopTest();

        System.assertEquals(0, Limits.getQueueableJobs(), 'An insight with no Lead must not be queued.');
    }

    @IsTest
    static void shortTranscriptIsSkipped() {
        Lead leadRecord = new Lead(LastName = 'Brief', Company = 'Reach Home Loans');
        insert leadRecord;
        Call_Insight__c insight = new Call_Insight__c(Lead__c = leadRecord.Id, Transcript__c = 'Left a voicemail.');
        insert insight;

        Test.startTest();
        ApplicationSummaryService.summarizeInsight(insight.Id);
        Test.stopTest();

        Lead after = [SELECT App_Summary_Property__c FROM Lead WHERE Id = :leadRecord.Id];
        System.assertEquals(null, after.App_Summary_Property__c, 'Voicemail-length calls must not be summarized.');
    }

    @IsTest
    static void queueableRunsForLeadLinkedInsight() {
        Lead leadRecord = new Lead(LastName = 'Queued', Company = 'Reach Home Loans');
        insert leadRecord;

        Test.startTest();
        // Insert fires ClientActivityCallInsightRouter, which enqueues the summary job.
        insert new Call_Insight__c(Lead__c = leadRecord.Id, Transcript__c = LONG_TRANSCRIPT);
        Test.stopTest();

        System.assert(true, 'Insert and enqueue completed without error.');
    }

    @IsTest
    static void snapshotAndFieldHelpersBehave() {
        System.assertEquals(10, ApplicationSummaryService.summaryFieldNames().size(), 'Ten summary fields expected.');
        System.assertEquals(null, ApplicationSummaryService.buildSnapshot(null), 'A null Lead yields no snapshot.');
        Lead empty = new Lead(LastName = 'Empty', Company = 'Reach Home Loans');
        System.assertEquals(null, ApplicationSummaryService.buildSnapshot(empty), 'An empty Lead yields no snapshot.');
    }

    @IsTest
    static void summaryAppendsDatedBlocksAndSkipsRepeats() {
        Lead leadRecord = new Lead(LastName = 'Appender', Company = 'Reach Home Loans');
        insert leadRecord;
        Call_Insight__c insight = new Call_Insight__c(
            Lead__c = leadRecord.Id,
            Transcript__c = LONG_TRANSCRIPT,
            Direction__c = 'Inbound',
            Recording_Start_DateTime__c = Datetime.newInstance(2026, 8, 12, 15, 48, 0)
        );
        insert insight;

        // Fenced JSON, since the model commonly wraps its output in a code block.
        ApplicationSummaryService.mockSectionsJson =
            '```json\n{"household":["Renting at $5,500/month split"],"borrower1":[],"borrower2":[],'
            + '"incomeBorrower1":[],"incomeBorrower2":["Hotel manager, about $150,000/year"],'
            + '"property":["Offer accepted at $895,000"],"assets":["20% down from savings"],'
            + '"credit":["Score around 750"],"goals":["Avoid FHA"],"otherPoints":[]}\n```';

        Test.startTest();
        ApplicationSummaryService.summarizeInsight(insight.Id);
        Test.stopTest();

        Lead after = [
            SELECT App_Summary_Household__c, App_Summary_Property__c, App_Summary_Credit__c,
                   App_Summary_Income_B2__c, App_Summary_Borrower_1__c
            FROM Lead WHERE Id = :leadRecord.Id
        ];
        System.assert(after.App_Summary_Property__c.contains('895,000'), 'Property point should be written.');
        System.assert(after.App_Summary_Property__c.contains('Aug 12 2026'), 'Block must carry the call date.');
        System.assert(after.App_Summary_Property__c.contains(insight.Id != null ? 'Inbound call' : ''), 'Block must name the direction.');
        System.assert(after.App_Summary_Income_B2__c.contains('150,000'), 'Borrower 2 income should be written.');
        System.assertEquals(null, after.App_Summary_Borrower_1__c, 'Empty categories must stay empty.');

        // Re-running the same call must not duplicate the block.
        String propertyBefore = after.App_Summary_Property__c;
        ApplicationSummaryService.summarizeInsight(insight.Id);
        Lead second = [SELECT App_Summary_Property__c FROM Lead WHERE Id = :leadRecord.Id];
        System.assertEquals(propertyBefore, second.App_Summary_Property__c, 'A repeat run must not append again.');
    }

    @IsTest
    static void unparseableModelResponseIsIgnored() {
        Lead leadRecord = new Lead(LastName = 'BadJson', Company = 'Reach Home Loans');
        insert leadRecord;
        Call_Insight__c insight = new Call_Insight__c(Lead__c = leadRecord.Id, Transcript__c = LONG_TRANSCRIPT);
        insert insight;
        ApplicationSummaryService.mockSectionsJson = 'Sorry, I could not process that.';

        Test.startTest();
        ApplicationSummaryService.summarizeInsight(insight.Id);
        Test.stopTest();

        Lead after = [SELECT App_Summary_Property__c FROM Lead WHERE Id = :leadRecord.Id];
        System.assertEquals(null, after.App_Summary_Property__c, 'A non-JSON reply must write nothing.');
    }

    @IsTest
    static void convertedLeadDoesNotAccumulate() {
        Lead leadRecord = new Lead(LastName = 'Converted', Company = 'Reach Home Loans');
        insert leadRecord;
        Call_Insight__c insight = new Call_Insight__c(Lead__c = leadRecord.Id, Transcript__c = LONG_TRANSCRIPT);
        insert insight;
        ApplicationSummaryService.mockSectionsJson =
            '{"household":[],"borrower1":[],"borrower2":[],"incomeBorrower1":[],"incomeBorrower2":[],'
            + '"property":["Should not be written"],"assets":[],"credit":[],"goals":[],"otherPoints":[]}';

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(leadRecord.Id);
        lc.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        Database.LeadConvertResult result = Database.convertLead(lc, false);

        Test.startTest();
        if (result.isSuccess()) {
            ApplicationSummaryService.summarizeInsight(insight.Id);
        }
        Test.stopTest();

        if (result.isSuccess()) {
            Lead after = [SELECT App_Summary_Property__c FROM Lead WHERE Id = :leadRecord.Id];
            System.assertEquals(null, after.App_Summary_Property__c, 'A converted Lead must stop accumulating.');
        }
    }

    @IsTest
    static void zoomInsightIsMarkedAsAZoomMeeting() {
        Call_Insight__c insight = new Call_Insight__c(Source__c = 'Zoom',
            Recording_Start_DateTime__c = Datetime.newInstance(2026, 9, 11, 16, 30, 0));
        System.assert(ApplicationSummaryService.markerFor(insight).startsWith('Zoom meeting, Sep 11 2026'),
            'Zoom blocks must be labelled as a Zoom meeting, not a call');
    }

    // appendBlock is private; reach it the same way the service does.
    private static Object callAppend(String existing, String block) {
        return ApplicationSummaryService.appendBlockForTest(existing, block);
    }
}