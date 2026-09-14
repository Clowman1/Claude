/**
 * Covers per-borrower condition assignment: the roster the picker reads, the three assignment
 * states, and the assignment surviving conversion.
 */
@IsTest
private class LeadConditionAssignmentTest {
    // Saving a request mints the lead's portal hash, which is AES encrypted, so the key and the
    // portal URL settings have to exist before any of these tests can save anything.
    @TestSetup
    static void setupSettings() {
        insert new AesKey__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            AesKey__c = '12345678901234567890123456789012'
        );
        BorrowerPortalSettings__c settings = new BorrowerPortalSettings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Borrower_Home_Url__c = 'https://example.force.com/documents/s/'
        );
        if (BorrowerPortalSettings__c.SObjectType.getDescribe().fields.getMap().containsKey('Lead_Borrower_Home_Url__c')) {
            settings.put('Lead_Borrower_Home_Url__c', 'https://example.force.com/documents/s/lead');
        }
        insert settings;
    }

    private static Lead newLead(String email) {
        Lead theLead = new Lead(
            FirstName = 'Lynn',
            LastName = 'Hall',
            Company = 'Assignment Test',
            Email = email
        );
        insert theLead;
        return theLead;
    }

    private static Borrower__c newBorrower(Id leadId, String first, String last, String email) {
        Borrower__c row = new Borrower__c(
            Lead__c = leadId,
            Name = first + ' ' + last,
            First_Name__c = first,
            Last_Name__c = last,
            Email__c = email
        );
        insert row;
        return row;
    }

    private static LeadDocumentRequestService.RequestInput inputFor(String assignment) {
        LeadDocumentRequestService.RequestInput input = new LeadDocumentRequestService.RequestInput();
        input.name = 'W-2';
        input.subject = 'W-2';
        input.description = 'Most recent W-2';
        input.category = 'Income';
        input.canBorrowerSee = true;
        input.includeInEmail = true;
        input.assignment = assignment;
        return input;
    }

    @IsTest
    static void rosterListsPrimaryFirstAndFlagsBorrowersWithoutEmail() {
        Lead theLead = newLead('lynn@example.invalid');
        newBorrower(theLead.Id, 'Wilbur', 'Hall', 'wilbur@example.invalid');
        newBorrower(theLead.Id, 'Marcus', 'Reyes', null);
        insert new Borrower__c(
            Lead__c = theLead.Id,
            Name = 'Gone Away',
            First_Name__c = 'Gone',
            Last_Name__c = 'Away',
            Email__c = 'gone@example.invalid',
            Removed__c = true
        );

        Test.startTest();
        List<LeadDocumentRequestService.BorrowerOption> options =
            LeadDocumentRequestService.getBorrowerOptions(theLead.Id);
        Test.stopTest();

        Assert.areEqual(4, options.size(), 'All borrowers, the primary, and two active co-borrowers');
        Assert.areEqual('ALL', options[0].value, 'The whole-file option comes first');
        Assert.isTrue(options[0].assignable);
        Assert.areEqual('PRIMARY', options[1].value, 'The primary is second and is not a Borrower__c row');
        Assert.areEqual('Lynn Hall', options[1].label);
        Assert.isTrue(options[1].isPrimary);
        Assert.areEqual('Wilbur Hall', options[2].label);
        Assert.isTrue(options[2].assignable, 'Wilbur has an email so he can be assigned conditions');
        Assert.areEqual('Marcus Reyes', options[3].label);
        Assert.isFalse(options[3].assignable, 'No email means no portal and no assignment');
        for (LeadDocumentRequestService.BorrowerOption option : options) {
            Assert.areNotEqual('Gone Away', option.label, 'Removed borrowers are never offered');
        }
    }

    @IsTest
    static void rosterIsEmptyForANullLead() {
        Test.startTest();
        Assert.isTrue(LeadDocumentRequestService.getBorrowerOptions(null).isEmpty());
        Test.stopTest();
    }

    @IsTest
    static void theThreeAssignmentStatesWriteDistinctRecords() {
        Lead theLead = newLead('lynn@example.invalid');
        Borrower__c wilbur = newBorrower(theLead.Id, 'Wilbur', 'Hall', 'wilbur@example.invalid');

        Test.startTest();
        LeadDocumentRequestService.saveRequests(theLead.Id, new List<LeadDocumentRequestService.RequestInput>{
            inputFor('ALL'),
            inputFor('PRIMARY'),
            inputFor(String.valueOf(wilbur.Id))
        });
        Test.stopTest();

        Map<String, Lead_Document_Request__c> byState = new Map<String, Lead_Document_Request__c>();
        for (Lead_Document_Request__c row : [
            SELECT Id, Borrower__c, Assigned_To_Primary__c FROM Lead_Document_Request__c WHERE Lead__c = :theLead.Id
        ]) {
            String key = row.Borrower__c != null ? 'BORROWER' : (row.Assigned_To_Primary__c ? 'PRIMARY' : 'ALL');
            byState.put(key, row);
        }

        Assert.areEqual(3, byState.size(), 'ALL, PRIMARY and a specific borrower must be distinguishable');
        Assert.isNull(byState.get('ALL').Borrower__c);
        Assert.isFalse(byState.get('ALL').Assigned_To_Primary__c, 'Shared means neither field is set');
        Assert.isNull(byState.get('PRIMARY').Borrower__c, 'The primary is not a Borrower__c row');
        Assert.isTrue(byState.get('PRIMARY').Assigned_To_Primary__c);
        Assert.areEqual(wilbur.Id, byState.get('BORROWER').Borrower__c);
        Assert.isFalse(byState.get('BORROWER').Assigned_To_Primary__c);
    }

    @IsTest
    static void blankAssignmentOnAnUpdateLeavesTheExistingOwnerAlone() {
        Lead theLead = newLead('lynn@example.invalid');
        Borrower__c wilbur = newBorrower(theLead.Id, 'Wilbur', 'Hall', 'wilbur@example.invalid');
        LeadDocumentRequestService.saveRequests(
            theLead.Id,
            new List<LeadDocumentRequestService.RequestInput>{ inputFor(String.valueOf(wilbur.Id)) }
        );
        Lead_Document_Request__c saved = [SELECT Id FROM Lead_Document_Request__c LIMIT 1];

        LeadDocumentRequestService.RequestInput edit = inputFor(null);
        edit.id = saved.Id;
        edit.description = 'Most recent W-2, both years';

        Test.startTest();
        LeadDocumentRequestService.saveRequests(theLead.Id, new List<LeadDocumentRequestService.RequestInput>{ edit });
        Test.stopTest();

        Lead_Document_Request__c reloaded = [
            SELECT Borrower__c, Description__c FROM Lead_Document_Request__c WHERE Id = :saved.Id
        ];
        Assert.areEqual(wilbur.Id, reloaded.Borrower__c, 'Editing text must not silently reset the condition to shared');
        Assert.areEqual('Most recent W-2, both years', reloaded.Description__c);
    }

    @IsTest
    static void portalLinksAreMintedForBorrowersWithAnEmailAndRevokedWithout() {
        Lead theLead = newLead('lynn@example.invalid');
        Borrower__c wilbur = newBorrower(theLead.Id, 'Wilbur', 'Hall', 'wilbur@example.invalid');
        Borrower__c marcus = newBorrower(theLead.Id, 'Marcus', 'Reyes', null);

        Test.startTest();
        List<LeadDocumentRequestService.BorrowerPortalLink> links =
            LeadDocumentRequestService.getBorrowerPortalLinks(theLead.Id);
        Test.stopTest();

        Map<String, LeadDocumentRequestService.BorrowerPortalLink> byLabel =
            new Map<String, LeadDocumentRequestService.BorrowerPortalLink>();
        for (LeadDocumentRequestService.BorrowerPortalLink link : links) {
            byLabel.put(link.label, link);
        }
        Assert.isTrue(byLabel.containsKey('Lynn Hall'), 'The primary gets a link from the Lead token');
        Assert.isTrue(byLabel.containsKey('Wilbur Hall'), 'A borrower with an email gets their own link');
        Assert.isFalse(byLabel.containsKey('Marcus Reyes'), 'No email means no portal and no link');

        Borrower__c wilburAfter = [SELECT Portal_Hash_Parameter__c FROM Borrower__c WHERE Id = :wilbur.Id];
        Assert.isNotNull(wilburAfter.Portal_Hash_Parameter__c, 'A token is minted on first use');
        Assert.isNull(
            [SELECT Portal_Hash_Parameter__c FROM Borrower__c WHERE Id = :marcus.Id].Portal_Hash_Parameter__c,
            'A borrower without an email never gets a token'
        );

        // Removing the email revokes the portal, which is what kills the existing link.
        wilbur.Email__c = null;
        update wilbur;
        LeadDocumentRequestService.getBorrowerPortalLinks(theLead.Id);
        Assert.isNull(
            [SELECT Portal_Hash_Parameter__c FROM Borrower__c WHERE Id = :wilbur.Id].Portal_Hash_Parameter__c,
            'Removing the email clears the token so the link stops resolving'
        );
    }

    @IsTest
    static void perBorrowerEmailsSplitConditionsByOwner() {
        Lead theLead = newLead('lynn@example.invalid');
        Borrower__c wilbur = newBorrower(theLead.Id, 'Wilbur', 'Hall', 'wilbur@example.invalid');
        newBorrower(theLead.Id, 'Marcus', 'Reyes', null);

        LeadDocumentRequestService.saveRequests(theLead.Id, new List<LeadDocumentRequestService.RequestInput>{
            inputFor('PRIMARY'),
            inputFor(String.valueOf(wilbur.Id)),
            inputFor('ALL')
        });

        Test.startTest();
        List<String> outcomes = LeadDocumentRequestService.sendPerBorrowerRequestEmails(
            theLead.Id,
            'Items Needed - Hall Mortgage Pre-Approval',
            null
        );
        Test.stopTest();

        Assert.areEqual(2, outcomes.size(), 'Only borrowers with an email are sent to');
        String joined = String.join(outcomes, ' | ');
        // The primary owns her own item plus the shared one; Wilbur owns his plus the shared one.
        Assert.isTrue(joined.contains('Lynn Hall: sent to lynn@example.invalid (2 items)'), joined);
        Assert.isTrue(joined.contains('Wilbur Hall: sent to wilbur@example.invalid (2 items)'), joined);
        Assert.isFalse(joined.contains('Marcus'), 'A borrower with no email is never a recipient');

        Assert.isNotNull(
            [SELECT Account__c FROM Borrower__c WHERE Id = :wilbur.Id].Account__c,
            'Sending mints the Person Account, because Messaging needs a real target object'
        );
    }

    @IsTest
    static void perBorrowerSendNeedsSomebodyToSendTo() {
        Lead theLead = newLead(null);
        newBorrower(theLead.Id, 'Marcus', 'Reyes', null);
        LeadDocumentRequestService.saveRequests(
            theLead.Id,
            new List<LeadDocumentRequestService.RequestInput>{ inputFor('ALL') }
        );

        Test.startTest();
        try {
            LeadDocumentRequestService.sendPerBorrowerRequestEmails(theLead.Id, 'Items Needed', null);
            Assert.fail('Expected a clear error when nobody on the file has an email');
        } catch (Exception expected) {
            Assert.isTrue(
                expected.getMessage().contains('nobody to send to'),
                'Should explain why nothing was sent: ' + expected.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void assignmentSurvivesConversion() {
        Lead theLead = newLead('lynn@example.invalid');
        Borrower__c wilbur = newBorrower(theLead.Id, 'Wilbur', 'Hall', 'wilbur@example.invalid');
        Transaction__c txn = new Transaction__c(Name = 'Hall - assignment');
        insert txn;

        LeadDocumentRequestService.saveRequests(theLead.Id, new List<LeadDocumentRequestService.RequestInput>{
            inputFor(String.valueOf(wilbur.Id)),
            inputFor('PRIMARY'),
            inputFor('ALL')
        });
        theLead.Converted_Transaction_ID__c = txn.Id;
        update theLead;

        Test.startTest();
        LeadDocumentCarryForwardService.carryForward(new Set<Id>{ theLead.Id });
        Test.stopTest();

        List<Condition__c> conditions = [
            SELECT Borrower__c, Assigned_To_Primary__c FROM Condition__c WHERE Transaction__c = :txn.Id
        ];
        Assert.areEqual(3, conditions.size(), 'Every condition carries forward');
        Integer assignedToWilbur = 0;
        Integer assignedToPrimary = 0;
        Integer shared = 0;
        for (Condition__c condition : conditions) {
            if (condition.Borrower__c == wilbur.Id) {
                assignedToWilbur++;
            } else if (condition.Assigned_To_Primary__c) {
                assignedToPrimary++;
            } else {
                shared++;
            }
        }
        Assert.areEqual(1, assignedToWilbur, 'The borrower assignment must not be lost at conversion');
        Assert.areEqual(1, assignedToPrimary);
        Assert.areEqual(1, shared);
    }
}
