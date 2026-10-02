// Phase 1b: every method checks the running user can open the Transaction. Writes are gated on
// read, not edit, on purpose: Loan Officers hold Transaction Read only and this form is one of
// their sanctioned write paths, so an edit check would lock them out.
public class TransactionNotesFormController {

    // Headings written by ApplicationSummaryService.buildSnapshot, mapped to the section and block
    // labels the modal shows. Keeping this list in step with SNAPSHOT_HEADING is what lets the
    // Transaction render the same seven sections the Lead does.
    private static final List<String> HEADING_ORDER = new List<String>{
        'BORROWER INFORMATION - HOUSEHOLD',
        'BORROWER 1',
        'BORROWER 2',
        'INCOME / EMPLOYMENT - BORROWER 1',
        'INCOME / EMPLOYMENT - BORROWER 2',
        'PROPERTY',
        'ASSETS',
        'CREDIT',
        'GOALS',
        'OTHER IMPORTANT POINTS'
    };

    private static final Map<String, String> SECTION_BY_HEADING = new Map<String, String>{
        'BORROWER INFORMATION - HOUSEHOLD' => 'Borrower Information',
        'BORROWER 1' => 'Borrower Information',
        'BORROWER 2' => 'Borrower Information',
        'INCOME / EMPLOYMENT - BORROWER 1' => 'Income',
        'INCOME / EMPLOYMENT - BORROWER 2' => 'Income',
        'PROPERTY' => 'Property',
        'ASSETS' => 'Assets',
        'CREDIT' => 'Credit',
        'GOALS' => 'Goals',
        'OTHER IMPORTANT POINTS' => 'Other Important Points'
    };

    private static final Map<String, String> BLOCK_BY_HEADING = new Map<String, String>{
        'BORROWER INFORMATION - HOUSEHOLD' => 'Household',
        'BORROWER 1' => 'Borrower 1',
        'BORROWER 2' => 'Borrower 2',
        'INCOME / EMPLOYMENT - BORROWER 1' => 'Borrower 1',
        'INCOME / EMPLOYMENT - BORROWER 2' => 'Borrower 2',
        'PROPERTY' => 'Property',
        'ASSETS' => 'Assets',
        'CREDIT' => 'Credit',
        'GOALS' => 'Goals',
        'OTHER IMPORTANT POINTS' => 'Other Important Points'
    };

    private static final List<String> SECTION_ORDER = new List<String>{
        'Borrower Information', 'Income', 'Property', 'Assets', 'Credit', 'Goals', 'Other Important Points'
    };

