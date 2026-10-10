# U8c – the recycle (2026-10-08)

Retrieved fresh from prod; `ref/` = untouched prod copies. Validation 0AfQi000001UMaPKAW: 29 tests, 0 failures.

| Class | Coverage |
|---|---|
| LeadRecycleService | 89% |
| ConvertLeadsInvocable | 85% |
| LeadConversionGuardService | 98% |
| LeadConvertedTransactionSyncService | 77% |
| LoWsVolumeService | 83% |
| TransactionStatusSync | 100% |

## What it does
- **Trigger:** `TransactionStatusSync` (after update) calls `LeadRecycleService.onTransactionUpdate`.
- **Recycle check:** when Status__c is Cancelled (on the status change or a later reason edit) and every condition below holds, it queues the recycle as its own transaction, so a recycle problem can never roll back the cancel.
  - Purchase loan, not a DPA 2nd.
  - Borrower reason set and not Alternative Lender / More Competitive Rate.
  - Not denied.
  - LO is an active standard user.
- **Job re-checks:** it re-checks all of the above, skips loans already recycled, and finds the original converted lead (Converted_Transaction_ID__c, else the latest converted into the borrower account by the loan date + 1 day).
- **Clone:**
  - Every createable field, except the intake / convert / appointment / portal triggers (`BLANKED`).
  - Keeps AriveId__c and the original Pre_Approval_Date__c.
  - Owner = the loan's LO.
  - Amount = lead amount, else the loan's Loan_Amount_1st__c. With neither, status is Nurture - Preapproval; otherwise Pre-Approval.
  - Recycled_From_Transaction__c set.
  - Inserted with LeadRecycleContext.silent, duplicate save allowed, and no assignment or auto-response rules.
- **After the insert:**
  - Co-borrowers (Borrower__c, not removed) copied onto the new lead.
  - One note "Back in pre-approval" (Lead Team note email suppressed).
  - One bell notification ("Lead Recycled" custom notification type) to the LO.
- **Reactivation:** a loan moving from Cancelled to any active status moves its open recycled lead to Nurturing, stamps Recycle_Reactivated_At__c (silent for flows) and adds a note.
- **Conversion:**
  - `ConvertLeadsInvocable` converts a recycled lead into the recycled loan's borrower account. This covers the TRID flow, the Convert screen flow and LO Workspace.
  - `LeadConversionGuardService` refuses any other account, which covers the standard Convert button.
  - `LeadConvertedTransactionSyncService` never falls back to the cancelled loan.
- **Volume drawer:** the new-lead count excludes recycled leads.

## Tests (LeadRecycleServiceTest)
- End-to-end cancel → recycle, with all field rules asserted.
- Idempotent on a later reason edit.
- Lender switch: no recycle.
- No amount → Nurture - Preapproval.
- Amount falls back to the loan.
- Reactivation → Nurturing.
- Re-convert lands in the same account; the standard convert into a new account is refused.
- Qualify-rule unit test.

Deployed 2026-10-09: 0AfQi000001UNppKAG (quick deploy of validation 0AfQi000001UMaPKAW). Go-live is forward only; nothing is backfilled.
