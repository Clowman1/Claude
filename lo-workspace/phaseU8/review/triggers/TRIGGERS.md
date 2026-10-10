# U8 review: Lead triggers, managed packages, rules on insert of a recycled Lead

Read-only review against Production, 2026-10-08. Retrieved sources are under `force-app/main/default`
(triggers, handler classes, Lead validation rules, Lead duplicate rules). Nothing was deployed or changed.

Scenario: Apex inserts a clone of the borrower's converted Lead, with Status `Pre-Approval`,
OwnerId = Transaction `Loan_Officer__c`, Loan Partner carried over, and `Recycled_From_Transaction__c` set.
That field **does not exist yet** (checked via describe).

## Key conclusion

- **No Apex Lead trigger sends anything on insert for this lead except `ManualLeadOwnerNotification`.** It emails
  the new owner "New Salesforce Lead".
- **`LeadLoanPartnerAssignment` can overwrite the Loan Partner you carry over.**
- **One validation rule will block 16% of the inserts:** `Lead_Rating_and_Loan_Amount_Fields_requr` (Pre-Approval
  with a blank `Loan_Amount__c`).
- **All three managed Lead triggers are inert for an insert.** TwilioSF and smagicinteract are update-only.
  ActiveCampaign's package licence is Disabled.
- **The real messaging risk is outside triggers.** Record-triggered flows on Lead insert, the `CommSent_*`-driven
  comms and the Scheduled_Message__c cadence are all flows, which is another reviewer's scope. Anything a flow does
  to *update* the new lead in the same transaction re-fires the update triggers listed below.

## Trigger inventory (tooling ApexTrigger, TableEnumOrId = Lead, all Active)

| Trigger | Events | Fires on our insert? |
|---|---|---|
| LeadTrigger | **after insert**, after update | yes. The task's "after update only" assumption is wrong. |
| ReachNewLeadWebhook | after insert, after update | yes, but no-op (see below) |
| ManualLeadOwnerNotification | after insert | **yes, sends email** |
| LeadLoanPartnerAssignment | before insert, before update | **yes, may overwrite Loan_Partner__c** |
| LeadBdAttribution | before insert, before update | yes, may rewrite Biz_Dev__c |
| PhoneFormatLead | before insert, before update | yes, harmless |
| LeadStatusWebhook | after update | no |
| ConsumerWebinarLeadStatusWebhook | after update | no |
| BizDevReachPreApprovalWebhook | after update | no |
| ConsumerWebinarDocsWebhook | after update | no |
| LeadConvertedTransactionSync | after update | no |
| LeadConversionGuard | before update | no |
| LeadConversionCarryForward | after update | no |
| ExternalLoRestampLead | after update | no |
| ActiveCamp.lead | before/after insert/update | fires, but the package is unlicensed (see section 2) |
| TwilioSF.LeadTrigger | before/after **update** only | no |
| smagicinteract.updateRelatedListTrigger | after **update** only | no |

## 1. Unmanaged triggers in detail

### Insert path

**ManualLeadOwnerNotification** → `ManualLeadOwnerNotificationService.notifyOwners`
- Sends a `Messaging.sendEmail` "New Salesforce Lead - '<name>'" to `Owner.Email`, from OWEA reachus@.
  `setSaveAsActivity(false)`, so no EmailMessage or Task is created.
- Eligibility: OwnerId is a User (005) AND `ReferralFormSourceEmail__c` is blank.
- **Will fire for most recycled leads** (owner = LO user). It is suppressed today only if the source Lead had a
  ReferralFormSourceEmail__c, which is copied by the clone.
- Skip: check at the top of `notifyOwners`. The static flag is sufficient, because this is insert-only and
  same-transaction. A field check (`Recycled_From_Transaction__c != null`) in `isEligible` is equally clean and
  durable.

**LeadLoanPartnerAssignment** → `LeadLoanPartnerAssignmentService.stampFromOwnerAssignments`
- Before insert: for a User owner, it sets `Loan_Partner__c = Owner's User.Loan_Partner__c`.
- It is **only overwritten when that User field is non-null.** A null result is skipped and the supplied value is
  kept.
- Correction to the brief: nothing is hard-coded to Nimbus. Today only 4 active users have a default:
  - Zachary Fritz, Adam Stephens and Brandon Brotsky → Megan Straight
  - Joe Olmsted → Joey D'Alessandro
