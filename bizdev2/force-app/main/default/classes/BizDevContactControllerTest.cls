@IsTest
private class BizDevContactControllerTest {
    @IsTest
    static void createsContactFromPartialDetails() {
        Id contactId = BizDevContactController.createContact(
            'Dana', 'Reyes', '4075551234', null, 'Broker Owner', null
        );

        Account created = [
            SELECT FirstName, LastName, PersonMobilePhone, Business_Type__c, RecordType.DeveloperName
            FROM Account
            WHERE Id = :contactId
        ];
        System.assertEquals('Dana', created.FirstName);
        System.assertEquals('Reyes', created.LastName);
        System.assertEquals('Broker Owner', created.Business_Type__c);
        System.assertEquals('BizDev_Expansion', created.RecordType.DeveloperName);
    }

    @IsTest
    static void fallsBackToAnIdentifierWhenNoLastNameGiven() {
        Id contactId = BizDevContactController.createContact(
            null, null, '4075559876', null, null, null
        );

        Account created = [SELECT LastName FROM Account WHERE Id = :contactId];
        System.assertEquals(
            '4075559876',
            created.LastName,
            'A contact saved with only a phone number must still be identifiable'
        );
    }

    @IsTest
    static void savesTheNoteTypedOnTheCreateForm() {
        Id contactId = BizDevContactController.createContact(
            'Sam', 'Ortiz', null, null, 'Loan Officer', 'Met at the UWM summit - wants to talk in Q4.'
        );

        List<Enhanced_Note__c> notes = [
            SELECT Body__c, Type__c FROM Enhanced_Note__c WHERE Account__c = :contactId
        ];
        System.assertEquals(1, notes.size(), 'The note typed on the create form should be saved');
        System.assertEquals('Met at the UWM summit - wants to talk in Q4.', notes[0].Body__c);
        System.assertEquals('Note', notes[0].Type__c);
    }

    @IsTest
    static void savesAContactThatIsNothingButANote() {
        Id contactId = BizDevContactController.createContact(
            null, null, null, null, null, 'Referred by Wemert - get the name from Adam.'
        );
        System.assertNotEquals(null, contactId, 'A note alone is enough to capture a contact');
    }

    @IsTest
    static void rejectsAnEntirelyEmptyContact() {
        try {
            BizDevContactController.createContact(null, '   ', null, null, null, null);
            System.assert(false, 'An empty contact should not be saved');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
    }

    @IsTest
    static void returnsContactsWithNotes() {
        Id contactId = BizDevContactController.createContact(
            'Pat', 'Nguyen', null, 'pat@example.com', 'Realtor', null
        );
        BizDevContactController.saveNote(contactId, 'Met at the Winter Park open house.');

        List<BizDevContactController.BizDevContact> contacts = BizDevContactController.getContacts();

        Boolean found = false;
        for (BizDevContactController.BizDevContact contactRow : contacts) {
            if (contactRow.id == contactId) {
                found = true;
                System.assertEquals('Realtor', contactRow.businessType);
                System.assertEquals('pat@example.com', contactRow.email);
                System.assertEquals(1, contactRow.noteCount);
                System.assertEquals('Met at the Winter Park open house.', contactRow.notes[0].body);
                System.assertEquals(
                    [SELECT Name FROM User WHERE Id = :UserInfo.getUserId()].Name,
                    contactRow.createdByName,
                    'The list should name whoever added the contact'
                );
            }
        }
        System.assert(found, 'The saved contact should appear in the list');
    }

    @IsTest
    static void rejectsABlankNote() {
        Id contactId = BizDevContactController.createContact(
            'Blank', 'Note', null, null, null, null
        );
        try {
            BizDevContactController.saveNote(contactId, '   ');
            System.assert(false, 'A blank note should not be saved');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
    }
}