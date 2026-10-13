# LO Workspace — Communication Settings (spec + build plan)

Grilled 2026-10-13. Built + deployed 2026-10-13 (deploys 0AfQi000001Ug2rKAC, permset 0AfQi000001Ug65KAC). Flow activation (activate/) and the daily schedule still pending. Audit source: fresh prod retrieve 2026-10-13.

## Scope rule
- Applies ONLY to External LOs in the LO Workspace (full-licence app AND Partner Workspace portal).
- Their automated texts go from the new no-reply number **(561) 589-4420 ONLY**. Same Twilio account as the package (`ACb3…0a34`), already A2P-approved.
- Internal users: number (772-238-5990), templates and flows unchanged.
- For External LO files, the existing shared-number send is **skipped** and the workspace send replaces it.
- Gap being closed: `Is_Community_User__c` is false for full-licence External LOs (e.g. LO Pilot), and the Lead-side agent flows have no gate at all, so today their files text agents from the shared number.

## Messages in the settings modal
Default = ON with the default template. Default sign-off "- Reach Home Loans". Locked footer: `No-reply`.

| Key | To | Trigger | Default body |
|---|---|---|---|
| A2 | Agent | Lead `Initial_Docs_Requested_Date__c` set | Documents have been requested from {Lead Name} to complete the Pre-Approval. - Reach Home Loans |
| A3 | Agent | Lead → Pre-Approval / letter finalized at new price | Great news! {Lead Name} is Pre-Approved. The Pre-Approval letter for Purchase Price {Purchase Price} and Loan Amount {Loan Amount} is on the way! - Reach Home Loans (price sentence only if both figures present) |
| A5 | Agent | `Disclosures_Out_Date__c` null→value | Disclosures have been sent to {Borrower Name} for review and signatures. We will let you know when they are executed. - Reach Home Loans |
| A6 | Agent | `Appraisal_1_Ordered_Date__c` null→value | The appraisal for {Borrower Name} has been ordered. - Reach Home Loans |
| A7 | Agent | `Appraisal_1_Received_Date__c` null→value | We have received the appraisal report for {Borrower Name}. - Reach Home Loans |
| A8 | Agent | Status → Submitted | Loan documents for {Borrower Name} have been submitted to underwriting for initial review. - Reach Home Loans |
| A9 | Agent | Status → Approved (= Clear to Close) | {Borrower Name} is Clear To Close! - Reach Home Loans |
| N2 | Agent | Transaction closed/funded | {Borrower Name} is officially closed! Thank you for the referral — it was a pleasure working with you. - Reach Home Loans |
| N4 | Borrower | Conditions/doc request sent | Hi {First Name}, I've requested a few items to complete your pre-approval. Upload them here: {Portal Link} - Reach Home Loans |
| N5 | Borrower | Open requests: days 3, 6, 9, 12, 15 after the newest request, then stop | Hi {First Name}, friendly reminder — {Open Count} items are still needed for your pre-approval: {Portal Link} - Reach Home Loans |
| N6 | Borrower | Lead → Pre-Approval | Congrats {First Name}, you're pre-approved! Your letter is headed to your inbox. - Reach Home Loans |
| N7 | Borrower | Disclosures Out | Hi {First Name}, your loan disclosures were just emailed for e-signature. Please sign within 3 days to keep things moving. - Reach Home Loans |
| N8 | Borrower | Status → Approved | {First Name}, you're Clear to Close! We'll confirm your signing details shortly. - Reach Home Loans |
| B2 | Borrower | Birthday, closed client | (current birthday text) |
| B3 | Borrower | Loan anniversary, closed client | (current anniversary text) |

