// O3 backfill: stamp pre-O3 Twilio texts from the last 90 days. NOT RUN. Run only after the deploy.
// The O3 fields have no FLS for anyone (reads are system-mode Apex), so this script must not name them in static SOQL.
// Rows whose Lead lookup points at a converted lead cannot be saved (INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY); they are skipped and counted.
// The before-update trigger (ExternalLoStampTwilioMessage -> LoWsTextsService.stamp) does the work, so this
// just touches the rows: outbound first, then inbound (replies thread on the outbound phone keys).
// Run 9 times, oldest window first, editing START_DAYS_AGO each time: 90, 80, 70, ... 10.
//   sf apex run -o Production -f backfill-90d.apex
// ~60 texts/day, so a 10-day window is ~600 rows: well inside one transaction's limits.
// Side effects checked 2026-10-09: EDGE_Twilio_Message_Relate_To_Transaction only re-fires when Twilio's own
// lookup/number/parent/direction fields change (they do not here); the reply-alert and owner flows are create-only.
Integer START_DAYS_AGO = 90;
Datetime fromAt = Datetime.now().addDays(-START_DAYS_AGO);
Datetime toAt = fromAt.addDays(10);

List<TwilioSF__Message__c> outbound = [
    SELECT Id FROM TwilioSF__Message__c
    WHERE CreatedDate >= :fromAt AND CreatedDate < :toAt
      AND TwilioSF__Direction__c != 'inbound' AND TwilioSF__To_Number__c != null
    ORDER BY CreatedDate
];
Integer outFail = 0; for (Database.SaveResult r : Database.update(outbound, false)) { if (!r.isSuccess()) outFail++; }
List<TwilioSF__Message__c> inbound = [
    SELECT Id FROM TwilioSF__Message__c
    WHERE CreatedDate >= :fromAt AND CreatedDate < :toAt
      AND TwilioSF__Direction__c = 'inbound' AND TwilioSF__From_Number__c != null
    ORDER BY CreatedDate
];
Integer inFail = 0; for (Database.SaveResult r : Database.update(inbound, false)) { if (!r.isSuccess()) inFail++; }
System.debug(LoggingLevel.ERROR, 'O3 backfill ' + fromAt.date() + ' to ' + toAt.date() + ': outbound ' + outbound.size()
    + ' (skipped ' + outFail + '), inbound ' + inbound.size() + ' (skipped ' + inFail + ')');
