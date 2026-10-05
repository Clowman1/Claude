// Formats every phone field to xxx-xxx-xxxx (see FormattingUtility.formatPhone).
trigger PhoneFormatTransaction on Transaction__c (before insert, before update) {
    FormattingUtility.formatPhoneFields(Trigger.new);
}
