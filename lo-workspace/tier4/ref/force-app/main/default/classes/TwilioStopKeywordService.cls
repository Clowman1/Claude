/**
 * An inbound text whose whole message is an opt-out keyword (STOP, UNSUBSCRIBE, ... see
 * LoWsAutoTextService.STOP_WORDS) opts that person out of every SMS automation in the org (decided 2026-10-20):
 *   - Lead: Opt_Out_from_SMS_Automation__c (the opt-out pill, Scheduled Messages) + smagicinteract__SMSOptOut__c
 *     (Lead_Automation flows).
 *   - Person Account: SMS_Opt_Out__c (SMS campaigns, birthday/anniversary texts, LO Workspace texts).
 * Applied to the Lead/Account the message is linked to AND every open Lead / Person Account with that number.
 * The Twilio_Message Process Builder stays: it also flags Lead_Responded_to_Text__c and forwards to the owner.
 *
 * Queueable so heavy Lead/Account automation can never fail the inbound message insert.
 * START does not clear these flags (they may also have been set by hand); LoWsAutoTextService honours a later START.
 */
public without sharing class TwilioStopKeywordService implements Queueable {
    private final Set<Id> messageIds;

    public TwilioStopKeywordService(Set<Id> messageIds) {
        this.messageIds = messageIds;
    }

    /** After insert on TwilioSF__Message__c. */
    public static void onInsert(List<TwilioSF__Message__c> rows) {
        Set<Id> stops = new Set<Id>();
        for (TwilioSF__Message__c m : rows) {
            if (m.TwilioSF__Direction__c == 'inbound'
                    && LoWsAutoTextService.STOP_WORDS.contains(LoWsAutoTextService.keyword(m.TwilioSF__Body__c))) {
                stops.add(m.Id);
            }
        }
        if (stops.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new TwilioStopKeywordService(stops));
        } else {
            System.debug(LoggingLevel.ERROR, 'TwilioStopKeywordService: no queueable left for ' + stops);
        }
    }

    public void execute(QueueableContext context) {
        apply(messageIds);
    }

    @TestVisible
    static void apply(Set<Id> ids) {
        Set<Id> leadIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<String> numbers = new Set<String>();
        for (TwilioSF__Message__c m : [
            SELECT TwilioSF__Lead__c, TwilioSF__Account__c, TwilioSF__From_Number_Unformatted__c
            FROM TwilioSF__Message__c WHERE Id IN :ids
        ]) {
            if (m.TwilioSF__Lead__c != null) leadIds.add(m.TwilioSF__Lead__c);
            if (m.TwilioSF__Account__c != null) accountIds.add(m.TwilioSF__Account__c);
            String d = LoWsAutoTextService.digits(m.TwilioSF__From_Number_Unformatted__c);
            if (d != null) numbers.add(d);
        }
        Set<String> variants = ExternalLoPhoneNormalizer.soqlVariants(numbers);

        List<Lead> leads = new List<Lead>();
        for (Lead l : [
            SELECT Id FROM Lead
            WHERE (Id IN :leadIds OR (IsConverted = false AND (MobilePhone IN :variants OR Phone IN :variants)))
              AND (Opt_Out_from_SMS_Automation__c = false OR smagicinteract__SMSOptOut__c = false)
            LIMIT 200
        ]) {
            leads.add(new Lead(Id = l.Id, Opt_Out_from_SMS_Automation__c = true, smagicinteract__SMSOptOut__c = true));
        }
        List<Account> accounts = new List<Account>();
        for (Account a : [
            SELECT Id FROM Account
            WHERE (Id IN :accountIds OR (IsPersonAccount = true AND (PersonMobilePhone IN :variants OR Phone IN :variants)))
              AND SMS_Opt_Out__c = false
            LIMIT 200
        ]) {
            accounts.add(new Account(Id = a.Id, SMS_Opt_Out__c = true));
        }
        log(leads, Database.update(leads, false));
        log(accounts, Database.update(accounts, false));
    }

    private static void log(List<SObject> rows, List<Database.SaveResult> results) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'TwilioStopKeywordService could not opt out ' + rows[i].Id + ': ' + results[i].getErrors());
            }
        }
    }
}