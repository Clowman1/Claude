# U8 review: recycling a cancelled purchase loan into a new Lead

Read-only review against prod (`Production`), 2026-10-08. Nothing was deployed or changed.
Fresh retrieves are in `force-app/` next to this file. The other 78 Transaction flows and 40 Lead
flows were retrieved to scratch and grepped.

Data window: **"moved to Cancelled"** is taken from `Loan_Event__c` (Type `Status Changed`,
`New_Value__c = 'Cancelled'`). It is written by flow `Loan_Event_Status_Changed` and covers the
period since 2025-06-27. Last 12 months: 323 events, 293 with a live `Loan__c`, **273 distinct
Transactions**. 30 events point at deleted Transactions. `Transaction__History` also tracks
`Status__c` (79,497 rows), but NewValue can't be filtered in SOQL, so Loan_Event__c was used.

---

## TL;DR: blockers and design changes

| # | Issue | Impact | Fix |
|---|---|---|---|
| B1 | `Lead.AriveId__c` is **unique / external ID** | Cloning "all createable fields" makes the insert **fail** with DUPLICATE_VALUE. All 70 original leads checked have it. | Never copy it. |
| B2 | `Lead.Arive_Status__c = 'LOAN_SETUP'` on 212/222 original leads | Flow `Convert_Lead_to_Person_Account_on_TRID_Date` (after-save, **Create**AndUpdate) would **convert the new lead immediately and create a new Transaction** | Null `Arive_Status__c`. |
| B3 | ~35 of the 112 matching cancellations are **loan-number swaps, not real withdrawals**. The old file is cancelled and a new Transaction for the same borrower is created within seconds (mostly by Christopher Lowman; 2601…/7-digit to 1526…). 25 of them have BWR `Opted to Proceed with a Different Loan Application`. | A recycled lead would sit beside a live loan | Exclude that BWR value, **and** re-check after a delay that no other Transaction exists for the account created on or after the cancelled one (`System.enqueueJob(job, 10)`). |
| B4 | "No automations fire for the new lead" **cannot be guaranteed**. There is no bypass flag in any Lead flow or trigger. 31 Lead flows are Create/CreateAndUpdate, 13 custom and 3 managed Apex triggers (ActiveCamp `lead`, TwilioSF `LeadTrigger`, smagicinteract). | Emails, SMS and webhooks to the LO, buyer's agent and realtor | Scrub the trigger-condition fields on the clone (list in §8). Accept the harmless ones. To get a real "nothing fires", add a bypass condition to each flow (large change). |
| B5 | **Loan Partner cannot be carried at insert.** `LeadLoanPartnerAssignment` (before insert) and flow `Assign_Loan_Partner_on_Lead` (ISNEW) both overwrite it from `Owner.Loan_Partner__c`. A follow-up update hits validation rule `Loan_Partner_Reassignment_Restricted` unless the running user has `Loan_Partner_Reassignment` or the value equals the owner's mapping. | On the 112 matches: Transaction LP = new owner's mapping on 54, differs on 21, Transaction LP blank on 37 | Accept the owner's default LP, or run the insert as a user with the custom permission (e.g. a platform-event subscriber configured as an admin integration user). |
| B6 | `Transaction.Loan_Officer__c` is **inactive or a community user on 16/112** (Justin Waters ×10, Edgard Gonzalez, Alaina Pugh, Lauren Williams…) | Insert fails (inactive owner) | Fallback order: original lead owner if active, then skip and log. |
| B7 | `Portal_Hash_Parameter__c` exists on Lead and on `Borrower__c` | Copying it reuses the old pre-approval portal link | Don't copy. |

