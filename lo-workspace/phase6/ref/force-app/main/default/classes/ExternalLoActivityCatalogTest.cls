@isTest
private class ExternalLoActivityCatalogTest {

    @isTest
    static void overrideInjectionReturnsActiveCatalog() {
        ExternalLoActivityCatalog.activityOverride = null;
        ExternalLoActivityCatalog.focusOverride = null;
        ExternalLoActivityCatalog.ActivityDefinition outreach = new ExternalLoActivityCatalog.ActivityDefinition();
        outreach.activityKey = 'realtor-outreach';
        outreach.categoryApiName = 'Realtor_Outreach';
        outreach.isActive = true;
        outreach.creditActivityTypes = new List<String>{ 'Call - Prospecting' };
        outreach.sortOrder = 1;
        ExternalLoActivityCatalog.ActivityDefinition inactive = new ExternalLoActivityCatalog.ActivityDefinition();
        inactive.activityKey = 'legacy';
        inactive.categoryApiName = 'Legacy';
        inactive.isActive = false;
        ExternalLoActivityCatalog.activityOverride = new List<ExternalLoActivityCatalog.ActivityDefinition>{
            outreach,
            inactive
        };

        Test.startTest();
        List<ExternalLoActivityCatalog.ActivityDefinition> active = ExternalLoActivityCatalog.activeActivities();
        ExternalLoActivityCatalog.ActivityDefinition byKey = ExternalLoActivityCatalog.activityByKey('realtor-outreach');
        String category = ExternalLoActivityCatalog.categoryForActivityType('Call - Prospecting');
        String activityType = ExternalLoActivityCatalog.activityTypeForCategory('Realtor_Outreach');
        Test.stopTest();

        System.assertEquals(1, active.size(), 'Inactive catalog rows stay out of the active list.');
        System.assertEquals('realtor-outreach', byKey.activityKey);
        System.assertEquals('Realtor_Outreach', category, 'Credit_Activity_Types back-credits historical Tasks.');
        System.assertEquals('Call - Prospecting', activityType);
        System.assertEquals(null, ExternalLoActivityCatalog.activityByKey('missing'));
        System.assertEquals(null, ExternalLoActivityCatalog.activityByCategory(null));
        System.assertEquals(null, ExternalLoActivityCatalog.categoryForActivityType(null));
        System.assertEquals(null, ExternalLoActivityCatalog.activityTypeForCategory('Missing'));
        ExternalLoActivityCatalog.activityOverride = null;
    }

    @isTest
    static void orgMetadataMapsRecordsAndFocuses() {
        ExternalLoActivityCatalog.activityOverride = null;
        ExternalLoActivityCatalog.focusOverride = null;

        Test.startTest();
        List<ExternalLoActivityCatalog.ActivityDefinition> orgActivities = ExternalLoActivityCatalog.activities();
        List<ExternalLoActivityCatalog.FocusDefinition> orgFocuses = ExternalLoActivityCatalog.focuses();
        List<ExternalLoActivityCatalog.FocusDefinition> activeFocuses = ExternalLoActivityCatalog.activeFocuses();
        ExternalLoActivityCatalog.ActivityDefinition outreach = ExternalLoActivityCatalog.activityByKey('realtor-outreach');
        ExternalLoActivityCatalog.FocusDefinition grow = ExternalLoActivityCatalog.focusByLabel('Grow new referral partners');
        String credited = ExternalLoActivityCatalog.categoryForActivityType('Open House');
        Test.stopTest();

        System.assert(orgActivities.size() >= 5, 'Seed CMDT or fallback must expose five categories.');
        System.assertNotEquals(null, outreach);
        System.assertEquals('Realtor_Outreach', outreach.categoryApiName);
        System.assert(outreach.creditActivityTypes.contains('Call - Prospecting'));
        System.assert(orgFocuses.size() >= 3);
        System.assert(activeFocuses.size() >= 3);
        System.assertNotEquals(null, grow);
        System.assertEquals(25, grow.weeklyPresets.get('realtor-outreach'));
        System.assertEquals('Partner_Meeting', credited, 'Open House back-credits partner meetings.');
        System.assertEquals(null, ExternalLoActivityCatalog.focusByLabel(null));
    }

    @isTest
    static void hardcodedFallbacksStayDeploySafe() {
        Test.startTest();
        List<ExternalLoActivityCatalog.ActivityDefinition> activities = ExternalLoActivityCatalog.defaultActivities();
        List<ExternalLoActivityCatalog.FocusDefinition> focuses = ExternalLoActivityCatalog.defaultFocuses();
        ExternalLoActivityCatalog.FocusDefinition inactive = new ExternalLoActivityCatalog.FocusDefinition();
        inactive.label = 'Legacy';
        inactive.isActive = false;
        ExternalLoActivityCatalog.focusOverride = new List<ExternalLoActivityCatalog.FocusDefinition>{ inactive };
        List<ExternalLoActivityCatalog.FocusDefinition> active = ExternalLoActivityCatalog.activeFocuses();
        Test.stopTest();

        System.assertEquals(5, activities.size());
        System.assertEquals(3, focuses.size());
        System.assertEquals('Grow new referral partners', active[0].label);
        ExternalLoActivityCatalog.focusOverride = null;
    }
}