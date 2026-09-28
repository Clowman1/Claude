@IsTest
private class ApprovedInvestorsControllerTest {
    @IsTest
    static void ordersPrimaryThenNonDelThenBroker() {
        Id businessRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Business_Account').getRecordTypeId();
        insert new List<Account>{
            new Account(Name = 'Aaa Broker', Type = 'Investor', RecordTypeId = businessRt, Investor_Channel__c = 'Broker'),
            new Account(Name = 'Bbb NonDel', Type = 'Investor', RecordTypeId = businessRt, Investor_Channel__c = 'Non-Delegated Correspondent'),
            new Account(Name = 'Zzz Primary', Type = 'Investor', RecordTypeId = businessRt, Investor_Channel__c = 'Non-Delegated Correspondent', Primary_Investor__c = true),
            new Account(Name = 'Not An Investor', RecordTypeId = businessRt)
        };

        Test.startTest();
        List<Account> investors = ApprovedInvestorsController.getInvestors();
        Test.stopTest();

        List<String> names = new List<String>();
        for (Account a : investors) {
            if (a.Name.startsWith('Aaa') || a.Name.startsWith('Bbb') || a.Name.startsWith('Zzz') || a.Name.startsWith('Not')) {
                names.add(a.Name);
            }
        }
        System.assertEquals(new List<String>{ 'Zzz Primary', 'Bbb NonDel', 'Aaa Broker' }, names);
    }
}
