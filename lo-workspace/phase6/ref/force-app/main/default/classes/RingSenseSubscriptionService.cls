/**
 * Lists and re-registers the RingSense webhook subscription. Adapter callouts only; DML is Custom_Log on failure.
 */
public without sharing class RingSenseSubscriptionService {
    private static final String LOG_SOURCE = 'RingSense Subscription';

    public class SubscriptionView {
        @AuraEnabled public String id;
        @AuraEnabled public String status;
        @AuraEnabled public String expirationTime;
        @AuraEnabled public String address;
        @AuraEnabled public String eventFilters;
    }

    public class StatusResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Datetime lastCallInsightCreatedDate;
        @AuraEnabled public Decimal hoursSinceLastInsight;
        @AuraEnabled public List<SubscriptionView> subscriptions;
        public StatusResult() {
            this.success = true;
            this.subscriptions = new List<SubscriptionView>();
        }
    }

    public static StatusResult getStatus() {
        StatusResult result = buildHealth();
        try {
            String token = getAccessToken();
            RingCentralApi_Models.SubscriptionListResponse listed = new RingCentralApi.ListSubscriptions(token).consume();
            result.subscriptions = toViews(listed);
            result.message = result.subscriptions.isEmpty() ? 'No subscriptions returned.' : 'Subscriptions loaded.';
        } catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
            logFailure(e);
        }
        return result;
    }

    public static StatusResult reregister() {
        StatusResult result = buildHealth();
        try {
            RingSense_Webhook_Config__mdt cfg = requireConfig();
            String token = getAccessToken();
            RingCentralApi_Models.SubscriptionListResponse listed = new RingCentralApi.ListSubscriptions(token).consume();
            RingCentralApi_Models.SubscriptionRecord match = findMatching(listed, cfg);
            String bodyJson = JSON.serialize(buildCreateRequest(cfg));
            RingCentralApi_Models.SubscriptionRecord saved;
            if (match != null && String.isNotBlank(match.id) && 'Active'.equalsIgnoreCase(match.status)) {
                saved = new RingCentralApi.RenewSubscription(token, match.id, bodyJson).consume();
                result.message = 'Renewed subscription ' + saved.id + '.';
            } else {
                saved = new RingCentralApi.CreateSubscription(token, bodyJson).consume();
                result.message = 'Created subscription ' + saved.id + '.';
            }
            RingCentralApi_Models.SubscriptionListResponse refreshed = new RingCentralApi.ListSubscriptions(token).consume();
            result.subscriptions = toViews(refreshed);
        } catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
            logFailure(e);
        }
        return result;
    }

    private static StatusResult buildHealth() {
        StatusResult result = new StatusResult();
        result.lastCallInsightCreatedDate = CallInsightRepository.selectLatestCreatedDate();
        if (result.lastCallInsightCreatedDate != null) {
            Long ms = Datetime.now().getTime() - result.lastCallInsightCreatedDate.getTime();
            result.hoursSinceLastInsight = Decimal.valueOf(ms).divide(3600000, 2);
        }
        return result;
    }

    @TestVisible
    private static String getAccessToken() {
        RingSense_Webhook_Config__mdt cfg = requireConfig();
        List<Ring_Central_Auth_Extension__mdt> authRows = [
            SELECT Token__c
            FROM Ring_Central_Auth_Extension__mdt
            WHERE DeveloperName = :cfg.Auth_Extension_Developer_Name__c
            LIMIT 1
        ];
        if (authRows.isEmpty() || String.isBlank(authRows[0].Token__c)) {
            throw new IllegalArgumentException(
                'Missing JWT on Ring_Central_Auth_Extension__mdt.' + cfg.Auth_Extension_Developer_Name__c
            );
        }
        RingCentralApi_Models.GetAccessTokenRequest getTokenReq = new RingCentralApi_Models.GetAccessTokenRequest();
        getTokenReq.jvtToken = authRows[0].Token__c.trim();
        getTokenReq.grant_type = 'urn:ietf:params:oauth:grant-type:jwt-bearer';
        return new RingCentralApi.AuthenticateGetAccessToken(getTokenReq).consume();
    }

    private static RingSense_Webhook_Config__mdt requireConfig() {
        RingSense_Webhook_Config__mdt cfg = RingSense_Webhook_Config__mdt.getInstance('Default');
        if (cfg == null || String.isBlank(cfg.Webhook_Address__c) || String.isBlank(cfg.Event_Filter__c)) {
            throw new IllegalArgumentException('RingSense_Webhook_Config__mdt.Default is missing required fields.');
        }
        return cfg;
    }

    private static RingCentralApi_Models.CreateSubscriptionRequest buildCreateRequest(RingSense_Webhook_Config__mdt cfg) {
        RingCentralApi_Models.CreateSubscriptionRequest req = new RingCentralApi_Models.CreateSubscriptionRequest();
        req.eventFilters = new List<String>{ cfg.Event_Filter__c };
        req.expiresIn = cfg.Expires_In__c == null ? 315360000L : cfg.Expires_In__c.longValue();
        req.deliveryMode = new RingCentralApi_Models.SubscriptionDeliveryMode();
        req.deliveryMode.transportType = 'WebHook';
        req.deliveryMode.address = cfg.Webhook_Address__c;
        return req;
    }

    private static RingCentralApi_Models.SubscriptionRecord findMatching(
        RingCentralApi_Models.SubscriptionListResponse listed,
        RingSense_Webhook_Config__mdt cfg
    ) {
        if (listed == null || listed.records == null) {
            return null;
        }
        for (RingCentralApi_Models.SubscriptionRecord rec : listed.records) {
            if (isMatching(rec, cfg)) {
                return rec;
            }
        }
        return null;
    }

    private static Boolean isMatching(
        RingCentralApi_Models.SubscriptionRecord rec,
        RingSense_Webhook_Config__mdt cfg
    ) {
        if (rec == null || rec.deliveryMode == null || String.isBlank(rec.deliveryMode.address)) {
            return false;
        }
        if (rec.deliveryMode.address != cfg.Webhook_Address__c) {
            return false;
        }
        if (rec.eventFilters == null) {
            return false;
        }
        for (String filter : rec.eventFilters) {
            if (filter != null && (filter == cfg.Event_Filter__c || filter.containsIgnoreCase('ringsense'))) {
                return true;
            }
        }
        return false;
    }

    private static List<SubscriptionView> toViews(RingCentralApi_Models.SubscriptionListResponse listed) {
        List<SubscriptionView> views = new List<SubscriptionView>();
        if (listed == null || listed.records == null) {
            return views;
        }
        for (RingCentralApi_Models.SubscriptionRecord rec : listed.records) {
            SubscriptionView view = new SubscriptionView();
            view.id = rec.id;
            view.status = rec.status;
            view.expirationTime = rec.expirationTime;
            view.address = rec.deliveryMode == null ? null : rec.deliveryMode.address;
            view.eventFilters = rec.eventFilters == null ? null : String.join(rec.eventFilters, ', ');
            views.add(view);
        }
        return views;
    }

    private static void logFailure(Exception e) {
        String payload = e.getTypeName() + ': ' + e.getMessage() + ' | ' + e.getStackTraceString();
        if (payload.length() > 32000) {
            payload = payload.substring(0, 32000);
        }
        insert new Custom_Log__c(Source__c = LOG_SOURCE, Data__c = payload);
    }
}