@isTest
private class ExternalLoOnboardingServiceTest {

    @testSetup
    static void setupData() {
        ExternalLoPortalTestHelper.grantPortalAccess(UserInfo.getUserId());
    }

    @isTest
    static void getState_returnsBaselineGoalsBeforeOnboarding() {
        ExternalLOBaselineHelper.baselineOverride = new External_LO_Baseline__mdt(
            Calls_Daily_Goal__c = 8,
            Texts_Daily_Goal__c = 4,
            Emails_Daily_Goal__c = 3,
            Meetings_Daily_Goal__c = 1,
            Open_House_Daily_Goal__c = 0,
            Business_Focus_Options__c = 'Realtor Relationships;Purchase Pipeline'
        );

        User subject = ExternalLoPortalTestHelper.createOnboardingSubject();
        System.runAs(subject) {
            Test.startTest();
            ExternalLoOnboardingService.OnboardingState state = ExternalLoWorkspaceController.getOnboardingState();
            Test.stopTest();

            System.assertEquals(false, state.complete, 'New users should need onboarding.');
            System.assertEquals(8, state.callsGoal, 'Unsaved goals should default from metadata.');
            System.assertEquals(2, state.focusOptions.size());
        }
    }

    @isTest
    static void save_persistsPerUserGoalsAndLocksEdits() {
        ExternalLOBaselineHelper.baselineOverride = new External_LO_Baseline__mdt(
            Calls_Daily_Goal__c = 10,
            Texts_Daily_Goal__c = 5,
            Emails_Daily_Goal__c = 5,
            Meetings_Daily_Goal__c = 1,
            Open_House_Daily_Goal__c = 0,
            Business_Focus_Options__c = 'Realtor Relationships;Purchase Pipeline;Refinance;Past Clients'
        );

        User subject = ExternalLoPortalTestHelper.createOnboardingSubject();
        System.runAs(subject) {
            Test.startTest();
            ExternalLoOnboardingService.OnboardingState state = ExternalLoWorkspaceController.saveOnboarding(
                'Purchase Pipeline',
                6,
                2,
                1,
                1,
                0,
                true
            );
            Test.stopTest();

            System.assertEquals(true, state.complete);
            System.assertEquals('Purchase Pipeline', state.businessFocus);
            System.assertEquals(6, state.callsGoal);

            User stored = [
                SELECT Business_Focus__c, Calls_Daily_Goal__c, External_LO_Onboarding_Complete__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
            ];
            System.assertEquals('Purchase Pipeline', stored.Business_Focus__c);
            System.assertEquals(6, stored.Calls_Daily_Goal__c.intValue());
            System.assertEquals(true, stored.External_LO_Onboarding_Complete__c);
        }
    }

    @isTest
    static void save_rejectsInvalidFocusAndSecondEdit() {
        ExternalLOBaselineHelper.baselineOverride = new External_LO_Baseline__mdt(
            Calls_Daily_Goal__c = 1,
            Texts_Daily_Goal__c = 1,
            Emails_Daily_Goal__c = 1,
            Meetings_Daily_Goal__c = 1,
            Open_House_Daily_Goal__c = 0,
            Business_Focus_Options__c = 'Realtor Relationships;Refinance'
        );

        User subject = ExternalLoPortalTestHelper.createOnboardingSubject();
        System.runAs(subject) {
            Boolean invalidCaught = false;
            try {
                ExternalLoWorkspaceController.saveOnboarding('Not A Real Focus', 1, 1, 1, 1, 0, false);
            } catch (AuraHandledException error) {
                invalidCaught = true;
                System.assert(error.getMessage().contains('focus'), 'Invalid focus should be explained to the user.');
            }
            System.assertEquals(true, invalidCaught, 'Invalid focus must fail.');

            ExternalLoWorkspaceController.saveOnboarding('Refinance', 1, 1, 1, 1, 0, true);

            // Plans stay editable after setup (LO Workspace decision 2026-09-30, Q14).
            ExternalLoWorkspaceController.saveOnboarding('Realtor Relationships', 9, 9, 9, 9, 0, false);
            User edited = [SELECT Business_Focus__c, External_LO_Onboarding_Complete__c FROM User WHERE Id = :UserInfo.getUserId()];
            System.assertEquals('Realtor Relationships', edited.Business_Focus__c, 'Focus can change after setup.');
            System.assertEquals(true, edited.External_LO_Onboarding_Complete__c, 'Editing never un-completes setup.');
        }
    }

