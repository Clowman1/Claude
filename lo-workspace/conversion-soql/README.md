# Conversion SOQL headroom fixes (2026-10-20)

Why: a Lead conversion measured 100/100 SOQL (Jhoana Carag dry run). Every Transaction__c save costs 7 SOQL even
when nothing changes, and a conversion saved the Transaction 4-5 times. Profile: side-session note conversion-soql-profile.md.

## Fix 1: write it at insert, not in follow-up saves
- `TransactionUtmCopyService.fillOnInsert` (called from the before-insert branch of `TransactionStatusSync`) writes UTMs and
  Loan Partner onto the new record. When the converted Lead is not yet linked (`Converted_Transaction_ID__c` null, meaning a
  conversion in progress), it also writes the subject property, Webinar_Date__c and App_Summary_Snapshot__c. Blank fields only.
  `LeadConversionFieldCarry` and `ApplicationSummaryService.snapshotOnConversion` then find nothing to update. Neither is changed.
- The after-insert UTM copy (which did its own `update`) is gone. On update it now runs only when Borrower_Name__c or Account__c changes.
- `LeadDocumentCarryForwardService` no longer calls `BorrowerPortalService.populateMissingPortalHashes`. Flow
  `Transaction_Set_Portal_Hash_Parameter` (AsyncAfterCommit, runs when the hash is null) already mints it.

## Fix 2: gate the always-on Transaction flows
- `Transaction_Share_With_Openers`, `Transaction_Share_With_Processors_Closers`: `NOT(ISBLANK(Id))` becomes
  `OR(ISNEW(), ISCHANGED(OwnerId))`. Manual shares are only lost on an owner change.
- `Transaction_Stamp_Webinar_Date_From_Converted_Lead`: now runs only when its criteria newly become true.

## Deploy
Flows land as Draft in prod. Activate the new versions with a FlowDefinition activeVersionNumber deploy.
Tests: TransactionUtmCopyServiceTest LeadDocumentCollectionServiceTest LeadConditionAssignmentTest
ExternalLoPortalConversionFacadeTest LeadConversionFieldCarryTest ApplicationSummaryServiceTest LeadPortalSubmissionTest

`ref/` holds unchanged, freshly retrieved copies for reading only. Do not deploy them.

## Measuring headroom
`measure-conversion-soql.apex` runs the conversion and then rolls it back, reporting SOQL use. Baseline after these fixes: 72 of 100 (2026-10-20, Jhoana Carag and Madilynn Hershberger). Re-run it after adding any automation on Lead update, Transaction__c insert/update, Condition__c insert or Lead_Document_Request__c update.

## Early warning (deployed 2026-10-20, 0AfQi000001VGPhKAO)
`ExternalLoPortalConversionFacade.warnIfNearSoqlLimit` runs after each successful LO Workspace conversion. When the conversion used
85 or more SOQL queries (`soqlAlertThreshold`), it emails clowman@reachhomeloans.com. It spends no SOQL and swallows every error.
The Convert_Lead screen flow and Convert_Lead_to_Person_Account_on_TRID_Date are NOT covered.
