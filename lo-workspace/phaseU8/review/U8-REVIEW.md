# U8 review – cancelled purchase loan → recycled Pre-Approval lead (2026-10-08)

Read-only. Nothing in prod was changed. Detail is in `flows/FLOWS.md`, `triggers/TRIGGERS.md`, `cancel/CANCEL.md`, `PROCESS_BUILDERS.md` and `ZAPS.md`.

## Size of it
- About **10 recycles a month**: Apr–Sep 2026 = 79 matches, 68 with an original lead found, 60 after removing loan-number swaps.
- `Borrower_Withdrawal_Reason__c` exists only since 2025-12-30. Blank reason = no recycle; 11% of purchase cancellations have no reason.

## How the pieces work (settled facts)
- **Purchase** = `Loan_Purpose__c = 'Purchase'`. Also exclude `Loan_Type_1st_TD__c = 'DPA 2nd'`, which is cancelled in lockstep with the first loan.
- **Finding the original lead:**
  1. The lead whose `Converted_Transaction_ID__c` is this loan.
  2. Otherwise, the latest lead converted into the borrower account by the loan's created date + 1 day. This was right 171/171 times where known.
  3. Otherwise skip. Coverage is 87%; the misses are mostly realtor-referral files with no lead.
- **Clone fields:**
  - Keep `AriveId__c`. It is an external ID and **not unique** (confirmed from describe).
  - Blank: `Arive_Status__c` (else the TRID flow converts the clone at once), `Converted_Transaction_ID__c`, `ReferralFormSourceEmail__c`, `Appointment_Date_Time__c`, `Initial_Docs_Requested_Date__c`, `Portal_Hash_Parameter__c`, `Follow_Up_Account__c`.
  - Keep the `CommSent_*` / `*_Webhook_Sent__c` flags and the SMS opt-outs.
  - Loan amount = original lead `Loan_Amount__c`, else the cancelled loan's `Loan_Amount_1st__c`.
- **Silencing:** there is no global bypass, so three layers:
  - The new field `Recycled_From_Transaction__c` in flow entry conditions.
  - A static flag in Apex triggers.
  - Clone hygiene above.

  What gets a guard:

  | Kind | What | Change |
  |---|---|---|
  | Flows | 9 must change: TRID convert, New-Referral reassignment + emails, Realtor Intake texts, still-in-queue email, status-change agent texts, website-lead internal SMS, docs-requested agent SMS, appointment Event, Loan Partner overwrite | Entry condition |
  | Process Builder | `Lead_Automation`: "A new lead is waiting!" texts to 10 users (23% of clones), and an FB-Refi borrower text | Formula guard |
  | Apex triggers | Owner "New Salesforce Lead" email, Loan Partner overwrite, BD re-attribution | Static flag |
  | Apex triggers | Lead Team share | Keeps running, so the Loan Partner can see the lead |
  | Managed packages | ActiveCampaign (licence disabled), Twilio and SMS-Magic (update-only) | None: inert on insert |
  | Zaps | "SF to Arive on New Lead": already stops because AriveId is present | Add a backup "not recycled" filter |
  | Zaps | "Docs Requested → GHL" | Needs the "not recycled" filter |

- **Loan Partner** can be carried over once the flow and the trigger are guarded.
- **Re-conversion into the same Person Account:**
  - One change in `ConvertLeadsInvocable` (`setAccountId` from the recycled loan's borrower) covers the screen flow, the TRID flow and the LO Workspace convert.
  - A check in `LeadConversionGuardService` covers the standard Convert button.
  - `LeadConvertedTransactionSyncService` must not fall back to the old cancelled loan.
- **Co-borrowers:** copy un-removed `Borrower__c` rows onto the new lead (16 rows exist org-wide).
- **Timing:** Queueable delayed 10 minutes. Skip if a newer loan exists for the borrower (loan-number swap) or if the loan is no longer Cancelled. Idempotent: skip if a lead with `Recycled_From_Transaction__c` = this loan exists.
- **Volume drawer:** exclude recycled leads from the new-lead count.

## Open decisions → see chat

## Decisions (user, 2026-10-08)
- **Q31** Exclusions stay exactly as set: Selected an Alternative Lender, Found a More Competetive Interest Rate, plus denials. Loan-number swaps were a past workaround, so no swap detection and no delay logic.
- **Q32** If both the lead's and the loan's amounts are blank, create the lead in **Nurture - Preapproval** instead. The validation rule only applies to Pre-Approval.
- **Q33** If the Transaction's Loan Officer is inactive or not a standard user: **do nothing** (no recycle, no fallback owner). Go-live forward only.
- **Q34** If a recycled loan is un-cancelled back to an active status, set its recycled lead to **Nurturing** with the note "Original loan was reactivated". Never delete it.
- **Q35** The existing RingCentral cancel drip runs alongside, untouched.
- **Q36** Copy the realtor. Skip `Stamp_Last_Referral_Date_on_Account` and `LeadBdAttribution` for the recycled lead.
- **Q37** **Keep the original Pre_Approval_Date__c.** Guard `Stamp_Pre_Approval_Date_when_Status_is_Pre_Approval` so it does not restamp the clone.
- **Q38** Only creation is silent; later status changes behave normally. The exception, per the recommendation: BizDevReachPreApprovalWebhook stays off for recycled leads (no already-sent guard).
- **Q39** I edit the two Zaps (add a "Recycled_From_Transaction__c does not exist" filter) after the field is deployed.
