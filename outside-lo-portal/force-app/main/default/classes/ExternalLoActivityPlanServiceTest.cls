@isTest
private class ExternalLoActivityPlanServiceTest {

    @testSetup
    static void setupCommunityUser() {
        User importer = ExternalLoPortalTestHelper.createCommunityOrStandardImporter();
        ExternalLoPortalTestHelper.grantPortalAccess(importer.Id);
    }

    @isTest
    static void missingRowsFallBackToCmdtDefaults() {
        User portalUser = [
            SELECT Id FROM User WHERE Alias = 'cimp' ORDER BY CreatedDate DESC LIMIT 1
        ];
        ExternalLoPortalTestHelper.grantPortalAccess(portalUser.Id);
        System.runAs(portalUser) {
            Test.startTest();
            ExternalLoActivityPlanService.ActivityPlan plan = ExternalLoActivityPlanService.getPlan(portalUser.Id);
            Test.stopTest();

            System.assertEquals(5, plan.workdaysPerWeek, 'Unset workdays clamp to 5.');
            System.assert(plan.rows.size() >= 5, 'Catalog defaults must populate a plan with no saved rows.');
            Map<String, Integer> weekly = ExternalLoActivityPlanService.weeklyTargetsByKey(plan);
            System.assert(weekly.containsKey('realtor-outreach'));
            ExternalLoActivityPlanService.PlanRow outreach;
            for (ExternalLoActivityPlanService.PlanRow row : plan.rows) {
                if (row.activityKey == 'realtor-outreach') {
                    outreach = row;
                }
            }
            System.assertEquals(
                ExternalLoGoalMath.dailyTarget(outreach.weeklyTarget, 5),
                outreach.dailyTarget
            );
        }
    }

    @isTest
    static void savedRowsOverrideDefaults() {
        User portalUser = [
            SELECT Id FROM User WHERE Alias = 'cimp' ORDER BY CreatedDate DESC LIMIT 1
        ];
        ExternalLoPortalTestHelper.grantPortalAccess(portalUser.Id);
        System.runAs(portalUser) {
            ExternalLoActivityGoalWriter.upsertGoals(
                portalUser.Id,
                new List<External_LO_Activity_Goal__c>{
                    new External_LO_Activity_Goal__c(
                        Activity_Key__c = 'realtor-outreach',
                        Weekly_Target__c = 10,
                        Is_Enabled__c = true
                    )
                }
            );

            Test.startTest();
            ExternalLoActivityPlanService.ActivityPlan plan = ExternalLoActivityPlanService.getPlan(portalUser.Id);
            Test.stopTest();

            ExternalLoActivityPlanService.PlanRow outreach;
            for (ExternalLoActivityPlanService.PlanRow row : plan.rows) {
                if (row.activityKey == 'realtor-outreach') {
                    outreach = row;
                }
            }
            System.assertEquals(10, outreach.weeklyTarget, 'Saved weekly target wins over CMDT default.');
            System.assertEquals(2, outreach.dailyTarget);
        }
    }

    @isTest
    static void portalProfileQueryCoversUserRepository() {
        User portalUser = [
            SELECT Id FROM User WHERE Alias = 'cimp' ORDER BY CreatedDate DESC LIMIT 1
        ];
        ExternalLoPortalTestHelper.grantPortalAccess(portalUser.Id);
        System.runAs(portalUser) {
            Test.startTest();
            System.assertEquals(null, UserRepository.getInstance().selectPortalProfile(null));
            User withPortal = UserRepository.getInstance().selectPortalProfile(portalUser.Id);
            User withoutPortal = UserRepository.getInstance().queryPortalProfile(portalUser.Id, false);
            Test.stopTest();
            System.assertEquals(portalUser.Id, withPortal.Id);
            System.assertEquals(portalUser.Id, withoutPortal.Id);
        }
    }

    @isTest
    static void portalProfileFallsBackForStandardUserWithoutFls() {
        User bareUser = ExternalLoPortalTestHelper.createStandardUser('bare');
        System.runAs(bareUser) {
            Test.startTest();
            User profileRecord = UserRepository.getInstance().selectPortalProfile(bareUser.Id);
            Test.stopTest();
            System.assertEquals(bareUser.Id, profileRecord.Id);
            System.assertEquals(
                true,
                profileRecord.External_LO_Onboarding_Complete__c,
                'Standard users missing portal FLS are treated as already set up.'
            );
        }
    }
}