// Formats every phone field to xxx-xxx-xxxx (see FormattingUtility.formatPhone).
trigger PhoneFormatBorrower on Borrower__c (before insert, before update) {
    FormattingUtility.formatPhoneFields(Trigger.new);
}