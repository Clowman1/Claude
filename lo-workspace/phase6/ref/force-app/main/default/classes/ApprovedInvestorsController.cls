// Feeds the Approved Investors modal on the Command Center. Without sharing on purpose:
// the list is a company-wide pricing reference, so Account sharing and FLS must not hide it.
public without sharing class ApprovedInvestorsController {
    @AuraEnabled(cacheable=true)
    public static List<Account> getInvestors() {
        return [
            SELECT Id, Name, Website, Description, Area_of_Specialty__c, Investor_Channel__c,
                Broker_Channel_Products__c, Investor_Summary__c, Primary_Investor__c
            FROM Account
            WHERE Type = 'Investor'
            // Picklists sort by definition order, and Non-Delegated Correspondent is defined first.
            ORDER BY Primary_Investor__c DESC, Investor_Channel__c NULLS LAST, Name
        ];
    }
}