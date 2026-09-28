public with sharing class ExternalLoPartnerService {

    public static List<ExternalLoPortalService.PartnerRow> searchPartners(String searchTerm) {
        PersonAccountRepository repository = new PersonAccountRepository();
        Id userId = UserInfo.getUserId();
        List<Account> matches = repository.searchSharedPartners(searchTerm, 20);
        List<ExternalLoPortalService.PartnerRow> rows = new List<ExternalLoPortalService.PartnerRow>();
        for (Account accountRecord : matches) {
            rows.add(ExternalLoPortalService.mapPartner(accountRecord, userId, new Map<Id, Datetime>()));
        }
        return rows;
    }

    public static ExternalLoPortalService.PartnerRow linkPartner(Id accountId) {
        if (accountId == null) {
            throw new DomainException('Select a partner record.');
        }
        PersonAccountRepository repository = new PersonAccountRepository();
        Account accountRecord = repository.selectPortalPartnerDetail(accountId, UserInfo.getUserId());
        if (accountRecord == null) {
            throw new DomainException('Partner record could not be found.');
        }
        if (ExternalLoPortalService.isHouseLocked(accountRecord, UserInfo.getUserId())) {
            throw new DomainException('This partner is managed by the Reach house team.');
        }
        return ExternalLoPortalService.mapPartner(accountRecord, UserInfo.getUserId(), new Map<Id, Datetime>());
    }

    public static CreatePartnerResult createPartner(CreatePartnerRequest request) {
        validateCreateRequest(request);
        PersonAccountRepository repository = new PersonAccountRepository();
        List<Account> matches = repository.searchSharedPartners(request.name, 5);
        if (!matches.isEmpty()) {
            throw new DomainException('A matching partner already exists. Use the existing record instead.');
        }

        // The name-only check above misses a partner stored under a different spelling, which
        // is how duplicates got in. Match on email and phone as well, using the same service
        // the realtor and title-agent create paths use, and surface it as a DomainException so
        // the portal error handling is unchanged.
        try {
            PersonAccountDuplicateService.blockIfDuplicate(request.email, request.phone);
        } catch (PersonAccountDuplicateService.DuplicateFoundException e) {
            throw new DomainException(e.getMessage());
        }

        Id recordTypeId = repository.selectPersonAccountRecordTypeId();
        if (recordTypeId == null) {
            throw new DomainException('Person Account record type is not configured.');
        }

        List<String> nameParts = request.name.trim().split('\\s+', 2);
        Account partner = new Account();
        partner.RecordTypeId = recordTypeId;
        partner.FirstName = nameParts[0];
        partner.LastName = nameParts.size() > 1 ? nameParts[1] : 'Partner';
        partner.PersonEmail = request.email;
        partner.Phone = request.phone;
        partner.Company__c = request.company;
        // The portal surfaces a partner's market from Account.BillingCity (see
        // ExternalLoPortalService.mapPartner).
        partner.BillingCity = request.market;
        partner.Group__pc = mapPartnerGroup(request.partnerType);
        partner.OwnerId = UserInfo.getUserId();
        partner.Follow_Up_LO__c = UserInfo.getUserId();

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<Account>{ partner }
        );
        insert decision.getRecords();
        Account savedPartner = (Account) decision.getRecords()[0];

        CreatePartnerResult result = new CreatePartnerResult();
        result.accountId = savedPartner.Id;
        result.userMessage = savedPartner.Name + ' added to the shared partner database.';
        return result;
    }

    private static void validateCreateRequest(CreatePartnerRequest request) {
        if (request == null || String.isBlank(request.name)) {
            throw new DomainException('Enter the partner name.');
        }
        if (String.isBlank(request.company)) {
            throw new DomainException('Enter the brokerage or company.');
        }
    }

    private static String mapPartnerGroup(String partnerType) {
        if (partnerType == 'Title') {
            return 'Title Agent';
        }
        if (partnerType == 'Insurance') {
            return 'Insurance Agent';
        }
        return 'Realtor';
    }

    public class CreatePartnerRequest {
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String partnerType;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String market;
    }

    public class CreatePartnerResult {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String userMessage;
    }
}