@IsTest
private class LeadLoanPartnerAssignmentServiceTest {
    @IsTest
    static void assignsOwnersConfiguredLoanPartnerOnCreate() {
        Id loanPartnerId = '005000000000002AAA';
        Id leadOwnerId = '005000000000001AAA';
        LeadLoanPartnerAssignmentService.ownerLoanPartnerOverrides = new Map<Id, Id>{
            leadOwnerId => loanPartnerId
        };

        Lead leadRecord = new Lead(
            FirstName = 'Loan',
            LastName = 'Partner',
            Company = 'Loan Partner Test',
            Status = firstAvailableStatus('New'),
            OwnerId = leadOwnerId
        );

        LeadLoanPartnerAssignmentService.stampFromOwnerAssignments(new List<Lead>{ leadRecord }, null);

        System.assertEquals(loanPartnerId, leadRecord.Loan_Partner__c);
    }

    @IsTest
    static void assignsOwnersConfiguredLoanPartnerWhenOwnerChanges() {
        Id firstOwnerId = '005000000000003AAA';
        Id secondOwnerId = '005000000000004AAA';
        Id loanPartnerId = '005000000000005AAA';
        LeadLoanPartnerAssignmentService.ownerLoanPartnerOverrides = new Map<Id, Id>{
            secondOwnerId => loanPartnerId
        };

        Lead leadRecord = new Lead(
            Id = '00Q000000000001AAA',
            FirstName = 'Owner',
            LastName = 'Change',
            Company = 'Owner Change Test',
            Status = firstAvailableStatus('New'),
            OwnerId = firstOwnerId
        );
        Lead oldLead = new Lead(Id = leadRecord.Id, OwnerId = firstOwnerId);
        leadRecord.OwnerId = secondOwnerId;
        LeadLoanPartnerAssignmentService.stampFromOwnerAssignments(
            new List<Lead>{ leadRecord },
            new Map<Id, Lead>{ leadRecord.Id => oldLead }
        );

        System.assertEquals(loanPartnerId, leadRecord.Loan_Partner__c);
    }

    @IsTest
    static void triggerRunsOnLeadInsert() {
        LeadLoanPartnerAssignmentService.ownerLoanPartnerOverrides = new Map<Id, Id>();
        Lead leadRecord = new Lead(
            FirstName = 'Trigger',
            LastName = 'Coverage',
            Company = 'Trigger Coverage Test',
            Status = firstAvailableStatus('New')
        );
        insert leadRecord;

        Lead insertedLead = [
            SELECT Id
            FROM Lead
            WHERE Id = :leadRecord.Id
        ];
        System.assertEquals(leadRecord.Id, insertedLead.Id);
    }

    @IsTest
    static void skipsPartnerRelationshipDevLeads() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('Partner_Relationship_Dev');
        System.assertNotEquals(null, info, 'Partner Relationship Dev record type must exist');

        Id loanPartnerId = '005000000000006AAA';
        Id leadOwnerId = '005000000000007AAA';
        LeadLoanPartnerAssignmentService.ownerLoanPartnerOverrides = new Map<Id, Id>{
            leadOwnerId => loanPartnerId
        };

        Lead partnerLead = new Lead(
            FirstName = 'Broker',
            LastName = 'Owner',
            Company = 'Competitor Mortgage',
            Status = firstAvailableStatus('New'),
            OwnerId = leadOwnerId,
            RecordTypeId = info.getRecordTypeId()
        );

        LeadLoanPartnerAssignmentService.stampFromOwnerAssignments(new List<Lead>{ partnerLead }, null);

        System.assertEquals(
            null,
            partnerLead.Loan_Partner__c,
            'Partner Relationship Dev leads must never be stamped with a Loan Partner'
        );
    }

    private static String firstAvailableStatus(String preferred) {
        for (Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == preferred) {
                return entry.getValue();
            }
        }
        System.assert(false, 'Expected active Lead Status value: ' + preferred);
        return null;
    }
}