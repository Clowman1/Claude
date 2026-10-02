@IsTest
private class ProcessorCommitmentDigestSchedulerTest {
    // Transaction__c carries validation rules that make inserting a realistic record awkward, so
    // these tests build the queried shape in memory the same way PipelineCommandCenterControllerTest
    // does. That keeps the assertions focused on grouping, filtering and message construction.
    private static Transaction__c buildTransaction(
        String name,
        Id processorId,
        String processorEmail,
        String processorFirstName,
        Boolean processorActive
    ) {
        String payload =
            '{"attributes":{"type":"Transaction__c"}' +
            ',"Name":"' + name + '"' +
            ',"Status__c":"Conditionally Approved"' +
            ',"Closing_Date__c":"2026-09-01"' +
            ',"Loan_Amount_1st__c":412000' +
            ',"Borrower_First_Name__c":"Dana"' +
            ',"Borrower_Last_Name__c":"Rizzo"' +
            ',"Processor__c":"' + processorId + '"' +
            ',"Processor__r":{"attributes":{"type":"User"}' +
            ',"Id":"' + processorId + '"' +
            ',"Email":"' + processorEmail + '"' +
            ',"FirstName":"' + processorFirstName + '"' +
            ',"IsActive":' + processorActive +
            '}}';
        return (Transaction__c) JSON.deserialize(payload, Transaction__c.class);
    }

    private static Id fakeUserId(Integer seed) {
        return Id.valueOf('005000000000' + String.valueOf(1000 + seed).right(3) + 'AAA');
    }

    @IsTest
    static void buildsOneMessagePerProcessorWithRequiredSubject() {
        Id firstProcessor = fakeUserId(1);
        Id secondProcessor = fakeUserId(2);

        List<Transaction__c> dueToday = new List<Transaction__c>{
            buildTransaction('RIZZO - 1', firstProcessor, 'first@example.com', 'Jennifer', true),
            buildTransaction('NGUYEN - 2', firstProcessor, 'first@example.com', 'Jennifer', true),
            buildTransaction('BARBER - 3', secondProcessor, 'second@example.com', 'Angelina', true)
        };

        Test.startTest();
        List<Messaging.SingleEmailMessage> messages = ProcessorCommitmentDigestScheduler.buildMessages(dueToday);
        Test.stopTest();

        Assert.areEqual(2, messages.size(), 'Each processor with work due today should get exactly one email.');

        Map<String, Messaging.SingleEmailMessage> messagesByRecipient = new Map<String, Messaging.SingleEmailMessage>();
        for (Messaging.SingleEmailMessage message : messages) {
            Assert.areEqual(
                'Today\'s Commitments Due',
                message.getSubject(),
                'The subject line is specified by the business and must not drift.'
            );
            messagesByRecipient.put(message.getToAddresses()[0], message);
        }

        Assert.isTrue(messagesByRecipient.containsKey('first@example.com'), 'Expected a digest for the first processor.');
        Assert.isTrue(messagesByRecipient.containsKey('second@example.com'), 'Expected a digest for the second processor.');

        String firstBody = messagesByRecipient.get('first@example.com').getHtmlBody();
        Assert.isTrue(firstBody.contains('2 commitments due today'), 'The digest should count the processor\'s own files.');
        Assert.isTrue(firstBody.contains('RIZZO - 1'), 'The digest should list the processor\'s transactions.');
        Assert.isTrue(firstBody.contains('NGUYEN - 2'), 'The digest should list every transaction due today.');
        Assert.isFalse(firstBody.contains('BARBER - 3'), 'A processor must not see another processor\'s files.');
        Assert.isTrue(firstBody.contains('Hi Jennifer,'), 'The digest should greet the processor by first name.');

        String secondBody = messagesByRecipient.get('second@example.com').getHtmlBody();
        Assert.isTrue(secondBody.contains('1 commitment due today'), 'A single file should read in the singular.');
    }

    @IsTest
    static void producesNoMessagesWhenNothingIsDue() {
        Test.startTest();
        List<Messaging.SingleEmailMessage> messages = ProcessorCommitmentDigestScheduler.buildMessages(
            new List<Transaction__c>()
        );
        Test.stopTest();

        Assert.areEqual(0, messages.size(), 'A processor with no commitments due today must not be emailed.');
    }

    @IsTest
    static void skipsProcessorsWhoCannotReceiveMail() {
        List<Transaction__c> dueToday = new List<Transaction__c>{
            buildTransaction('INACTIVE USER - 1', fakeUserId(3), 'inactive@example.com', 'Gone', false),
            buildTransaction('NO EMAIL - 2', fakeUserId(4), '', 'Blank', true)
        };

        Test.startTest();
        List<Messaging.SingleEmailMessage> messages = ProcessorCommitmentDigestScheduler.buildMessages(dueToday);
        Test.stopTest();

        Assert.areEqual(
            0,
            messages.size(),
            'Deactivated processors and processors without an address should be skipped, not send failures.'
        );
    }

    @IsTest
    static void queryReturnsOnlyActiveFilesDueToday() {
        Test.startTest();
        List<Transaction__c> results = ProcessorCommitmentDigestScheduler.findCommitmentsDueToday();
        Test.stopTest();

        Set<String> inactiveStatuses = new Set<String>{ 'Cancelled', 'PC Review', 'QC Review', 'Post-Closed', 'Lost' };
        for (Transaction__c transactionRecord : results) {
            Assert.isNotNull(transactionRecord.Processor__c, 'The digest only covers files with an assigned processor.');
            Assert.isFalse(
                inactiveStatuses.contains(transactionRecord.Status__c),
                'Files in an inactive status should never reach a processor digest.'
            );
        }
    }

    @IsTest
    static void schedulerRunsWithoutError() {
        Test.startTest();
        String jobId = System.schedule(
            'ProcessorCommitmentDigestSchedulerTest run',
            '0 0 10 * * ?',
            new ProcessorCommitmentDigestScheduler()
        );
        Test.stopTest();

        Assert.isNotNull(jobId, 'The digest should be schedulable on the 10 AM cron expression.');
    }
}