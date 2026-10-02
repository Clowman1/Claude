/**
 * Created by toma on 3/11/2022.
 */

public with sharing class RingCentralApi {
    public final static String IMPORT_URL = 'https://platform.ringcentral.com/restapi/v1.0/account/~/extension/~/sms';
    public final static String GET_TOKEN = 'https://platform.ringcentral.com/restapi/oauth/token'; 
	public final static String GET_USER_CALL_RECORDS = 'https://platform.ringcentral.com/restapi/v1.0/account/~/call-log?perPage=1000';
    public final static String GET_USER_MESSAGE_RECORDS = 'https://platform.ringcentral.com/restapi/v1.0/account/~/extension/~~/message-store?perPage=100';
    public final static String SUBSCRIPTION_URL = 'https://platform.ringcentral.com/restapi/v1.0/subscription';

    public class AuthenticateGetAccessToken extends RingCentralConsumer{
        public AuthenticateGetAccessToken(RingCentralApi_Models.GetAccessTokenRequest request){
            super(GET_TOKEN,'POST');
            String urlEncodedRequest =
                'grant_type=' + EncodingUtil.urlEncode(request.grant_type, 'UTF-8') +
                '&assertion=' + EncodingUtil.urlEncode(request.jvtToken, 'UTF-8');

            RingCentralAppAuth__c appCredentials = RingCentralAppAuth__c.getOrgDefaults();
            String clientId = appCredentials.ClientId__c;
            String clientSecret = appCredentials.ClientSecret__c;
            String authHeader = EncodingUtil.base64Encode(blob.valueOf(clientId+':'+clientSecret));
            this.request.setHeader('Authorization','Basic '+authHeader);
            this.request.setHeader('Content-Type','application/x-www-form-urlencoded');
            this.request.setBody(urlEncodedRequest);
        }
        public String consume(){
            send();
            RingCentralApi_Models.TokenResponse resBody =  (RingCentralApi_Models.TokenResponse) JSON.deserialize(this.response.getBody(),RingCentralApi_Models.TokenResponse.class);
            return resBody.access_token;
        }
    }

	public class GetUserCallRecords extends RingCentralConsumer{
		public GetUserCallRecords(String token, String nextURL, String dateFrom){
			super(nextURL == null ? GET_USER_CALL_RECORDS + (String.isEmpty(dateFrom) ? '':('&dateFrom=' + dateFrom)) : nextURL , 'GET');
			this.request.setHeader('ACCEPT','application/json');
			this.request.setHeader('Authorization','Bearer '+token);
		}
		 public RingCentralApi_Models.GetUserCallRecordsResponse consume(){
            send();
            if(this.response.getStatusCode() == 200){
				String resopnseStr = this.response.getBody().replace('from','fromObj');
				RingCentralApi_Models.GetUserCallRecordsResponse userCallLogResponse = (RingCentralApi_Models.GetUserCallRecordsResponse)JSON.deserialize(resopnseStr,RingCentralApi_Models.GetUserCallRecordsResponse.class);
                return userCallLogResponse;
            }else{
                return null;
            }
        }
	}

    public class GetUserMessageRecords extends RingCentralConsumer{
		public GetUserMessageRecords(String token, String nextURL, String extensionId, String dateFrom){
			super(nextURL == null ? GET_USER_MESSAGE_RECORDS.replace('~~', extensionId) + (String.isEmpty(dateFrom) ? '':('&dateFrom=' + dateFrom)) : nextURL , 'GET');
			this.request.setHeader('ACCEPT','application/json');
			this.request.setHeader('Authorization','Bearer '+token);
		}
		 public RingCentralApi_Models.MessageStoreResponse consume(){
            send();
            if(this.response.getStatusCode() == 200){
				String resopnseStr = this.response.getBody().replace('from','fromObj');
				RingCentralApi_Models.MessageStoreResponse userCallLogResponse = (RingCentralApi_Models.MessageStoreResponse)JSON.deserialize(resopnseStr,RingCentralApi_Models.MessageStoreResponse.class);
                return userCallLogResponse;
            }else{
                return null;
            }
        }
	}
    
    public class ListSubscriptions extends RingCentralConsumer {
        public ListSubscriptions(String token) {
            super(SUBSCRIPTION_URL, 'GET');
            this.request.setHeader('ACCEPT', 'application/json');
            this.request.setHeader('Authorization', 'Bearer ' + token);
        }
        public RingCentralApi_Models.SubscriptionListResponse consume() {
            send();
            return (RingCentralApi_Models.SubscriptionListResponse) JSON.deserialize(
                this.response.getBody(),
                RingCentralApi_Models.SubscriptionListResponse.class
            );
        }
    }

    public class CreateSubscription extends RingCentralConsumer {
        public CreateSubscription(String token, String bodyJson) {
            super(SUBSCRIPTION_URL, 'POST');
            this.request.setHeader('ACCEPT', 'application/json');
            this.request.setHeader('Content-Type', 'application/json');
            this.request.setHeader('Authorization', 'Bearer ' + token);
            this.request.setBody(bodyJson);
        }
        public RingCentralApi_Models.SubscriptionRecord consume() {
            send();
            return (RingCentralApi_Models.SubscriptionRecord) JSON.deserialize(
                this.response.getBody(),
                RingCentralApi_Models.SubscriptionRecord.class
            );
        }
    }

    public class RenewSubscription extends RingCentralConsumer {
        public RenewSubscription(String token, String subscriptionId, String bodyJson) {
            super(SUBSCRIPTION_URL + '/' + subscriptionId, 'PUT');
            this.request.setHeader('ACCEPT', 'application/json');
            this.request.setHeader('Content-Type', 'application/json');
            this.request.setHeader('Authorization', 'Bearer ' + token);
            this.request.setBody(bodyJson);
        }
        public RingCentralApi_Models.SubscriptionRecord consume() {
            send();
            return (RingCentralApi_Models.SubscriptionRecord) JSON.deserialize(
                this.response.getBody(),
                RingCentralApi_Models.SubscriptionRecord.class
            );
        }
    }

	/*
    public class SendSMSConsumer extends RingCentralConsumer{
        public SendSMSConsumer(Map<String,Object> request, String accountId, String extensionId, String token){
            super(String.format(IMPORT_URL, new List<String>{accountId, extensionId}), 'POST');
            this.request.setHeader('Authorization','Bearer '+token);
            this.request.setHeader('Content-Type','application/json');
            this.request.setHeader('ACCEPT','application/json');
            this.request.setBody(JSON.serialize(request));
        }
        public RingCentralApi_Models.SendSMSResponse consume(){
            send();
            if(this.response.getStatusCode() == 200){
                return (RingCentralApi_Models.SendSMSResponse) JSON.deserialize(this.response.getBody(),RingCentralApi_Models.SendSmsResponse.class);
            }else{
                return null;
            }
        }
    }
	*/
    public virtual class RingCentralConsumer extends RestApiConsumer{
        public RingCentralConsumer(String endpoint, String method){
            super(endpoint, method);
            //this.authStrategy = new RingCentralHeaders();
        }
    }
    public static String urlEncode(Map<String, String> vals) {
        String result = '';
        for(String thisKey : vals.keySet()) {
            result += thisKey+ '=' + vals.get(thisKey) + '&';
        }
        return result.removeEnd('&');
    }
	
}