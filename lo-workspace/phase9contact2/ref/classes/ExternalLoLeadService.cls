// ADR-0001: Lead insert uses SYSTEM_MODE because Customer Community Plus cannot be granted Create Lead.

public with sharing class ExternalLoLeadService {

    public static CreateLeadResult createLead(CreateLeadRequest request) {
        Boolean tagMode = LoWsPartnerTagService.isTagMode();
        if (tagMode) {
            prepareLoWorkspaceRequest(request);
        } else {
            validateCreateRequest(request);
        }
        LeadRepository leadRepository = LeadRepository.getInstance();
        Id ownerId = UserInfo.getUserId();
        // LO Workspace (Phase 6): org-wide duplicate rules. Nurturing -> take over; worked elsewhere -> refuse.
        if (tagMode) {
            LoWsLeadIntakeService.Verdict verdict = LoWsLeadIntakeService.decide(
                ownerId, new List<String>{ request.email }, new List<String>{ request.phone })[0];
            if (verdict.message == LoWsLeadIntakeService.BLOCKED_MESSAGE) {
                LoWsLeadIntakeService.alertAdmins('Add lead', new List<String>{ request.name + ' -> ' + verdict.alert });
            }
            if (verdict.message != null) {
                throw new DomainException(verdict.message);
            }
            if (verdict.takeoverLeadId != null) {
                LoWsLeadIntakeService.takeOver(new Map<Id, String>{ verdict.takeoverLeadId => request.leadSource }, ownerId);
                if (request.realtorId != null) {
                    // Now my lead: record the referring realtor like on a new one.
                    Lead taken = new Lead(Id = verdict.takeoverLeadId);
                    LoWsLeadDetailsService.applyRealtor(taken, request.realtorId);
                    Database.update(taken, AccessLevel.SYSTEM_MODE);
                }
                CreateLeadResult taken = new CreateLeadResult();
                taken.leadId = verdict.takeoverLeadId;
                taken.userMessage = request.name.trim() + ' added to your leads.';
                return taken;
            }
        }
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
        if (tagMode) {
            leadRecord.FirstName = request.firstName.trim();
            leadRecord.LastName = request.lastName.trim();
            if (request.realtorId != null) {
                LoWsLeadDetailsService.applyRealtor(leadRecord, request.realtorId);
            }
        }
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

    /**
     * LO Workspace Add lead (My Leads, a My Realtors row, a realtor page): first + last name, phone,
     * email and loan purpose are required, no loan amount. A referring realtor must be one of my
     * partners and makes the source 'Realtor Referral', as BD's createReferralLead and the internal
     * intake do; otherwise the lead keeps the source sent (the form sends none). The portal path is unchanged.
     */
    private static void prepareLoWorkspaceRequest(CreateLeadRequest request) {
        if (request == null) throw new DomainException('Enter the borrower\'s first and last name.');
        LoWsLeadDetailsService.validateNewLead(request.firstName, request.lastName, request.phone, request.email, request.purpose);
        request.name = request.firstName.trim() + ' ' + request.lastName.trim();
        request.email = request.email.trim();
        request.phone = request.phone.trim();
        if (request.realtorId != null) {
            if (LoWsLeadDetailsService.myPartners(new Set<Id>{ request.realtorId }).isEmpty()) {
                throw new DomainException(LoWsLeadDetailsService.FOREIGN_REALTOR);
            }
            request.leadSource = 'Realtor Referral';
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
        // LO Workspace Add lead.
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public Id realtorId;
        @AuraEnabled public Boolean forceCreate;
    }

    public class CreateLeadResult {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String userMessage;
    }
}