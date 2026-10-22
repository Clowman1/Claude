@isTest
private class LoWsVolumeServiceTest {

    @isTest
    static void sumsMyClosedPreApprovedAndNewLeads() {
        Id me = UserInfo.getUserId();
        Date monthStart = Date.today().toStartOfMonth();
        insert new List<Transaction__c>{
            new Transaction__c(Name = 'MTD 1', Loan_Officer__c = me, Status__c = 'Funding',
                Funding_Date__c = monthStart, Loan_Amount_1st__c = 300000),
            new Transaction__c(Name = 'Last month', Loan_Officer__c = me, Status__c = 'Funding',
                Funding_Date__c = monthStart.addDays(-3), Loan_Amount_1st__c = 250000),
            // Cancelled with a funding date never counts as closed.
            new Transaction__c(Name = 'Cancelled', Loan_Officer__c = me, Status__c = 'Cancelled',
                Funding_Date__c = monthStart, Loan_Amount_1st__c = 999999),
            // DPA 2nd never counts toward volume or units.
            new Transaction__c(Name = 'DPA 2nd', Loan_Officer__c = me, Status__c = 'Funding',
                Funding_Date__c = monthStart, Loan_Amount_1st__c = 15000, Loan_Type_1st_TD__c = 'DPA 2nd')
        };
        Id consumer = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND DeveloperName = 'Consumer_Lead_record_type' LIMIT 1].Id;
        insert new Lead(RecordTypeId = consumer, FirstName = 'Vol', LastName = 'PreApproved', Company = 'V',
            Status = 'Pre-Approval', Loan_Amount__c = 400000, OwnerId = me);

        Test.startTest();
        LoWsVolumeService.Volume v = LoWsVolumeService.getVolume();
        Test.stopTest();

        System.assertEquals(300000, v.closedMtdAmount);
        System.assertEquals(1, v.closedMtdUnits);
        System.assertEquals(250000, v.closedLastMonthAmount);
        System.assertEquals(1, v.closedLastMonthUnits);
        System.assert(v.preApprovedAmount >= 400000, String.valueOf(v.preApprovedAmount));
        System.assert(v.preApprovedUnits >= 1);
        System.assert(v.newLeadsMtd >= 1, 'The lead created today counts as new this month.');
        System.assertNotEquals(null, v.monthLabel);
        System.assertEquals([SELECT FirstName FROM User WHERE Id = :me].FirstName, v.firstName, 'Header is personalised.');
        System.assertEquals(Date.today().day(), v.dayOfMonth);
    }

    @isTest
    static void countsNewLeadsAndRealtorTagsByMonth() {
        Id me = UserInfo.getUserId();
        Date monthStart = Date.today().toStartOfMonth();
        Datetime lastMonthNoon = Datetime.newInstance(monthStart.addDays(-2), Time.newInstance(12, 0, 0, 0));
        Id consumer = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND DeveloperName = 'Consumer_Lead_record_type' LIMIT 1].Id;
        Lead thisMonth = new Lead(RecordTypeId = consumer, FirstName = 'Vol', LastName = 'Now', Company = 'V', Status = 'New', OwnerId = me);
        Lead lastMonth = new Lead(RecordTypeId = consumer, FirstName = 'Vol', LastName = 'Then', Company = 'V', Status = 'New', OwnerId = me);
        insert new List<Lead>{ thisMonth, lastMonth };
        Test.setCreatedDate(lastMonth.Id, lastMonthNoon);

        Id personRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Account realtor = new Account(RecordTypeId = personRt, FirstName = 'Rita', LastName = 'VolRealtor');
        Account title = new Account(RecordTypeId = personRt, FirstName = 'Tom', LastName = 'VolTitle', BD_Industry__c = 'Title Agent');
        insert new List<Account>{ realtor, title };
        Map<Id, Account> contacts = new Map<Id, Account>([SELECT Id, PersonContactId FROM Account WHERE Id IN :new List<Id>{ realtor.Id, title.Id }]);
        External_User_Assignment__c createdLastMonth = new External_User_Assignment__c(User__c = me, Unique_Key__c = 'vol-d');
        insert new List<External_User_Assignment__c>{
            // Realtor (blank industry) added today: this month.
            new External_User_Assignment__c(User__c = me, Unique_Key__c = 'vol-a', Contact__c = contacts.get(realtor.Id).PersonContactId,
                Assigned_Date__c = Date.today()),
            // Other industries are Other Contacts, never counted.
            new External_User_Assignment__c(User__c = me, Unique_Key__c = 'vol-b', Contact__c = contacts.get(title.Id).PersonContactId,
                Assigned_Date__c = Date.today()),
            // Assigned date wins over the created date: last month.
            new External_User_Assignment__c(User__c = me, Unique_Key__c = 'vol-c', Contact__c = contacts.get(realtor.Id).PersonContactId,
                Assigned_Date__c = monthStart.addDays(-1)),
            // No assigned date: the created day decides.
            createdLastMonth
        };
        Test.setCreatedDate(createdLastMonth.Id, lastMonthNoon);

        Test.startTest();
        LoWsVolumeService.Volume v = LoWsVolumeService.getVolume();
        Test.stopTest();

        System.assertEquals(1, v.newLeadsMtd);
        System.assertEquals(1, v.newLeadsLastMonth);
        System.assertEquals(1, v.realtorsMtd);
        System.assertEquals(2, v.realtorsLastMonth);
    }
}