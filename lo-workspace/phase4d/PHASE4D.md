# Phase 4d: Outside LO record pages

Status: built and validated (check-only) on 2026-10-01. **Not deployed.**

- Validation: `0AfQi000001Tm2HKAS`. It succeeded with 6/6 components and 7/7 tests in AppraisalOrderController_Test.
- Source: every page was built from fresh prod retrieves in `ref/`. `scripts/build-pages.js` regenerates the three FlexiPages from `ref/`, so after a fresh retrieve you can re-run it rather than hand-editing.

## Where the pages come from

Internal LOs (Loan Officer Profile) get these pages today:

| Object | Large | Small |
|---|---|---|
| Lead | `Lead_Expandable_Record_Page` (org default) | `Lead_Record_Page` (org default) |
| Transaction__c | `Transaction_Expandable_Record_Page` (org default) | same page |
| Person Account | `Person_Account_Record_Page` (app + record type + profile, in Reach_Home_Loans_Lightning / CEO / LightningSales) | system default |

LO_Workspace had no assignments, so outside LOs fell back to the org defaults. That means Person Accounts showed `Account_Record_Page`.

`Transaction_Expandable_Record_Page_Outside_LO` already exists in prod. It is an old Nimbus-era page that was never assigned, and it has no Documents viewer. I did not reuse it and did not delete it. It is a cleanup candidate.

## New components

### LO_Workspace_Lead_Record_Page
This is a copy of `Lead_Expandable_Record_Page`.
- **Keeps:**
  - Action strip: Application Summary, Sync/Open ARIVE, Pre-Approval Letter, Realtor Convert.
  - Lead hero, borrower panel, leadActivityAssistant, zoomMeetingAssistant and the activity panel.
  - Tabs: Details, Document Requests, Documents, RingSense, Zoom, Scheduled Messages, Notes and Related.
- **Removes:**
  - `homeToolsDrawer` (the Command Center drawer).
  - `TwilioSF:TwoWayMessages`, because outside LOs have no Twilio seat at launch. Automated texts still fire without a seat.
- The Lead page had no DocuSign, PCC, Wire, Clone or Order Appraisal components to remove.

### LO_Workspace_Transaction_Record_Page
This is a copy of `Transaction_Expandable_Record_Page`. It is assigned for both Large and Small, because the internal page serves phones too.
- **Keeps:**
  - Highlights panel, path, history, ARIVE embed, borrower panel and the funder/closer/post-closing alert banners (read-only).
  - Tabs: Details, Notes, Related, COC, RingSense, Documents (uploader + viewer) and Activity.
  - The Transaction_Templated_Messages flow.
- **Changes:**
  - Highlights panel: the `Edit` dynamic action is removed, so no actions remain.
  - Path: `hideUpdateButton=true`. "Mark Status as Complete" needs Edit.
  - Action strip: `transactionQuickActions` gets `allowedActions` set to Application Summary, Submission Form (shows only in TRID Application), COC Request and Back Under Contract (shows only in Cancelled).
  - Appraisal tab: `AppraisalOrder`, which has the Cancel Order and Fetch Reports buttons, is replaced with `loWsAppraisalPanel`. That panel shows order facts, timeline and documents, and lets the LO read and send comments. It cannot order.
- **Removes:**
  - DocuSign card (`transactionDocuSign`). Outside LOs have no access to its controller anyway.
  - Command Center drawer.
  - Conditions tab. Its tabset is already hidden from LO profiles.
  - IRS Form 1098 tab (admin only).
  - Submission Quality tab. Its read-only lock is hardcoded to the two internal Loan Officer profile Ids, so outside LOs would have had an editable checklist backed by a without-sharing controller that writes the loan.
  - Checklist tab: Opener and Post-Closing checklists, the BPS verification save, and the Closing/Funding checklist update actions.
  - Wire Request walk-through tab.
  - "Active Appraisal Order" update action.
- **Strip actions dropped by the allowlist:**
  - Wire Calculator, Order Appraisal, Closing Portal, Cancel Loan, Fetch ValueLink, Commitment Letter, Create DPA 2nd, Add to Closing Queue and Exclude From MCR (ops actions).
  - Create Title Agent. This is the Pipeline Command Center title-agent action; title agents are created as a partner or on the Submission Form instead.
  - Actions that need Edit:
    - Update UWM (with-sharing invocables).
    - Sync ARIVE and MERS Min Capture (Update-type actions).
    - Revert to Closing (user-mode update).

