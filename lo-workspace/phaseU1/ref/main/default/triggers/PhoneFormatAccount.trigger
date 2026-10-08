// Formats every phone field to xxx-xxx-xxxx (see FormattingUtility.formatPhone).
trigger PhoneFormatAccount on Account (before insert, before update) {
    FormattingUtility.formatPhoneFields(Trigger.new);
}