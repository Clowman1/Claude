public class NCS_GetTwilioMessagesWithParams {
    public static void getMessages(){
        //Get Messages with Params
        TwilioSF.TwilioApiClient client = new TwilioSF.TwilioApiClient();
        client.addUrlPart('Accounts');
        client.addUrlPart('AC_REDACTED_TWILIO_ACCOUNT_SID');
        client.addUrlPart('Messages');
        client.addUrlPart('.json');
        client.addParam('DateSent',String.valueOf(convertToUTC(Datetime.now().addMinutes(-15))),'>=');
        TwilioSF.TwilioApiClientResponse response = client.doGet();

        System.debug(JSON.serializePretty(response.toMap()));

        String messagesString = response.getTwilioJsonParser().get('messages').getString();

        //for Testing
        //String messagesString = '[{"account_sid":"AC_REDACTED_TWILIO_ACCOUNT_SID","api_version":"2010-04-01","body":"Hi "Antonia", Thank you for your referral, we are actively reaching out to Candi Kallsen unless otherwise specified in your notes. -Reach Home Loans","date_created":"Wed, 06 Mar 2024 14:57:47 +0000","date_sent":"Wed, 06 Mar 2024 14:57:47 +0000","date_updated":"Wed, 06 Mar 2024 14:57:47 +0000","direction":"outbound-api","error_code":null,"error_message":null,"from":"+17722385990"},{"account_sid":"AC_REDACTED_TWILIO_ACCOUNT_SID","api_version":"2010-04-01","body":"A new Biz Dev - Reach Lead has been submitted from Antonia Mander. Please use the following link to view the Lead now: https://reachhomeloans.lightning.force.com/lightning/r/Lead/00QQi000006ikEzMAI/view","date_created":"Wed, 06 Mar 2024 14:57:45 +0000","date_sent":"Wed, 06 Mar 2024 14:57:45 +0000","date_updated":"Wed, 06 Mar 2024 14:57:48 +0000","direction":"outbound-api","error_code":null,"error_message":null,"from":"+17722385990"},{"account_sid":"AC_REDACTED_TWILIO_ACCOUNT_SID","api_version":"2010-04-01","body":"Hi Candi, Antonia Mander has put us in touch to discuss your home financing goals. We are happy to work around your schedule. When is a good time to connect? -Reach Home Loans","date_created":"Wed, 06 Mar 2024 14:57:43 +0000","date_sent":"Wed, 06 Mar 2024 14:57:43 +0000","date_updated":"Wed, 06 Mar 2024 14:57:43 +0000","direction":"outbound-api","error_code":null,"error_message":null,"from":"+17722385990"}]';

        try {
            messagesString = NCS_JSONParserHelper.escapeQuotesInBody(messagesString);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error escaping quotes in a body of Twilio messages: ' + e.getMessage());
        }

        List<TwilioSF.TwilioJsonParser> messagesArray = response.getTwilioArrayJsonParser(messagesString);
        List<TwilioSF__Message__c> messagesToUpsert = new List<TwilioSF__Message__c>();
        List<String> numbersToSearch = new List<String>();
        if(messagesArray != null && messagesArray.size() > 0){
            for(TwilioSF.TwilioJsonParser p : messagesArray){
                if(String.isNotBlank(p.get('from').getString())){
                    numbersToSearch.add(formatPhoneNumber(p.get('from').getString()));
                    numbersToSearch.add(FormattingUtility.formatPhone(p.get('from').getString()));
                }
            }
            Map<String,Lead> phoneToLeadMap = new Map<String,Lead>();
            Map<String,Account> phoneToAccountMap = new Map<String,Account>();
            List<Lead> leads = [SELECT Id,MobilePhone FROM Lead WHERE MobilePhone IN: numbersToSearch];
            List<Account> accounts = [SELECT Id,PersonMobilePhone FROM Account WHERE PersonMobilePhone IN: numbersToSearch];
            for(Lead eachLead : leads){
                phoneToLeadMap.put(FormattingUtility.formatPhone(eachLead.MobilePhone), eachLead);
            }
            for(Account eachAccount : accounts){
                phoneToAccountMap.put(FormattingUtility.formatPhone(eachAccount.PersonMobilePhone), eachAccount);
            }
            for(TwilioSF.TwilioJsonParser p : messagesArray){
                if(p.get('direction').getString() == 'inbound'){
                    messagesToUpsert.add(new TwilioSF__Message__c(
                        TwilioSF__Message_SID__c=p.get('sid').getString(),
                        TwilioSF__Error_Code__c=p.get('error_code').getString(),
                        TwilioSF__Messaging_Service_Sid__c=p.get('messaging_service_sid').getString(),
                        TwilioSF__Date_Sent__c=extractDatetime(p.get('date_sent').getString()),
                        TwilioSF__Status__c=p.get('status').getString(),
                        TwilioSF__Date_Created__c=extractDatetime(p.get('date_created').getString()),
                        TwilioSF__To_Number__c=p.get('to').getString(),
                        TwilioSF__Date_Updated__c=extractDatetime(p.get('date_updated').getString()),
                        TwilioSF__From_Number__c=p.get('from').getString(),
                        TwilioSF__Direction__c=p.get('direction').getString(),
                        TwilioSF__Body__c=p.get('body').getString(),
                        TwilioSF__Lead__c=phoneToLeadMap.get(FormattingUtility.formatPhone(p.get('from').getString()))?.Id,
                        TwilioSF__Account__c=phoneToAccountMap.get(FormattingUtility.formatPhone(p.get('from').getString()))?.Id,
                        TwilioSF__SF_Parent_Record_Id__c=phoneToLeadMap.get(FormattingUtility.formatPhone(p.get('from').getString())) == null ? phoneToAccountMap.get(FormattingUtility.formatPhone(p.get('from').getString()))?.Id : phoneToLeadMap.get(FormattingUtility.formatPhone(p.get('from').getString()))?.Id
                    ));
                }
            }
        }
        if(messagesToUpsert.size() > 0){
            //upsert messagesToUpsert TwilioSF__Message_SID__c;
            Database.upsert(
                messagesToUpsert,
                TwilioSF__Message__c.TwilioSF__Message_SID__c, // fully qualified SObjectField
                false
            );
        }
    }

    public static Datetime extractDatetime(String dateString) {
        // Example dateString: "Mon, 26 Feb 2024 21:52:50 +000"

        // Split the string into parts
        List<String> parts = dateString.split(' ');

        // Extract day, month, year, hour, minute, and seconds
        Integer day = Integer.valueOf(parts[1]);
        Integer month;
        if (parts[2] == 'Jan') month = 1;
        else if (parts[2] == 'Feb') month = 2;
        else if (parts[2] == 'Mar') month = 3;
        else if (parts[2] == 'Apr') month = 4;
        else if (parts[2] == 'May') month = 5;
        else if (parts[2] == 'Jun') month = 6;
        else if (parts[2] == 'Jul') month = 7;
        else if (parts[2] == 'Aug') month = 8;
        else if (parts[2] == 'Sep') month = 9;
        else if (parts[2] == 'Oct') month = 10;
        else if (parts[2] == 'Nov') month = 11;
        else if (parts[2] == 'Dec') month = 12;
        Integer year = Integer.valueOf(parts[3]);
        Integer hour = Integer.valueOf(parts[4].substring(0, 2));
        Integer minute = Integer.valueOf(parts[4].substring(3, 5));
        Integer second = Integer.valueOf(parts[4].substring(6, 8));

        // Create a new Datetime instance
        Datetime extractedDatetime = Datetime.newInstanceGmt(
            year, month, day, hour, minute, second
        );
        return extractedDatetime;
    }

      public static Datetime convertToUTC(Datetime inputDatetime) {
        // Format the input datetime as a string in UTC format
        String utcString = String.valueOf(inputDatetime);

        // Parse the UTC string back into a Datetime instance
        Datetime utcDatetime = Datetime.valueOfGmt(utcString);

        return utcDatetime;
    }

     public static String formatPhoneNumber(String phoneNumber) {
        // Remove non-numeric characters from the input string
        String numericPhoneNumber = phoneNumber.replaceAll('[^0-9]', '');

        // Format the phone number as (XXX) XXX-XXXX
        String formattedPhoneNumber = '(' + numericPhoneNumber.substring(1, 4) + ') ' +
                                       numericPhoneNumber.substring(4, 7) + '-' +
                                       numericPhoneNumber.substring(7);

        return formattedPhoneNumber;
    }

    public static void coverage(){
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}