public with sharing class RingSenseRelateCallInsightInvocable {
    public class Input {
        @InvocableVariable(required=true)
        public Id callInsightId;

        @InvocableVariable(required=true)
        public String recipientPhoneNumber;
    }

    public class Output {
        @InvocableVariable
        public Id leadId;

        @InvocableVariable
        public Id accountId;

        @InvocableVariable
        public Id transactionId;
    }

    @InvocableMethod(label='Resolve RingSense Call Insight Relationships')
    public static List<Output> resolveRelationships(List<Input> inputs) {
        List<Output> outputs = new List<Output>();
        if (inputs == null || inputs.isEmpty()) {
            return outputs;
        }

        Set<String> phoneNumbers = new Set<String>();
        for (Input inputRow : inputs) {
            if (inputRow != null && !String.isBlank(inputRow.recipientPhoneNumber)) {
                phoneNumbers.add(inputRow.recipientPhoneNumber);
            }
        }

        Map<String, Id> leadIdsByPhone = RingCentralLeadPriorityMatcher.getOpenLeadIdsByPhoneNumbers(phoneNumbers);
        Map<String, Id> contactIdsByPhone = RingCentralLeadPriorityMatcher.getContactIdsByPhoneNumbers(phoneNumbers);
        Map<Id, Id> accountIdsByContactId = RingCentralLeadPriorityMatcher.getAccountIdsByContactIds(new Set<Id>(contactIdsByPhone.values()));
        Map<Id, Id> transactionByAccountId = RingCentralLeadPriorityMatcher.getMostRecentActiveTransactionByAccountIds(new Set<Id>(accountIdsByContactId.values()));

        for (Input inputRow : inputs) {
            Output outputRow = new Output();
            if (inputRow != null && !String.isBlank(inputRow.recipientPhoneNumber)) {
                String normalized = RingCentralLeadPriorityMatcher.normalizePhoneNumber(inputRow.recipientPhoneNumber);

                Id contactId = contactIdsByPhone.get(normalized);
                Id accountId = accountIdsByContactId.get(contactId);
                Id transactionId = transactionByAccountId.get(accountId);

                if (transactionId != null) {
                    outputRow.transactionId = transactionId;
                    outputRow.accountId = accountId;
                } else {
                    Id leadId = leadIdsByPhone.get(normalized);
                    if (leadId != null) {
                        outputRow.leadId = leadId;
                    } else {
                        outputRow.accountId = accountId;
                    }
                }
            }
            outputs.add(outputRow);
        }

        return outputs;
    }
}