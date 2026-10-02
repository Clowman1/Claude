@isTest
public with sharing class LeadNotesFormControllerTest {
	@TestSetup
	static void makeData(){
		Lead testLead = new Lead(
			FirstName = 'Test',
			LastName = Datetime.now().toString()
		);

		insert testLead;
	}
    @isTest
	static void getNotesTest() {
		Lead testLead = [SELECT Id FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		String testLeadNotes = 'Test Lead Notes on: ' + Datetime.now().toString();
		testLead.Lead_Notes_JSON__c = testLeadNotes;

		update testLead;

		Test.startTest();
		String actualNotes = LeadNotesFormController.getNotes(testLead.Id);
		Test.stopTest();

		System.assertEquals(testLeadNotes, actualNotes, 'Wrong notes returned');
    }

	@isTest
	static void saveNotesTest() {
		Lead testLead = [SELECT Id FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		String testLeadNotes = 'Test Lead Notes on: ' + Datetime.now().toString();

		Test.startTest();
		LeadNotesFormController.saveNotes(testLead.Id, testLeadNotes);
		Test.stopTest();

		Lead actualLead = [SELECT Id, Lead_Notes_JSON__c FROM Lead WHERE Id = :testLead.Id];

		System.assertEquals(testLeadNotes, actualLead.Lead_Notes_JSON__c, 'Notes were not set');
	}

	@isTest
	static void createNoteTest() {
		Lead testLead = [SELECT Id, Name FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		Map<String, String> notesMap = new Map<String, String>{
			'Borrower Name' => testLead.Name
		};
		String notesJSON = JSON.serialize(notesMap);

		Test.startTest();
		LeadNotesFormController.createNote(testLead.Id, notesJSON, notesJSON);
		Test.stopTest();

		Enhanced_Note__c note = [SELECT Id, Body__c FROM Enhanced_Note__c WHERE Lead__c = :testLead.Id ORDER BY CreatedDate DESC LIMIT 1];

		System.assertNotEquals(null, note, 'Note should be created');
		System.assertEquals(true, note.Body__c.contains(testLead.name), 'Enhanced Note is not populated correctly');
	}

	@isTest
	static void summaryViewReturnsEverySectionInOrder() {
		Lead testLead = [SELECT Id FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		testLead.App_Summary_Household__c = 'Renting in Key West';
		testLead.App_Summary_Property__c = 'Purchase price 895,000';
		update testLead;

		Test.startTest();
		LeadNotesFormController.SummaryView view = LeadNotesFormController.getApplicationSummary(testLead.Id);
		Test.stopTest();

		System.assertEquals(7, view.sections.size(), 'The modal shows seven sections.');

		List<String> expectedOrder = new List<String>{
			'Borrower Information', 'Income', 'Property', 'Assets', 'Credit', 'Goals', 'Other Important Points'
		};
		for (Integer i = 0; i < expectedOrder.size(); i++) {
			System.assertEquals(expectedOrder[i], view.sections[i].label, 'Section order must match the agreed layout.');
		}

		System.assertEquals(3, view.sections[0].blocks.size(), 'Borrower Information holds household plus both borrowers.');
		System.assertEquals(false, view.sections[0].single, 'A multi block section shows its sub headings.');
		System.assertEquals(true, view.sections[2].single, 'Property is a single block section.');
		System.assertEquals('Renting in Key West', view.sections[0].blocks[0].value, 'Household content should load.');
		System.assertEquals(false, view.hasCoBorrower, 'No borrower 2 content means no co-borrower.');
	}

	@isTest
	static void coBorrowerIsDetectedFromBorrowerTwoContent() {
		Lead testLead = [SELECT Id FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		testLead.App_Summary_Income_B2__c = 'Assistant General Manager, 150,000';
		update testLead;

		Test.startTest();
		LeadNotesFormController.SummaryView view = LeadNotesFormController.getApplicationSummary(testLead.Id);
		Test.stopTest();

		System.assertEquals(true, view.hasCoBorrower, 'Borrower 2 income should switch the co-borrower blocks on.');
		System.assertEquals(true, view.sections[1].blocks[1].coBorrower, 'Second income block belongs to the co-borrower.');
	}

	@isTest
	static void saveWritesOnlyKnownSummaryFields() {
		Lead testLead = [SELECT Id FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		List<Map<String, Object>> blocks = new List<Map<String, Object>>{
			new Map<String, Object>{ 'field' => 'App_Summary_Goals__c', 'value' => 'Minimize interest paid' },
			new Map<String, Object>{ 'field' => 'App_Summary_Credit__c', 'value' => 'Mortgage scores near 666' },
			// Anything not on the allow list must be ignored rather than written.
			new Map<String, Object>{ 'field' => 'LastName', 'value' => 'Should Not Be Written' }
		};

		Test.startTest();
		LeadNotesFormController.saveApplicationSummary(testLead.Id, JSON.serialize(blocks));
		Test.stopTest();

		Lead saved = [
			SELECT App_Summary_Goals__c, App_Summary_Credit__c, LastName
			FROM Lead WHERE Id = :testLead.Id
		];
		System.assertEquals('Minimize interest paid', saved.App_Summary_Goals__c, 'Goals should save.');
		System.assertEquals('Mortgage scores near 666', saved.App_Summary_Credit__c, 'Credit should save.');
		System.assertNotEquals('Should Not Be Written', saved.LastName, 'Fields outside the allow list must be ignored.');
	}

	@isTest
	static void blankSectionClearsTheField() {
		Lead testLead = [SELECT Id FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		testLead.App_Summary_Assets__c = 'Twenty percent down';
		update testLead;

		List<Map<String, Object>> blocks = new List<Map<String, Object>>{
			new Map<String, Object>{ 'field' => 'App_Summary_Assets__c', 'value' => '' }
		};

		Test.startTest();
		LeadNotesFormController.saveApplicationSummary(testLead.Id, JSON.serialize(blocks));
		Test.stopTest();

		Lead saved = [SELECT App_Summary_Assets__c FROM Lead WHERE Id = :testLead.Id];
		System.assertEquals(null, saved.App_Summary_Assets__c, 'Clearing a section should clear the field.');
	}

	@isTest
	static void summaryNoteGroupsBlocksUnderSectionHeadings() {
		Lead testLead = [SELECT Id FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		List<Map<String, Object>> blocks = new List<Map<String, Object>>{
			new Map<String, Object>{ 'sectionLabel' => 'Borrower Information', 'label' => 'Household', 'value' => 'Renting in Key West' },
			new Map<String, Object>{ 'sectionLabel' => 'Goals', 'label' => 'Goals', 'value' => 'Recast after inheritance' },
			new Map<String, Object>{ 'sectionLabel' => 'Assets', 'label' => 'Assets', 'value' => '' }
		};

		Test.startTest();
		LeadNotesFormController.createSummaryNote(testLead.Id, JSON.serialize(blocks));
		Test.stopTest();

		Enhanced_Note__c note = [
			SELECT Subject__c, Body__c FROM Enhanced_Note__c
			WHERE Lead__c = :testLead.Id ORDER BY CreatedDate DESC LIMIT 1
		];
		System.assertEquals('Application Summary', note.Subject__c, 'Note should be titled for the summary.');
		System.assertEquals(true, note.Body__c.contains('Borrower Information'), 'Section heading should appear.');
		System.assertEquals(true, note.Body__c.contains('Household'), 'Sub heading should appear for multi block sections.');
		System.assertEquals(true, note.Body__c.contains('Recast after inheritance'), 'Content should appear.');
		System.assertEquals(false, note.Body__c.contains('Assets'), 'Empty sections should be left out entirely.');
	}

	@isTest
	static void summaryNoteIsSkippedWhenEverythingIsBlank() {
		Lead testLead = [SELECT Id FROM Lead ORDER BY CreatedDate DESC LIMIT 1];
		List<Map<String, Object>> blocks = new List<Map<String, Object>>{
			new Map<String, Object>{ 'sectionLabel' => 'Goals', 'label' => 'Goals', 'value' => '' }
		};

		Test.startTest();
		LeadNotesFormController.createSummaryNote(testLead.Id, JSON.serialize(blocks));
		Test.stopTest();

		Integer notes = [SELECT COUNT() FROM Enhanced_Note__c WHERE Lead__c = :testLead.Id];
		System.assertEquals(0, notes, 'An empty summary should not create a note.');
	}
}