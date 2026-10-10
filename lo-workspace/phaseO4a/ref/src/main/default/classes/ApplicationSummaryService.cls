/**
 * Builds the Lead Application Summary from RingSense call and Zoom meeting transcripts.
 *
 * Only Leads accumulate. Each new Call_Insight__c appends a dated block beneath whatever is
 * already in each category field - existing content is never read-modified-replaced. Once a Lead
 * converts, LeadConvertedTransactionSyncService copies a point-in-time snapshot onto the
 * Transaction and nothing appends there again.
 */
public without sharing class ApplicationSummaryService {

    // Response key -> Lead field. The keys are what the model is asked to return.
    private static final Map<String, String> FIELD_BY_KEY = new Map<String, String>{
        'household' => 'App_Summary_Household__c',
        'borrower1' => 'App_Summary_Borrower_1__c',
        'borrower2' => 'App_Summary_Borrower_2__c',
        'incomeBorrower1' => 'App_Summary_Income_B1__c',
        'incomeBorrower2' => 'App_Summary_Income_B2__c',
        'property' => 'App_Summary_Property__c',
        'assets' => 'App_Summary_Assets__c',
        'credit' => 'App_Summary_Credit__c',
        'goals' => 'App_Summary_Goals__c',
        'otherPoints' => 'App_Summary_Other_Points__c'
    };

    // Section order and headings used when snapshotting to the Transaction.
    private static final List<String> SNAPSHOT_ORDER = new List<String>{
        'household', 'borrower1', 'borrower2', 'incomeBorrower1', 'incomeBorrower2',
        'property', 'assets', 'credit', 'goals', 'otherPoints'
    };
    private static final Map<String, String> SNAPSHOT_HEADING = new Map<String, String>{
        'household' => 'BORROWER INFORMATION - HOUSEHOLD',
        'borrower1' => 'BORROWER 1',
        'borrower2' => 'BORROWER 2',
        'incomeBorrower1' => 'INCOME / EMPLOYMENT - BORROWER 1',
        'incomeBorrower2' => 'INCOME / EMPLOYMENT - BORROWER 2',
        'property' => 'PROPERTY',
        'assets' => 'ASSETS',
        'credit' => 'CREDIT',
        'goals' => 'GOALS',
        'otherPoints' => 'OTHER IMPORTANT POINTS'
    };

    private static final Integer FIELD_LIMIT = 32768;
    // OpenAI calls are slow; a transaction allows only ~120s of cumulative callout time.
    private static final Integer INSIGHTS_PER_JOB = 3;
    private static final Integer MIN_TRANSCRIPT_LENGTH = 400;

    @TestVisible
    private static String mockSectionsJson;

    // ---------------------------------------------------------------- trigger entry point

    public static void enqueueForInsights(List<Call_Insight__c> insights) {
        if (insights == null || insights.isEmpty() || System.isBatch() || System.isFuture()) {
            return;
        }
        List<Id> queue = new List<Id>();
        for (Call_Insight__c insight : insights) {
            // Only pre-conversion Leads accumulate. An insight already tied to a Transaction
            // belongs to a converted file, whose summary is frozen at its snapshot.
            if (insight.Lead__c != null && insight.Transaction__c == null) {
                queue.add(insight.Id);
            }
        }
        if (queue.isEmpty() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        System.enqueueJob(new SummaryJob(queue));
    }

    public class SummaryJob implements Queueable, Database.AllowsCallouts {
        private List<Id> insightIds;

        public SummaryJob(List<Id> insightIds) {
            this.insightIds = insightIds;
        }

        public void execute(QueueableContext context) {
            List<Id> batch = new List<Id>();
            List<Id> remainder = new List<Id>();
            for (Integer i = 0; i < insightIds.size(); i++) {
                if (i < INSIGHTS_PER_JOB) {
                    batch.add(insightIds[i]);
                } else {
                    remainder.add(insightIds[i]);
                }
            }
            for (Id insightId : batch) {
                try {
                    summarizeInsight(insightId);
                } catch (Exception e) {
                    // One bad transcript must not stop the rest of the batch.
                    System.debug(LoggingLevel.ERROR, 'Application Summary failed for ' + insightId
                        + ': ' + e.getTypeName() + ': ' + e.getMessage());
                }
            }
            if (!remainder.isEmpty() && !Test.isRunningTest()) {
                System.enqueueJob(new SummaryJob(remainder));
            }
        }
    }

    // ---------------------------------------------------------------- summarize one call

    public static void summarizeInsight(Id insightId) {
        List<Call_Insight__c> insights = [
            SELECT Id, Name, Lead__c, Transaction__c, Transcript__c, Direction__c, Source__c,
                   Recording_Start_DateTime__c, CreatedDate
            FROM Call_Insight__c
            WHERE Id = :insightId
            LIMIT 1
        ];
        if (insights.isEmpty()) {
            return;
        }
        Call_Insight__c insight = insights[0];
        String transcript = stripMarkup(insight.Transcript__c);
        if (insight.Lead__c == null || transcript.length() < MIN_TRANSCRIPT_LENGTH) {
            // Very short calls (voicemails, wrong numbers) carry nothing worth summarizing.
            return;
        }

        Lead leadRecord = [
            SELECT Id, IsConverted, App_Summary_Household__c, App_Summary_Borrower_1__c,
                   App_Summary_Borrower_2__c, App_Summary_Income_B1__c, App_Summary_Income_B2__c,
                   App_Summary_Property__c, App_Summary_Assets__c, App_Summary_Credit__c,
                   App_Summary_Goals__c, App_Summary_Other_Points__c
            FROM Lead
            WHERE Id = :insight.Lead__c
            LIMIT 1
        ];
        if (leadRecord.IsConverted) {
            return;
        }

        String marker = markerFor(insight);
        if (alreadyApplied(leadRecord, marker)) {
            // The job ran before for this call; appending again would duplicate the block.
            return;
        }

        Map<String, Object> sections = requestSections(transcript);
        if (sections == null || sections.isEmpty()) {
            return;
        }

        Lead updates = new Lead(Id = leadRecord.Id);
        Boolean hasChange = false;
        for (String key : FIELD_BY_KEY.keySet()) {
            String block = renderBlock(sections.get(key), marker);
            if (String.isBlank(block)) {
                continue;
            }
            String fieldName = FIELD_BY_KEY.get(key);
            String existing = (String) leadRecord.get(fieldName);
            String combined = appendBlock(existing, block);
            if (combined == null) {
                System.debug(LoggingLevel.ERROR, 'Application Summary: ' + fieldName
                    + ' is full on Lead ' + leadRecord.Id + '; skipped ' + marker);
                continue;
            }
            updates.put(fieldName, combined);
            hasChange = true;
        }
        if (hasChange) {
            update updates;
        }
    }

    // Appends beneath existing content. Returns null when the block will not fit, so the caller
    // can skip rather than truncate - nothing already saved is ever removed.
    @TestVisible
    private static String appendBlock(String existing, String block) {
        String current = String.isBlank(existing) ? '' : existing;
        String combined = String.isBlank(current) ? block : current + '\n\n' + block;
        return combined.length() > FIELD_LIMIT ? null : combined;
    }

    // Each block carries the call it came from, which doubles as the duplicate guard.
    @TestVisible
    private static String markerFor(Call_Insight__c insight) {
        Datetime callTime = insight.Recording_Start_DateTime__c == null
            ? insight.CreatedDate
            : insight.Recording_Start_DateTime__c;
        String direction = insight.Source__c == 'Zoom'
            ? 'Zoom meeting'
            : String.isBlank(insight.Direction__c)
            ? 'Call'
            : insight.Direction__c.substringBefore('-').capitalize() + ' call';
        return direction + ', ' + callTime.format('MMM d yyyy h:mm a') + ' (' + insight.Name + ')';
    }

    private static Boolean alreadyApplied(Lead leadRecord, String marker) {
        String tail = '(' + marker.substringAfterLast('(');
        for (String fieldName : FIELD_BY_KEY.values()) {
            String value = (String) leadRecord.get(fieldName);
            if (String.isNotBlank(value) && value.contains(tail)) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static String renderBlock(Object rawPoints, String marker) {
        if (!(rawPoints instanceof List<Object>)) {
            return null;
        }
        List<String> lines = new List<String>();
        for (Object point : (List<Object>) rawPoints) {
            String text = point == null ? '' : String.valueOf(point).trim();
            if (String.isNotBlank(text)) {
                lines.add('- ' + text);
            }
        }
        if (lines.isEmpty()) {
            return null;
        }
        return '-- ' + marker + '\n' + String.join(lines, '\n');
    }

    // ---------------------------------------------------------------- model call

    private static Map<String, Object> requestSections(String transcript) {
        // Tests drive the full append path by injecting a response instead of calling out.
        String response = Test.isRunningTest()
            ? mockSectionsJson
            : ChatGPTService.sendPrompt(buildPrompt(transcript));
        if (String.isBlank(response)) {
            return null;
        }
        String payload = response.trim();
        // Models often wrap JSON in a fenced code block.
        if (payload.startsWith('```')) {
            payload = payload.substringAfter('\n').substringBeforeLast('```').trim();
        }
        try {
            Object parsed = JSON.deserializeUntyped(payload);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Application Summary: unparseable model response: ' + e.getMessage());
            return null;
        }
    }

    @TestVisible
    private static String buildPrompt(String transcript) {
        return 'You are summarizing a mortgage discovery call for a loan officer\'s application notes.\n'
            + 'Extract only facts stated in the transcript. Never infer, estimate or invent. If a category '
            + 'has nothing stated, return an empty array for it.\n\n'
            + 'Return ONLY minified JSON with exactly these keys, each an array of short bullet strings:\n'
            + '{"household":[],"borrower1":[],"borrower2":[],"incomeBorrower1":[],"incomeBorrower2":[],'
            + '"property":[],"assets":[],"credit":[],"goals":[],"otherPoints":[]}\n\n'
            + 'Key meanings:\n'
            + '- household: shared living situation - current rent, where they live, payment comfort.\n'
            + '- borrower1 / borrower2: who each borrower is. borrower2 is the co-borrower, empty if only one.\n'
            + '- incomeBorrower1 / incomeBorrower2: employer, tenure, hours, pay type, W-2 or self-employed.\n'
            + '- property: address, purchase price, offer, closing timeline, seller concessions, insurance.\n'
            + '- assets: down payment amount and source, reserves, gifts, expected funds.\n'
            + '- credit: scores stated, and any credit concerns.\n'
            + '- goals: what the borrower wants - loan type preferences, cash to close, interest goals.\n'
            + '- otherPoints: anything materially important that fits no other key.\n\n'
            + 'Keep each bullet under 200 characters. Include figures exactly as stated.\n\n'
            + 'TRANSCRIPT:\n' + transcript;
    }

    // ---------------------------------------------------------------- snapshot on conversion

    /** Renders the Lead's accumulated summary as the frozen Transaction snapshot. */
    public static String buildSnapshot(Lead leadRecord) {
        if (leadRecord == null) {
            return null;
        }
        List<String> parts = new List<String>();
        for (String key : SNAPSHOT_ORDER) {
            String value = (String) leadRecord.get(FIELD_BY_KEY.get(key));
            if (String.isNotBlank(value)) {
                parts.add(SNAPSHOT_HEADING.get(key) + '\n' + value.trim());
            }
        }
        if (parts.isEmpty()) {
            return null;
        }
        String snapshot = 'Application Summary snapshot taken at conversion on '
            + Datetime.now().format('MMM d yyyy h:mm a') + '\n\n' + String.join(parts, '\n\n');
        return snapshot.length() > FIELD_LIMIT ? snapshot.abbreviate(FIELD_LIMIT) : snapshot;
    }

    /**
     * Writes the snapshot when a Lead converts. Gated separately from the Loan Partner sync,
     * which requires a Loan Partner to be set - a Lead without one still needs its snapshot.
     * Written once only: an existing snapshot is never refreshed or overwritten.
     */
    public static void snapshotOnConversion(List<Lead> newRecords, Map<Id, Lead> oldMap) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        Map<Id, Lead> leadByTransactionId = new Map<Id, Lead>();
        for (Lead leadRecord : newRecords) {
            if (!leadRecord.IsConverted || leadRecord.Converted_Transaction_ID__c == null) {
                continue;
            }
            Lead priorRecord = oldMap == null ? null : oldMap.get(leadRecord.Id);
            Boolean justConverted = priorRecord == null
                || priorRecord.IsConverted != leadRecord.IsConverted
                || priorRecord.Converted_Transaction_ID__c != leadRecord.Converted_Transaction_ID__c;
            if (justConverted) {
                leadByTransactionId.put(leadRecord.Converted_Transaction_ID__c, leadRecord);
            }
        }
        if (leadByTransactionId.isEmpty()) {
            return;
        }
        List<Transaction__c> updates = new List<Transaction__c>();
        for (Transaction__c transactionRecord : [
            SELECT Id, App_Summary_Snapshot__c
            FROM Transaction__c
            WHERE Id IN :leadByTransactionId.keySet()
        ]) {
            if (String.isNotBlank(transactionRecord.App_Summary_Snapshot__c)) {
                continue;
            }
            String snapshot = buildSnapshot(leadByTransactionId.get(transactionRecord.Id));
            if (String.isNotBlank(snapshot)) {
                updates.add(new Transaction__c(Id = transactionRecord.Id, App_Summary_Snapshot__c = snapshot));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    @TestVisible
    private static String appendBlockForTest(String existing, String block) {
        return appendBlock(existing, block);
    }

    public static List<String> summaryFieldNames() {
        return new List<String>(FIELD_BY_KEY.values());
    }

    private static String stripMarkup(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.replaceAll('<[^>]*>', ' ').replaceAll('&nbsp;', ' ').replaceAll('[ \\t]+', ' ').trim();
    }
}