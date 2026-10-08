# LO Workspace upgrades — build plan (2026-10-08)

Decisions: `UPGRADES-2026-10.md`. Mockups (all approved): https://claude.ai/artifact/LvBC73nTDw3iYbdZXzzr5T

Every phase: retrieve fresh from prod first, deploy only changed files, RunSpecifiedTests, test as the pilot `outsidelo.internal@reachhomeloans.com`, your sign-off before each prod deploy. Ordered lowest risk first; U8 is the only org-wide change.

| Phase | What | Touches | Risk |
|---|---|---|---|
| U1 | Removals & filters | Reminder pop-up, Credit expired, Needs update, Conditions | Low |
| U2 | My Loans tabs + board | Active / Closed / Cancelled, board default | Low |
| U3 | Weekly touch + Up Next | Touch rule, list sort, Open all modal | Medium |
| U4 | Notes B + Appraisal A | New note modal, appraisal tab | Low |
| U5 | Communications tab | Lead, Transaction, Person Account pages | Medium (data access) |
| U6 | Volume drawer | Right-edge tab, main screens only | Low |
| U7 | Other Contacts tab | Tagging, BD Industry values | Low |
| U8 | Cancel → Pre-Approval recycle | Transaction + Lead automation, all LOs | High |

## U1 — Removals & filters
- **Reminder pop-up:** set `UserPreferencesActivityRemindersPopup = false` and `UserPreferencesTaskRemindersCheckboxDefault = false` on every External Loan Officer role user, plus a User trigger step so new External LOs get it automatically. `LoWsCalendarService.createFollowUp` stops setting `IsReminderSet` on Tasks.
- **Credit expired:** remove the filter, badge and "Expires …" label (`externalLoPreApprovals`, `ExternalLoPortalService.mapPreApproval` / `derivePreApprovalStatus` / filters). `ExternalLOBaselineHelper.preApprovalReviewUrgency` drops its credit branch for External LOs only, because the same helper feeds Perfect Day for internal users.
- **Needs update:** `mapLoan` sets it only for `Status__c = 'Waiting On Loan Officer'`. Remove the 3-day stale prompts (`ExternalLoPromptService`, `PerfectDayHomeBuilder`) for External LOs. The "Status since" detail line stays as plain info.
- **Conditions:** `LoanRepository.selectPortalConditionSnapshotByLoanId` adds `Category__c` and drops rows whose category contains Closing, TC, Final Docs or Post Clos. LO Workspace only.

## U2 — My Loans
- `LoanRepository.selectPortalLoansByUser` takes a status set. Active = today's active set minus Funding. Closed = Funding, PC Review, Post-Closed. Cancelled = Cancelled, Lost.
- `externalLoLoans` gets the three tabs with counts, plus the board (default) and list toggle, remembered per user in the browser.
- Board columns: Application (Open, TRID Application, Disclosures Out) · Processing (Pre-Processing, Processing, Submitted, Suspended, Re-Submitted, Waiting On Loan Officer) · Approved (Conditionally Approved, no CTC date) · Clear to Close (`Clear_to_Close_Date__c` set) · Closing.

## U3 — Weekly touch + Up Next
- New shared touch check: a Task or Event of type call, SMS or meeting on the lead, or an `EmailMessageRelation` to or from the lead's email, in the last 7 days. This replaces `LastActivityDate` in `mapPreApproval`.
- Pre-approval list: touch-due first (oldest touch at the top), then the newest created.
- `ExternalLoPromptService` adds a "Weekly touch" prompt per due pre-approval.
- New Apex method returns the full uncapped list; the 8-item cap stays for the card. A new "Open all" modal in `externalLoActivityPrompts` is grouped Overdue / Today / Coming up, with filters.

## U4 — Notes B + Appraisal A
- New LWC note modal (type chips, one text box, pin) replaces the `window.open('/apex/AddNewNote')` call in `externalLoLeads`, `externalLoLoans` and `loWsPastClientDetail`. It writes `Enhanced_Note__c` (Type__c, Body__c, Lead__c / Transaction__c / Account__c).
- **New field:** `Enhanced_Note__c.Is_Pinned__c` (checkbox); pinned notes sort first.
- `loWsAppraisalPanel` is restyled to A: status line, 4-step tracker, key facts, collapsed history, and the existing appraisal-company message thread. It keeps the same `AppraisalOrderController` calls; no data changes.