    public class SummaryBlock {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public SummaryBlock(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class SummarySection {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public List<SummaryBlock> blocks { get; set; }
        @AuraEnabled public Boolean single { get; set; }

        public SummarySection(String label, List<SummaryBlock> blocks) {
            this.label = label;
            this.name = label.replaceAll('[^a-zA-Z0-9]', '');
            this.blocks = blocks;
            this.single = blocks.size() == 1;
        }
    }

    public class SummaryView {
        @AuraEnabled public List<SummarySection> sections { get; set; }
        @AuraEnabled public String capturedAt { get; set; }
        @AuraEnabled public Boolean hasSnapshot { get; set; }
    }

    /**
     * Renders the conversion snapshot as the same seven sections the Lead modal shows.
     * Always read only: the snapshot is a record of what was known at conversion, so it is
     * reconstructed for display and never written back.
     */
    @AuraEnabled
    public static SummaryView getApplicationSummary(Id recordId) {
        try {
            RecordAccessGuard.requireRead(recordId);
            Transaction__c transactionRecord = [
                SELECT Id, App_Summary_Snapshot__c FROM Transaction__c WHERE Id = :recordId
            ];

            SummaryView view = new SummaryView();
            view.hasSnapshot = String.isNotBlank(transactionRecord.App_Summary_Snapshot__c);
            view.sections = new List<SummarySection>();
            if (!view.hasSnapshot) {
                return view;
            }

            Map<String, String> textByHeading = parseSnapshot(transactionRecord.App_Summary_Snapshot__c, view);

            Map<String, List<SummaryBlock>> blocksBySection = new Map<String, List<SummaryBlock>>();
            for (String heading : HEADING_ORDER) {
                String value = textByHeading.get(heading);
                if (String.isBlank(value)) {
                    continue;
                }
                String sectionLabel = SECTION_BY_HEADING.get(heading);
                if (!blocksBySection.containsKey(sectionLabel)) {
                    blocksBySection.put(sectionLabel, new List<SummaryBlock>());
                }
                blocksBySection.get(sectionLabel).add(new SummaryBlock(BLOCK_BY_HEADING.get(heading), value));
            }

            // Sections with nothing captured are left out rather than shown as empty boxes.
            for (String sectionLabel : SECTION_ORDER) {
                if (blocksBySection.containsKey(sectionLabel)) {
                    view.sections.add(new SummarySection(sectionLabel, blocksBySection.get(sectionLabel)));
                }
            }
            return view;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Splits the snapshot on its heading lines. Content is accumulated until the next known
     * heading, so a section whose body contains blank lines survives intact.
     */
    @TestVisible
    private static Map<String, String> parseSnapshot(String snapshot, SummaryView view) {
        Map<String, String> textByHeading = new Map<String, String>();
        Set<String> headings = new Set<String>(HEADING_ORDER);
        String currentHeading = null;
        List<String> buffer = new List<String>();

        for (String rawLine : snapshot.split('\n')) {
            String line = rawLine == null ? '' : rawLine.trim();
            if (headings.contains(line)) {
                if (currentHeading != null) {
                    textByHeading.put(currentHeading, String.join(buffer, '\n').trim());
                }
                currentHeading = line;
                buffer = new List<String>();
                continue;
            }
            if (currentHeading == null) {
                // Everything before the first heading is the "snapshot taken at" preamble.
                if (view != null && String.isBlank(view.capturedAt) && line.startsWithIgnoreCase('Application Summary snapshot taken')) {
                    view.capturedAt = line;
                }
                continue;
            }
            buffer.add(rawLine);
        }
        if (currentHeading != null) {
            textByHeading.put(currentHeading, String.join(buffer, '\n').trim());
        }
        return textByHeading;
    }

    @AuraEnabled
    public static String getNotes(Id recordId){
        try {
            RecordAccessGuard.requireRead(recordId);
            return [SELECT Id, Lead_Notes_JSON__c FROM Transaction__c WHERE Id = :recordId].Lead_Notes_JSON__c;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveNotes(Id recordId, String notes){
        try {
            RecordAccessGuard.requireRead(recordId);
            Transaction__c l = new Transaction__c(Id = recordId, Lead_Notes_JSON__c = notes);
            update l;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void createNote(Id recordId, String borrowerNotes, String coBorrowerNotes){
        try {
            RecordAccessGuard.requireRead(recordId);
            User currentUser = getCurrentUser();
            Enhanced_Note__c newNote = new Enhanced_Note__c();
            newNote.Transaction__c = recordId;
            newNote.Subject__c = 'Transaction Details';
            newNote.Body__c = getNoteBody(borrowerNotes, coBorrowerNotes);

            insert newNote;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static User getCurrentUser() {
        return [
            SELECT Id, Enhanced_Note_Role__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
    }

    private static String getNoteBody(String borrowerNotes, String coBorrowerNotes) {
        String body = '<p><b>Borrower</b></p><ul>';
        Map<String, Object> notesMap = (Map<String, Object>) JSON.deserializeUntyped(borrowerNotes);

        for (String key :notesMap.keySet()) {
            body += '<li>' + key + ': ' + (String) notesMap.get(key) + '</li>';
        }

        body = body + '</ul>';

        Map<String, Object> coBorrNotesMap = (Map<String, Object>) JSON.deserializeUntyped(coBorrowerNotes);

        if (coBorrNotesMap != null && coBorrNotesMap.size() > 0) {
            body = body + '<hr/><p><b>Co-Borrower</b></p><ul>';
            for (String key : coBorrNotesMap.keySet()) {
                body += '<li>' + key + ': ' + (String) coBorrNotesMap.get(key) + '</li>';
            }

            body = body + '</ul>';
        }

        return body;
    }
}