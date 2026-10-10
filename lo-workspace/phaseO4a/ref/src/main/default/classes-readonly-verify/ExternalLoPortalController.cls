public with sharing class ExternalLoPortalController {

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.LeadRow> getLeads(String filterKey, String searchTerm) {
        return ExternalLoPortalService.getLeads(filterKey, searchTerm);
    }

    @AuraEnabled(cacheable=true)
    public static ExternalLoPortalService.LeadDetail getLeadDetail(Id leadId) {
        return ExternalLoPortalService.getLeadDetail(leadId);
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.LeadRow> findLeadDuplicates(
        String name,
        String phone,
        String email
    ) {
        return ExternalLoPortalService.findLeadDuplicates(name, phone, email);
    }

    @AuraEnabled
    public static ExternalLoLeadService.CreateLeadResult createLead(
        String name,
        String phone,
        String email,
        String purpose,
        Decimal loanAmount,
        String loanProgram,
        String leadSource,
        String market,
        String notes,
        Boolean forceCreate
    ) {
        ExternalLoLeadService.CreateLeadRequest request = new ExternalLoLeadService.CreateLeadRequest();
        request.name = name;
        request.phone = phone;
        request.email = email;
        request.purpose = purpose;
        request.loanAmount = loanAmount;
        request.loanProgram = loanProgram;
        request.leadSource = leadSource;
        request.market = market;
        request.notes = notes;
        request.forceCreate = forceCreate;
        try {
            return ExternalLoLeadService.createLead(request);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.PartnerRow> getRealtors(String filterKey, String searchTerm) {
        return ExternalLoPortalService.getRealtors(filterKey, searchTerm);
    }

    /** My Realtors (kind realtor) and Other Contacts (kind other) in LO Workspace. */
    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.PartnerRow> getPartnersByKind(String filterKey, String searchTerm, String kind) {
        return ExternalLoPortalService.getPartners(filterKey, searchTerm, kind);
    }

    @AuraEnabled(cacheable=true)
    public static ExternalLoPortalService.PartnerDetail getPartnerDetail(Id accountId) {
        return ExternalLoPortalService.getPartnerDetail(accountId);
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.PartnerRow> searchPartners(String searchTerm) {
        return ExternalLoPartnerService.searchPartners(searchTerm);
    }

    @AuraEnabled
    public static ExternalLoPortalService.PartnerRow linkPartner(Id accountId) {
        try {
            return ExternalLoPartnerService.linkPartner(accountId);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static ExternalLoPartnerService.CreatePartnerResult createPartner(
        String name,
        String phone,
        String email,
        String company,
        String market,
        String partnerType
    ) {
        ExternalLoPartnerService.CreatePartnerRequest request = new ExternalLoPartnerService.CreatePartnerRequest();
        request.name = name;
        request.phone = phone;
        request.email = email;
        request.company = company;
        request.market = market;
        request.partnerType = partnerType;
        try {
            return ExternalLoPartnerService.createPartner(request);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    // ---- LO Workspace partner tags (outside LOs only; see LoWsPartnerTagService) ----

    /** Tag me on an existing partner: after a duplicate hit (email/phone) or from search. */
    @AuraEnabled
    public static void tagPartner(Id accountId, String email, String phone) {
        try {
            requireTagMode();
            LoWsPartnerTagService.tagExisting(accountId, email, phone);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static void untagPartner(Id accountId) {
        try {
            requireTagMode();
            LoWsPartnerTagService.untag(accountId);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static void setPartnerStage(Id accountId, String stage) {
        try {
            requireTagMode();
            LoWsPartnerTagService.setStage(accountId, stage);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    // ---- LO Workspace lead / partner / client Overview (LoWsContactService, LoWsLeadDetailsService) ----
    // Not cacheable on purpose: the cards re-read after every save.

    @AuraEnabled
    public static LoWsContactService.ContactInfo getContactInfo(Id recordId) {
        try {
            return LoWsContactService.getContact(recordId);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getLeadStatusOptions() {
        try {
            return LoWsContactService.leadStatusOptions();
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    /** Status dropdown on the lead header and Board drag-and-drop (LO Workspace, owner only). */
    @AuraEnabled
    public static String updateLeadStatus(Id leadId, String status) {
        try {
            return LoWsContactService.updateLeadStatus(leadId, status);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static LoWsContactService.ContactInfo updateContactInfo(
        Id recordId, String firstName, String lastName, String phone, String email,
        String street, String city, String state, String postalCode, String relationship
    ) {
        try {
            return LoWsContactService.updateContact(recordId, firstName, lastName, phone, email, street, city, state, postalCode, relationship);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static LoWsBorrowerService.BorrowerList getLeadBorrowers(Id leadId) {
        try {
            return LoWsBorrowerService.listBorrowers(leadId);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static Id addLeadBorrower(Id leadId, String firstName, String lastName, String phone, String email, String relationship) {
        try {
            return LoWsBorrowerService.addBorrower(leadId, firstName, lastName, phone, email, relationship);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static void removeLeadBorrower(Id borrowerId) {
        try {
            LoWsBorrowerService.removeBorrower(borrowerId);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static LoWsLeadDetailsService.Details getPreApprovalDetails(Id leadId) {
        try {
            return LoWsLeadDetailsService.getDetails(leadId);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    /** detailsJson: a JSON Details (a nested DTO parameter would bind empty, see logActivity). */
    @AuraEnabled
    public static LoWsLeadDetailsService.Details savePreApprovalDetails(Id leadId, String detailsJson) {
        try {
            return LoWsLeadDetailsService.saveDetails(leadId, detailsJson);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled(cacheable=true)
    public static LoWsLeadDetailsService.FormOptions getAddLeadOptions() {
        try {
            requireTagMode();
            return LoWsLeadDetailsService.formOptions();
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    /** LO Workspace Add lead (My Leads, a My Realtors row, a realtor page). Phase 6 duplicate rules apply. */
    @AuraEnabled
    public static ExternalLoLeadService.CreateLeadResult createLoWorkspaceLead(
        String firstName, String lastName, String phone, String email, String purpose, Id realtorId,
        String newRealtorName, String newRealtorPhone, String newRealtorEmail, String newRealtorCompany, String newRealtorMarket,
        String leadSource
    ) {
        try {
            requireTagMode();
            ExternalLoLeadService.CreateLeadRequest request = new ExternalLoLeadService.CreateLeadRequest();
            request.firstName = firstName;
            request.lastName = lastName;
            request.phone = phone;
            request.email = email;
            request.purpose = purpose;
            request.realtorId = realtorId;
            request.leadSource = leadSource; // ignored when a realtor is set (Realtor Referral)
            request.forceCreate = true;
            return LoWsLeadDetailsService.createLead(request,
                newRealtorName, newRealtorPhone, newRealtorEmail, newRealtorCompany, newRealtorMarket);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    private static void requireTagMode() {
        if (!LoWsPartnerTagService.isTagMode()) {
            throw new DomainException('Partner tags are available in LO Workspace only.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.PreApprovalRow> getPreApprovals(
        String filterKey,
        String searchTerm
    ) {
        return ExternalLoPortalService.getPreApprovals(filterKey, searchTerm);
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.LoanRow> getLoans(String filterKey, String searchTerm) {
        return ExternalLoPortalService.getLoans(filterKey, searchTerm);
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getLoanTabCounts() {
        return ExternalLoPortalService.getLoanTabCounts();
    }

    @AuraEnabled(cacheable=true)
    public static ExternalLoPortalService.LoanDetail getLoanDetail(Id loanId) {
        return ExternalLoPortalService.getLoanDetail(loanId);
    }

    // Not cacheable: the drawer reloads this imperatively right after logging an
    // activity, and a cached payload would show stale rows.
    @AuraEnabled
    public static ExternalLoPortalService.RecordSetPayload getRecordSet(String recordSetKey) {
        return ExternalLoPortalService.getRecordSet(recordSetKey);
    }

    @AuraEnabled(cacheable=true)
    public static ExternalLoPortalService.NavBadges getNavBadges() {
        return ExternalLoPortalService.getNavBadges();
    }

    @AuraEnabled
    public static ExternalLoCommunicationService.LogResult logCommunication(
        Id recordId,
        String objectApiName,
        String channel,
        String outcome,
        String notes,
        String followUpOption
    ) {
        ExternalLoCommunicationService.LogRequest request = new ExternalLoCommunicationService.LogRequest();
        request.recordId = recordId;
        request.objectApiName = objectApiName;
        request.channel = channel;
        request.outcome = outcome;
        request.notes = notes;
        request.followUpOption = followUpOption;
        try {
            return ExternalLoCommunicationService.logCommunication(request);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static ExternalLoActivityLogService.LogResult logActivity(
        String activityKey,
        String channel,
        Integer activityCount,
        Id recordId,
        String objectApiName,
        String notes,
        String promptKey,
        String followUpOption,
        String callOutcome
    ) {
        try {
            // Aura binds a nested @AuraEnabled DTO parameter as an *empty*
            // instance rather than deserializing it, so activityKey arrived
            // null and every save failed the category check. Same defect the
            // onboarding save hit; keep the signature primitive.
            ExternalLoActivityLogService.LogRequest request = new ExternalLoActivityLogService.LogRequest();
            request.activityKey = activityKey;
            request.channel = channel;
            request.activityCount = activityCount;
            request.recordId = recordId;
            request.objectApiName = objectApiName;
            request.notes = notes;
            request.promptKey = promptKey;
            request.followUpOption = followUpOption;
            request.callOutcome = callOutcome;
            return ExternalLoActivityLogService.logActivity(request);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static ExternalLoActivityLogService.LogResult snoozePrompt(
        String promptKey,
        Id recordId,
        String objectApiName
    ) {
        try {
            return ExternalLoActivityLogService.snoozePrompt(promptKey, recordId, objectApiName);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoActivityLogService.SearchHit> searchLoggableRecords(String searchTerm) {
        try {
            return ExternalLoActivityLogService.searchLoggableRecords(searchTerm);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.PartnerRow> getRealtorProspects(String searchTerm) {
        return ExternalLoPortalService.getRealtors('prospects', searchTerm == null ? '' : searchTerm);
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.LeadRow> getPastClientRows(String searchTerm) {
        try {
            return ExternalLoPortalService.getPastClients(searchTerm == null ? '' : searchTerm);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    /** LO Workspace past client page (Person Account). Owner or read access is checked in the service. */
    @AuraEnabled
    public static ExternalLoPortalService.PastClientDetail getPastClientDetail(Id accountId) {
        try {
            return ExternalLoPortalService.getPastClientDetail(accountId);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    /** LO Workspace routing for an Account: 'pastClients', 'realtors' or null. */
    @AuraEnabled(cacheable=true)
    public static String getAccountWorkspaceView(Id accountId) {
        try {
            return ExternalLoPortalService.accountWorkspaceView(accountId);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled(cacheable=true)
    public static ExternalLoProgressService.ProgressPayload getActivityRollup(String cacheBust) {
        // cacheBust is the LWC wire cache key only. Date.now() does not fit Apex Integer.
        try {
            return ExternalLoProgressService.getProgress(UserInfo.getUserId());
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    /**
     * Only curated text may cross the Aura boundary to external portal users:
     * domain-validation messages and DML/validation-rule messages (written for
     * end users). Any other exception is logged and replaced with a generic
     * message so internal details never leak.
     */
    private static AuraHandledException toAura(Exception error) {
        String message;
        if (error instanceof DomainException) {
            message = error.getMessage();
        } else if (error instanceof DmlException) {
            DmlException dmlError = (DmlException) error;
            List<String> dmlMessages = new List<String>();
            for (Integer i = 0; i < dmlError.getNumDml(); i++) {
                dmlMessages.add(dmlError.getDmlMessage(i));
            }
            message = String.join(dmlMessages, ' ');
        } else {
            System.debug(LoggingLevel.ERROR,
                'ExternalLoPortalController unexpected error: ' + error.getTypeName()
                + ' — ' + error.getMessage() + '\n' + error.getStackTraceString());
            message = null;
        }
        if (String.isBlank(message) || message == 'Script-thrown exception') {
            message = 'The record could not be saved. Screenshot this message and send it to an admin.';
        }
        AuraHandledException wrapped = new AuraHandledException(message);
        wrapped.setMessage(message);
        return wrapped;
    }
}