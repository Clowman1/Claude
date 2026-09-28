// ADR-0001: Lead insert uses SYSTEM_MODE because Customer Community Plus cannot be granted Create Lead.

public with sharing class ExternalLoLeadService {

    public static CreateLeadResult createLead(CreateLeadRequest request) {
        validateCreateRequest(request);
        LeadRepository leadRepository = LeadRepository.getInstance();
        Id ownerId = UserInfo.getUserId();
        List<Lead> duplicates = leadRepository.selectDuplicateLeads(
            ownerId,
            request.name,
            normalizePhone(request.phone),
            request.email
        );
        if (!duplicates.isEmpty() && request.forceCreate != true) {
            throw new DomainException('Possible duplicate lead found. Review existing records before creating another.');
        }

        Id recordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
              AND DeveloperName = 'Consumer_Lead_record_type'
            LIMIT 1
        ].Id;

        List<String> nameParts = request.name.trim().split('\\s+', 2);
        Lead leadRecord = new Lead();
        leadRecord.RecordTypeId = recordTypeId;
        leadRecord.FirstName = nameParts.size() > 1 ? nameParts[0] : request.name.trim();
        leadRecord.LastName = nameParts.size() > 1 ? nameParts[1] : 'Borrower';
        leadRecord.Company = leadRecord.LastName + ' Household';
        leadRecord.Status = 'New';
        leadRecord.OwnerId = ownerId;
        leadRecord.Phone = request.phone;
        leadRecord.Email = request.email;
        leadRecord.Loan_Purpose__c = request.purpose;
        leadRecord.Loan_Amount__c = request.loanAmount;
        leadRecord.Loan_Program__c = request.loanProgram;
        leadRecord.LeadSource = request.leadSource;
        leadRecord.City = request.market;
        leadRecord.Description = request.notes;
        if (request.referringPartnerId != null) {
            leadRecord.Loan_Partner__c = request.referringPartnerId;
        }

        Database.insert(new List<Lead>{ leadRecord }, AccessLevel.SYSTEM_MODE);

        CreateLeadResult result = new CreateLeadResult();
        result.leadId = leadRecord.Id;
        result.userMessage = (leadRecord.FirstName + ' ' + leadRecord.LastName).trim() + ' added to your leads.';
        return result;
    }

    private static void validateCreateRequest(CreateLeadRequest request) {
        if (request == null || String.isBlank(request.name)) {
            throw new DomainException('Enter the borrower name.');
        }
        if (String.isBlank(request.phone) && String.isBlank(request.email)) {
            throw new DomainException('Add a phone number or email so you can follow up.');
        }
        if (request.loanAmount == null || request.loanAmount <= 0) {
            throw new DomainException('Enter an estimated loan amount.');
        }
    }

    private static String normalizePhone(String phone) {
        return String.isBlank(phone) ? null : phone.replaceAll('[^0-9]', '');
    }

    public class CreateLeadRequest {
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String purpose;
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public String loanProgram;
        @AuraEnabled public String leadSource;
        @AuraEnabled public String market;
        @AuraEnabled public String notes;
        @AuraEnabled public Id referringPartnerId;
        @AuraEnabled public Boolean forceCreate;
    }

    public class CreateLeadResult {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String userMessage;
    }
}