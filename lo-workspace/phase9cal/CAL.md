# Phase 9 — Calendar and follow-ups (+ no Lead Team email for logged notes)

Validated (check-only) 2026-10-02: **0AfQi000001TsajKAC**, 88/88 tests. NOT deployed.

Coverage: LoWsCalendarService 98%, ExternalLoCommunicationService 97%, ExternalLoActivityLogService 95%,
ExternalLoPortalController 84%, PerfectDayHomeService 92%, ExternalLoPromptService 90%, TaskRepository 81%,
LeadNoteTeamNotifier 98%.

## Deploy (two steps, from `lo-workspace/phase9cal`)

```
# 1. Apex + LWC
sf project deploy quick -o Production --job-id 0AfQi000001TsajKAC
# or, if the validation expired:
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LoWsCalendarServiceTest --tests ExternalLoActivityLogServiceTest --tests LoWsActivityLogTest --tests ExternalLoPortalCoverageTest --tests PerfectDayHomeServiceTest --tests ExternalLoPortalServiceTest --tests ExternalLoPromptServiceTest --tests LoWsPartnerTagServiceTest --tests LeadNoteTeamNotifierTest

# 2. Permission set (class access for LoWsCalendarService), AFTER step 1 (the class must exist)
sf project deploy start -o Production -d force-app-perm --test-level NoTestRun
```

