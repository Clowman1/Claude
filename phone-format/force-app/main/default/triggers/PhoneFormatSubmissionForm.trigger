// Formats every phone field to xxx-xxx-xxxx (see FormattingUtility.formatPhone).
trigger PhoneFormatSubmissionForm on Submission_Form__c (before insert, before update) {
    FormattingUtility.formatPhoneFields(Trigger.new);
}
