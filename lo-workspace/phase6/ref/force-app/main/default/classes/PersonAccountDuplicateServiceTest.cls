@IsTest
private class PersonAccountDuplicateServiceTest {

    private static final Id PERSON_RT = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId();

    private static Account makePerson(String first, String last, String email, String phone) {
        return new Account(
            RecordTypeId = PERSON_RT,
            FirstName = first,
            LastName = last,
            PersonEmail = email,
            PersonMobilePhone = phone
        );
    }

    @TestSetup
    static void setup() {
        insert new List<Account>{
            makePerson('Dana', 'Whitfield', 'dana.whitfield@example.org', '(407) 244-6554'),
            makePerson('Marcus', 'Adeyemi', 'marcus.adeyemi@example.org', '813-451-2048'),
            makePerson('Priya', 'Raghunathan', null, '(321) 230-3041')
        };
    }

    @IsTest
    static void matchesOnEmailExactly() {
        Test.startTest();
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches('DANA.WHITFIELD@EXAMPLE.ORG', null, null);
        Test.stopTest();

        Assert.areEqual(1, matches.size(), 'Email should match one Person Account regardless of case');
        Assert.areEqual('Email', matches[0].matchedOn, 'Match reason should be email only');
        Assert.areEqual(0, matches[0].loanFiles, 'No transactions were created for this account');
    }

    @IsTest
    static void matchesPhoneAcrossDifferentStoredFormats() {
        // Stored as "813-451-2048", typed as "(813) 451-2048" — must still match.
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches(null, '(813) 451-2048', null);

        Assert.areEqual(1, matches.size(), 'Phone should match despite a different stored format');
        Assert.areEqual('Phone', matches[0].matchedOn, 'Match reason should be phone only');
    }

    @IsTest
    static void matchesPhoneWithCountryCode() {
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches(null, '+1 407 244 6554', null);
        Assert.areEqual(1, matches.size(), 'A leading country code should be stripped before comparing');
    }

    @IsTest
    static void reportsBothWhenEmailAndPhoneMatchSameRecord() {
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches('dana.whitfield@example.org', '4072446554', null);
        Assert.areEqual(1, matches.size(), 'Same record matched twice is still one match');
        Assert.areEqual('Email and phone', matches[0].matchedOn, 'Both signals should be reported');
    }

    @IsTest
    static void ignoresDifferentAreaCodeSharingLastFourDigits() {
        // 6554 is the same tail as Dana's number but the area code differs, so it must not match.
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches(null, '(555) 999-6554', null);
        Assert.areEqual(0, matches.size(), 'A different area code sharing the last four digits is not a duplicate');
    }

    @IsTest
    static void skipsTheRecordBeingEdited() {
        Account existing = [SELECT Id FROM Account WHERE PersonEmail = 'dana.whitfield@example.org' LIMIT 1];
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches('dana.whitfield@example.org', null, existing.Id);
        Assert.areEqual(0, matches.size(), 'The record being edited must not flag itself');
    }

    @IsTest
    static void returnsNothingForBlankOrPlaceholderInput() {
        Assert.areEqual(0, PersonAccountDuplicateService.findMatches(null, null, null).size(),
            'No input means no matches');
        Assert.areEqual(0, PersonAccountDuplicateService.findMatches('   ', '  ', null).size(),
            'Whitespace is not input');
        Assert.areEqual(0, PersonAccountDuplicateService.findMatches('tbd@email.com', null, null).size(),
            'Placeholder emails must never group unrelated people');
        Assert.areEqual(0, PersonAccountDuplicateService.findMatches(null, '000-000-0000', null).size(),
            'Placeholder phone numbers must never match');
        Assert.areEqual(0, PersonAccountDuplicateService.findMatches(null, '12345', null).size(),
            'A phone that is not 10 digits cannot be compared');
    }

