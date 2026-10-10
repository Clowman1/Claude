// Phase 1b: no sharing keyword (runs without sharing from Aura), so every method checks the Lead
// the browser names: read for views and new notes, edit for writes to Lead fields.
public class LeadNotesFormController {

	// Section layout for the Application Summary modal. Order and headings mirror
	// ApplicationSummaryService.SNAPSHOT_ORDER so the modal, the snapshot written on conversion
	// and the AI prompt all describe the file the same way.
	private static final Map<String, String> BLOCK_LABELS = new Map<String, String>{
		'App_Summary_Household__c' => 'Household',
		'App_Summary_Borrower_1__c' => 'Borrower 1',
		'App_Summary_Borrower_2__c' => 'Borrower 2',
		'App_Summary_Income_B1__c' => 'Borrower 1',
		'App_Summary_Income_B2__c' => 'Borrower 2',
		'App_Summary_Property__c' => 'Property',
		'App_Summary_Assets__c' => 'Assets',
		'App_Summary_Credit__c' => 'Credit',
		'App_Summary_Goals__c' => 'Goals',
		'App_Summary_Other_Points__c' => 'Other Important Points'
	};

	// Only these fields may be written back from the modal.
	private static final Set<String> WRITABLE_FIELDS = BLOCK_LABELS.keySet();

	// Blocks that only make sense once a second borrower exists.
	private static final Set<String> CO_BORROWER_FIELDS = new Set<String>{
		'App_Summary_Borrower_2__c',
		'App_Summary_Income_B2__c'
	};

	public class SummaryBlock {
		@AuraEnabled public String label { get; set; }
		@AuraEnabled public String field { get; set; }
		@AuraEnabled public String value { get; set; }
		@AuraEnabled public Boolean coBorrower { get; set; }

		public SummaryBlock(String label, String field, String value) {
			this.label = label;
			this.field = field;
			this.value = value;
			this.coBorrower = CO_BORROWER_FIELDS.contains(field);
		}
	}

	public class SummarySection {
		@AuraEnabled public String label { get; set; }
		@AuraEnabled public String name { get; set; }
		@AuraEnabled public List<SummaryBlock> blocks { get; set; }
		// A single-block section renders one full-width box with no sub-heading.
		@AuraEnabled public Boolean single { get; set; }

		public SummarySection(String label, String name, List<SummaryBlock> blocks) {
			this.label = label;
			this.name = name;
			this.blocks = blocks;
			this.single = blocks.size() == 1;
		}
	}

	public class SummaryView {
		@AuraEnabled public List<SummarySection> sections { get; set; }
		@AuraEnabled public Boolean hasCoBorrower { get; set; }
		@AuraEnabled public Boolean readOnly { get; set; }
		@AuraEnabled public String legacyNotes { get; set; }
	}

