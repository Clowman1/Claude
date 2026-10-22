/**
 * Reads External_LO_Activity__mdt and External_LO_Focus__mdt with hardcoded
 * fallbacks so Apex can deploy before seed records land.
 */
public with sharing class ExternalLoActivityCatalog {

    @TestVisible
    private static List<ActivityDefinition> activityOverride;

    @TestVisible
    private static List<FocusDefinition> focusOverride;

    public class ActivityDefinition {
        @AuraEnabled public String activityKey;
        @AuraEnabled public String categoryApiName;
        @AuraEnabled public String shortLabel;
        @AuraEnabled public String unitNoun;
        @AuraEnabled public String description;
        @AuraEnabled public String coachingNote;
        @AuraEnabled public String iconName;
        @AuraEnabled public String tone;
        @AuraEnabled public String cadence;
        @AuraEnabled public Integer defaultWeeklyTarget;
        @AuraEnabled public List<Integer> targetOptions;
        @AuraEnabled public Boolean requiresContact;
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public List<String> creditActivityTypes;
    }

    public class FocusDefinition {
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Map<String, Integer> weeklyPresets;
    }

    public static List<ActivityDefinition> activities() {
        if (activityOverride != null) {
            return cloneActivities(activityOverride);
        }
        List<ActivityDefinition> rows = new List<ActivityDefinition>();
        List<External_LO_Activity__mdt> records = new List<External_LO_Activity__mdt>(
            External_LO_Activity__mdt.getAll().values()
        );
        if (records.isEmpty()) {
            return defaultActivities();
        }
        records.sort(new ActivitySort());
        for (External_LO_Activity__mdt record : records) {
            rows.add(fromActivityRecord(record));
        }
        return rows;
    }

    public static List<ActivityDefinition> activeActivities() {
        List<ActivityDefinition> rows = new List<ActivityDefinition>();
        for (ActivityDefinition item : activities()) {
            if (item.isActive == true) {
                rows.add(item);
            }
        }
        return rows;
    }

    public static ActivityDefinition activityByKey(String activityKey) {
        if (String.isBlank(activityKey)) {
            return null;
        }
        for (ActivityDefinition item : activities()) {
            if (item.activityKey == activityKey) {
                return item;
            }
        }
        return null;
    }

    public static ActivityDefinition activityByCategory(String categoryApiName) {
        if (String.isBlank(categoryApiName)) {
            return null;
        }
        for (ActivityDefinition item : activities()) {
            if (item.categoryApiName == categoryApiName) {
                return item;
            }
        }
        return null;
    }

    public static String categoryForActivityType(String activityType) {
        if (String.isBlank(activityType)) {
            return null;
        }
        for (ActivityDefinition item : activities()) {
            if (item.creditActivityTypes != null && item.creditActivityTypes.contains(activityType)) {
                return item.categoryApiName;
            }
        }
        return null;
    }

    public static String activityTypeForCategory(String categoryApiName) {
        ActivityDefinition item = activityByCategory(categoryApiName);
        if (item == null || item.creditActivityTypes == null || item.creditActivityTypes.isEmpty()) {
            return null;
        }
        return item.creditActivityTypes[0];
    }

    public static List<FocusDefinition> focuses() {
        if (focusOverride != null) {
            return cloneFocuses(focusOverride);
        }
        List<FocusDefinition> rows = new List<FocusDefinition>();
        List<External_LO_Focus__mdt> records = new List<External_LO_Focus__mdt>(
            External_LO_Focus__mdt.getAll().values()
        );
        if (records.isEmpty()) {
            return defaultFocuses();
        }
        records.sort(new FocusSort());
        for (External_LO_Focus__mdt record : records) {
            rows.add(fromFocusRecord(record));
        }
        return rows;
    }

    public static List<FocusDefinition> activeFocuses() {
        List<FocusDefinition> rows = new List<FocusDefinition>();
        for (FocusDefinition item : focuses()) {
            if (item.isActive == true) {
                rows.add(item);
            }
        }
        if (rows.isEmpty()) {
            return defaultFocuses();
        }
        return rows;
    }

    public static FocusDefinition focusByLabel(String label) {
        if (String.isBlank(label)) {
            return null;
        }
        String needle = label.trim();
        for (FocusDefinition item : focuses()) {
            if (item.label == needle) {
                return item;
            }
        }
        return null;
    }

    private static ActivityDefinition fromActivityRecord(External_LO_Activity__mdt record) {
        ActivityDefinition item = new ActivityDefinition();
        item.activityKey = record.Activity_Key__c;
        item.categoryApiName = record.Category_Api_Name__c;
        item.shortLabel = record.Short_Label__c;
        item.unitNoun = record.Unit__c;
        item.description = record.Description__c;
        item.coachingNote = record.Coaching_Note__c;
        item.iconName = record.Icon_Name__c;
        item.tone = record.Tone__c;
        item.cadence = record.Cadence__c;
        item.defaultWeeklyTarget = record.Default_Weekly_Target__c == null
            ? 0
            : record.Default_Weekly_Target__c.intValue();
        item.targetOptions = splitIntegers(record.Target_Options__c);
        item.requiresContact = record.Requires_Contact__c == true;
        item.sortOrder = record.Sort_Order__c == null ? 0 : record.Sort_Order__c.intValue();
        item.isActive = record.Is_Active__c == true;
        item.creditActivityTypes = splitStrings(record.Credit_Activity_Types__c);
        return item;
    }

    private static FocusDefinition fromFocusRecord(External_LO_Focus__mdt record) {
        FocusDefinition item = new FocusDefinition();
        item.label = record.MasterLabel;
        item.description = record.Description__c;
        item.sortOrder = record.Sort_Order__c == null ? 0 : record.Sort_Order__c.intValue();
        item.isActive = record.Is_Active__c == true;
        item.weeklyPresets = new Map<String, Integer>{
            'realtor-outreach' => intOrZero(record.Preset_Realtor_Outreach__c),
            'consumer-conversation' => intOrZero(record.Preset_Consumer_Conversation__c),
            'social-engagement' => intOrZero(record.Preset_Social_Engagement__c),
            'past-client-call' => intOrZero(record.Preset_Past_Client_Call__c),
            'partner-meeting' => intOrZero(record.Preset_Partner_Meeting__c)
        };
        return item;
    }

    @TestVisible
    private static List<ActivityDefinition> defaultActivities() {
        return new List<ActivityDefinition>{
            buildActivity('realtor-outreach', 'Realtor_Outreach', 'Realtor outreach', 'touches', 'users', 'brand', 'daily', 20, '10;15;20;25;30', true, 1, 'Call - Prospecting;Call - Active Agent'),
            buildActivity('consumer-conversation', 'Consumer_Conversation', 'Consumer convos', 'conversations', 'phone', 'teal', 'daily', 10, '5;8;10;15;20', true, 2, 'Call - Prospecting;Call - Active Agent;Text'),
            buildActivity('social-engagement', 'Social_Engagement', 'Social posts', 'engagements', 'share-2', 'navy', 'daily', 15, '5;10;15;20;25', false, 3, 'Text;Email'),
            buildActivity('past-client-call', 'Past_Client_Call', 'Past clients', 'calls', 'history', 'success', 'daily', 5, '3;5;8;10;12', true, 4, 'Call - Prospecting;Call - Active Agent'),
            buildActivity('partner-meeting', 'Partner_Meeting', 'Partner meetings', 'meetings', 'handshake', 'warn', 'weekly', 3, '1;2;3;4;5', true, 5, 'Meeting (New Agent);Meeting (Active Agent);Open House')
        };
    }

    private static ActivityDefinition buildActivity(
        String activityKey,
        String categoryApiName,
        String shortLabel,
        String unitNoun,
        String iconName,
        String tone,
        String cadence,
        Integer weekly,
        String targetOptions,
        Boolean requiresContact,
        Integer sortOrder,
        String creditTypes
    ) {
        ActivityDefinition item = new ActivityDefinition();
        item.activityKey = activityKey;
        item.categoryApiName = categoryApiName;
        item.shortLabel = shortLabel;
        item.unitNoun = unitNoun;
        item.iconName = iconName;
        item.tone = tone;
        item.cadence = cadence;
        item.defaultWeeklyTarget = weekly;
        item.targetOptions = splitIntegers(targetOptions);
        item.requiresContact = requiresContact;
        item.sortOrder = sortOrder;
        item.isActive = true;
        item.creditActivityTypes = splitStrings(creditTypes);
        return item;
    }

    @TestVisible
    private static List<FocusDefinition> defaultFocuses() {
        return new List<FocusDefinition>{
            buildFocus('Grow new referral partners', 1, 25, 8, 20, 3, 4),
            buildFocus('Deepen existing partners', 2, 10, 10, 15, 5, 5),
            buildFocus('Mine my past-client base', 3, 8, 12, 10, 12, 2)
        };
    }

    private static FocusDefinition buildFocus(
        String label,
        Integer sortOrder,
        Integer realtor,
        Integer consumer,
        Integer social,
        Integer pastClient,
        Integer meeting
    ) {
        FocusDefinition item = new FocusDefinition();
        item.label = label;
        item.sortOrder = sortOrder;
        item.isActive = true;
        item.weeklyPresets = new Map<String, Integer>{
            'realtor-outreach' => realtor,
            'consumer-conversation' => consumer,
            'social-engagement' => social,
            'past-client-call' => pastClient,
            'partner-meeting' => meeting
        };
        return item;
    }

    private static List<Integer> splitIntegers(String raw) {
        List<Integer> values = new List<Integer>();
        for (String part : splitStrings(raw)) {
            if (part.isNumeric()) {
                values.add(Integer.valueOf(part));
            }
        }
        return values;
    }

    private static List<String> splitStrings(String raw) {
        List<String> values = new List<String>();
        if (String.isBlank(raw)) {
            return values;
        }
        for (String part : raw.split(';')) {
            String trimmed = part?.trim();
            if (!String.isBlank(trimmed)) {
                values.add(trimmed);
            }
        }
        return values;
    }

    private static Integer intOrZero(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    private static List<ActivityDefinition> cloneActivities(List<ActivityDefinition> source) {
        return source == null ? new List<ActivityDefinition>() : new List<ActivityDefinition>(source);
    }

    private static List<FocusDefinition> cloneFocuses(List<FocusDefinition> source) {
        return source == null ? new List<FocusDefinition>() : new List<FocusDefinition>(source);
    }

    private class ActivitySort implements Comparator<External_LO_Activity__mdt> {
        public Integer compare(External_LO_Activity__mdt left, External_LO_Activity__mdt right) {
            Decimal leftOrder = left.Sort_Order__c == null ? 0 : left.Sort_Order__c;
            Decimal rightOrder = right.Sort_Order__c == null ? 0 : right.Sort_Order__c;
            if (leftOrder > rightOrder) {
                return 1;
            }
            if (leftOrder < rightOrder) {
                return -1;
            }
            return 0;
        }
    }

    private class FocusSort implements Comparator<External_LO_Focus__mdt> {
        public Integer compare(External_LO_Focus__mdt left, External_LO_Focus__mdt right) {
            Decimal leftOrder = left.Sort_Order__c == null ? 0 : left.Sort_Order__c;
            Decimal rightOrder = right.Sort_Order__c == null ? 0 : right.Sort_Order__c;
            if (leftOrder > rightOrder) {
                return 1;
            }
            if (leftOrder < rightOrder) {
                return -1;
            }
            return 0;
        }
    }
}