# Conversion wall time (2026-10-26)

Lead conversion took 30-60 s, mostly Task work (profile: side-session note conversion-wall-time-profile.md).

## Deployed 2026-10-26
Flows 0AfQi000001VewfKAC, activation 0AfQi000001VeyHKAS.
- Task_Stamp_Last_RC_Call_SMS_on_Account v4: runs only on new Tasks, a change of rcsfl__call_start_time__c, or a WhoId change that is not a lead conversion (prior WhoId 00Q).
- Task_Stamp_Last_RC_Call_SMS_on_Transaction v10: same idea; it skips the conversion move from Opportunity (006) to Transaction.
- Lead_Conversion_Relate_Activity_To_Transaction v2: the Task re-point now runs on a Run Asynchronously path after commit.

`ref/` = the versions that were active before (Account v3, Transaction v9, Relate v1). Do not deploy.

## Rollback
`sf project deploy start --target-org Production --metadata-dir rollback --test-level RunSpecifiedTests --tests ExternalLoPortalConversionFacadeTest`
