public with sharing class ExternalLoWorkspaceController {
    @AuraEnabled(cacheable=true)
    public static ExternalLoOnboardingService.OnboardingState getOnboardingState() {
        try {
            return ExternalLoOnboardingService.getState();
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled
    public static ExternalLoOnboardingService.OnboardingState saveOnboarding(
        String businessFocus,
        Integer callsGoal,
        Integer textsGoal,
        Integer emailsGoal,
        Integer meetingsGoal,
        Integer openHousesGoal,
        Boolean completeOnboarding
    ) {
        ExternalLoOnboardingService.SaveRequest request = new ExternalLoOnboardingService.SaveRequest();
        request.businessFocus = businessFocus;
        request.callsGoal = callsGoal;
        request.textsGoal = textsGoal;
        request.emailsGoal = emailsGoal;
        request.meetingsGoal = meetingsGoal;
        request.openHousesGoal = openHousesGoal;
        request.completeOnboarding = completeOnboarding;
        try {
            return ExternalLoOnboardingService.save(request);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    /**
     * Weekly activity-plan snapshot for the running user.
     */
    @AuraEnabled(cacheable=true)
    public static ExternalLoActivityPlanService.ActivityPlan getActivityPlan() {
        try {
            return ExternalLoActivityPlanService.getPlan(UserInfo.getUserId());
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    /**
     * Six-step wizard save. Accepts a typed DTO so weekly targets stay together.
     */
    @AuraEnabled
    public static ExternalLoOnboardingService.OnboardingState saveOnboardingV2(
        String businessFocus,
        Integer workdaysPerWeek,
        Boolean completeOnboarding,
        String goalsJson,
        Integer monthlyUnitGoal,
        Decimal monthlyVolumeGoal,
        Integer targetRealtorCount
    ) {
        try {
            // Aura binds a nested @AuraEnabled DTO parameter as an *empty*
            // instance rather than deserializing it, which silently dropped
            // businessFocus and failed the focus check. Primitives plus a JSON
            // string bind reliably; the service contract is unchanged.
            ExternalLoOnboardingService.SaveRequestV2 request =
                new ExternalLoOnboardingService.SaveRequestV2();
            request.businessFocus = businessFocus;
            request.workdaysPerWeek = workdaysPerWeek;
            request.completeOnboarding = completeOnboarding;
            request.goals = parseGoals(goalsJson);
            // Optional (LO Workspace): the older portal wizard omits them and the saved values stay.
            request.monthlyUnitGoal = monthlyUnitGoal;
            request.monthlyVolumeGoal = monthlyVolumeGoal;
            request.targetRealtorCount = targetRealtorCount;
            return ExternalLoOnboardingService.saveV2(request);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @TestVisible
    private static List<ExternalLoOnboardingService.GoalInput> parseGoals(String goalsJson) {
        if (String.isBlank(goalsJson)) {
            return new List<ExternalLoOnboardingService.GoalInput>();
        }
        return (List<ExternalLoOnboardingService.GoalInput>) JSON.deserialize(
            goalsJson,
            List<ExternalLoOnboardingService.GoalInput>.class
        );
    }

    @AuraEnabled
    public static ExternalLoCsvImportService.ImportResult importCsv(String family, String csvBody) {
        try {
            return ExternalLoCsvImportService.importCsv(family, csvBody);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ExternalLoPortalService.LeadRow> getPastClients(String searchTerm) {
        try {
            return ExternalLoPortalService.getPastClients(searchTerm == null ? '' : searchTerm);
        } catch (Exception error) {
            throw toAura(error);
        }
    }

    @TestVisible
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
                'ExternalLoWorkspaceController unexpected error: ' + error.getTypeName()
                + ' — ' + error.getMessage() + '\n' + error.getStackTraceString());
            message = null;
        }
        if (String.isBlank(message) || message == 'Script-thrown exception') {
            message = System.Label.ExtLO_Generic_Error;
        }
        AuraHandledException wrapped = new AuraHandledException(message);
        wrapped.setMessage(message);
        return wrapped;
    }
}