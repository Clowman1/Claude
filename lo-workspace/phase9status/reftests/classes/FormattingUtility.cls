public class FormattingUtility {
    // Text (non-Phone type) fields that also hold phone numbers.
    private static final Map<SObjectType, List<String>> TEXT_PHONE_FIELDS = new Map<SObjectType, List<String>>{
        Lead.SObjectType => new List<String>{ 'Agent_Phone__c' },
        Transaction__c.SObjectType => new List<String>{ 'Borrower_Home_Phone__c' }
    };
    // Twilio needs E.164 here; User.Extension is not a full number.
    private static final Set<String> SKIP_FIELDS = new Set<String>{ 'TwilioSF__Twilio_Personal_Number__c', 'Extension' };
    private static final Map<SObjectType, List<String>> phoneFieldsByType = new Map<SObjectType, List<String>>();

    // US numbers (10 digits, or 11 with a leading 1) become xxx-xxx-xxxx. Anything else
    // (extensions, international, notes typed into the field) is returned untouched.
    public static String formatPhone(String phone){
        if(String.isBlank(phone) || !phone.trim().containsOnly('0123456789 ()+-.')){
            return phone;
        }
        String digits = phone.replaceAll('[^0-9]', '');
        if(digits.length() == 11 && digits.startsWith('1')){
            digits = digits.substring(1);
        }
        if(digits.length() != 10){
            return phone;
        }
        return digits.substring(0,3) + '-' + digits.substring(3,6) + '-' + digits.substring(6);
    }

    // Called from before insert/update triggers: formats every editable phone field on the records.
    public static void formatPhoneFields(List<SObject> records){
        if(records == null || records.isEmpty()){
            return;
        }
        List<String> fields = phoneFields(records[0].getSObjectType());
        for(SObject record : records){
            for(String field : fields){
                String value = (String) record.get(field);
                String formatted = formatPhone(value);
                if(formatted != value){
                    record.put(field, formatted);
                }
            }
        }
    }

    private static List<String> phoneFields(SObjectType sObjType){
        if(!phoneFieldsByType.containsKey(sObjType)){
            List<String> fields = new List<String>();
            for(SObjectField f : sObjType.getDescribe().fields.getMap().values()){
                DescribeFieldResult d = f.getDescribe();
                if(d.getType() == DisplayType.PHONE && d.isUpdateable() && !d.isCalculated() && !SKIP_FIELDS.contains(d.getName())){
                    fields.add(d.getName());
                }
            }
            if(TEXT_PHONE_FIELDS.containsKey(sObjType)){
                fields.addAll(TEXT_PHONE_FIELDS.get(sObjType));
            }
            phoneFieldsByType.put(sObjType, fields);
        }
        return phoneFieldsByType.get(sObjType);
    }
}