/**
 * First-run Partner Workspace setup. V1 keeps daily channel goals for existing
 * callers. V2 persists weekly audience targets on External_LO_Activity_Goal__c.
 * ADR-0002: User updates use SYSTEM_MODE so community FLS can stay read-only.
 */
public with sharing class ExternalLoOnboardingService {

    /**
     * Current user's onboarding plus activity-plan snapshot for the wizard.
     */
    public static OnboardingState getState() {
        return buildState(loadCurrentUser());
    }

    /**
     * Legacy daily-channel save. Completion cannot be flipped off. After setup
     * the plan is locked; only an admin can change focus or targets on the User.
     */
    public static OnboardingState save(SaveRequest request) {
        if (request == null) {
            throw new DomainException('Choose a focus and your daily goals to continue.');
        }
        User currentUser = loadCurrentUser();
        rejectPlanEditsAfterComplete(currentUser);
        List<String> focusOptions = ExternalLOBaselineHelper.businessFocusOptions();
        if (String.isBlank(request.businessFocus) || !isAllowedFocus(request.businessFocus.trim(), focusOptions)) {
            throw new DomainException('Choose one area of business to focus on.');
        }

        User updateShell = new User(
            Id = currentUser.Id,
            Business_Focus__c = request.businessFocus.trim(),
            Calls_Daily_Goal__c = requireGoal(request.callsGoal, 'calls'),
            Texts_Daily_Goal__c = requireGoal(request.textsGoal, 'texts'),
            Emails_Daily_Goal__c = requireGoal(request.emailsGoal, 'emails'),
            Meetings_Daily_Goal__c = requireGoal(request.meetingsGoal, 'meetings'),
            Open_House_Daily_Goal__c = requireGoal(request.openHousesGoal, 'open houses')
        );
        applyCompletionFlag(updateShell, currentUser, request.completeOnboarding);
        Database.update(new List<User>{ updateShell }, AccessLevel.SYSTEM_MODE);
        return buildState(loadCurrentUser());
    }

    /**
     * Six-step wizard save: focus, workdays, and weekly category targets.
     */
    public static OnboardingState saveV2(SaveRequestV2 request) {
        if (request == null) {
            throw new DomainException('Choose a focus and your weekly plan to continue.');
        }
        User currentUser = loadCurrentUser();
        rejectPlanEditsAfterComplete(currentUser);
        String focusLabel = request.businessFocus == null ? '' : request.businessFocus.trim();
        if (String.isBlank(focusLabel) || !isAllowedFocus(focusLabel, ExternalLOBaselineHelper.businessFocusOptions())) {
            throw new DomainException('Choose one area of business to focus on.');
        }
        Integer workdays = ExternalLoGoalMath.clampWorkdays(request.workdaysPerWeek);
        Map<String, GoalInput> inputByKey = indexGoalInputs(request.goals);
        List<External_LO_Activity_Goal__c> toSave = new List<External_LO_Activity_Goal__c>();
        for (ExternalLoActivityCatalog.ActivityDefinition activity : ExternalLoActivityCatalog.activeActivities()) {
            GoalInput input = inputByKey.get(activity.activityKey);
            Integer weekly = input == null || input.weeklyTarget == null
                ? activity.defaultWeeklyTarget
                : requireWeeklyGoal(input.weeklyTarget, activity.shortLabel);
            Boolean enabled = input == null ? true : input.isEnabled != false;
            External_LO_Activity_Goal__c row = new External_LO_Activity_Goal__c();
            row.Activity_Key__c = activity.activityKey;
            row.Weekly_Target__c = weekly;
            row.Is_Enabled__c = enabled;
            toSave.add(row);
        }

        User updateShell = new User(
            Id = currentUser.Id,
            Business_Focus__c = focusLabel,
            ExtLO_Workdays_Per_Week__c = workdays
        );
        applyCompletionFlag(updateShell, currentUser, request.completeOnboarding);
        Database.update(new List<User>{ updateShell }, AccessLevel.SYSTEM_MODE);
        ExternalLoActivityGoalWriter.upsertGoals(currentUser.Id, toSave);
        return buildState(loadCurrentUser());
    }

    private static User loadCurrentUser() {
        User currentUser = UserRepository.getInstance().selectPortalProfile(UserInfo.getUserId());
        if (currentUser == null) {
            throw new DomainException('Your user profile could not be loaded.');
        }
        return currentUser;
    }

    private static OnboardingState buildState(User currentUser) {
        External_LO_Baseline__mdt baseline = ExternalLOBaselineHelper.getBaseline();
        OnboardingState state = new OnboardingState();
        state.complete = currentUser.External_LO_Onboarding_Complete__c == true;
        state.businessFocus = currentUser.Business_Focus__c;
        state.focusOptions = ExternalLOBaselineHelper.businessFocusOptions();
        state.focuses = ExternalLoActivityCatalog.activeFocuses();
        state.callsGoal = goalOrBaseline(currentUser.Calls_Daily_Goal__c, baseline.Calls_Daily_Goal__c);
        state.textsGoal = goalOrBaseline(currentUser.Texts_Daily_Goal__c, baseline.Texts_Daily_Goal__c);
        state.emailsGoal = goalOrBaseline(currentUser.Emails_Daily_Goal__c, baseline.Emails_Daily_Goal__c);
        state.meetingsGoal = goalOrBaseline(currentUser.Meetings_Daily_Goal__c, baseline.Meetings_Daily_Goal__c);
        state.openHousesGoal = goalOrBaseline(currentUser.Open_House_Daily_Goal__c, baseline.Open_House_Daily_Goal__c);
        state.userName = currentUser.Name;
        state.activityPlan = ExternalLoActivityPlanService.getPlan(currentUser.Id, currentUser);
        state.workdaysPerWeek = state.activityPlan.workdaysPerWeek;
        return state;
    }

    private static void rejectPlanEditsAfterComplete(User currentUser) {
        if (currentUser.External_LO_Onboarding_Complete__c == true) {
            throw new DomainException('Your weekly plan is locked. Ask an admin if you need to change it.');
        }
    }

    private static void applyCompletionFlag(User updateShell, User currentUser, Boolean completeOnboarding) {
        if (currentUser.External_LO_Onboarding_Complete__c == true) {
            updateShell.External_LO_Onboarding_Complete__c = true;
            return;
        }
        if (completeOnboarding == true) {
            updateShell.External_LO_Onboarding_Complete__c = true;
        }
    }

    private static Boolean isAllowedFocus(String label, List<String> focusOptions) {
        if (!String.isBlank(label) && focusOptions != null && focusOptions.contains(label)) {
            return true;
        }
        return ExternalLoActivityCatalog.focusByLabel(label) != null;
    }

    private static Map<String, GoalInput> indexGoalInputs(List<GoalInput> goals) {
        Map<String, GoalInput> byKey = new Map<String, GoalInput>();
        if (goals == null) {
            return byKey;
        }
        for (GoalInput input : goals) {
            if (input != null && !String.isBlank(input.activityKey)) {
                byKey.put(input.activityKey, input);
            }
        }
        return byKey;
    }

    private static Integer goalOrBaseline(Decimal userGoal, Decimal baselineGoal) {
        if (userGoal != null) {
            return userGoal.intValue();
        }
        return baselineGoal == null ? 0 : baselineGoal.intValue();
    }

    private static Decimal requireGoal(Integer goalValue, String label) {
        if (goalValue == null || goalValue < 0) {
            throw new DomainException('Enter a daily ' + label + ' goal of 0 or more.');
        }
        if (goalValue > 200) {
            throw new DomainException('Daily ' + label + ' goal must be 200 or fewer.');
        }
        return goalValue;
    }

    private static Integer requireWeeklyGoal(Integer goalValue, String label) {
        if (goalValue == null || goalValue < 0) {
            throw new DomainException('Enter a weekly ' + label + ' target of 0 or more.');
        }
        if (goalValue > 200) {
            throw new DomainException('Weekly ' + label + ' target must be 200 or fewer.');
        }
        return goalValue;
    }

    public class OnboardingState {
        @AuraEnabled public Boolean complete;
        @AuraEnabled public String businessFocus;
        @AuraEnabled public List<String> focusOptions;
        @AuraEnabled public List<ExternalLoActivityCatalog.FocusDefinition> focuses;
        @AuraEnabled public Integer callsGoal;
        @AuraEnabled public Integer textsGoal;
        @AuraEnabled public Integer emailsGoal;
        @AuraEnabled public Integer meetingsGoal;
        @AuraEnabled public Integer openHousesGoal;
        @AuraEnabled public String userName;
        @AuraEnabled public Integer workdaysPerWeek;
        @AuraEnabled public ExternalLoActivityPlanService.ActivityPlan activityPlan;
    }

    public class SaveRequest {
        @AuraEnabled public String businessFocus;
        @AuraEnabled public Integer callsGoal;
        @AuraEnabled public Integer textsGoal;
        @AuraEnabled public Integer emailsGoal;
        @AuraEnabled public Integer meetingsGoal;
        @AuraEnabled public Integer openHousesGoal;
        @AuraEnabled public Boolean completeOnboarding;
    }

    public class SaveRequestV2 {
        @AuraEnabled public String businessFocus;
        @AuraEnabled public Integer workdaysPerWeek;
        @AuraEnabled public Boolean completeOnboarding;
        @AuraEnabled public List<GoalInput> goals;
    }

    public class GoalInput {
        @AuraEnabled public String activityKey;
        @AuraEnabled public Integer weeklyTarget;
        @AuraEnabled public Boolean isEnabled;
    }
}