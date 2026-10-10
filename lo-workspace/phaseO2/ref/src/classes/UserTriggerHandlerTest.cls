@isTest
private class UserTriggerHandlerTest {

    @isTest static void testBeforeInsertOrUpdate() {
        User u = new User(
                Alias = 'tuser',
                Email='testuser123@test.com',
                Username='testuser123@test.com.' + DateTime.now().getTime(),
                FirstName='Bob',
                LastName='Smith',
                MobilePhone='12484567890',
                Title='Loan Officer',
                Phone='9876543210',
                Fax='1112223333',
                OverrideEmailSignature__c = true,
                TimeZoneSidKey='GMT',
                LocaleSidKey='en_US',
                EmailEncodingKey='UTF-8',
                ProfileId = [SELECT Id FROM Profile WHERE Name='Standard User'].Id,
                LanguageLocaleKey='en_US',
                Headshot_URL__c='image.jpg',
                NMLS__c = '1866656'
        );

        Test.startTest();
        insert u;
        update u;
        Test.stopTest();

        User updatedUser = [SELECT Id, Email_Signature__c FROM User WHERE Id = :u.Id];

        System.assertNotEquals(updatedUser.Email_Signature__c, null);
        System.assert(updatedUser.Email_Signature__c.contains('Bob Smith'));
        System.assert(updatedUser.Email_Signature__c.contains('Loan Officer'));
        System.assert(updatedUser.Email_Signature__c.contains('987-654-3210'));
        System.assert(updatedUser.Email_Signature__c.contains('1866656'));
    }

    @isTest static void externalLoReminderPopupIsForcedOff() {
        List<UserRole> roles = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer' LIMIT 1];
        if (roles.isEmpty()) {
            return; // role only exists in prod-shaped orgs
        }
        User u = new User(
                Alias = 'extlo',
                Email = 'extlo.reminder@test.com',
                Username = 'extlo.reminder@test.com.' + DateTime.now().getTime(),
                FirstName = 'Ext',
                LastName = 'LO',
                TimeZoneSidKey = 'GMT',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
                LanguageLocaleKey = 'en_US',
                UserRoleId = roles[0].Id,
                UserPreferencesActivityRemindersPopup = true,
                UserPreferencesTaskRemindersCheckboxDefault = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            u.UserPreferencesActivityRemindersPopup = true;
            update u;
        }
        User saved = [SELECT UserPreferencesActivityRemindersPopup, UserPreferencesTaskRemindersCheckboxDefault FROM User WHERE Id = :u.Id];
        System.assertEquals(false, saved.UserPreferencesActivityRemindersPopup, 'External LOs never get the reminder pop-up.');
        System.assertEquals(false, saved.UserPreferencesTaskRemindersCheckboxDefault);
    }

    @isTest static void testFormattingUtility() {
        User u = new User(
                Alias = 'tuser',
                Email='testuser123@test.com',
                Username='testuser123@test.com.' + DateTime.now().getTime(),
                FirstName='Bob',
                LastName='Smith',
                MobilePhone='12484567890',
                Title='Loan Officer',
                Phone='9876543210',
                Fax='1112223333',
                OverrideEmailSignature__c = true,
                TimeZoneSidKey='GMT',
                LocaleSidKey='en_US',
                EmailEncodingKey='UTF-8',
                ProfileId = [SELECT Id FROM Profile WHERE Name='Standard User'].Id,
                LanguageLocaleKey='en_US',
                Headshot_URL__c='image.jpg',
                NMLS__c = '1866656'
        );

        Test.startTest();
        insert u;
        update u;
        String formattedMobilePhone = FormattingUtility.formatPhone(u.MobilePhone);
        Test.stopTest();
        System.assertEquals('248-456-7890', formattedMobilePhone);
    }

}