	@AuraEnabled
	public static SummaryView getApplicationSummary(Id recordId) {
		try {
			RecordAccessGuard.requireRead(recordId);
			Lead leadRecord = [
				SELECT Id, Lead_Notes_JSON__c,
					App_Summary_Household__c, App_Summary_Borrower_1__c, App_Summary_Borrower_2__c,
					App_Summary_Income_B1__c, App_Summary_Income_B2__c, App_Summary_Property__c,
					App_Summary_Assets__c, App_Summary_Credit__c, App_Summary_Goals__c,
					App_Summary_Other_Points__c
				FROM Lead
				WHERE Id = :recordId
			];

			SummaryView view = new SummaryView();
			view.sections = new List<SummarySection>{
				new SummarySection('Borrower Information', 'borrowerInformation', new List<SummaryBlock>{
					block(leadRecord, 'App_Summary_Household__c'),
					block(leadRecord, 'App_Summary_Borrower_1__c'),
					block(leadRecord, 'App_Summary_Borrower_2__c')
				}),
				new SummarySection('Income', 'income', new List<SummaryBlock>{
					block(leadRecord, 'App_Summary_Income_B1__c'),
					block(leadRecord, 'App_Summary_Income_B2__c')
				}),
				new SummarySection('Property', 'property', new List<SummaryBlock>{
					block(leadRecord, 'App_Summary_Property__c')
				}),
				new SummarySection('Assets', 'assets', new List<SummaryBlock>{
					block(leadRecord, 'App_Summary_Assets__c')
				}),
				new SummarySection('Credit', 'credit', new List<SummaryBlock>{
					block(leadRecord, 'App_Summary_Credit__c')
				}),
				new SummarySection('Goals', 'goals', new List<SummaryBlock>{
					block(leadRecord, 'App_Summary_Goals__c')
				}),
				new SummarySection('Other Important Points', 'otherPoints', new List<SummaryBlock>{
					block(leadRecord, 'App_Summary_Other_Points__c')
				})
			};

			view.hasCoBorrower = String.isNotBlank(leadRecord.App_Summary_Borrower_2__c)
				|| String.isNotBlank(leadRecord.App_Summary_Income_B2__c);
			// Edit rights come from field level security, so the modal never has to know about profiles.
			view.readOnly = !Schema.SObjectType.Lead.fields.App_Summary_Household__c.isUpdateable();
			// Notes captured by the old manual form are preserved and shown read-only rather than
			// merged into the AI sections, where they would corrupt the prose.
			view.legacyNotes = leadRecord.Lead_Notes_JSON__c;
			return view;
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	private static SummaryBlock block(Lead leadRecord, String fieldName) {
		return new SummaryBlock(
			BLOCK_LABELS.get(fieldName),
			fieldName,
			(String) leadRecord.get(fieldName)
		);
	}

	/**
	 * Writes edited sections back to the Lead. New call content is appended by
	 * ApplicationSummaryService against its own per-call markers, so saving here never has to
	 * merge - it just persists whatever the user currently sees.
	 */
	@AuraEnabled
	public static void saveApplicationSummary(Id recordId, String blocksJson) {
		try {
			RecordAccessGuard.requireEdit(recordId);
			List<Object> rawBlocks = (List<Object>) JSON.deserializeUntyped(blocksJson);
			Lead leadRecord = new Lead(Id = recordId);
			Boolean anyWritten = false;

			for (Object rawBlock : rawBlocks) {
				Map<String, Object> blockMap = (Map<String, Object>) rawBlock;
				String fieldName = (String) blockMap.get('field');
				if (String.isBlank(fieldName) || !WRITABLE_FIELDS.contains(fieldName)) {
					continue;
				}
				String value = (String) blockMap.get('value');
				if (value != null && value.length() > 32768) {
					value = value.left(32768);
				}
				leadRecord.put(fieldName, String.isBlank(value) ? null : value);
				anyWritten = true;
			}

			if (anyWritten) {
				update leadRecord;
			}
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * Writes the Application Summary to an Enhanced Note so it lands in the notes timeline.
	 */
	@AuraEnabled
	public static void createSummaryNote(Id recordId, String blocksJson) {
		try {
			RecordAccessGuard.requireRead(recordId);
			List<Object> rawBlocks = (List<Object>) JSON.deserializeUntyped(blocksJson);
			String body = '';
			String currentSection = '';

			for (Object rawBlock : rawBlocks) {
				Map<String, Object> blockMap = (Map<String, Object>) rawBlock;
				String value = (String) blockMap.get('value');
				if (String.isBlank(value)) {
					continue;
				}
				String sectionLabel = (String) blockMap.get('sectionLabel');
				String blockLabel = (String) blockMap.get('label');
				if (sectionLabel != currentSection) {
					body += '<p><b>' + sectionLabel.escapeHtml4() + '</b></p>';
					currentSection = sectionLabel;
				}
				if (sectionLabel != blockLabel) {
					body += '<p><i>' + blockLabel.escapeHtml4() + '</i></p>';
				}
				body += '<p>' + value.escapeHtml4().replace('\n', '<br/>') + '</p>';
			}

			if (String.isBlank(body)) {
				return;
			}

			Enhanced_Note__c newNote = new Enhanced_Note__c();
			newNote.Lead__c = recordId;
			newNote.Subject__c = 'Application Summary';
			newNote.Body__c = body;
			insert newNote;
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	@AuraEnabled
	public static String getNotes(Id recordId){
		try {
			RecordAccessGuard.requireRead(recordId);
			return [SELECT Id, Lead_Notes_JSON__c FROM Lead WHERE Id = :recordId].Lead_Notes_JSON__c;
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	@AuraEnabled
	public static void saveNotes(Id recordId, String notes){
		try {
			RecordAccessGuard.requireEdit(recordId);
			Lead l = new Lead(Id = recordId, Lead_Notes_JSON__c = notes);
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
			newNote.Lead__c = recordId;
			newNote.Subject__c = 'Lead Details';
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