    @IsTest
    static void flowFindReturnsExistingAccountForBorrowerPath() {
        PersonAccountDuplicateService.FindRequest request = new PersonAccountDuplicateService.FindRequest();
        request.email = 'marcus.adeyemi@example.org';
        request.phone = null;

        Test.startTest();
        List<PersonAccountDuplicateService.FindResult> results =
            PersonAccountDuplicateService.findMatchingPersonAccount(
                new List<PersonAccountDuplicateService.FindRequest>{ request });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One request returns one result');
        Assert.isTrue(results[0].found, 'The borrower already has a Person Account');
        Assert.isNotNull(results[0].accountId, 'The existing account Id should be returned for attaching');
        Assert.areEqual(1, results[0].matchCount, 'One matching account');
    }

    @IsTest
    static void flowFindReportsNotFoundSoTheFlowCreatesANewAccount() {
        PersonAccountDuplicateService.FindRequest request = new PersonAccountDuplicateService.FindRequest();
        request.email = 'brand.new.borrower@example.org';
        request.phone = '(206) 555-0147';

        List<PersonAccountDuplicateService.FindResult> results =
            PersonAccountDuplicateService.findMatchingPersonAccount(
                new List<PersonAccountDuplicateService.FindRequest>{ request });

        Assert.isFalse(results[0].found, 'A genuinely new borrower must not be matched');
        Assert.isNull(results[0].accountId, 'Nothing to attach to');
    }

    @IsTest
    static void matchesPersonWithNoEmailByPhoneAlone() {
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches('someone.else@example.org', '(321) 230-3041', null);
        Assert.areEqual(1, matches.size(), 'A record with no email is still reachable by phone');
        Assert.areEqual('Phone', matches[0].matchedOn, 'Only the phone matched');
    }

    @IsTest
    static void blockIfDuplicateThrowsOnEmailMatch() {
        Boolean blocked = false;
        String message;
        try {
            PersonAccountDuplicateService.blockIfDuplicate('dana.whitfield@example.org', null);
        } catch (PersonAccountDuplicateService.DuplicateFoundException e) {
            blocked = true;
            message = e.getMessage();
        }
        Assert.isTrue(blocked, 'An existing email must hard stop the create');
        Assert.isNotNull(message, 'The throw should carry a message');
    }

    @IsTest
    static void blockIfDuplicateThrowsOnPhoneMatchAndExplainsTheOfficeLineCase() {
        Boolean blocked = false;
        String message;
        try {
            PersonAccountDuplicateService.blockIfDuplicate(null, '(321) 230-3041');
        } catch (PersonAccountDuplicateService.DuplicateFoundException e) {
            blocked = true;
            message = e.getMessage();
        }
        Assert.isTrue(blocked, 'An existing phone must hard stop the create');
        Assert.isNotNull(message, 'The throw should carry a message');
    }

    @IsTest
    static void blockIfDuplicateAllowsAGenuinelyNewPerson() {
        PersonAccountDuplicateService.blockIfDuplicate('nobody.here@example.org', '(206) 555-0188');
        Assert.isTrue(true, 'A new person must not be blocked');
    }

    @IsTest
    static void blockIfDuplicateIgnoresBlankInput() {
        PersonAccountDuplicateService.blockIfDuplicate(null, null);
        Assert.isTrue(true, 'No input cannot be a duplicate');
    }

    @IsTest
    static void duplicateMessageNamesTheMatchAndTellsUserToSelectIt() {
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches('dana.whitfield@example.org', null, null);
        String message = PersonAccountDuplicateService.buildDuplicateMessage(matches);
        Assert.isTrue(message.contains('already exists'), message);
        Assert.isTrue(message.contains('Dana Whitfield'), 'The existing person should be named: ' + message);
        Assert.isTrue(message.contains('Select the existing account'), message);
    }

    @IsTest
    static void phoneOnlyMessageExplainsTheSharedOfficeLineCase() {
        List<PersonAccountDuplicateService.Match> matches =
            PersonAccountDuplicateService.findMatches(null, '(321) 230-3041', null);
        String message = PersonAccountDuplicateService.buildDuplicateMessage(matches);
        Assert.isTrue(message.contains('direct mobile'),
            'A phone-only match must tell the user to use the agent direct number: ' + message);
    }
}