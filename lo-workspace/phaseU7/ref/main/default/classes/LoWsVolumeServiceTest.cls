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
                Funding_Date__c = monthStart, Loan_Amount_1st__c = 999999)
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
    }
}