- So a recycled lead owned by one of those four would have its carried-over Loan Partner replaced.
- Skip: static flag at the top of `stampFromOwnerAssignments`. Insert-only concern, same transaction.
- Alternative without touching it: insert, then update `Loan_Partner__c`. That update then must pass
  `Loan_Partner_Reassignment_Restricted` (below), so the flag is cleaner.

**LeadTrigger** (after insert branch) → `LeadLoanPartnerShareTriggerHandler.handleAfterInsertOrUpdate`
- Creates a Manual/Edit LeadShare for `Loan_Partner__c` and `Other_Lead_Team_Member__c` when they are not the
  owner. This goes through `LoanPartnerLeadShareService`, as a queueable plus Database.insert, and logs to
  Custom_Log__c.
- **Silent, no notifications. Do NOT skip.** Lead OWD is Private, so without it the Loan Partner cannot see the
  recycled lead.
- The update branch (`LeadSmsOptOutSchMsgTrigHandler`) is update-only. It acts only when
  `Opt_Out_from_SMS_Automation__c` flips.

**ReachNewLeadWebhook** → `ReachNewLeadWebhookSvc.enqueueQualifiedLeads`
- Zapier callout (hooks/catch/449994/4uj6r8l), queueable.
- Fires only when `Biz_Dev__c = 'Biz Dev - Reach'` AND `Status = 'New'` AND `BDR_New_Webhook_Sent__c = false`.
  On update, it also requires that the lead was not already qualified.
- **No-op for a Pre-Approval insert.** It would fire later if someone moved the recycled lead to `New`.
  1,638 of 3,092 converted leads are Biz Dev - Reach.
- Skip: field check in the loop. Copying `BDR_New_Webhook_Sent__c = true` onto the clone also suppresses it.

**LeadBdAttribution** (before insert)
- Not a message. If `BD_Attribution_Override__c` is false and the Buying Agent or Referral Source belongs to an
  active BD rep's book, it rewrites `Biz_Dev__c` to that rep's designation. It can also move a non-realtor
  Buying Agent into Referral_Source__c when ReferralFormSourceEmail__c is set.
- It skips `IsConverted` leads, but the clone is not converted, so it runs.
- Effect: the clone's Biz_Dev__c may differ from the source. `Biz_Dev__c` feeds the BizDev Pre-Approval webhook.
- Skip: static flag, if an exact clone is wanted. Otherwise accept it, since it is today's correct attribution.

**PhoneFormatLead** → `FormattingUtility.formatPhoneFields`. This only reformats phones to xxx-xxx-xxxx. Keep it.

### Update path (only relevant if something updates the recycled lead: same-transaction flows, later edits, async jobs)

| Trigger | Fires when | Effect |
|---|---|---|
| LeadStatusWebhook (`LeadStatusZapierWebhookService`) | Status moves from New/Contact Attempt 1-5 to a non-early status; LeadSource is Website or *-Linktree; matching `Website_/Linktree_Status_Webhook_Sent__c` false | Zapier callout |
| ConsumerWebinarLeadStatusWebhook | same early→later transition, LeadSource 'Consumer Webinar', `Consumer_Webinar_Contacted_Webhook_Sent__c` false | Zapier callout |
| ConsumerWebinarDocsWebhook | Status → 'Documents Requested', LeadSource 'Consumer Webinar', `CW_Docs_Req_Webhook_Sent__c` false | Zapier callout |
| BizDevReachPreApprovalWebhook | Status changes **to** 'Pre-Approval' with Biz_Dev 'Biz Dev - Reach'; no sent-flag guard | Zapier callout |
| LeadConversionGuard | IsConverted false→true | addError if open Lead_Document_Request__c (would block re-conversion of the recycled lead later, by design) |
| LeadConversionCarryForward | `Converted_Transaction_ID__c` changes | moves docs/fields to that Transaction |
| LeadConvertedTransactionSync | converted-lead loan partner sync + App Summary snapshot | writes the Transaction |
| ExternalLoRestampLead | owner/team fields change to/from an External LO | restamps child records (queueable) |
| LeadTrigger (SMS opt-out branch) | Opt_Out_from_SMS_Automation__c flips | updates Scheduled_Message__c |

