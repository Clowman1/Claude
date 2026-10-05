public with sharing class LeadPortalDocumentRequestFacade {
    /**
     * Partner Workspace DTOs intentionally avoid @AuraEnabled Id fields tied to Lead (or reference
     * rows the community profile cannot read). Experience Cloud LDS strips or blocks those values
     * and surfaces "sObject type 'Lead' is not supported".
     */
    public class PortalPresetConditionRow {
        @AuraEnabled public String referenceKey;
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public String section;
        @AuraEnabled public Boolean defaultSelected;
        @AuraEnabled public Decimal sortOrder;
    }

    public class PortalRequestRow {
        @AuraEnabled public String requestKey;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String description;
        @AuraEnabled public String rejectionNotes;
        @AuraEnabled public String subject;
        @AuraEnabled public String category;
        @AuraEnabled public String type;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Date requestedDate;
        @AuraEnabled public String assignedToName;
        @AuraEnabled public Boolean includeInEmail;
        @AuraEnabled public Boolean canBorrowerSee;
        @AuraEnabled public String convertedConditionKey;
        @AuraEnabled public String referenceKey;
        @AuraEnabled public Decimal fileCount;
        @AuraEnabled public String assignment;
        @AuraEnabled public String borrowerName;
        @AuraEnabled public Boolean borrowerMissingEmail;
    }

    public class PortalDocumentRequestView {
        @AuraEnabled public String contextRecordId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String borrowerLastName;
        @AuraEnabled public String borrowerEmail;
        @AuraEnabled public String portalLink;
        @AuraEnabled public Boolean isConverted;
        @AuraEnabled public Boolean spanishCommunications;
        @AuraEnabled public String convertedTransactionId;
        @AuraEnabled public List<PortalRequestRow> requests;
        @AuraEnabled public List<LeadDocumentRequestService.BorrowerOption> borrowerOptions;
    }

    public class PortalSaveResponse {
        @AuraEnabled public Integer createdCount;
    }

    private static Id parseContextRecordId(String contextRecordId) {
        if (String.isBlank(contextRecordId)) {
            return null;
        }
        return (Id) contextRecordId;
    }

    @AuraEnabled
    public static PortalDocumentRequestView initializePortalData(String contextRecordId) {
        Id leadId = parseContextRecordId(contextRecordId);
        LeadDocumentRequestService.LeadDocumentRequestData data =
            LeadDocumentRequestService.initializeInternalData(leadId);

        PortalDocumentRequestView view = new PortalDocumentRequestView();
        view.contextRecordId = leadId == null ? null : String.valueOf(leadId);
        view.leadName = data.leadName;
        view.borrowerLastName = data.borrowerLastName;
        view.borrowerEmail = data.borrowerEmail;
        view.portalLink = data.portalLink;
        view.isConverted = data.isConverted;
        view.spanishCommunications = data.spanishCommunications;
        view.convertedTransactionId = data.convertedTransactionId == null
            ? null
            : String.valueOf(data.convertedTransactionId);
        view.requests = toPortalRequestRows(data.requests);
        view.borrowerOptions = LeadDocumentRequestService.getBorrowerOptions(leadId);
        return view;
    }

    @AuraEnabled
    public static List<LeadDocumentRequestService.BorrowerOption> getBorrowerOptions(String contextRecordId) {
        return LeadDocumentRequestService.getBorrowerOptions(parseContextRecordId(contextRecordId));
    }

    @AuraEnabled
    public static List<PortalPresetConditionRow> getPortalPresetConditions(
        String loanPurpose,
        String employmentType,
        String selfEmploymentType
    ) {
        List<PortalPresetConditionRow> rows = new List<PortalPresetConditionRow>();
        for (LeadPresetConditionSelectorController.PresetConditionItem item :
            LeadPresetConditionSelectorController.getPortalPresetConditions(
                loanPurpose,
                employmentType,
                selfEmploymentType
            )
        ) {
            rows.add(toPortalPresetRow(item));
        }
        return rows;
    }

    @AuraEnabled
    public static PortalSaveResponse createPortalSelectedConditions(
        String contextRecordId,
        List<String> selectedKeys,
        String assignment
    ) {
        LeadPresetConditionSelectorController.SaveResponse response =
            LeadPresetConditionSelectorController.createSelectedConditionKeys(
                parseContextRecordId(contextRecordId),
                selectedKeys,
                assignment
            );
        PortalSaveResponse portalResponse = new PortalSaveResponse();
        portalResponse.createdCount = response == null ? 0 : response.createdCount;
        return portalResponse;
    }

    @AuraEnabled
    public static List<PortalRequestRow> savePortalRequests(
        String contextRecordId,
        List<LeadDocumentRequestService.RequestInput> requests
    ) {
        return toPortalRequestRows(
            LeadDocumentRequestService.saveRequests(parseContextRecordId(contextRecordId), requests)
        );
    }

    @AuraEnabled
    public static Boolean setPortalSpanishCommunications(String contextRecordId, Boolean useSpanish) {
        return LeadDocumentRequestService.setSpanishCommunications(
            parseContextRecordId(contextRecordId),
            useSpanish
        );
    }

    @AuraEnabled
    public static List<LeadDocumentRequestService.BorrowerPortalLink> getPortalBorrowerLinks(
        String contextRecordId
    ) {
        return LeadDocumentRequestService.getBorrowerPortalLinks(parseContextRecordId(contextRecordId));
    }

    @AuraEnabled
    public static String getPortalSharedTemplatePreview(
        String contextRecordId,
        String templateDeveloperName
    ) {
        return LeadDocumentRequestService.getSharedTemplatePreview(
            parseContextRecordId(contextRecordId),
            templateDeveloperName
        );
    }

    @AuraEnabled
    public static LeadDocumentRequestService.EmailInformation getPortalEmailTemplatePreview(
        String contextRecordId,
        String templateDeveloperName
    ) {
        return LeadDocumentRequestService.getEmailTemplatePreview(
            parseContextRecordId(contextRecordId),
            templateDeveloperName
        );
    }

    @AuraEnabled
    public static List<String> sendPortalPerBorrowerRequestEmails(
        String contextRecordId,
        String subject,
        String templateDeveloperName
    ) {
        return LeadDocumentRequestService.sendPerBorrowerRequestEmails(
            parseContextRecordId(contextRecordId),
            subject,
            templateDeveloperName
        );
    }

    @AuraEnabled
    public static String sendPortalComposedRequestEmail(
        String contextRecordId,
        String subject,
        String htmlBody,
        String toAddresses,
        String ccAddresses,
        String templateDeveloperName
    ) {
        return LeadDocumentRequestService.sendEditedRequestEmail(
            parseContextRecordId(contextRecordId),
            subject,
            htmlBody,
            toAddresses,
            ccAddresses,
            templateDeveloperName
        );
    }

    private static List<PortalRequestRow> toPortalRequestRows(
        List<LeadDocumentRequestService.RequestItem> items
    ) {
        List<PortalRequestRow> rows = new List<PortalRequestRow>();
        if (items == null) {
            return rows;
        }
        for (LeadDocumentRequestService.RequestItem item : items) {
            rows.add(toPortalRequestRow(item));
        }
        return rows;
    }

    private static PortalRequestRow toPortalRequestRow(LeadDocumentRequestService.RequestItem item) {
        PortalRequestRow row = new PortalRequestRow();
        row.requestKey = item.id == null ? null : String.valueOf(item.id);
        row.name = item.name;
        row.status = item.status;
        row.description = item.description;
        row.rejectionNotes = item.rejectionNotes;
        row.subject = item.subject;
        row.category = item.category;
        row.type = item.type;
        row.createdDate = item.createdDate;
        row.requestedDate = item.requestedDate;
        row.assignedToName = item.assignedToName;
        row.includeInEmail = item.includeInEmail;
        row.canBorrowerSee = item.canBorrowerSee;
        row.convertedConditionKey = item.convertedConditionId == null
            ? null
            : String.valueOf(item.convertedConditionId);
        row.referenceKey = item.referenceId == null ? null : String.valueOf(item.referenceId);
        row.fileCount = item.fileCount;
        row.assignment = item.assignment;
        row.borrowerName = item.borrowerName;
        row.borrowerMissingEmail = item.borrowerMissingEmail;
        return row;
    }

    private static PortalPresetConditionRow toPortalPresetRow(
        LeadPresetConditionSelectorController.PresetConditionItem item
    ) {
        PortalPresetConditionRow row = new PortalPresetConditionRow();
        String resolvedKey = String.isNotBlank(item.key) ? item.key : (item.id == null ? null : String.valueOf(item.id));
        row.referenceKey = resolvedKey;
        row.key = resolvedKey;
        row.label = item.label;
        row.description = item.description;
        row.category = item.category;
        row.section = item.section;
        row.defaultSelected = item.defaultSelected;
        row.sortOrder = item.sortOrder;
        return row;
    }
}