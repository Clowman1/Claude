@IsTest
private class LoWsPartnerTagBackfillTest {

    @IsTest
    static void tagsOwnedPartnersOnceAndSkipsBorrowers() {
        Id personRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Account realtor = new Account(RecordTypeId = personRt, FirstName = 'Tag', LastName = 'Realtor', Is_Realtor__c = true);
        Account borrower = new Account(RecordTypeId = personRt, FirstName = 'Tag', LastName = 'Borrower');
        insert new List<Account>{ realtor, borrower };
        Id me = UserInfo.getUserId();

        Test.startTest();
        Integer first = LoWsPartnerTagBackfill.tagOwnedPartners(me, 'Active Partner');
        Integer second = LoWsPartnerTagBackfill.tagOwnedPartners(me, 'Active Partner');
        Test.stopTest();

        Id contactId = [SELECT PersonContactId FROM Account WHERE Id = :realtor.Id].PersonContactId;
        List<External_User_Assignment__c> tags = [
            SELECT Stage__c, Contact__c, OwnerId FROM External_User_Assignment__c WHERE User__c = :me AND Contact__c = :contactId
        ];
        Assert.areEqual(1, tags.size());
        Assert.areEqual('Active Partner', tags[0].Stage__c);
        Assert.areEqual(me, tags[0].OwnerId);
        Assert.areEqual(0, second, 'second run must be a no-op');
        Assert.areEqual(0, [SELECT COUNT() FROM External_User_Assignment__c WHERE Contact__r.AccountId = :borrower.Id]);
        Assert.isTrue(first >= 1);
    }

    @IsTest
    static void rejectsUnknownStage() {
        try {
            LoWsPartnerTagBackfill.tagOwnedPartners(UserInfo.getUserId(), 'Bogus');
            Assert.fail('expected an exception');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Bogus'));
        }
    }
}
