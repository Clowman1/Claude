// Formats every phone field to xxx-xxx-xxxx (see FormattingUtility.formatPhone).
trigger PhoneFormatLead on Lead (before insert, before update) {
    FormattingUtility.formatPhoneFields(Trigger.new);
}