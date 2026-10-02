@isTest
public with sharing class TransactionNotesFormControllerTest {
	@TestSetup
	static void makeData(){
		Transaction__c testLead = new Transaction__c();

		insert testLead;
	}
    @isTest
	static void getNotesTest() {
		Transaction__c testLead = [SELECT Id FROM Transaction__c ORDER BY CreatedDate DESC LIMIT 1];
		String testLeadNotes = 'Test Lead Notes on: ' + Datetime.now().toString();
		testLead.Lead_Notes_JSON__c = testLeadNotes;

		update testLead;

		Test.startTest();
		String actualNotes = TransactionNotesFormController.getNotes(testLead.Id);
		Test.stopTest();

		System.assertEquals(testLeadNotes, actualNotes, 'Wrong notes returned');
    }

	@isTest
	static void saveNotesTest() {
		Transaction__c testLead = [SELECT Id FROM Transaction__c ORDER BY CreatedDate DESC LIMIT 1];
		String testLeadNotes = 'Test Lead Notes on: ' + Datetime.now().toString();

		Test.startTest();
		TransactionNotesFormController.saveNotes(testLead.Id, testLeadNotes);
		Test.stopTest();

		Transaction__c actualLead = [SELECT Id, Lead_Notes_JSON__c FROM Transaction__c WHERE Id = :testLead.Id];

		System.assertEquals(testLeadNotes, actualLead.Lead_Notes_JSON__c, 'Notes were not set');
	}

	@isTest
	static void createNoteTest() {
		Transaction__c testLead = [SELECT Id, Name FROM Transaction__c ORDER BY CreatedDate DESC LIMIT 1];
		Map<String, String> notesMap = new Map<String, String>{
			'Borrower Name' => testLead.Name
		};
		String notesJSON = JSON.serialize(notesMap);

		Test.startTest();
		TransactionNotesFormController.createNote(testLead.Id, notesJSON, notesJSON);
		Test.stopTest();

		Enhanced_Note__c note = [SELECT Id, Body__c FROM Enhanced_Note__c WHERE Transaction__c = :testLead.Id ORDER BY CreatedDate DESC LIMIT 1];

		System.assertNotEquals(null, note, 'Note should be created');
		System.assertEquals(true, note.Body__c.contains(testLead.name), 'Enhanced Note is not populated correctly');
	}

	// Mirrors the shape ApplicationSummaryService.buildSnapshot writes on conversion, including a
	// section whose body runs across a blank line.
	private static String sampleSnapshot() {
		return String.join(new List<String>{
			'Application Summary snapshot taken at conversion on Aug 18 2026 1:00 PM',
			'',
			'BORROWER INFORMATION - HOUSEHOLD',
			'Renting in Key West, Florida',
			'',
			'BORROWER 2',
			'Jason Powers',
			'',
			'INCOME / EMPLOYMENT - BORROWER 1',
			'Server at Red Shoe Island Bistro',
			'',
			'PROPERTY',
			'Purchase price 895,000',
			'',
			'Second line of the property notes',
			'',
			'GOALS',
			'Minimize total interest paid'
		}, '\n');
	}

	@isTest
	static void snapshotRendersOnlySectionsThatHaveContent() {
		Transaction__c testTransaction = [SELECT Id FROM Transaction__c ORDER BY CreatedDate DESC LIMIT 1];
		testTransaction.App_Summary_Snapshot__c = sampleSnapshot();
		update testTransaction;

		Test.startTest();
		TransactionNotesFormController.SummaryView view =
			TransactionNotesFormController.getApplicationSummary(testTransaction.Id);
		Test.stopTest();

		System.assertEquals(true, view.hasSnapshot, 'A populated snapshot should be reported as present.');
		System.assertEquals(4, view.sections.size(), 'Only Borrower Information, Income, Property and Goals have content.');
		System.assertEquals('Borrower Information', view.sections[0].label, 'Sections keep the agreed order.');
		System.assertEquals('Income', view.sections[1].label, 'Sections keep the agreed order.');
		System.assertEquals('Property', view.sections[2].label, 'Sections keep the agreed order.');
		System.assertEquals('Goals', view.sections[3].label, 'Sections keep the agreed order.');
		// Household and Borrower 2 have content; Borrower 1 does not and is dropped entirely.
		System.assertEquals(2, view.sections[0].blocks.size(), 'A heading with no content should be skipped, not blanked.');
		System.assertEquals('Household', view.sections[0].blocks[0].label, 'Household leads the borrower section.');
		System.assertEquals('Borrower 2', view.sections[0].blocks[1].label, 'Borrower 2 follows once Borrower 1 is skipped.');
		System.assertEquals(true, view.sections[2].single, 'A one block section renders without a sub heading.');
		System.assertEquals(true, view.capturedAt.contains('Aug 18 2026'), 'The captured-at line should be surfaced.');
	}

	@isTest
	static void snapshotKeepsBlankLinesInsideASection() {
		Transaction__c testTransaction = [SELECT Id FROM Transaction__c ORDER BY CreatedDate DESC LIMIT 1];
		testTransaction.App_Summary_Snapshot__c = sampleSnapshot();
		update testTransaction;

		Test.startTest();
		TransactionNotesFormController.SummaryView view =
			TransactionNotesFormController.getApplicationSummary(testTransaction.Id);
		Test.stopTest();

		String property = view.sections[2].blocks[0].value;
		System.assertEquals(true, property.contains('Purchase price 895,000'), 'First line should survive.');
		System.assertEquals(true, property.contains('Second line of the property notes'), 'Content after a blank line belongs to the same section.');
	}

	@isTest
	static void emptySnapshotReportsNothingCaptured() {
		Transaction__c testTransaction = [SELECT Id FROM Transaction__c ORDER BY CreatedDate DESC LIMIT 1];

		Test.startTest();
		TransactionNotesFormController.SummaryView view =
			TransactionNotesFormController.getApplicationSummary(testTransaction.Id);
		Test.stopTest();

		System.assertEquals(false, view.hasSnapshot, 'A file with no snapshot should say so.');
		System.assertEquals(0, view.sections.size(), 'No snapshot means no sections to render.');
	}
}