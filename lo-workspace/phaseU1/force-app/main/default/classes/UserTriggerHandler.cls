public class UserTriggerHandler {
    public void beforeInsertOrUpdate(List<User> users) {
        Map<String, String> templates = fetchEmailSignatureTemplates();
        Id externalLoRoleId = externalLoRoleId();
        for (User user : users) {
            user.Email_Signature__c = formatEmailSignature(user, templates);
            // External LOs see follow-ups in Up Next / To Do, so the native reminder pop-up stays off
            // (decided 2026-10-08). Re-applied on every save so it can't drift back on.
            if (externalLoRoleId != null && user.UserRoleId == externalLoRoleId) {
                user.UserPreferencesActivityRemindersPopup = false;
                user.UserPreferencesTaskRemindersCheckboxDefault = false;
                user.UserPreferencesEventRemindersCheckboxDefault = false;
            }
        }
    }

    private static Id externalLoRoleId() {
        List<UserRole> roles = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer' LIMIT 1];
        return roles.isEmpty() ? null : roles[0].Id;
    }

    public void afterInsertOrUpdate(List<User> users, Map<Id, User> oldUsersById) {
        LoanPartnerLeadShareService.enqueueForUserChanges(users, oldUsersById);
    }

    private Map<String, String> fetchEmailSignatureTemplates() {
        Map<String, String> templateMap = new Map<String, String>();
        for (EmailSignatureTemplate__mdt template : [
                SELECT Id, DeveloperName, TemplateBody__c FROM EmailSignatureTemplate__mdt
                WHERE DeveloperName IN ('Default_Signature', 'Default_Signature_Without_NMLS', 'Email_Sig_Headshot_With_NMLS', 'Email_Sig_Headshot_Without_NMLS')
        ]) {
            templateMap.put(template.DeveloperName, template.TemplateBody__c);
        }
        return templateMap;
    }

    private String formatEmailSignature(User user, Map<String, String> templates) {
        String emailSignatureKey = getEmailSignatureKey(user);
        String emailSignature = templates.get(emailSignatureKey);

        user.Fax = FormattingUtility.formatPhone(user.Fax);
        user.Phone = FormattingUtility.formatPhone(user.Phone);
        user.MobilePhone = FormattingUtility.formatPhone(user.MobilePhone);

        if(user.OverrideEmailSignature__c && emailSignature != null) {
            emailSignature = emailSignature
                    .replace('$$userName$$', user.FirstName + ' ' + user.LastName)
                    .replace('$$userTitle$$', String.isBlank(user.Title) ? '' : user.Title)
                    .replace('$$userPhone$$', String.isBlank(user.Phone) ? '' : user.Phone)
                    .replace('$$userFax$$', String.isBlank(user.Fax) ? '' : user.Fax)
                    .replace('$$userNMLS$$', String.isBlank(user.NMLS__c) ? '' : user.NMLS__c)
                    .replace('https:userHeadShotURL.jpg', String.isBlank(user.Headshot_URL__c) ? '' : user.Headshot_URL__c);
        }
        return emailSignature;
    }

    private String getEmailSignatureKey(User user) {
        if(!String.isBlank(user.Headshot_URL__c) && !String.isBlank(user.NMLS__c)) {
            return 'Email_Sig_Headshot_With_NMLS';
        } else if(!String.isBlank(user.Headshot_URL__c)) {
            return 'Email_Sig_Headshot_Without_NMLS';
        } else if(!String.isBlank(user.NMLS__c)) {
            return 'Default_Signature';
        } else {
            return 'Default_Signature_Without_NMLS';
        }
    }
}