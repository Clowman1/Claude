@IsTest
private class FormattingUtilityTest {
    @IsTest
    static void formatsUsNumbersAndLeavesTheRestAlone() {
        System.assertEquals('772-238-5990', FormattingUtility.formatPhone('7722385990'));
        System.assertEquals('772-238-5990', FormattingUtility.formatPhone('(772) 238-5990'));
        System.assertEquals('772-238-5990', FormattingUtility.formatPhone('+1 772.238.5990'));
        System.assertEquals('772-238-5990', FormattingUtility.formatPhone('17722385990'));
        System.assertEquals('772-238-5990', FormattingUtility.formatPhone('772-238-5990'));
        System.assertEquals('407-801-9776 X119', FormattingUtility.formatPhone('407-801-9776 X119'));
        System.assertEquals('+442045265871', FormattingUtility.formatPhone('+442045265871'));
        System.assertEquals('555', FormattingUtility.formatPhone('555'));
        System.assertEquals('a@b.com', FormattingUtility.formatPhone('a@b.com'));
        System.assertEquals(null, FormattingUtility.formatPhone(null));
    }

    @IsTest
    static void triggersFormatOnInsertAndUpdate() {
        Lead l = new Lead(LastName = 'Phone', Company = 'Test', Phone = '(772) 238-5990', MobilePhone = '7722385991', Agent_Phone__c = '+17722385992');
        insert l;
        l = [SELECT Phone, MobilePhone, Agent_Phone__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('772-238-5990', l.Phone);
        System.assertEquals('772-238-5991', l.MobilePhone);
        System.assertEquals('772-238-5992', l.Agent_Phone__c);

        l.Phone = '772.238.5993';
        update l;
        System.assertEquals('772-238-5993', [SELECT Phone FROM Lead WHERE Id = :l.Id].Phone);

        Id personRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Account a = new Account(LastName = 'Phone Test', RecordTypeId = personRt, PersonMobilePhone = '(772) 238-5996', PersonHomePhone = '7722385994');
        insert a;
        a = [SELECT PersonHomePhone, PersonMobilePhone FROM Account WHERE Id = :a.Id];
        System.assertEquals('772-238-5994', a.PersonHomePhone);
        System.assertEquals('772-238-5996', a.PersonMobilePhone);

        Contact c = new Contact(LastName = 'Phone', MobilePhone = '7722385995');
        insert c;
        System.assertEquals('772-238-5995', [SELECT MobilePhone FROM Contact WHERE Id = :c.Id].MobilePhone);
    }

    @IsTest
    static void customObjectTriggersFormatOnInsert() {
        Transaction__c t = new Transaction__c(BAA_Phone__c = '7722385990', Borrower_Home_Phone__c = '(772) 238-5991');
        insert t;
        t = [SELECT BAA_Phone__c, Borrower_Home_Phone__c FROM Transaction__c WHERE Id = :t.Id];
        System.assertEquals('772-238-5990', t.BAA_Phone__c);
        System.assertEquals('772-238-5991', t.Borrower_Home_Phone__c);
        Submission_Form__c s = new Submission_Form__c(Borrower_Phone__c = '7722385992');
        insert s;
        System.assertEquals('772-238-5992', [SELECT Borrower_Phone__c FROM Submission_Form__c WHERE Id = :s.Id].Borrower_Phone__c);
        Recruit__c r = new Recruit__c(Cell_Phone__c = '7722385993');
        insert r;
        System.assertEquals('772-238-5993', [SELECT Cell_Phone__c FROM Recruit__c WHERE Id = :r.Id].Cell_Phone__c);
        Borrower__c b = new Borrower__c(Phone__c = '7722385994', Transaction__c = t.Id);
        insert b;
        System.assertEquals('772-238-5994', [SELECT Phone__c FROM Borrower__c WHERE Id = :b.Id].Phone__c);
    }
}