### LO_Workspace_Account_Record_Page
This is a copy of `Person_Account_Record_Page`, which internal LOs use for Person Accounts.
- **Removes:** the Command Center drawer, Twilio, and `bdLogTouchCard` (BD only; outside LOs have no access to its controller).
- **Adds:** an `IsPersonAccount = true` visibility rule on `accountRecordHero` and `accountActivityAssistant`. This copies the rule on `Account_Record_Page`, because the app default also catches the 168 business accounts.
- `accountRecordHero` "Create Lead" stays. It is guarded by `RecordAccessGuard.requireRead` (Phase 1b).

### LWC changes (no Apex)
- `transactionQuickActions`: adds an optional `@api allowedActions` design property. When it is blank, the component behaves exactly as before, so the internal page is unchanged.
- `loWsAppraisalPanel`: adds an `@api recordId` that forwards to `loanId`, and is now exposed on `lightning__RecordPage` for Transaction__c. The My Loans drawer still passes `loan-id`.

### Assignment: `LO_Workspace.app`
- **App default** (actionOverrides) for every profile:
  - Lead: Large.
  - Transaction__c: Large and Small.
  - Account: Large.
- **App + profile** (profileActionOverrides): the same four rows for `External Loan Officer Profile`. This is a custom profile, so the profile-name trap does not apply. No record type is set, and validation accepted that.
- No Profile XML is deployed.

Profiles and permission sets that can see LO_Workspace (SetupEntityAccess, 2026-10-01):
- External Loan Officer Profile: Outside LO Pilot.
- Permission set `LO_Workspace_Demo`: Brandon Brotsky, System Administrator.

No other profile has the app visible. Internal LOs on their usual apps see no change. Brandon sees these pages inside LO_Workspace, with the same removals.

## Back Under Contract
The owner said "Not Clone Transaction (they should have the 'back under contract' option for existing Canceled Transactions)". This **reuses what already exists**: the `Transaction__c.Back_Under_Contract` quick action, which runs the screen flow `Back_Under_Contract_Transaction` v5 (Active).
- The strip shows the action only when Status = Cancelled, and the flow rejects any other status.
- The flow creates a new Purchase Transaction. It copies:
  - Borrower, Loan Officer and Loan Partner. The Loan Partner rule is in memory under submission-form-edit-window.
  - Owner, ARIVE Id, Biz Dev, Referral Source and Buying Agent Assistant.
- It runs in user context and needs only Create. Outside LOs have Transaction Create and edit FLS on all the fields it sets (checked).
- Nothing new was built.

**Test before go-live:** as the pilot, run Back Under Contract on a cancelled test loan. Two things could fail for an outside LO:
1. The flow reads the borrower Person Account in user mode, and Account OWD is Private. If the LO can't read the borrower, the new loan's Name is blank and the insert fails.
2. The new record's Owner is copied from the cancelled loan, which is an ops user, not the LO. If either fails, the fix is to run the flow in system context.

## Deploy
From `lo-workspace/phase4d`:
```
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests AppraisalOrderController_Test
```
Or quick-deploy the validation: `sf project deploy quick -o Production --job-id 0AfQi000001Tm2HKAS`. Validations expire after 10 days.

`validate` does not accept NoTestRun, so AppraisalOrderController_Test runs; it covers the panel's controller.

After deploying, open a Lead, a Transaction and a Person Account as the pilot in LO Workspace, on desktop and on the phone.

## Open questions
1. **Lead on phones:** the Small form factor still uses the org default `Lead_Record_Page`. That page has the Command Center drawer and the layout's highlights actions, and nothing outside LOs are barred from. Do you want a phone Lead page as well?
2. **COC Request (and the COC tab):** both are kept because internal LOs have them. The flow runs in system mode, creates a COC and a Case, and emails the lock desk. Should outside LOs keep them?
3. **Back Under Contract:** if the pilot test above fails, should the flow switch to system context? That change affects every user.
