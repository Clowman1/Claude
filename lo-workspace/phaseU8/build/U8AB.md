# U8a + U8b – fields and silence guards (2026-10-08)

Retrieved fresh from prod 2026-10-08; `ref/` = untouched prod copies. Combined check-only validation: 0AfQi000001UMH3KAO (13 tests, 0 failures; LeadRecycleContext 100%, BD attribution 93%, partner assignment 94%, BizDev webhook 98%, owner notification 86%).

## U8a (`u8a/`): no behaviour change
- Lead fields:
  - `Recycled_From_Transaction__c`: lookup to Transaction__c, SetNull, related list "Recycled Leads".
  - `Recycle_Reactivated_At__c`: DateTime.
- Permission set `Lead_Recycle_Fields` (read both). Assign to Adam Stephens (the Zapier Salesforce connection, a System Administrator) and to Chris.
- Then add the Zap filter "Recycled_From_Transaction__c does not exist" to 169907490 (SF to Arive on New Lead) and 359372859 (Docs Requested → GHL).

## U8b (`u8b/`): inert until a recycled lead exists
- **`LeadRecycleContext.silent`** (new static flag). Early return in:
  - `ManualLeadOwnerNotificationService.notifyOwners` (owner email)
  - `LeadLoanPartnerAssignmentService.stampFromOwnerAssignments`
  - `LeadBdAttribution.apply`
- `BizDevReachPreApprovalWebhookService` skips any lead with `Recycled_From_Transaction__c` set (permanent).
- Test fix: `BizDevReachPreApprovalWebhookServiceTest` used the retired picklist value "Biz Dev - Pugh" and was already failing in prod. It now uses "Biz Dev - Fritz".
- **Permanent entry filter** `Recycled_From_Transaction__c IsNull` (creation-type flows):
  - New_Lead_from_Realtor_Intake_Form
  - New_Referral_Lead_Send_Notification_When_It_s_Still_In_Queue
  - Update_Lead_Information_on_New_Referral
  - Website_Lead_Internal_Notification
  - Lead_to_Event_for_Appointments
- **First-step decision `Recycle_Silent_Check`.** It ends the flow when `OR(AND(ISNEW(), Recycled_From_Transaction__c set), ISCHANGED(Recycle_Reactivated_At__c))`; otherwise it proceeds exactly as before. Applied to:
  - Assign_Loan_Partner_on_Lead
  - Convert_Lead_to_Person_Account_on_TRID_Date
  - Lead_Notify_Buyers_Agent_Docs_Requested
  - Lead_Status_Change_Message_Sends
  - Stamp_Pre_Approval_Date_when_Status_is_Pre_Approval (Q37: keep the original date)
  - Stamp_Last_Referral_Date_on_Account (Q36)
  - Lead_Assign_Follow_Up_Lead_to_Transactions
- **Process Builder `Lead_Automation`:** the "New Lead, Mobile is blank" (texts to 10 users) and "New Lead created from Twilio" formulas gain `ISBLANK(Recycled_From_Transaction__c)`.
- **Flow activation:** flows land as Draft; a FlowDefinition activeVersionNumber deploy is the second step. Active versions before the change are in `flow-versions-before.txt`, which is the rollback reference.

## U8a deployed 2026-10-08
- 0AfQi000001UMIfKAO: Recycled_From_Transaction__c, Recycle_Reactivated_At__c and permission set Lead_Recycle_Fields. Assigned to Adam Stephens (the Zapier Salesforce connection) and Chris.
- 0AfQi000001UMLtKAO: **Is_Recycled__c** formula checkbox (`NOT(ISBLANK(Recycled_From_Transaction__c))`), added to the permission set. Zapier samples omit blank lookups but include checkboxes.
- **Zap 359372859 Docs Requested → GHL**:
  - Published v3 "Skip recycled leads (Is Recycled filter, U8)". The main filter is now LeadSource = Consumer Webinar AND Is Recycled is false.
  - The path `gives[..]["Is_Recycled"]["c"]` is the same form the live GHL action already uses for Loan_Amount__c and Purchase_Price__c.
- **Zap 169907490 SF to Arive on New Lead: NOT finished.**
  - Its "New Record" samples all predate the fields, and no new Lead has arrived since the deploy (~7/day).
  - An unpublished draft holds two empty rules plus a "Modified Record" test sample. Live v19 is unchanged and still stops on AriveId (copied on recycle), so it is protected.
  - To finish: Find new records → select the new sample → set one empty rule to "Is Recycled C (Boolean) is false" → remove the other empty rule → publish.

## U8b deployed 2026-10-08
- 0AfQi000001UMNVKA4: Apex guards + 13 flow versions (as Draft). The flows had not changed since retrieve (versions matched `flow-versions-before.txt`).
- 0AfQi000001UMP7KAO: FlowDefinition activation. All 13 are now active on the new version; see `flow-versions-after.txt`. Rollback = redeploy FlowDefinition with the "before" numbers.