## U5 — Communications tab
- New `LoWsCommunicationsService`, which first checks the user can read the record (`UserRecordAccess`), then reads:
  - Calls and SMS: Tasks matched on `rcsfl__from_number__c` / `rcsfl__to_number__c` (reusing the BD Command Center pattern), plus hand-logged calls and texts. Calls get a Summary link when a `Call_Insight__c` exists.
  - Emails: `EmailMessageRelation` on the borrower's address, grouped into threads.
- It reads without sharing **after** that access check, so the LO sees every Reach user's contact with that borrower, labelled by sender.
- One LWC `loWsCommunications` (Calls / SMS / Emails subtabs) goes in the Lead and Loan detail tabs and on the LO Workspace Person Account page.

## U6 — Volume drawer
- New `LoWsVolumeService` covering:
  - Closed last month and month-to-date: `Loan_Amount_1st__c` by `Funding_Date__c`, plus units.
  - Pre-Approval leads: `Loan_Amount__c` plus units.
  - New leads, last month and month-to-date, excluding recycled leads.
  - Tags added, last month and month-to-date, from `External_User_Assignment__c.Assigned_Date__c`.
- **Placement (decided 2026-10-08):** a fixed right-edge "Volume" tab plus a slide-out drawer, exactly as in the mockup, on LO Workspace's main screens only: home (Perfect Day), My Loans, Pre-Approvals, Leads, Realtors, Other Contacts. It is not on Lead, Transaction or Account record pages. One `loWsVolumeDrawer` LWC is dropped onto each of those pages. The utility bar is kept free for the RingCentral widget (for LOs who use the company RingCentral account). The edge tab must sit above the utility bar and not overlap it.

## U7 — Other Contacts tab
- Reuses the realtor tag (`External_User_Assignment__c`, `LoWsPartnerTagService`). Other Contacts = tagged accounts whose `BD_Industry__c` isn't Realtor. That field already has CPA, Title Agent, Insurance Agent, Financial Planner, Attorney, Builder and Other.
- Add **Home Inspector** and **Appraiser** values to `BD_Industry__c` (redeploy the Account record types too, or the new values fail on existing records).
- New tab LWC that mirrors `externalLoRealtors`, with a type filter and add/duplicate check.

## U8 — Cancellation recycle (all LOs)
1. **Inventory first (no deploy):** every Lead trigger, record-triggered flow and Zapier "new Lead" Zap that sends outreach, routes or assigns, and how each one will skip a recycled lead.
2. **New Lead field:** `Recycled_From_Transaction__c` (lookup to Transaction__c). Lead, not Transaction, so the Transaction field cap is not touched.
3. **Trigger:** `TransactionStatusSync` after update calls `LeadRecycleService` (queueable) when Status__c changes to Cancelled. Conditions: purchase loan; `Borrower_Withdrawal_Reason__c` filled in and not *Selected an Alternative Lender* / *Found a More Competetive Interest Rate*; `Withdrawn_Reason__c` not App Denied / Pre-Approval Denied.
4. **Clone:** clone the converted Lead (`ConvertedAccountId` = the Transaction's borrower, newest) with all createable fields. Status Pre-Approval, Owner = `Loan_Officer__c`, Loan Partner carried over, `Borrower__c` co-borrowers copied, `Recycled_From_Transaction__c` set. The insert runs in system mode so it gets past the Lead Source lock, and duplicate rules are allowed to save.
5. **Silence:** a static `LeadRecycleService.running` flag for Apex triggers, plus `Recycled_From_Transaction__c != null` entry criteria on flows and a Zap filter on the same field. Loan Partner auto-assign is skipped so the carried-over partner sticks.
6. **Notify:** one custom notification to the LO: "Loan for [Borrower] cancelled; they're back in your pre-approvals."
7. **Reconversion:** every conversion path (Submission Form, `ExternalLoPortalConversionFacade`, TRID flow) converts a recycled lead into the original Person Account.
8. **Test:** cancel a test loan for each reason and for refi vs purchase; confirm nothing reaches the borrower; reconvert and confirm there's no duplicate account.

## Notes
- Item 1's user preference is a data change. I'll show you the user list before applying it.
- U8 step 1 may surface automations outside our repo (Zapier, Nimbus flows). Anything I can't silence safely comes back to you before the build.