Recommended trigger rule (all must hold):
`Status__c` changed to `Cancelled` AND `Loan_Purpose__c = 'Purchase'` AND `Loan_Type_1st_TD__c != 'DPA 2nd'`
(and the record is not referenced by another Transaction's `Second_Mortgage__c`) AND BWR not blank AND BWR NOT IN
(`Selected an Alternative Lender`, `Found a More Competetive Interest Rate`, **`Opted to Proceed with a Different Loan Application`**)
AND `Withdrawn_Reason__c` NOT IN (`App Denied`, `Pre-Approval Denied`) AND no recycled lead already exists for this Transaction (idempotent),
then, after the 10-minute delay, no other Transaction exists on `Borrower_Name__c` with CreatedDate >= the cancelled one's CreatedDate.

Expected volume: **about 10 recycled leads a month** (see §3).

---

## 1. Finding the original Lead from a Transaction

Links that exist:
- `Lead.Converted_Transaction_ID__c` (lookup to Transaction__c). It is stamped by `Convert_Lead`, the TRID flow and the External LO portal after conversion.
- `Lead.ConvertedAccountId` = `Transaction__c.Borrower_Name__c` (the Person Account; non-null on all 273, and always a Person Account).
- `Transaction__c.Account__c`: set on only 1 of 273, and equal to Borrower_Name__c there. Useless.
- Lead lookups on Transaction__c: `Realtor_Buying_Agent_Lead__c`, `Realtor_Listing_Agent_Lead__c` (realtors) and `New_Follow_Up_Lead__c`. The last is written only by flow `Lead_Assign_Follow_Up_Lead_to_Transactions` for Past Client follow-up leads (`AccountFollowUpController`), and is populated on 14 Transactions. None of these point to the borrower's original lead.
- `ConvertedOpportunityId`: populated (conversions create Opportunities; 1,911 exist), but Opportunity has **no custom lookups**, so there is no path to Transaction. Not usable.

Coverage on the 273 Transactions cancelled in the last 12 months:

| Method | 0 leads | exactly 1 | 2+ |
|---|---|---|---|
| A: `Lead.Converted_Transaction_ID__c = Txn.Id` | 102 | **171** | 0 |
| B: `Lead.ConvertedAccountId = Txn.Borrower_Name__c` | 35 | 211 | 27 |
| `ConvertedAccountId = Txn.Account__c` | 272 | 0 | 1 |

- Every A lead also satisfies B (171/171 have ConvertedAccountId = Borrower_Name__c).
- "Most recently converted lead for the account" is **wrong in 4 of 23** multi-lead cases where A is known: the borrower converted again later for another loan, e.g. Rusciano and Gracie.
- Rule "latest ConvertedDate **≤ Txn.CreatedDate + 1 day**" picked the right lead in **171/171** cases where A is known.
- Combined: A finds 171, the B fallback adds 67 (59 single, 8 multi), **35 (13%) have no lead at all**. Those are mostly Realtor Referral or blank-source files created without a lead (2025: 18, 2026: 17).

**Recommended rule:**
1. `SELECT … FROM Lead WHERE Converted_Transaction_ID__c = :txnId ORDER BY ConvertedDate DESC LIMIT 1`
2. else `WHERE IsConverted = true AND ConvertedAccountId = :txn.Borrower_Name__c AND ConvertedDate <= :txn.CreatedDate.date()+1 ORDER BY ConvertedDate DESC, CreatedDate DESC LIMIT 1`
3. else skip and log; don't synthesise a lead from the Account.

`TransactionUtmCopyService` already uses the same A-then-B pattern.

## 2. Purchase detection

- **`Transaction__c.Loan_Purpose__c`** (picklist: Purchase | Refinance | HELOC | HELOAN). On the 273: Purchase 240, Refinance 26, HELOC 5, `Cash-Out Refinance` 1 (an inactive legacy value), null 1. Use `= 'Purchase'`.
- Record type is **channel**, not purpose: Correspondent 166, Brokered 107. Don't use it.
- `Purchase_Price__c` is set on 217/240 purchases (and on 5 non-purchases), so it isn't reliable. `Purchase_Date__c` (Contract Date) is set on only 7.
- `Refinance_Purpose_Picklist__c` exists but isn't needed.
- DPA seconds: `Loan_Type_1st_TD__c = 'DPA 2nd'` (6 cancelled overall, 1 in the match set). `DpaSecondTransactionStatusSync` copies the first's `Status__c` to the `Second_Mortgage__c` record in the same transaction, so a second goes Cancelled alongside its first. It does not copy BWR, so the BWR filter already excludes most seconds. Exclude them explicitly anyway.

## 3. Volume

`Borrower_Withdrawal_Reason__c` was **created 2025-12-30**, so it is blank on every cancellation before Jan 2026. Only Jan 2026 onward is meaningful.

By month of the first Cancelled event:

| Month | Cancelled | Purchase | Purchase w/ blank BWR | **Match rule (as specified)** | match with an original lead | match minus loan-number swaps |
|---|---|---|---|---|---|---|
| 2026-01 | 17 | 14 | 2 | 11 | 10 | 9 |
| 2026-02 | 16 | 13 | 1 | 10 | 10 | 5 |
| 2026-03 | 15 | 15 | 2 | 9 | 7 | 2 |
| 2026-04 | 22 | 19 | 3 | 8 | 8 | 5 |
| 2026-05 | 24 | 23 | 0 | 14 | 12 | 10 |
| 2026-06 | 42 | 39 | 3 | 24 | 20 | 16 |
| 2026-07 | 23 | 21 | 6 | 11 | 9 | 9 |
| 2026-08 | 25 | 21 | 1 | 14 | 12 | 12 |
| 2026-09 | 14 | 14 | 3 | 8 | 7 | 8 |
| 2026-10 (to 8th) | 6 | 5 | 1 | 3 | 3 | 1 |

- Last 6 full months (Apr–Sep): rule as specified **79 (about 13/month)**. With the original-lead requirement, 68. After removing same-borrower swaps, **60 (about 10/month)**.
- Blank BWR since Jan 2026: **29 of 224 cancellations (13%)**, purchases 22/198 (11%). Most blanks are `App Denied` or no Withdrawn Reason. The blank-BWR purchases with `App Withdrawn By Borrower` are the real lost recycles (47 over 12 months, mostly before BWR existed).
- BWR on the 273: blank 98, Selected an Alternative Lender 49, Property Did Not Pass Inspection 40, Different Loan Application 35, Chose Not to Proceed 18, Other 13, Different Property 10, Direct Purchase 4, Competitive Rate 3, Costs Too High 3.
- **Reversals:** 7 of 273 were cancelled and later restored (6 now Post-Closed; Kalentek went Funding to Cancelled to PC Review **today**). 4 of the 7 had a qualifying BWR. Handle this by deleting or flagging the recycled lead when the Transaction leaves Cancelled, or by deferring the recycle (the 10-minute delay catches same-session flips only).
- **Later Transaction on the same account:** 60 of 112 matches. 35 were created within 3 hours (swaps, B3); the rest 1–60 days later. A recycled lead converting later handles the slow ones naturally. The fast ones must be excluded.

## 4. Existing automation on Transaction cancel

**Trigger `TransactionStatusSync`** (before/after insert/update):
- before: `TransactionStatusAgeService.stampCurrentStatusSince` (status-since stamp).
- after: `TransactionUtmCopyService.copyFromConvertedLeads`, `PurchaseDefaultConditionService.ensureForPurchaseTransactions` (skips Cancelled), `LoanOfficerRecordSharingService.syncTransactionShares`.
- after update: `DpaSecondTransactionStatusSync.syncAfterUpdate`. It mirrors status to the DPA second and **already enqueues a Queueable** (`FinalStatusSyncJob`).

Nothing in the trigger reacts to Cancelled.

Other Transaction triggers: `ReachTxPostClosedWebhook`, `ExternalLoRestampTransaction`, `PhoneFormatTransaction`. None act on Cancelled.

**Flows** (all 80 active Transaction record-triggered flows were grepped for Cancelled, Withdrawn and Withdrawal):
- `Transaction_Create_Scheduled_Message_On_Status_Cancelled` (after update). Entry: Status changed to Cancelled, `Pre_Approval_Date__c` not null, `Withdrawn_Reason__c = 'App Withdrawn By Borrower'`, BWR ≠ `Selected an Alternative Lender` (blank passes). It calls `AccountSmsEnrollmentInvocable`, which calls `AccountSmsEnrollmentService`. That service **enrols the borrower's Person Account in the RingCentral SMS drip** `Account Pre-Approval Message` (first template "Pre-Approved Client – Follow-Up 1", execution flow `SMS_Campaign_Account_Pre_Approval_Autolaunched`). It sends only if:
  - the account owner is one of 8 usernames in `Account_SMS_Allowed_Owner__mdt` (Brotsky, Byron, Olmsted, Waters, Williams, Rebagliati, Straight, Fritz)
  - `Biz_Dev__c = 'Biz Dev - Reach'` (`Lead_Pre_Approval_Allowed_Biz_Devs__c`)
  - there is a mobile number
  - the account is not opted out
  - there is no unsent drip already
  
  **So yes: something already messages the borrower on cancel.** 61 of the 112 rule matches meet its Transaction criteria. In practice 3–9 accounts a month get enrolled (Apr–Sep 2026).
- `Transaction_Remove_Account_From_SMS_Campaign_On_Active` blocks unsent drip messages when any Transaction for the account moves to a non-Cancelled, non-Post-Closed, non-Suspended status. Converting the recycled lead into a new Transaction stops the drip. Working the lead does not.
- `Transaction_Stamp_Borrower_Withdrawal_Reason_on_Account` copies BWR to `Account.Borrower_Withdrawal_Reason__c` whenever BWR changes, regardless of status. Nothing else in the repo reads that Account field.
- `Loan_Event_Status_Changed` only logs `Loan_Event__c` rows (old and new status, entry and exit times). It is harmless and is the data source used here.
- `Brokered_Transaction_Notification` excludes Cancelled. Not relevant.

**Does anything already flip the converted Lead or the Account Type?** No. Nothing touches the original Lead. On the Account, only `Borrower_Withdrawal_Reason__c` is stamped; `Type__c` is not touched.

**Conflict or duplication with the recycle:**
- The recycle doesn't duplicate any record creation.
- **Messaging overlap:** about half the recycled borrowers would also be in the Account SMS drip, which is a separate "pre-approval nurture" track. The Lead drip `Lead_Create_Scheduled_Message_On_Status_Pre_Approval` is **Update-only** (Status changes to Pre-Approval, owner in 8 hard-coded IDs, not opted out). Inserting the lead at Pre-Approval doesn't fire it. If the LO later moves the lead off Pre-Approval and back, a second SMS track starts. Decide whether the recycle replaces the Account drip (e.g. block Account drip rows for recycled accounts) or coexists with it.

## 5. Conversion paths and how each chooses the Account

| Path | Account choice today | Change |
|---|---|---|
| **`ConvertLeadsInvocable`** (Apex) | `Datacloud.FindDuplicatesByIds` on the lead returns the **first Account match** from active Lead duplicate rules, then `lc.setAccountId`. `Custom_Lead_Duplicate_Rule` (Lead vs PersonAccount, Standard_PersonAccount_Match_Rule, **Allow/Report**). If there's no match, a new Person Account is created. | **One change here covers 3 of 4 paths.** Before the duplicate check, read `Recycled_From_Transaction__r.Borrower_Name__c` and `setAccountId` with it. Fall back to the existing duplicate logic. |
| Screen flow **`Convert_Lead`** (the LO's convert action) | Calls `ConvertLeadsInvocable` | none |
| Flow **`Convert_Lead_to_Person_Account_on_TRID_Date`** (Lead after-save; entry `Arive_Status__c = 'LOAN_SETUP'`, not converted, owner role ≠ External_Loan_Officer) | Calls `ConvertLeadsInvocable`. Then creates the Transaction (`Borrower_Name__c = $Record.ConvertedAccountId`), sets Account `Type__c` to Borrower/Realtor Account, re-points Enhanced Notes, stamps `Converted_Transaction_ID__c`. | none. Note that it re-types the existing Account to `Borrower Account`, which is fine. |
| **`ExternalLoPortalConversionFacade.confirmConversionWithReceived`** | Calls `ConvertLeadsInvocable.convertLeads`, then `createTransactionForConvertedLead` | none |
| Standard **Convert** button (Lightning) | User picks from the suggested matches or creates a new account. No code hook. 2 of 87 non-realtor conversions in the last 90 days lacked `Converted_Transaction_ID__c`, so this path is rarely used. | Safety net: in `LeadConversionGuardService` (before update, IsConverted false to true), `addError` when `Recycled_From_Transaction__c != null` and `ConvertedAccountId != Recycled_From_Transaction__r.Borrower_Name__c`. This catches every path. |
| Realtor "convert" (`RealtorLeadConvertService`) | Realtor record type only. Doesn't really convert. | n/a |
| Submission Form flows (`Loan_Origination_Submission_Form`, `…_Update_Transaction`, `Update_Transaction_on_Submission_Form_Creation`) | **Do not convert leads.** They create realtor/title Accounts and update the Transaction. | n/a |

Post-conversion Lead triggers and flows checked for "existing account" safety:
- `LeadConversionGuard`: blocks conversion while `Lead_Document_Request__c` rows are open. This also applies to the recycled lead (fine).
- `LeadConversionCarryForward`: documents and field carry.
  - `LeadDocumentCarryForwardService` already ignores Account files created before the lead, so it's repeat-borrower safe.
  - `LeadConversionFieldCarry` **overwrites** Person Account SSN, DOB, loan amount, income and value when the lead has values. Intended.
- `LeadConvertedTransactionSync`: Loan Partner sync. **Side effect:** at convert time `Converted_Transaction_ID__c` is still null, so it falls back to the *most recent Transaction on the Account*. That is the old cancelled loan, whose `Loan_Partner__c` can be overwritten with the new lead's Loan Partner. It's minor. Fix by skipping the account fallback when `Recycled_From_Transaction__c != null`. `ApplicationSummaryService.snapshotOnConversion` is keyed on `Converted_Transaction_ID__c` (fine).
- `Link_Borrowers_On_Lead_Conversion` (on `Converted_Transaction_ID__c` set) calls `BorrowerPersonAccountService.linkForTransactions`, which stamps `Transaction__c` on Borrower__c rows where `Lead__c = lead` and `Transaction__c = null`, and find-or-creates Person Accounts by email. Safe.
- Call Insights, activities, document requests and Submission_Form flows are all keyed on Lead Id or Opportunity Id. Safe.

The Person Account duplicate rule is `Allow`. Today 52 of 523 conversions in the last 12 months landed on a pre-existing account. 16 of 506 converted-lead emails already have more than one Person Account, so the duplicate-rule match can pick the wrong duplicate. This is why the explicit `setAccountId` is needed.

## 6. Co-borrowers: `Borrower__c`

Fields: `Lead__c` (Lead), `Transaction__c` (Transaction__c), `Account__c` (Person Account), `First_Name__c`, `Last_Name__c`, `Email__c`, `Phone__c`, `Relationship__c`, `Removed__c`, `Portal_Hash_Parameter__c`.
Triggers: `ExternalLoStampBorrower` and `PhoneFormatBorrower` (before insert/update).

The model is a single row per co-borrower: it is created on the Lead (`Lead__c`), and on conversion the **same row** gets `Transaction__c` stamped (`Lead__c` stays).

To copy: read `Borrower__c WHERE (Transaction__c = :txnId OR Lead__c = :origLeadId) AND Removed__c = false`, then insert new rows with:
- `Lead__c = newLead`
- `Transaction__c = null`
- First, Last, Email, Phone, Relationship and `Account__c` copied (`Account__c` keeps the Person Account, so `findOrCreate` skips it)
- `Portal_Hash_Parameter__c` **not** copied

Volume is tiny: **16 Borrower__c rows in the whole org**, a new feature. Legacy co-borrower data lives in the Lead and Person Account `__pc` fields (see memory: Person Account `__pc` is authoritative). Those come across with the field clone.

## 7. Field headroom

- Org is **Enterprise Edition**, so the limit is 500 custom fields per object.
- **Lead: 225 custom fields** (Tooling `CustomField` count; describe shows 214 visible). There is plenty of room for `Recycled_From_Transaction__c`.
- Transaction__c: **496/500** (it was 495 on 2026-09-28). Correct not to add anything there.
- `Lead.Follow_Up_Account__c` and `Transaction.New_Follow_Up_Lead__c` are an existing "follow-up lead" pattern for Past Client leads. Don't reuse them. `Lead_Assign_Follow_Up_Lead_to_Transactions` rewrites `New_Follow_Up_Lead__c` on **all** Transactions of the account when `LeadSource = 'Past Client'` and `Follow_Up_Account__c` is set. Leave `Follow_Up_Account__c` blank on the clone (it was blank on all 70 originals checked).

## 8. Clone hygiene: Lead automations that would fire on insert

Counts below are for the 70 original leads of matched Transactions found via `Converted_Transaction_ID__c`.

**Must null or override** (they break the insert or contact third parties):

| Field | Populated on originals | What fires if copied |
|---|---|---|
| `AriveId__c` | 70/70 | unique field, so the **insert fails** |
| `Arive_Status__c` | 70/70 (LOAN_SETUP) | TRID flow **auto-converts and creates a Transaction** |
| `Converted_Transaction_ID__c` | (createable) | conversion carry-forward, Link_Borrowers, Call Insights/Activity re-pointing **against the old Transaction** on the first update |
| `ReferralFormSourceEmail__c` | 24/70 | `Update_Lead_Information_on_New_Referral` (email, Custom_Log, platform event); `New_Referral_Lead_Send_Notification…` (scheduled email); `New_Lead_from_Realtor_Intake_Form` (**email + Twilio SMS to the agent**); `Realtor_Lead_Placeholder_Email` |
| `Appointment_Date_Time__c` | 62/70 | `Lead_to_Event_for_Appointments` creates a calendar **Event** |
| `Initial_Docs_Requested_Date__c` | 0/70 | `Lead_Notify_Buyers_Agent_Docs_Requested` (Twilio **SMS to buyer's agent**) |
| `Portal_Hash_Parameter__c` | | reuses the old portal link |
| `Pre_Approval_Date__c` | | overwritten to today anyway by `Stamp_Pre_Approval_Date_when_Status_is_Pre_Approval` (before-save, Status = Pre-Approval) |
| `Follow_Up_Account__c` | 0/70 | see §7 |
| `IsConverted`, `Status` | | set Status explicitly to `Pre-Approval` |

**Decide** (business call):
- `Realtor_Buying_Agent__c` (68/70) and `Referral_Source__c` (64/70). Copying them fires:
  - `Stamp_Last_Referral_Date_on_Account`, which moves the **realtor's "last referral date"**
  - `Lead_Branch_Assignment`
  - `Share_Leads_With_Lawrence_Lanos` (realtor group)
  - `Stamp_Referred_By…`
  - `LeadBdAttribution` (BD credit)
  
  Realtor and BD dashboards would double-count the referral. Filter recycled leads out of those reports via `Recycled_From_Transaction__c`.
- `LeadSource`: 2/70 are `Website`, which fires `Website_Lead_Internal_Notification` (internal Twilio SMS). 6 are `Past Client` (harmless unless `Follow_Up_Account__c` is set).
- `*_Webhook_Sent__c` flags: copying them as true suppresses re-sends. Keep copying them.

**Will fire regardless** (no bypass; mostly harmless):
- `ManualLeadOwnerNotification` (after insert) **emails the owner LO** when the owner is a user and `ReferralFormSourceEmail__c` is blank. Arguably a feature: the LO learns about the recycled lead.
- `LeadLoanPartnerAssignment` and `Assign_Loan_Partner_on_Lead` set or clear Loan Partner from the owner (B5).
- `LeadTrigger` (TwilioSF), `lead` (**ActiveCamp**, which may push the lead into ActiveCampaign marketing) and `updateRelatedListTrigger` (smagicinteract) are managed and can't be bypassed.
- `Lead_Event_Status_Changed` (log row), `Set_First_Contact_Date_on_Lead`, `Lead_Default_Scenario_Manager` (Consumer record types), `PhoneFormatLead`, `Flow_to_Force_Company_field_to_Empty`.
- `ReachNewLeadWebhook` only qualifies `Status = 'New'` and Biz Dev Reach, so it **won't fire** at Pre-Approval. `Shark_Tank_New_Lead` fires only for a queue owner (it won't).

Record type: 171 of the originals are `Consumer_Under_Contract_Lead_Record_Type` and 50 are `Consumer_Lead_record_type`. The recycled buyer is no longer under contract, so consider forcing `Consumer_Lead_record_type`. `Lead_Default_Scenario_Manager` fires for either.

## 9. Queueable notes

- Enqueue from `TransactionStatusSync` after update only when candidates exist. The cancel can arrive inside a Queueable: `DpaSecondTransactionStatusSync.FinalStatusSyncJob`, Zapier/ARIVE updates, and LO Workspace jobs. Guard with `Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()` and skip when `System.isBatch() || System.isFuture()`, or route through a platform event.
- The Queueable runs as the cancelling user (a processor, usually). The Lead insert then depends on that user's Lead create and FLS, unless the class is `without sharing` + `AccessLevel.SYSTEM_MODE`. The validation rule in B5 still applies.
- Make it idempotent: skip if a Lead with `Recycled_From_Transaction__c = txnId` exists. This covers re-cancels after reversals.