    @isTest
    static void saveV2_persistsWeeklyPlanAndLocksAfterComplete() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        System.runAs(importer) {
            ExternalLoOnboardingService.SaveRequestV2 request = new ExternalLoOnboardingService.SaveRequestV2();
            request.businessFocus = 'Grow new referral partners';
            request.workdaysPerWeek = 4;
            request.completeOnboarding = true;
            request.goals = new List<ExternalLoOnboardingService.GoalInput>{
                goalInput('realtor-outreach', 25, true),
                goalInput('consumer-conversation', 8, true),
                goalInput('social-engagement', 20, false),
                goalInput('past-client-call', 3, true),
                goalInput('partner-meeting', 4, true)
            };

            Test.startTest();
            ExternalLoOnboardingService.OnboardingState state = ExternalLoWorkspaceController.saveOnboardingV2(
                request.businessFocus,
                request.workdaysPerWeek,
                request.completeOnboarding,
                JSON.serialize(request.goals),
                null,
                null,
                null
            );
            Test.stopTest();

            System.assertEquals(true, state.complete);
            System.assertEquals(4, state.workdaysPerWeek);
            System.assertEquals('Grow new referral partners', state.businessFocus);
            Map<String, ExternalLoActivityPlanService.PlanRow> byKey = new Map<String, ExternalLoActivityPlanService.PlanRow>();
            for (ExternalLoActivityPlanService.PlanRow row : state.activityPlan.rows) {
                byKey.put(row.activityKey, row);
            }
            System.assertEquals(25, byKey.get('realtor-outreach').weeklyTarget);
            System.assertEquals(false, byKey.get('social-engagement').isEnabled);
            System.assertEquals(
                ExternalLoGoalMath.dailyTarget(25, 4),
                byKey.get('realtor-outreach').dailyTarget,
                'Daily target is ceil(weekly / workdays).'
            );
            System.assertNotEquals(null, ExternalLoWorkspaceController.getActivityPlan());

            // Plans stay editable after setup (Q14): a re-save with 5 workdays must succeed and keep setup complete.
            ExternalLoWorkspaceController.saveOnboardingV2(request.businessFocus, 5, false, JSON.serialize(request.goals), null, null, null);
            User edited = [SELECT ExtLO_Workdays_Per_Week__c, External_LO_Onboarding_Complete__c FROM User WHERE Id = :UserInfo.getUserId()];
            System.assertEquals(5, edited.ExtLO_Workdays_Per_Week__c, 'Workdays can change after setup.');
            System.assertEquals(true, edited.External_LO_Onboarding_Complete__c, 'Editing never un-completes setup.');
        }
    }

    private static ExternalLoOnboardingService.GoalInput goalInput(String activityKey, Integer weekly, Boolean enabled) {
        ExternalLoOnboardingService.GoalInput input = new ExternalLoOnboardingService.GoalInput();
        input.activityKey = activityKey;
        input.weeklyTarget = weekly;
        input.isEnabled = enabled;
        return input;
    }

    @isTest
    static void selectPortalProfile_standardUserWithoutPermsetUsesFlsFallback() {
        User bareUser = ExternalLoPortalTestHelper.createStandardUser('nops');
        User profileRecord;
        System.runAs(bareUser) {
            Test.startTest();
            profileRecord = UserRepository.getInstance().selectPortalProfile(bareUser.Id);
            Test.stopTest();
        }
        System.assertNotEquals(null, profileRecord, 'FLS fallback must still return the running user.');
        System.assertEquals(
            true,
            profileRecord.External_LO_Onboarding_Complete__c,
            'Internal users missing portal FLS must not be sent through Partner Workspace setup.'
        );
    }

    @isTest
    static void saveOnboardingV2_bindsPrimitivesAndGoalsJson() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
        System.runAs(importer) {
            // Aura binds a nested DTO parameter as an empty instance, which
            // silently dropped businessFocus. The controller now takes
            // primitives plus a goals JSON string, so this guards the contract.
            System.assertEquals(
                0,
                ExternalLoWorkspaceController.parseGoals(null).size(),
                'A blank goals payload yields an empty list, not a null.'
            );
            System.assertEquals(0, ExternalLoWorkspaceController.parseGoals('   ').size());

            List<ExternalLoOnboardingService.GoalInput> parsed = ExternalLoWorkspaceController.parseGoals(
                '[{"activityKey":"realtor-outreach","weeklyTarget":25,"isEnabled":true}]'
            );
            System.assertEquals(1, parsed.size());
            System.assertEquals('realtor-outreach', parsed[0].activityKey);
            System.assertEquals(25, parsed[0].weeklyTarget);
            System.assertEquals(true, parsed[0].isEnabled);

            Test.startTest();
            ExternalLoOnboardingService.OnboardingState state = ExternalLoWorkspaceController.saveOnboardingV2(
                'Deepen existing partners',
                3,
                true,
                '[{"activityKey":"realtor-outreach","weeklyTarget":12,"isEnabled":true}]',
                4,
                1200000,
                10
            );
            System.assertEquals(4, state.monthlyUnitGoal, 'Production goals come back in the state');
            System.assertEquals(1200000, state.monthlyVolumeGoal);
            System.assertEquals(10, state.targetRealtorCount);
            External_LO_Plan_Change__c change = [SELECT User__c, Summary__c FROM External_LO_Plan_Change__c ORDER BY CreatedDate DESC LIMIT 1];
            System.assertEquals(UserInfo.getUserId(), change.User__c, 'Each save leaves a plan snapshot for managers');
            System.assert(change.Summary__c.contains('Monthly loans: 4'), change.Summary__c);
            Test.stopTest();

            System.assertEquals('Deepen existing partners', state.businessFocus,
                'The focus must survive the Aura parameter binding.');
            System.assertEquals(true, state.complete);
            System.assertEquals(3, state.workdaysPerWeek);
        }
    }
}