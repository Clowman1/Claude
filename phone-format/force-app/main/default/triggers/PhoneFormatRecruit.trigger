// Formats every phone field to xxx-xxx-xxxx (see FormattingUtility.formatPhone).
trigger PhoneFormatRecruit on Recruit__c (before insert, before update) {
    FormattingUtility.formatPhoneFields(Trigger.new);
}