Notes:
- Inserting directly as Pre-Approval means none of the status webhooks fire at insert. **BizDevReachPreApproval
  is the dangerous one later**: it has no "already sent" flag, so any Pre-Approval → X → Pre-Approval round trip
  on a Biz Dev - Reach recycled lead posts to Zapier.
- **Do NOT copy `Converted_Transaction_ID__c`** (2,623 converted leads have it). A later edit of it would trigger
  CarryForward/TransactionSync against the cancelled Transaction. The clone must null it.
- Copying the `*_Webhook_Sent__c` and `CommSent_*` flags from the source (often already true) is a free secondary
  suppressor for the Apex webhooks and for whatever flows key on `CommSent_*`. Do not reset them to false.

### Recommended skip mechanism

- Use one helper, e.g. `LeadRecycleService.isRecycled(Lead l)`, returning
  `running || l.Recycled_From_Transaction__c != null`.
- **Static flag only:** LeadLoanPartnerAssignment and LeadBdAttribution, which are before-insert data rewrites.
  The flag also covers ManualLeadOwnerNotification.
- **Field check (durable):** the five Zapier webhook services (ReachNewLead, LeadStatus, ConsumerWebinarLeadStatus,
  ConsumerWebinarDocs, BizDevReachPreApproval). Async or later-transaction updates do not see the static flag.
- **Decision needed:** should the field check suppress these webhooks *forever*, or only until the LO works the
  lead? If only until then, gate on the flag plus the sent-flags copied from the source instead.
- **Leave untouched:** LeadTrigger share handler, PhoneFormatLead, the conversion triggers (they only act on
  conversion fields) and ExternalLoRestampLead.

### Triggers on related objects

- None of the Lead triggers create Task/Event/EmailMessage/Account/Contact records on insert, so the
  EmailMessage/Task/Call_Insight/Account triggers are not reached by the insert itself.
  - Active ones checked: EmailMessageTrigger, InitialItemsNeededSmsFromEmailMessage, TaskTrigger,
    ClientActivity*Router, ScheduledMessageAutoBlockOnLeadSmsOptOut, PhoneFormatAccount/Contact,
    ExternalLoStamp*.
  - **InitialItemsNeededSmsFromEmailMessage** would matter only if a flow emails the borrower, because it texts off
    EmailMessage inserts.
- Do not set DMLOptions assignment-rule or auto-response headers on the insert. Apex insert does not run Lead
  assignment or auto-response rules by default.

## 2. Managed package triggers

**ActiveCamp.lead** (before/after insert/update, body hidden)
- **PackageLicense ActiveCamp: Status = Disabled** (AllowedLicenses -1, UsedLicenses 0).
- The package's objects are unqueryable even as a System Admin ("sObject type 'ActiveCamp__Setup_Data__c' is not
  supported"), so its sync criteria (`Sync_Type__c`, `Sync_Criteria__c`, `Map_Standard_Lead__c`) **cannot be read**.
- The package's own scheduled job failed with "batchExecutor ... requires a license to use".
- Its only other async job, `leadDataBatch`, has sat in "Processing" since 2025-11-21. It was created by
  christian.mlteam@gmail.com ("Christian MarketingLogin"), now **inactive**.
- The hourly "ActiveCampaign Sync" CronTrigger is still WAITING (fires `0 0 * * * ?`) and is owned by that inactive
  user.
- No InboundLeadQueueable or LeadPostSyncQueueable runs exist. 52 Leads were inserted in the last 7 days without
  error.
- Conclusion: the ActiveCampaign Salesforce package is **dead in this org**. Its trigger does not break inserts and
  does not produce any sync jobs. Nothing to suppress, and no bypass setting is readable anyway.
  `ActiveCamp__Setup_Settings__c` is a protected custom setting, invisible.
- Residual risk: if ActiveCampaign is fed some other way (a Zapier "new Lead" Zap, or AC polling the API), that is
  outside Salesforce triggers. Check the Zapier account for Lead-created triggers into ActiveCampaign.
- Cleanup candidate: abort the orphan cron and uninstall. **Not done.**

**TwilioSF.LeadTrigger** (before/after **update** only, body hidden)
- **Does not fire on insert.** On update it maintains `TwilioSF__Unformatted_Phone__c` / `__Unformatted_Mobile__c`
  (LeadDomain/LeadSelector). It does not send messages itself.
