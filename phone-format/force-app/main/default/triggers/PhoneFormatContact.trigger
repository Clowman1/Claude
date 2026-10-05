// Formats every phone field to xxx-xxx-xxxx (see FormattingUtility.formatPhone).
trigger PhoneFormatContact on Contact (before insert, before update) {
    FormattingUtility.formatPhoneFields(Trigger.new);
}