Why two steps: deploying External_LO_Access puts the PSG External_Loan_Officer into recalculation, and every
test that assigns the PSG then fails ("You can only assign users to permission set groups that have the
Updated status"). The permset is in `force-app-perm/` and was not validated (it references the new class).

Then **republish Partner Workspace**: portalCommunicationModal, portalActivityModal, perfectDayHome and
externalLoActivityPrompts are shared with the portal, and loWsFollowUpPicker is new in their tree.

`ref/` = fresh prod copies (not deployed). `force-app/` = changed components only.

## What was built

### Calendar
- Fred's BD [Calendar] button just navigates to the standard Event home (`standard__objectPage Event home`).
  That tab is Hidden on the External Loan Officer Profile, so it was NOT reused. New minimal LWC instead.
- **loWsAppointments** (new): the "Upcoming appointments" card + the Calendar modal (week agenda, ‹ Today ›,
  7 days, each day lists events with time, subject, location and related name). `@api openCalendar()`;
  `hide-card` = modal only.
- Perfect Day header: new **Calendar** button next to In Person Invite (LO Workspace only).
- loWsInPersonEvents' "Open calendar" link also opened the hidden Event tab; it now opens this calendar
  (it embeds `<c-lo-ws-appointments hide-card>`). Works on Perfect Day and My Realtors.
- Apex **LoWsCalendarService.getMyEvents(startAt, endAt)**: `OwnerId = UserInfo.getUserId()` hard-coded, no
  user parameter, `WITH SYSTEM_MODE`, overlap query, blank range = next 7 days, capped at 62 days, 500 rows.
  Invitee copies of group events are child Events owned by the invitee, so they are included.

### Upcoming appointments (Perfect Day, right column)
Order: Up Next (3) → Today's plan → In-person events → **Upcoming appointments** → Recent log.
Kept as its own card, not merged: In-person events are Campaigns with RSVP counts and open the RSVP tracker;
appointments are Events (Outlook-synced, exact follow-ups, Zoom) and open the record. Different data, different
click. Next 7 days, max 8 rows (+N more → calendar). Row: day chip, time (or All day), subject (opens the
Event record page), related name: Lead → My Leads drawer, loan → My Loans drawer, anything else (partner,
contact) → its record page. Refreshes after a log.

### Follow-ups (Log communication + Log an activity)
- New shared LWC **loWsFollowUpPicker**: No follow-up / General follow-up / Exact time.
  - General: Tomorrow / In 3 days / Next week / Pick a date (native date input, min today).
  - Exact: native datetime-local, required, must be in the future.
  - Partner Workspace portal: Exact time is hidden (no calendar there); General stays (it shows on the
    portal's Perfect Day too).
- Log communication defaults to General · Tomorrow (same default as the old buttons). Log an activity
  defaults to No follow-up and shows the picker only once a contact is picked (never Social posts).
- Wire format: one string `followUpOption` = none | tomorrow | 3-days | next-week | date:YYYY-MM-DD |
  exact:<ISO>. logCommunication's Aura signature is unchanged; logActivity gained one trailing param
  `followUpOption` (blank = none).
- **General** → Task: Status Not Started, Priority Normal, ActivityDate = that day, Subject
  "Follow up: <name>", WhoId (Lead) or WhatId (Account/loan), IsReminderSet, ReminderDateTime =
  8:00 AM in the user's time zone that day. Subject is never read back.
- **Exact** → Event: OwnerId = LO, StartDateTime, DurationInMinutes 30, IsReminderSet, reminder 15 min
  before, WhoId/WhatId as above.
- The old fixed 9 AM, 15-minute "Follow up" Event is removed (createFollowUpEvent / followUpDateTime deleted).
  `LogResult.followUpEventId` keeps its name for existing callers but now holds the Task or Event Id.
- Everything runs in one transaction: a bad follow-up date/time rolls the log back with the message.

### Tasks due today on Perfect Day
- Before: only overdue tasks (ActivityDate < today) were computed, and only into the hidden `upNext` and the
  Overdue metric. Nothing due today was surfaced.
- Now: `TaskRepository.selectOpenDueTasksByOwner` (open, ActivityDate ≤ today, Prompt_Key__c = null so
  prompt-snooze Tasks are excluded, newest due first) → `ExternalLoPromptService.followUpPrompts` → put
  AHEAD of the computed prompts in Up Next (list still capped at 8, card shows 3).
- Row: "Follow-up due today" or "Overdue · was due <date>", title "Follow up with <related name>" (from
  Who/What, not Subject), notes as the script. Buttons: **Mark complete** (existing completeUpNextItem),
  Log (opens Log an activity on that contact), Tomorrow (existing deferUpNextItem → due tomorrow).
- Overdue follow-ups keep showing until completed. Completing does not credit a goal (no category/type).

### Logged notes don't email the Lead Team (owner decision, added mid-build)
- LeadNoteTeamNotifier: `@TestVisible public static Boolean suppressForLoggedActivity` — notifyForNotes
  returns early when true.
- ExternalLoActivityLogService.addNote (used by BOTH logActivity and logCommunication) sets it around the
  note insert and resets it in `finally`. Notes stay Type = Note. AddNewNote notes still email.

## Changed components
- Apex new: LoWsCalendarService, LoWsCalendarServiceTest.
- Apex changed: ExternalLoCommunicationService, ExternalLoActivityLogService, ExternalLoPortalController
  (logActivity + 1 param), TaskRepository (+1 method), ExternalLoPromptService (PromptItem.taskId /
  canComplete + followUpPrompts), PerfectDayHomeService (follow-ups first in prompts), LeadNoteTeamNotifier.
- Tests changed: ExternalLoActivityLogServiceTest (2 controller calls get the new trailing `null`),
  **ExternalLoPortalServiceTest — minimal: one assertion in logCommunication_withFollowUpCreatesEvent now
  counts an open Task instead of an Event** (the parallel contact-info agent may also touch this class —
  merge, don't overwrite). ExternalLoPortalService itself is NOT changed.
- LWC new: loWsAppointments, loWsFollowUpPicker. Changed: perfectDayHome, externalLoActivityPrompts,
  portalCommunicationModal, portalActivityModal, loWsInPersonEvents.
- Permset (step 2): External_LO_Access + classAccess LoWsCalendarService. Brandon is System Administrator, so he
  needs nothing.

## Tests (LoWsCalendarServiceTest, run as a real External LO with the PSG)
- generalFollowUpCreatesTaskWith8amReminder (logCommunication 'tomorrow' + logActivity 'date:'), no Event made.
- exactTimeRequiresDatetimeAndCreatesEventWithReminder (blank, past, malformed, unknown all refused; Event 30
  min, reminder −15, on the calendar).
- taskDueTodayAndOverdueShowOnPerfectDayUntilCompleted (today + overdue show, future doesn't, Mark complete
  removes it).
- calendarReturnsOnlyMyEvents (another owner's event never shows; 7-day default; 62-day cap).
- loggedNotesDoNotEmailTheLeadTeamButManualNotesStillDo (0 email invocations for both services; a direct
  Type Note insert still emails).
- outsideLoCanSeeZoomMeetingsSoEventSavesWork.

## Zoom object access (event-trigger-needs-zoom-object-access)
External_LO_Access itself has NO Zoom_Meeting__c permission, but the PSG External_Loan_Officer includes
Zoom_Meeting_Sync_Access (and Zoom_Meeting_Assistant_Access). Verified by test (Zoom_Meeting__c accessible as the
LO) and by the exact-time test inserting an Event as the LO. Note EventTrigger only queries Zoom on after
update/delete; on insert, EventTriggerHandler (without sharing) stamps the Lead's Appointment_Date_Time__c /
Appointment_Date__c / Appointment_Time__c from the newest Event — so an exact-time follow-up on a lead also sets
the lead's appointment, and selectLeadIdsWithFutureEvents then keeps that lead out of "New leads to contact".
The old 9 AM Event did the same.

## Outlook (Einstein Activity Capture) — enabling an outside LO
Nothing was configured. Steps (Setup, as admin):
1. **PSL**: Setup → Users → the LO → Permission Set License Assignments → Edit Assignments → tick
   *Standard Einstein Activity Capture* (StandardEinsteinActivityCapturePsl). The pilot
   (005Qi00000iSURvIAO) already has it. Then assign whatever permission set your EAC configuration uses
   (Standard Einstein Activity Capture permission set), if users are added to configurations by permset.
2. **Configuration**: Setup → Einstein Activity Capture → Settings → Configurations → open the active
   Microsoft configuration (or create one) → add the LO (or the External Loan Officer profile / their
   permission set) under Assigned users → in the configuration enable **Sync events** with direction
   **Both** (Salesforce ↔ Microsoft) so Apex-created Events reach Outlook. Keep email capture ON: Salesforce
   documents that events don't sync Salesforce→Outlook when email capture is off and direction is
   Salesforce→Exchange.
3. **One-time connection by the LO**: avatar → Settings → Einstein Activity Capture (or the prompt in the
   Activity Capture setup page) → Connect account → sign in to the @reachhomeloans.com Microsoft 365 account
   and accept. Sync starts within ~15 minutes.

Notes and limits:
- **Tasks never sync to Outlook** under EAC; only Events. So General follow-ups live in Salesforce (Perfect
  Day + the Task reminder popup); Exact time follow-ups are the ones that reach Outlook.
- An Event created by Apex is an ordinary Event owned by the LO, so it is eligible to sync once the LO is in a
  configuration with Salesforce→Microsoft sync; EAC matches/creates it after insert (typically 15+ min).
  The related Lead (WhoId) is NOT added as an Outlook attendee — the borrower never gets an invite (same
  finding as zoom-event-calendar-sync: use the .ics path for that). Custom fields don't sync. Reminder
  mapping to Outlook is unverified — check on the pilot.
- Outlook meetings sync in as Events owned by the LO, so they appear in Upcoming appointments and the calendar
  (all-day events can be off by a day at the 7-day edge: stored as midnight GMT).
- Verify on the pilot after enabling: create an exact-time follow-up and confirm it lands in Outlook.

## Open questions
1. Up Next shows ALL open tasks due today/overdue (not only follow-ups made here). Brandon (demo, sysadmin)
   may have many old open tasks that will now fill his Up Next. OK, or restrict to follow-up tasks?
2. Log an activity defaults to No follow-up; Log communication to General · Tomorrow. Same default for both?
3. Exact-time follow-ups on a lead also stamp the lead's Appointment date/time (existing EventTrigger
   behaviour). Acceptable?
4. Should "Log" on a follow-up row also auto-complete the follow-up? Today it's a separate Mark complete.
   (Answered in round 2: keep 1 and 2 as they are; 3 = no stamping; 4 = yes.)

---

# Round 2 (2026-10-02), built on deploy 0AfQi000001TscLKAS (+ permset 0AfQi000001TsfZKAS)

Validated (check-only): **0AfQi000001Tsu5KAC**, 83/83 tests. NOT deployed.
Coverage: LoWsCalendarService 98%, ExternalLoActivityLogService 95%, LeadRepository 91%, EventTriggerHandler 80%.

```
sf project deploy quick -o Production --job-id 0AfQi000001Tsu5KAC
# or, if the validation expired:
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LoWsCalendarServiceTest --tests EventTriggerHandlerTest --tests LeadRepositoryTest --tests EventDurationGuardTest --tests ExternalLoActivityLogServiceTest --tests LoWsActivityLogTest --tests ExternalLoPortalCoverageTest --tests PerfectDayHomeServiceTest --tests ExternalLoPortalServiceTest --tests ExternalLoPromptServiceTest
```
There is no permission set in this round. After deploying, republish Partner Workspace, because perfectDayHome is shared with it.
`force-app/` now holds only this round's changes. The round-1 sources, already in prod, moved to `round1-deployed/`.

## 1. Up Next: unchanged
It still shows all due and overdue tasks, as the owner asked.

## 2. Follow-up picker on every contact category: confirmed, no change
- **Log communication:** always has a target, so the picker always shows. Default is General · Tomorrow.
- **Log an activity:** the picker shows whenever a contact is picked or pre-filled (`!isSocial && recordId`).
  - Every contact-bound category gets it: Realtor outreach, Partner meetings, Consumer convos, Past clients.
  - A no-contact category also gets it if the LO still picks a contact.
  - It is hidden only for Social posts. Default is No follow-up.

## 3. Exact-time follow-ups don't touch the lead
- **Marker:** the follow-up Event gets `Prompt_Key__c = 'follow-up'`. It's an Activity field, so Events have it.
- **EventTriggerHandler** (before insert and update):
  - Skips marked Events: no Appointment_Date_Time__c, Appointment_Date__c or Appointment_Time__c stamp, and no Lead update at all. So no Lead trigger, flow or status automation runs.
  - Its "latest event" subquery also ignores follow-ups, so a later follow-up never stops a real appointment from stamping.
  - Internal appointments behave exactly as before.
- **LeadRepository.selectLeadIdsWithFutureEvents** ignores marked Events, so the lead stays in "New leads to contact".
  - Switched from WITH SECURITY_ENFORCED to WITH SYSTEM_MODE. Prompt_Key__c read access exists only in the External LO permission sets, so Brandon (System Administrator) would get an error.
  - Its only caller is PerfectDayHomeService, which passes the user's own lead Ids.
- **Other automation on inserting an Event with WhoId = Lead** (checked):
  - `EventDurationGuardTrigger`: only adjusts the end time on lead events. A 30-minute follow-up that starts on a quarter hour is unchanged. Harmless.
  - Flow `Event_Create_Enhanced_Note` (after create, WhoId 00Q or WhatId a01):
    - Creates a Type **Meeting** Enhanced_Note__c on the lead or loan. Body = Description, which is blank for follow-ups.
    - Doesn't show on the Notes tab (that tab shows Note or blank only) and sends no email (LeadNoteTeamNotifier fires only on Note).
    - Doesn't touch status. Left as is.
  - Flow `Event_starts_in_15_minutes`: only for owner 005f2000009Buua. Not relevant.
  - Flow `Event_to_Account_Appointment_Update`: when WhatId is an Account, it stamps **Account.Appointment_Date_Time__c**. Exact follow-ups on a partner or past client still do this; it's not a lead. Open question 1 below.
  - EventTrigger after update and delete calls ZoomEventSync. Zoom access was verified in round 1.
- **Test:** `exactFollowUpLeavesTheLeadAppointmentStatusAndNewLeadQueueAlone`.
  - Status stays New, there is no stamp, and the lead is not treated as booked.
  - Control: a real appointment on the same lead still stamps and still counts as booked.

## 4. Log on a due follow-up row completes it
- **How:** "Log" in Up Next passes promptKey `task:<Task Id>`. In the same save, after inserting the log Task, logActivity completes that Task (Status Completed, ActivityDate today) if it belongs to the user.
- The key is NOT stamped on the log Task. There is no Aura signature change.
- **Refusals:** someone else's task, a bad Id or a non-Task Id returns "That follow-up could not be found…", and the whole save rolls back.
- **Test:** `logOnAFollowUpRowCompletesThatFollowUpInTheSameSave`.

## 5. Calendar rebuilt (owner revision, loWsAppointments)
- **Modal:** 90vw × 85vh on desktop; full width and 92vh on phones.
- **Header:**
  - ‹ Today › buttons.
  - A title such as "October 2026", "Oct 4 – 10, 2026" or "Mon, Oct 5, 2026".
  - Month / Week / Day pills in the grey-blue style of the shell's detail tabs.
- **Month view** (default):
  - A 7-column CSS grid, Sunday to Saturday, 42 cells.
  - Leading and trailing days greyed out; today highlighted.
  - Up to 3 chips per day (time + subject) and "+N more", which opens the Day view. Clicking the day number also opens the Day view.
  - On phones (640px or narrower when the calendar opens), it becomes an agenda list of the month's days that have events.
- **Week view** is a 7-column hourly grid; **Day view** is a single column.
  - Hours run 7 am–9 pm, widened to fit earlier or later events.
  - Events are placed by start time and duration (minimum 22px tall); overlapping events sit side by side.
  - All-day events go in a strip at the top.
- **Colours:** lead blue, loan green, partner or contact purple, other grey, all-day teal.
- **Clicking an event** opens a popover with time, subject, related name and location. Buttons:
  - **Open:** the lead or loan inside the workspace, or the record page for anything else.
  - **Event:** the Event record page.
  - **Close.**
- **Data:** getMyEvents per visible range. A month grid is 42 days, inside the 62-day cap. Plain LWC + CSS grid.
- The Upcoming appointments card is unchanged.

## NOT built: blocked by the session's permission guard
The tool guard refused these edits ("Modify Shared Resources" / "Real-World Transactions"). Nothing was worked around. The owner or Chris needs to approve them or make them.

**Item 5: lead status from logged calls.**
- Planned rules: reached → Working; not reached → next Contact Attempt, capped at 6 (the highest active value).
- Forward-only, LO Workspace only, run after the Task insert in system mode, with a warning instead of a failure.
- The design is ready: ExternalLoActivityLogService.progressLeadAfterCall, plus a Reached / Left voicemail / No answer choice in Log an activity for calls on a lead. Log communication already has outcomes.
- None of it is in the package.

**(b) Document request → Documents Requested.**
- Finding: `LeadDocumentRequestService.stampInitialDocsRequested` ALREADY does this for everyone, in system mode. On the **first** send of an initial template (purchase or refinance) it sets Status = Documents Requested and Initial_Docs_Requested_Date__c.
- It is not forward-only: a first send on a lead already at Pre-Approval or Nurture would pull it back. Later sends never move it.
- The planned outside-LO-only change was refused. It would have moved the status on every initial send, only from New / Contacted/Call Back / Contact Attempt N / Working / Application Link Out / Application, and never on converted leads.

**(c) Validation rules.**
- Of the 9 active Lead validation rules, only `Calls_Required_for_Status_Change` gates status on calls.
  - Before: `AND(ISCHANGED(Status), NOT(ISCHANGED(Number_of_Calls__c)), $Profile.Name <> 'System Administrator', NOT(ISCHANGED(LO_Takeover_At__c)), OR(CONTAINS(Record_Type__c,'Consumer Purchase'), CONTAINS(Record_Type__c,'Consumer Refinance')))`
  - Planned after: the same plus `NOT($Permission.External_LO)`. Refused.
- This rule only hits the record type "Consumer Refinance Lead Record Type", which is inactive: 6 of the outside LOs' 266 open leads. "Consumer Lead Record Type" never matches.
- The other rules don't block an outside LO changing the status of their own lead:
  - Lead_Source_Change_Restricted, Lead_already_claimed, No_Owner_Change_on_Leads, Loan_Officers_Cannot_Change_Owner, Loan_Partner_Reassignment_Restricted and Lawrence_Lanos_Rule gate owner, source or Loan Partner only.
  - `Lead_Rating_and_Loan_Amount_Fields_requr` requires Loan_Amount__c at Pre-Approval. That's a data requirement, not a call requirement.
- Tests for (b) and (c) were not written.

## Side effects of the status moves (research for item 5 and (b))
None of these status-only moves sends a Twilio SMS or an email.

**On every Status change:**
- Flow `Lead_Event_Status_Changed` closes the latest `Lead_Event__c` history row and creates a new one.
- Managed triggers TwilioSF.LeadTrigger, ActiveCamp.lead and smagicinteract.updateRelatedListTrigger run. They are closed source, so whether ActiveCampaign syncs anything is unverified.

**New → Contact Attempt 1, and Contact Attempt k → k+1:**
- `Lead_Status_Change_Message_Sends` (Realtor Referral leads with a buying agent) enters its Attempt 1/2 and Attempt 3 branches. Those branches have no connector, so **no SMS** is sent.
- Phase 6's note that Contact Attempt 1-3 texts the agent is out of date: only Pre-Approval sends.
- No Zapier post.

**New or Contact Attempt → Working:**
- `Set_First_Contact_Date_on_Lead` stamps First_Contact_DateTime__c, first time only.
- `Lead_Stamp_Initial_Contact_Date` stamps Initial_Contact_Date__c. Only from a Contact Attempt or Contacted/Call Back status, and it overwrites every time.
- Zapier webhooks, each sent once per lead with name, email, phone, old and new status, and owner:
  - `LeadStatusWebhook`: LeadSource Website or *-Linktree.
  - `ConsumerWebinarLeadStatusWebhook`: Consumer Webinar.

**→ Documents Requested:**
- Same as Working, except the two Zapier status posts fire only from New or a Contact Attempt, not from Working.
- Flow `Leads_Documents_Requested` sets User_working_the_lead__c to the LO.
- `ConsumerWebinarDocsWebhook` posts to Zapier once (Consumer Webinar leads).
- The buyer's agent SMS (`Lead_Notify_Buyers_Agent_Docs_Requested`) fires when Initial_Docs_Requested_Date__c becomes non-null (the first initial document request email), NOT on Status.

## Open questions (round 2)
1. Exact follow-ups on an Account (partner or past client) still stamp Account.Appointment_Date_Time__c through flow Event_to_Account_Appointment_Update. Should follow-ups be excluded there too? That's a flow change, which lands as Draft and needs a second step to activate.
2. Items 5, (b) and (c) need explicit approval to go ahead (see above).

---

# Round 3 (2026-10-02): status rules, built on deploy 0AfQi000001TsyvKAC

The coordinator relayed the user's approval. Round 2's package moved to `round2-deployed/`. `force-app/` holds only this round's changes.

Validated (check-only): **0AfQi000001Tv8nKAC**, 127/127 tests. NOT deployed.
Coverage: LeadDocumentRequestService 82%, ExternalLoActivityLogService 94%.

**Deploy:** one step. The validation rule and the Apex were validated together, and the tests ran against the new rule.
```
sf project deploy quick -o Production --job-id 0AfQi000001Tv8nKAC
# or, if the validation expired:
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LoWsLeadStatusTest --tests ExternalLoActivityLogServiceTest --tests LoWsActivityLogTest --tests LoWsCalendarServiceTest --tests ExternalLoPortalCoverageTest --tests LeadDocumentCollectionServiceTest --tests LeadPortalDocumentRequestFacadeTest --tests LeadConditionAssignmentTest --tests LeadPortalPresetConditionTest --tests LeadPortalSubmissionTest --tests LeadReviewQueueTest --tests LeadPresetCondSelectorTest --tests LoWsBorrowerServiceTest
```
No LWC changed and no permission set, so no portal republish is needed. LeadDocumentRequestService's 75% gate needs the 6 lead-document test classes in that command.

## In the package
**(c) `Calls_Required_for_Status_Change`:** `NOT($Permission.External_LO)` added, with the before/after from round 2.

**(b) LeadDocumentRequestService.stampInitialDocsRequested:**
- Internal users: unchanged. Only the first initial send stamps Initial_Docs_Requested_Date__c and moves the status.
- External_LO users: every initial-template send moves the status to Documents Requested, but only from New, Contacted/Call Back, Contact Attempt N, Working, Application Link Out or Application. Never from Pre-Approval or later, Nurture*, or a converted lead.
- The date is still stamped on the first send only, so the buyer's agent SMS still fires once, as today.

**Item 5 (server side):** `ExternalLoActivityLogService.progressLeadAfterCall` + `nextLeadStatus`.
- Rules: reached → Working; left voicemail or no answer → next Contact Attempt, capped at the highest active value (6). Forward only.
- Scope: LO Workspace (tag mode), Lead, Call only.
- It runs after the log Task insert in system mode. A refusal keeps the log and returns `statusWarning`.
- `logActivity` uses it via the new `LogRequest.callOutcome`, and its message reads "… logged — lead moved to Contact Attempt 1."

**Tests: `LoWsLeadStatusTest`.** Users get the External_LO_Access permission set only, not the permission set group.
- The status rules table.
- Via logActivity: New + voicemail → CA1; CA1 + no answer → CA2; New + reached → Working; a Pre-Approval lead is unchanged.
- Document request: Working → Documents Requested; a later send moves a CA2 lead; Pre-Approval is unchanged. Internal behaviour is unchanged.
- SeeAllData test on two existing Consumer Refinance leads:
  - An outside LO moves New → Pre-Approval with no call.
  - An internal Loan Officer Profile user is still blocked by "Log an Activity".

## NOT built: the permission guard refused these edits again
Agent-relayed approval doesn't clear the guard. The user needs to approve these directly, or make them.
1. **ExternalLoCommunicationService:** calling `progressLeadAfterCall(recordId, channel, outcome)` after the follow-up, adding `statusWarning`, and putting the new status in the success toast. Refused as "Security Weaken" / "Modify Shared Resources". So **Log communication does not move status yet.**
2. Not attempted, because they are part of the same refused outcome:
   - `ExternalLoPortalController.logActivity`: a trailing `callOutcome` param.
   - portalActivityModal: a Reached / Left voicemail / No answer choice for calls on a lead.
   - The toast text in both modals and perfectDayHome.

   Until these exist, **Log an activity can't send an outcome either**, so item 5 is server-side only and not reachable from the UI.
3. `Task.CallDisposition` from `callOutcome` in logActivity. Refused; a cosmetic stamp only.