- `TwilioSF__TriggerSettings__c` (hierarchy, protected) exists and is presumably the per-user/profile disable
  switch, but its fields and records are not readable via the API.
- The package licence is Active (19/20).
- Actual Twilio sends (`TwilioSendMessageQueue`, 374 runs; 456 TwilioSF__Message__c in 7 days) come from org
  automation, not this trigger: the "Create Twilio Messages 1-12" crons owned by sfupdates (Nimbus) and flows.
  That is flows scope.
- Copy the `TwilioSF__Unformatted_*` values with the clone, so they are right without needing an update.

**smagicinteract.updateRelatedListTrigger** (after **update** only)
- Does not fire on insert. It copies SMS history to converted records.
- The `Update_Related_Lists__c` custom setting has **0 records** (all off), and there were 0 smsMagic__c records
  in 90 days. Inert.

**Bottom line for packages:** nothing fires on insert that sends anything. No bypass setting is needed. Nothing we
could configure is readable anyway (protected settings).

## 3. Duplicate rules and validation rules on insert

### Duplicate rules (Lead)

| Rule | Active | Insert action | Notes |
|---|---|---|---|
| Custom_Lead_Duplicate_Rule | yes | **Allow**, Report | matches Person Account (Standard_PersonAccount_Match_Rule_v1_0) |
| Standard_Rule_for_Leads_with_Duplicate_Contacts | yes | **Allow**, Alert + Report | matches Contact; filter LeadSource != Website |
| Standard_Lead_Duplicate_Rule | no | - | - |

- Neither blocks. The clone **will** match the borrower's own Person Account and Contact, and "Report" will create
  DuplicateRecordSet/Item rows. This is cosmetic, but those duplicate reports will list every recycled lead.
- There is no duplicate rule against other Leads (the Lead-to-Lead rule is inactive), so the converted source Lead
  does not trigger anything.

### Active Lead validation rules (9)

`ISCHANGED()` is false on insert, so the seven rules built on it **cannot fire on insert**:

- No_Owner_Change_on_Leads
- Lead_already_claimed
- Calls_Required_for_Status_Change
- Lawrence_Lanos_Rule
- Loan_Officers_Cannot_Change_Owner
- Loan_Partner_Reassignment_Restricted
- Lead_Source_Change_Restricted

The Lead Source lock is therefore irrelevant to the insert. It would only bite an insert-then-update approach.

The rules that **do** evaluate on insert:

| Rule | Formula | Impact |
|---|---|---|
| **Lead_Rating_and_Loan_Amount_Fields_requr** | `ISPICKVAL(Status,'Pre-Approval') && ISBLANK(Loan_Amount__c)` | **BLOCKER.** 786 of 3,092 converted leads, and 431 of 2,623 with a Converted_Transaction_ID__c, have a blank Loan_Amount__c. No bypass permission. Fix: default `Loan_Amount__c` from the Transaction's **`Loan_Amount_1st__c`**. `Transaction__c.Loan_Amount__c` is a dead 0%-populated twin, so do not use it. Have a fallback (e.g. Base_Loan_Amount__c) or skip/flag the recycle if still blank. |
| Preapproval_Type_Mutual_Exclusion | `Zoom_Preapproval__c && In_Person_Preapproval__c` | 0 converted leads have both true. No risk. |

### Other insert-time hazards for a full-field clone

- Required on insert: only `LastName`. Company is not required, because Person Accounts are on.
- Unique fields: none. `AriveId__c` is an External ID, but **not unique**. A clone carrying it means any
  ARIVE/Zapier upsert-by-AriveId would hit 2 Leads (MULTIPLE_RECORDS error). Recommend nulling it on the clone,
  unless the ARIVE link is meant to move to the recycled lead.
- Non-createable fields (IsConverted, ConvertedAccountId/ContactId/Date, formulas, system fields) are ignored on
  insert from a queried clone. Build the clone from a describe of createable fields to be explicit.
- Must null: `Converted_Transaction_ID__c` (see above).
- Should keep: the `*_Webhook_Sent__c` and `CommSent_*` flags (they act as suppressors), `TwilioSF__Unformatted_*`,
  `Opt_Out_from_SMS_Automation__c` and `smagicinteract__SMSOptOut__c`.
