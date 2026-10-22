/**
 * Volume drawer (LO Workspace, decided 2026-10-08). All figures are the running LO's own:
 * - Closed: Transactions where I am the Loan Officer (or owner), excluding DPA 2nd, by Funding_Date__c, summing
 *   Loan_Amount_1st__c ("Total Loan Amount"); month to date stops at today.
 * - Pre-approved: my open Leads in status Pre-Approval, summing Lead.Loan_Amount__c.
 * - New leads: Leads I own created in the period.
 * - Realtor partners added: my External_User_Assignment__c tags created in the period whose partner
 *   is a realtor (BD_Industry__c Realtor or blank; other industries are Other Contacts).
 */
public with sharing class LoWsVolumeService {

    public class Volume {
        @AuraEnabled public Decimal closedMtdAmount = 0;
        @AuraEnabled public Integer closedMtdUnits = 0;
        @AuraEnabled public Decimal closedLastMonthAmount = 0;
        @AuraEnabled public Integer closedLastMonthUnits = 0;
        @AuraEnabled public Decimal preApprovedAmount = 0;
        @AuraEnabled public Integer preApprovedUnits = 0;
        @AuraEnabled public Integer newLeadsMtd = 0;
        @AuraEnabled public Integer newLeadsLastMonth = 0;
        @AuraEnabled public Integer realtorsMtd = 0;
        @AuraEnabled public Integer realtorsLastMonth = 0;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String lastMonthLabel;
        @AuraEnabled public String firstName;
        @AuraEnabled public String photoUrl;
        /** Days elapsed / days in month, for the month-to-date pace line. */
        @AuraEnabled public Integer dayOfMonth;
        @AuraEnabled public Integer daysInMonth;
    }

    private static final List<String> NOT_CLOSED = new List<String>{ 'Cancelled', 'Lost' };
    // DPA 2nd loans never count toward an LO's volume or units (same rule as Payroll Review, 2026-10-21).
    private static final String DPA_2ND = 'DPA 2nd';

    @AuraEnabled
    public static Volume getVolume() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        Date monthStart = today.toStartOfMonth();
        Date lastMonthStart = monthStart.addMonths(-1);
        Volume v = new Volume();
        v.monthLabel = Datetime.newInstance(monthStart, Time.newInstance(12, 0, 0, 0)).format('MMMM yyyy');
        v.lastMonthLabel = Datetime.newInstance(lastMonthStart, Time.newInstance(12, 0, 0, 0)).format('MMMM');
        User u = [SELECT FirstName, SmallPhotoUrl FROM User WHERE Id = :me];
        v.firstName = u.FirstName;
        v.photoUrl = u.SmallPhotoUrl;
        v.dayOfMonth = today.day();
        v.daysInMonth = Date.daysInMonth(today.year(), today.month());

        AggregateResult mtd = [
            SELECT SUM(Loan_Amount_1st__c) amt, COUNT(Id) n FROM Transaction__c
            WHERE (Loan_Officer__c = :me OR OwnerId = :me)
              AND Funding_Date__c >= :monthStart AND Funding_Date__c <= :today
              AND Status__c NOT IN :NOT_CLOSED AND Loan_Type_1st_TD__c != :DPA_2ND
            WITH USER_MODE
        ];
        v.closedMtdAmount = (Decimal) mtd.get('amt') ?? 0;
        v.closedMtdUnits = (Integer) mtd.get('n');

        AggregateResult last = [
            SELECT SUM(Loan_Amount_1st__c) amt, COUNT(Id) n FROM Transaction__c
            WHERE (Loan_Officer__c = :me OR OwnerId = :me)
              AND Funding_Date__c >= :lastMonthStart AND Funding_Date__c < :monthStart
              AND Status__c NOT IN :NOT_CLOSED AND Loan_Type_1st_TD__c != :DPA_2ND
            WITH USER_MODE
        ];
        v.closedLastMonthAmount = (Decimal) last.get('amt') ?? 0;
        v.closedLastMonthUnits = (Integer) last.get('n');

        AggregateResult pre = [
            SELECT SUM(Loan_Amount__c) amt, COUNT(Id) n FROM Lead
            WHERE OwnerId = :me AND IsConverted = false AND Status = 'Pre-Approval'
            WITH USER_MODE
        ];
        v.preApprovedAmount = (Decimal) pre.get('amt') ?? 0;
        v.preApprovedUnits = (Integer) pre.get('n');

        // New leads exclude U8 recycled leads (they are returning borrowers, not new business). SYSTEM_MODE,
        // scoped to my own leads, so LOs don't need access to the recycle field.
        Datetime lastMonthStartAt = Datetime.newInstance(lastMonthStart, Time.newInstance(0, 0, 0, 0));
        Datetime monthStartAt = Datetime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        v.newLeadsMtd = [
            SELECT COUNT() FROM Lead
            WHERE OwnerId = :me AND CreatedDate >= :monthStartAt AND Recycled_From_Transaction__c = null
            WITH SYSTEM_MODE
        ];
        v.newLeadsLastMonth = [
            SELECT COUNT() FROM Lead
            WHERE OwnerId = :me AND CreatedDate >= :lastMonthStartAt AND CreatedDate < :monthStartAt
              AND Recycled_From_Transaction__c = null
            WITH SYSTEM_MODE
        ];

        // One row per (assigned date, created day in my time zone): the same date rule as before, without loading every tag.
        for (AggregateResult g : [
            SELECT Assigned_Date__c assigned, DAY_ONLY(convertTimezone(CreatedDate)) created, COUNT(Id) n
            FROM External_User_Assignment__c
            WHERE User__c = :me AND CreatedDate >= :lastMonthStartAt
              AND (Contact__r.Account.BD_Industry__c = null OR Contact__r.Account.BD_Industry__c = 'Realtor')
            WITH SYSTEM_MODE
            GROUP BY Assigned_Date__c, DAY_ONLY(convertTimezone(CreatedDate))
        ]) {
            Date added = (Date) g.get('assigned') ?? (Date) g.get('created');
            Integer n = (Integer) g.get('n');
            if (added >= monthStart) {
                v.realtorsMtd += n;
            } else if (added >= lastMonthStart) {
                v.realtorsLastMonth += n;
            }
        }
        return v;
    }
}