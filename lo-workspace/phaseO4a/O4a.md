# Phase O4a: LO Workspace build-first items (Round 6: 46, 48.1, 49, 51)

Decisions are in `../onboarding/ONBOARDING-GRILL.md`. The prod copies, retrieved 2026-10-09, are in `ref/src`. Every component was built from them, except externalLoRealtors, which was built from `../phaseO3/force-app` (see Dependency). `ref/src/main/default/classes-readonly-verify` holds read-only copies used for the checks in item 4.
Nothing has been deployed and no data was changed.

Check-only validation: **0AfQi000001UPDJKA4** (2026-10-09, after the owner answers). 39 tests ran with 0 failures. LeadPreApprovalLetterController coverage is 82% (329/402). It supersedes 0AfQi000001UP5FKAW.
Tests: LeadPreApprovalLetterTest, LeadNotesFormControllerTest, ZoomMeetingControllerTest (`sh run-validate.sh`).
Deploy: `sf project deploy quick --job-id <id> -o Production --wait 30`

## Dependency on O3
`externalLoRealtors` is O3's version plus the Zoom card. Deploy O3 first. Because O3 contains Apex, it invalidates this validation id, so run `sh run-validate.sh` again and quick-deploy the new id.

## What changed
1. **Application Summary button** (externalLoLeads header, after "Convert to transaction"). It shows in LO Workspace only.
   - The quick action `Leads_Notes_Form` is the Aura component `LeadNotesForm`, and an LWC cannot embed Aura. The new `loWsApplicationSummary` is a thin LWC copy of its markup.
   - It calls the same Apex (`LeadNotesFormController.getApplicationSummary` / `saveApplicationSummary` / `createSummaryNote`), with the same sections, co-borrower rule, read-only rule and strings.
   - It is imported on demand inside the existing letter-style modal.
   - Access is already granted: Application_Summary_Access and External_LO_Access both give class access and are in the PSG. No permset changes.
2. **"Schedule a Zoom" card**: right column of the lead Overview, past client Overview and realtor page, in LO Workspace only.
   - The new `loWsZoomCard` dynamically imports `zoomMeetingAssistant`, so the portal bundle never loads it.
   - `zoomMeetingAssistant` gets `variant="compact"`: no hero, one column, inline reconnect panel, and it fires `scheduled`. With no variant, the record pages are unchanged.
   - Event, .ics and invite email are untouched (same `scheduleMeeting`).
   - When Zoom is not connected, the card shows the reconnect path from the controller's own not-connected / "Reconnect Zoom" errors, instead of an error toast.
   - Next appt: `LoWsContactService.nextAppointments` already reads future Events with `OwnerId = me AND WhoId = lead`, and the scheduler creates exactly that. On `scheduled`, the lead page refreshes the contact card and the lead lists. Nothing is duplicated.
   - Layout: all three pages already used `.detail-grid` (2fr/1fr from 768px, stacked below). The card goes in the side column.
3. **Letter guard (48.1)**
   - The button stays visible. If the lead's Status is not Pre-Approval, it shows a warning toast with the direction text and the modal does not open.
   - Server side: `getContext` and `saveDetailsAndBuildLetter` already refused every user. For External_LO users only, `finalizeLetter` and `deliverFinalizedLetter` now re-check, and the refusal uses the LO wording.
   - Internal users keep the "log a call" message and an ungated finalize.
   - New test: `outsideLoIsRefusedAtFinalizeAndDeliveryUntilPreApproval`.
4. **Follow-up picker (49)**
   - Verified in `LoWsCalendarService.createFollowUp`: the Task has `IsReminderSet = false`, and so does the exact-time Event.
   - Verified in `PerfectDayHomeService`: open Tasks due today or overdue lead Up Next (after document-review alerts).
   - The general hint is reworded. The exact-time hint also wrongly promised "a reminder 15 minutes before", so that was removed.
5. **Tab (51)**: the `LO_Workspace` description is now "Your daily workspace: Perfect Day, goals, leads, pre-approvals, loans and partners."

## Owner answers (2026-10-09), now built

### Letter rule
A letter may be issued at Pre-Approval or any later status. This applies to **everyone**, at getContext, saveDetailsAndBuildLetter, finalizeLetter and deliverFinalizedLetter.

The one list is `LeadPreApprovalLetterController.LETTER_STATUSES`:
- Pre-Approval
- Nurture - Preapproval
- Nurture-Pre-Approval (legacy spelling, about 600 leads)
- Active
- Under Contract
- Submitted For Disclosures

The LO Workspace button asks the server through `getLetterBlockedReason`, so the list is not repeated in JS.

Messages:
- Internal: "Pre-approval letters unlock once this Lead reaches Pre-Approval. Please log a call to move the status to Pre-Approval, then try again."
- LO Workspace: "Pre-approval letters unlock once this lead reaches Pre-Approval. Move the lead to Pre-Approval once you've reviewed credit and documents."

Placement comes from picklist order (StandardValueSet LeadStatus) and `ExternalLoPortalService` stage sets.

These statuses were left OUT and need confirming with the owner:
- **Scheduling Meeting, Meeting Set, Meeting Complete.** They come after Pre-Approval in the picklist, but they read as consult-meeting statuses.
- **Call - Referral Pending.** A converted status.
- **Nurturing - Meeting Complete, Nurturing.** Generic nurture, 30k leads.
- **Credit Repair.** Last in the picklist, but not pre-approved.
- **Documents Requested, Documents Received for Review, Application.** These sit before Pre-Approval in the picklist, yet the stage logic groups them under 'pre-approval'.
- **30 Day + Follow Up.**

Converted leads: they are refused up front with "This lead has already been converted to a loan, so a new pre-approval letter cannot be issued from it."
- Internal: not reachable. A converted Lead record page redirects, so the quick action never shows.
- LO Workspace: reachable. getLeadDetail does not exclude converted leads; they open from deep links and search. Before this change the letter failed on the Lead update, because the platform refuses DML on converted leads.

New tests: `lettersAreIssuedFromPreApprovalOnwardAndRefusedBefore` and `convertedLeadsAreRefusedWithTheirOwnMessage`. They replace the earlier LO-only test.

### Zoom "Realtor Agent Meeting" template
The template lives client-side, in `zoomMeetingAssistant.js` `buildInvitation`. There is no Apex or metadata copy.
- The subject is now "Your Zoom with <host name> is Set - <name>".
- The body says "meet with <host first name>".
- The host is the Schedule For pick, otherwise the scheduler.
- The "BranTheMortgageMan" handle was dropped. User has no per-user handle or link field.
- Brandon scheduling for himself still sees his own name, but his subject now reads "Brandon Brotsky", not "BranTheMortgageMan".

### Reconnect panel
Unchanged.