Out of scope: A1 + B1 (realtor intake only), A4 (field already absent from workspace UI — verified), RC drips + Initial Items (send from a person's RC line, internal allowlist), event invites, internal staff texts.

## Decisions
- Per-LO templates: free text + merge-field picker + Reset to default + live char count (warn > 160). No usage counts.
- Per-contact "automated texts off" toggle: Lead overview, Realtor page, Past Client page, Loan page (borrower + agent toggles = the same underlying switches). Turning OFF shows a warning: all automated messages to this contact stop until toggled back on in the LO Workspace. ON needs no confirm. Affects workspace texts only; new fields, NOT the existing opt-out fields.
- No auto-reply on the new number. STOP handled by Twilio Advanced Opt-Out.
- Inbound reply → Up Next card "Text reply from {Name}: '{first 80 chars}…'" with Open + Mark handled; stays until Mark handled.
  - Agent reply → Realtor page.
  - Borrower reply → Lead (unconverted) → else active Loan → else Past Client; Communications → Texts tab.
- Instant triggers send immediately; scheduled (N5, B2, B3) at 10am ET.
- Rollout: straight to prod, pilot user LO Pilot, then all External LOs.

## Build plan
1. **Data**
   - `LoWs_Comm_Template__mdt`: Key, Audience (Agent/Borrower), Label, Default_Body, Sort. One row per message above.
   - `LoWs_Comm_Setting__c` (owned by the LO): Message_Key__c, Enabled__c, Body__c. A row exists only once the LO changes something; no row = default ON + default body.
   - `Lead.LoWs_Texts_Off__c`, `Account.LoWs_Texts_Off__c` (checkbox).
   - `TwilioSF__Message__c.LoWs_Reply_Handled__c` (checkbox).
   - Lead: `LoWs_Last_Docs_Reminder__c` (date) for N5 cadence.
   - Custom label `LoWs_Twilio_From_Number` = 5615894420.
   - External-LO flag the flows can read (User checkbox set by `onboarding/provision-external-lo.js`, or profile-name check — pick at build).
2. **Gate the old senders**: A2, A3, A5–A9 flows and the B2/B3 scheduled flows skip External-LO files/clients.
3. **Sender**: `LoWsAutoTextService` — resolve template (override or default), skip if LO toggle off or contact `LoWs_Texts_Off__c`, render merge fields, append `No-reply`, send via `TwilioSF__TwilioSendSMS` with `fromNumber` = label. Reuse existing `CommSent_*` guards. Called from Lead/Transaction/Lead_Document_Request__c triggers + one daily 10am schedulable (N5, B2, B3).
4. **Inbound**: existing account-wide poller already captures replies. Add: To = new number → stamp the External LO (most recent outbound from new number to that phone) + target record; gate `Route_Twilio_Reply_to_Owner` / `Alert_Message_Owner_of_New_Reply` off for these.
5. **UI**
   - Shell `externalLoPortalShell`: "Communication Settings" button in the sidebar-user block (+ mobile drawer), `data-tour` hook.
   - `loWsCommSettingsModal` (hand-rolled modal pattern, grouped Agent / Borrower).
   - `loWsTextsToggle` with confirm pop-up, placed on the four pages.
   - Up Next: new high-alert prompt kind `textReply` in `PerfectDayHomeService`; Mark handled sets `LoWs_Reply_Handled__c`.
   - Deep link: `c__tab` URL state; `initialTab` on Loans + Past Client; `initialSubTab='texts'` on `loWsCommunications`.
6. **Access**: SYSTEM_MODE service pattern (as `LoWsOnboardingGateService`); add classes/objects to the External LO permset group.
7. **Deploy**: fresh retrieve first; RunSpecifiedTests; flows land as Draft → activate in a second deploy.
8. **Verify**: LO Pilot file with a test phone — trigger A5/N7, reply, card appears within ~5 min, Open lands on Texts, Mark handled clears it; toggle off → no send; internal file still sends from 772 number.

## Verify at build
- How External LO past clients are identified for B2/B3 (Account owner vs last Transaction `Loan_Officer__c`).
- Calling the TwilioSF action from Apex/trigger context (callout timing) — fall back to an autolaunched flow wrapper.
- N2 trigger field (Funded vs Closed status/date) and the Portal Link source for N4/N5.
- N5 stop conditions besides "no open requests" (e.g. Lead converted/closed, contact toggled off).

## As built (2026-10-13)
- Settings: JSON in `User.LoWs_Comm_Settings__c` (no custom object). Defaults live in `LoWsAutoTextService.CATALOG`.
- External LO = role External_Loan_Officer (`User.LoWs_External_LO__c` formula; `Account.LoWs_Owner_External_LO__c` for B2/B3). Portal (Community) LOs are not in this role, so their files keep today's behaviour.
- Send path: `Invocable.Action` -> package action `TwilioSF__TwilioSendSMS` with fromNumber = `$Label.LoWs_Twilio_From_Number`.
- Triggers: LoWsAutoTextLead, LoWsAutoTextTransaction, LoWsAutoTextDocRequest. Daily: `LoWsAutoTextDaily` (schedule '0 0 10 * * ?').
- B2/B3 are sent against the client's newest loan so replies thread to the LO.
- Replies: `LoWsTextsService.replyPrompts` (High alert in Up Next); threading for the 561 number only matches sends from it; `TwilioSF__Message__c.LoWs_Reply_Handled__c`.
- Class access: `LoWsCommSettingsController` added to permission set External_LO_Perfect_Day_Access (deploy it alone: a PSG recalculation breaks LoWsCalendarServiceTest mid-deploy).
- Flows gated: 5 Transaction agent flows (Loan_Officer__r.LoWs_External_LO__c), 2 Lead agent flows (Owner is External LO ends like silent recycle), birthday/anniversary (Get Records filter), Alert_Message_Owner_of_New_Reply (To != +15615894420).
- Deep link: 'texts' tab opens Communications -> Texts on Leads and Loans; realtor/past-client pages open on their page (realtor page shows its Texts card).
- ponytail: the Texts deep link is in memory only (not in the URL), like the existing 'requests' tab; add c__tab when someone needs shareable links.
- 2026-10-13: all 10 gated flows verified ACTIVE at the activate/ versions. Daily schedule STARTED by owner request: System.schedule('LoWsAutoTextDaily', '0 0 10 * * ?') → CronTrigger 08eQi00001G7l6w, runs as Chris (ET), first fire 2026-10-14 10:00 ET.
