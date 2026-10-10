# External LO Onboarding + LO Workspace Guided Tour — grilling log

Status: GRILLING IN PROGRESS (started 2026-10-08). Build nothing until the user confirms shared understanding.

## Round 1 decisions (2026-10-08)

1. **Deliverable** = admin runbook + provisioning script (creates user, profile/role/PSG/PSLs/package seats, User fields; prints gaps) + in-app "Get connected" checklist in LO Workspace with live status + Connect buttons. Welcome one-pager deferred.
2. **Who onboards** = Chris only for now; managers (Brandon, Adam) send the hire details (name, NMLS, licensed states, mobile, start date).
3. **Stages** = Pre-hire (manager + M365 admin: NMLS/states, Outlook mailbox, Zoom account) → Day 0 (admin: SF user, licenses, permsets, User fields, landing-page config) → Day 1 (LO: first login, MFA, mobile app, connect accounts, setup Q&A, tour) → Week 1 (manager: test landing-page lead, logged call, pre-approval letter, Perfect Week review).
4. **Day 1 order** = Connect accounts → Setup Q&A → Tour.
5. **Gating** = BOTH the connections and the setup Q&A are REQUIRED before using LO Workspace (user overrode the "nudge only" recommendation). Tour stays skippable/replayable.
6. **Tour placement** = LO Workspace only; hidden in the Partner Workspace portal (shared shell).
7. **Tour shape** = full "perfect day" run (~12-15 stops) on first login + a "Take the tour" chapter menu for replays.
8. **Offboarding** = included in the runbook, admin-only (Chris). Freeze, reassign leads + realtor tags, revoke OAuth, free paid seats, disable landing page.
9. **Avatar** = "Bran the Mortgage Man", friendly coaching male voice. Source image: `bran-source.png` (user-provided; illustrated man with glasses holding a house, thumbs up, Reach logo sweater, full scene background).

## Round 2 decisions (2026-10-08)

10. **Avatar art** = Bran ISOLATED: no house, no background (transparent cut-out). Removing the house needs the hand repainted — an image-editing/AI-image task, not code. Fallback until the cut-out exists: head-and-shoulders circle crop (excludes the house).
11. **Voice** = text-only speech bubbles in a friendly coaching voice. No audio at launch.
12. **Bran is a mascot**, never presented as Brandon. Get Brandon's OK on the likeness.
13. **Gate escape hatch** = lock screen lists what's missing + "Contact Chris"; admin-only per-user, per-connection waiver, logged.
14. **Gate is one-time** (first login only). Later breakage = red banner + red checklist row, never a lockout.
15. **Tour progress** stored on the User record (completed date + chapters seen).
16. **Desktop only**; one "LO Workspace on your phone" chapter in the desktop tour.
17. **Existing users** (pilot, Brandon, Chris) do NOT get the auto-tour; they get the "Take the tour" menu. Auto-launch only for LOs who haven't finished first-login setup.


## Org facts (read-only check 2026-10-08)

- Licenses: Salesforce 21/24 used (3 spare). EAC PSL 23/100. TwilioSF 19/20 seats (1 free). RingCentral (rcsfl 6.25.2) is site-wide; per-user = Call Center "RingCentral" (04vAJ0000008OJSYA2) + Nimbus pull job keyed on User.Rc_Extension_Id__c + RingCentral_*_Token__c.
- EAC: pilot has the PSL but NOT the `StandardEinsteinActivityCapturePsl` permset (Joe + 22 users have both); PSG lacks it. EAC configuration membership + Connected Accounts are Setup/user-only; connection status is NOT queryable.
- Zoom per-user OAuth: principal + UserExternalCredential CRUD already in the PSG. Connection status NOT queryable via SOQL (a live test callout through the per-user named credential is the only check).
- Twilio: automated texts (incl. In-Person Invite) send seatless from the default sender — confirmed on the pilot 2026-10-05.
- Auth: no SSO; MFA enforced on the profile + PSG; no IP ranges/login hours.
- Pilot User.Email = clowman@ (shared with Chris) — breaks landing-page email matching and HomeToolsController email lists. Real LOs need their own RHL mailbox as Email.
- Landing-page webhook NOT live: LO_Landing_Page_Config__mdt has 0 records (503), guest permset unassigned, never smoke-tested (PHASE6 steps 1-3 outstanding). One shared secret; each LO's page sends loEmail = their Username.
- Never add External LOs to internal sharing groups (Lead Sharing, Access To Realtor Accounts, LP groups…). User.Loan_Partner__c must stay blank.
- First-login hook: User.External_LO_Onboarding_Complete__c (ExternalLoOnboardingService.getState); shell handleOnboardingCompleted; isExperienceCloudContext() = *.site.com.
- No onboarding runbook exists yet in lo-workspace/.

**Avatar poses (final, full-body v2 2026-10-08)**: 8 transparent PNGs (~310-430 x 587) in `poses/`: bran-waving, -pointing, -presenting, -thinking, -arms-crossed, -hands-on-hips, -thumbs-up, -double-thumbs. Only bran-hands-on-hips has a stray fragment (a neighbouring hand at the right edge) — trim before upload.

## Round 3 decisions (2026-10-08)

18. **Gate rows**: REQUIRED = Zoom (live test callout through the per-user credential) + Outlook/EAC (LO attests "I've connected"; Chris confirms when emails land). RECOMMENDED, non-blocking = Salesforce mobile app (green on first mobile login).
19. **RingCentral** = manager decides at hire. If yes: script sets Call Center + RC extension prerequisites, and it becomes a REQUIRED gate row (extension id + pull-job authorization). Flag: the RC call-log pull job is Nimbus code — needs an owner.
20. **Twilio** = no seat by default (script refuses if 0 free). NEW: the LO must be able to SEE the Twilio texts going to agents. Fact: TwilioSF__Message__c is Public Read/Write org-wide (1,584 outbound + 183 inbound in 30 days), lookups only to Lead/Contact/Account — no Transaction link.
21. **EAC** = script assigns PSL + `StandardEinsteinActivityCapturePsl` permset; runbook carries the manual Setup step (add to EAC configuration). Fix the pilot first as the script's first test.
22. **Pilot mailbox** = give the pilot its own M365 mailbox (e.g. outsidelo.internal@) to test Outlook + landing page end to end.
23. **Landing-page webhook** = one-time org setup in the runbook, smoke-tested with the pilot. PLUS: prompt Chris to set up the LO's landing page whenever a new External LO user is created.
24. **User fields**: Admin Day 0 = NMLS, Licensed States, Phone, Email signature, Headshot, Enhanced_Note_Role__c "Loan Officer", Intake_Form_Notification__c + Include_in_Lead_Stagnant_Alerts__c on. LO via setup Q&A = goals/workdays/business focus. Always blank = Loan_Partner__c, Zoom_Host_Email__c. Script refuses Loan_Partner__c and internal sharing groups.
25. **Hire intake** = fixed field list sent by email/Teams; Chris pastes into the script.
26. **Offboarding** = leads + owned accounts → manager named at offboarding (default Brandon); in-flight loans' Loan Officer → internal LO the manager picks; realtor tags removed; freeze, reassign, then deactivate.

## Round 4 decisions (2026-10-08)

27. **Twilio visibility** = only texts about the LO's own leads/loans (incl. agents on those loans); never another LO's texts to the same realtor. Messages carry no Transaction link → stamp the originating loan at send time (confirm mechanism in build). Needs a restriction rule like the other 8 Public R/W objects.
28. **Agent replies** (inbound) shown read-only + "reply from your phone" hint with the agent's number. No reply from SF (no seat).
29. **Placement** = "Texts" tab on each My Loans loan + Texts section on the realtor page; inbound agent replies (not automated sends) surface in the Perfect Day Recent log.
30. **Landing-page prompt** = email + bell notification to Chris whenever a user becomes an active External LO (catches Setup-created users); script prints the same reminder.
31. **Empty workspace** = record-level stops show an annotated screenshot inside Bran's bubble when there is no data; real spotlight when data exists (replay menu).
32. **Tour script doc** (every stop: page, highlight, pose, exact bubble text) approved by the user BEFORE build.
33. **Tour text lives in code** (one JS step file); wording changes = quick deploy.
34. **Oversight tab** gets per-LO onboarding status (setup done, each connection green/red/waived, tour done). Week-1 manager checks stay in the runbook only.

## Round 5 decisions (2026-10-08)

35. **Reset onboarding** = admin-only action: clears setup-complete flag, connection attestations, waivers, tour progress; keeps goals + data. Used to re-test the gate on the pilot.
36. **Waivers** = "Waive" button on the LO's row in the Oversight onboarding status, admin-only (Brandon/Adam see status, can't waive), reason required + logged.
37. **Zoom** = every outside LO gets a Reach company Zoom licence under their RHL email (required so recordings/transcripts reach Call_Insight__c) UNLESS Chris waives it. Owners: M365 mailbox = Bianca Rodrigues with the IT team; Zoom user + RingCentral user/extension = Chris.
38. **"Ready" alert** = email + bell to Chris + the LO's manager when the LO clears the gate ("X is live in LO Workspace") — starts the Week-1 checks.
39. **Runbook** = `lo-workspace/onboarding/RUNBOOK.md` (single source) + a private web artifact for Brandon/Adam with the hire-details list + Week-1 checks.

Action items for the user: Brandon's OK on the Bran likeness; RC call-log pull job (Nimbus code) needs an owner.

## Proposed build order (pending user confirmation)

- O1 Provisioning: script (sf CLI) + pilot fixes (EAC permset, own mailbox) + one-time landing-page webhook setup + smoke test.
- O2 First-login gate: "Get connected" checklist (Zoom live test, Outlook attest, RingCentral when flagged, mobile recommended), waivers, reset, alerts (Q30, Q38), Oversight onboarding status.
- O3 Agent texts: stamp originating loan on TwilioSF__Message__c + restriction rule + loan Texts tab + realtor Texts section + replies in Recent log.
- O4 Tour: script doc → user approval → Bran tour LWC (LO Workspace only, User-record progress, chapter menu).
- O5 Runbook + offboarding section + manager artifact.

## Status 2026-10-08 (paused by user)

User CONFIRMED shared understanding and said "Begin". O1 started: only PHASE6.md was re-read. NO org changes and no files built yet.
Resume with O1:
1. Fix pilot: assign `StandardEinsteinActivityCapturePsl` permset (PSL already held) — approved under Q21.
2. Landing-page go-live (PHASE6 post-deploy steps): assign `LO_Landing_Page_Webhook_Guest_Access` to Integrations guest 005Qi00000FehqSIAR; create LO_Landing_Page_Config__mdt `Default` with a generated secret (Setup or metadata deploy; give secret to marketing); smoke test with loEmail = outsidelo.internal@reachhomeloans.com (username), fresh example.com email, no phone; delete the test lead after.
3. Write the provisioning script (dry-run first) + reconcile mode for existing users.
Pilot's own mailbox waits on Bianca/IT.

## O1 progress 2026-10-09

- DONE: pilot given permset StandardEinsteinActivityCapturePsl (PSA 0PaQi00000vUczuKAC).
- DONE: Integrations Site Guest User given LO_Landing_Page_Webhook_Guest_Access (PSA 0PaQi00000vUgx4KAC).
- BLOCKED for Claude (auto-mode refused generating + deploying a prod secret): Chris creates LO_Landing_Page_Config `Default` in Setup > Custom Metadata Types > LO Landing Page Config > Manage Records > New, Webhook Secret = a long random string. Then smoke test.
- BUILT: `provision-external-lo.js` (+ `hire.example.json`). Dry run default, `--apply` to change. Input checks (RHL email, NMLS digits, states, refuses Loan Partner/groups), refuses duplicate Email / no free licence / no Twilio seat; reconcile mode for existing users (adds missing PSL/PSG/EAC permset/Twilio only, never overwrites fields, warns on Email/NMLS/states/groups/Loan Partner). Prints the manual steps. Dry-run tested: bad input, pilot reconcile (now nothing to do; warns Email = clowman@), new hire. The --apply create path is NOT yet exercised — first real hire (or a throwaway user) proves it.
- Webhook secret: the Default record was created by Chris 2026-10-09 10:16 but Webhook_Secret__c is blank — the field is NOT on the mdt page layout. My layout deploy was refused (auto mode blocks prod deploys) → Chris adds it in Setup (Page Layouts > drag Webhook Secret), then fills the value.

## New requirement 2026-10-09: no "External LO" / "Outside LO" wording visible to LOs

User: the words "External LO" / "Outside LO" must not be seen anywhere by the loan officers in LO Workspace — backend only (roles, profiles, permsets, API names stay). Inventory of user-visible hits running (read-only). Scope questions pending (portal? managers? replacement wording?).
- 2026-10-09: Chris added the secret (64 chars). SMOKE TEST PASSED: POST → 202; lead 00QQi00000slD2mMAE owned by the pilot, New, LeadSource "LO Landing Page", Consumer RT, Loan_Partner__c null, Custom_Log__c "LO Landing Page" row with no errors. Test lead deleted (recycle bin). Landing-page webhook is LIVE. O1 complete except the pilot's own mailbox (Bianca/IT) and a real-hire run of `--apply`.

### Wording decisions (2026-10-09)
Inventory (read-only, fresh retrieve): LOs actually see only (1) CustomLabel ExtLO_Shell_User_Role "External Loan Officer" under their name in the shell (shared with portal) and (2) the LO_Workspace app description. Raw list: scratchpad rename-inventory/hits.md.
40. Shell role line → "Loan Officer" in LO Workspace only (context-dependent like brandTitle); portal label unchanged. Folded into O2 (same shell file).
41. App description → "Your daily workspace: Perfect Day, leads, pre-approvals, loans and realtors."
42. Relabel (labels only, API names unchanged): User.ExtLO_Workdays_Per_Week__c → "Workdays Per Week"; User.External_LO_Onboarding_Complete__c → "LO Workspace Setup Complete" (+ help text); External_LO_Activity_Goal__c → "Activity Goal(s)"; report type LO_Workspace_Loans description reworded.
43. Pilot user → Name "LO Pilot", Title "Loan Officer". Profile/role names stay (backend).
44. Reports "Outside LO Leads/Loans by Status" → "LO Workspace Leads/Loans by Status" (+ descriptions); Oversight empty state reworded (folded into O2). Portal "Outside LO Portal" reports/flow untouched (Harold).
- 2026-10-09 RELABEL DEPLOYED 0AfQi000001UNxtKAG (lo-workspace/phaseRename, ref/ = pre-change org copies): app description, User fields → "Workdays Per Week" / "Workspace Setup Complete" (neutral for the portal too), object → "Activity Goal(s)", report type description, reports → "LO Workspace Leads/Loans by Status". Pilot user renamed "LO Pilot", Title "Loan Officer". Shell role line + Oversight empty state go with O2. Prod deploys DO work now (label-only needs RunSpecifiedTests, e.g. AppraisalOrderController_Test).

## O2 status 2026-10-09
BUILT + VALIDATED (lo-workspace/phaseO2, O2.md): check-only 0AfQi000001UOIrKAO, 29 tests, 0 failures. Reviewed: gate/banner apply only to External_LO users who have NOT finished setup → no existing user affected except the shell role line ("Loan Officer"). DEPLOYED 2026-10-09 (0AfQi000001UOPJKA4). LO_Workspace_Onboarding_Admin assigned to Chris. Script works against the new field (pilot dry run OK).
After deploy: assign LO_Workspace_Onboarding_Admin to Chris (005f2000009OtLnAAK) — the provisioning script needs the new field; then Oversight → Onboarding → Reset onboarding on the pilot to see the gate.
Follow-ups: (1) throttle the post-gate Zoom check (currently a live callout on every LO Workspace load after the gate; nobody affected yet); (2) LoWsLeadIntakeServiceTest.webhookRejectsBadCalls now fails (expects 503, the Default record exists → 401) and ExternalLoCsvImportServiceTest has 4 duplicate-match failures against current prod — both pre-existing/environmental, fix before the next deploy that needs them; (3) existing Nimbus RingCentral callback saves tokens to whatever user Id is in `state`.

## 2026-10-09 later
- O2b DEPLOYED 0AfQi000001UOxBKAW: Zoom banner re-check at most once/24h; LoWsLeadIntakeServiceTest uses testSecret='' seam; ExternalLoCsvImportServiceTest root cause = tests ran as Chris who holds LO_Workspace_Demo (isTagMode) → now run as a test-created admin.
- O3 BUILT + VALIDATED 0AfQi000001UOsLKAW (lo-workspace/phaseO3/O3.md), NOT deployed, awaiting owner decisions Q52-Q55. Extends loWsCommunications with a "Texts" subtab (no duplicate tab); attribution from TwilioSF__SF_Parent_Record_Id__c (no flow edits); ~83% of agent texts attributable; replies thread to the most recent outbound to that number within 30 days. Backfill script backfill-90d.apex not run.
- TOUR-SCRIPT.md drafted (15-stop Perfect Day run + 13 chapters, 19 screenshots, ~70 hooks). Owner questions Q45-Q51 pending.

## Round 6 decisions (2026-10-09)
45. "Take the tour": sidebar link under the LO's name + "?" on the Perfect Day banner.
46. BUILD FIRST, then tour: (a) Application Summary button on the LO Workspace lead page, next to "Convert to transaction"; (b) a Zoom scheduler in the Overview of every lead AND person account (past clients, realtors) — clean matching panel on the right side, schedules Zoom meetings tied to the record + their calendar (reuse zoomMeetingAssistant). Approved Investors chapter stays screenshot-only.
47. Phone chapter as is (2 tabs + ☰).
48. Rules for bubble copy (and behaviour):
  1. Pre-Approval Letter: an LO may issue it whenever lead Status = Pre-Approval; otherwise the button must give clear direction (what status is needed / how to get there).
  2. Convert: the bubble lists the application items; the modal already pulls what's in SF and offers "Info received" for the rest.
  3. Submission Form: appears on the Transaction after converting; complete it once the loan is imported and locked (if locking) with the chosen investor.
  4. Document review: no clock — it is an urgent action in Up Next (existing HIGH ALERT).
  5. Realtor Met → Active Partner: a manual move, or automatically when they send an attached lead.
  6. COC button (My Loans): submits a Change of Circumstance to Reach's COC team; LOs must NOT make changes directly with investors — the internal lock desk / COC team does.
49. Follow-up reminders surface in Up Next, NOT native popups → reword the follow-up picker's "8:00 AM reminder" hint.
50. Yes: fictional demo data on the pilot (example.com, no real phones) for the 19 screenshots, deleted after; recapture on page changes.
51. "Partner"/"Portal" wording is FINE. Only "Outside"/"External" must go → fix just the Perfect Day tab description ("Outside loan officers' workspace…").
52. Birthday/anniversary (account-parent) texts NOT shown. 53. Recent log shows borrower AND agent replies (as built). 54. Keep RingCentral SMS and Twilio Texts as separate subtabs for now. 55. 30-day reply window.
O3: re-validated 0AfQi000001UOynKAG (33 tests, 0 fail) after O2b invalidated the first id; my deploy was refused by auto mode → Chris runs the quick deploy, then `sh lo-workspace/phaseO3/run-backfill.sh`.
- O4a BUILT + VALIDATED 0AfQi000001UP5FKAW (lo-workspace/phaseO4a/O4a.md): Application Summary button (LWC copy loWsApplicationSummary over LeadNotesFormController), "Schedule a Zoom" card (loWsZoomCard → zoomMeetingAssistant variant=compact) on lead/past client/realtor Overview, letter guard toast + server re-check at finalize/deliver for External_LO, follow-up hint wording, tab description. Depends on O3 (externalLoRealtors built from O3) → deploy O3 first, then re-validate O4a. Open: letter only at Status=Pre-Approval (no reissue after); "Realtor Agent Meeting" Zoom template hard-codes Brandon/BranTheMortgageMan; reconnect panel only after a failed action.
- O3 re-validated 0AfQi000001UP8TKAW (another session deployed leadPreApprovalLetter at 14:54 today).
56. Letter: new letters may be issued at Pre-Approval OR any later status (owner's general rule → applies to everyone, not just LO Workspace). Exact allowed-status list to be confirmed with the owner.
57. "Realtor Agent Meeting" Zoom template → specific to whoever schedules (no hard-coded Brandon).
58. Zoom reconnect panel only after a failed action (as is).
- O3 DEPLOYED 2026-10-09 (0AfQi000001UPBhKAO). Backfill run (90 days, 9 windows): 5,035 outbound + 634 inbound touched, 32 outbound skipped (Lead lookup → converted lead: INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY). Backfill script fixed: O3 fields have NO FLS for anyone, so anonymous Apex must not reference them (even dynamic SOQL fails); uses Database.update(allOrNone=false).
- O4a re-validated 0AfQi000001UPDJKA4 (pre-O3 — must re-validate after O3). Letter allowed list (one constant LETTER_STATUSES): Pre-Approval, Nurture - Preapproval, Nurture-Pre-Approval, Active, Under Contract, Submitted For Disclosures; converted leads refused with their own message; applies to internal too (finalize/deliver now also gated for internal). Zoom invite names the host, "BranTheMortgageMan" handle dropped. Awaiting owner confirmation of the excluded statuses (Q59).
59. Owner CONFIRMED the letter status lists as proposed.
- O4a DEPLOYED 2026-10-09 (0AfQi000001UPI9KAO, validation 0AfQi000001UPGXKA4, 39 tests). NEXT: update TOUR-SCRIPT.md with Round 6 rules + new stops (Application Summary, Schedule a Zoom, Texts subtab), then fictional demo data on the pilot + 19 screenshots, then build the tour (O4b).
60. Demo texts: NO TwilioSF__Message__c inserts — inject example messages into the page DOM in Claude's browser just before each Texts screenshot; nothing saved.
61. RingCentral stop: yes, shown only to LOs set up with Reach's company RingCentral (LoWs_RingCentral_Required__c) for partner/client communication.
62. Brandon gave the go-ahead on the Bran likeness.
63. Demo data = option (b): real demo leads/realtors/events; ONE converted demo loan (stays at first status, deleted same day, Zapier/ARIVE checked after); other loan milestones = browser-only DOM copies for the screenshot; past client added as an IMPORTED past client (no loan → no MyHomeIQ webhook).
64. Claude's built-in browser can't pass Chris's biometric 2FA → screenshots via Claude in Chrome (Chris's logged-in Chrome), using Setup "Login as" LO Pilot.

## Demo data log 2026-10-09 (DELETE after screenshots)
Created via API as Chris, OwnerId = pilot, Consumer RT, LeadSource LO Landing Page, @example.com, no phones. Lead_Default_Scenario_Manager stamps Byron Richie on insert → cleared on every demo lead (notes would email him). Loan_Partner__c stayed null; no Twilio messages created.
Leads: L1 Demo Avery Nguyen 00QQi00000smdzFMAQ (New) · L2 Demo Blake Carter 00QQi00000smVaIMAU (Contact Attempt 1) · L3 Demo Casey Rivera 00QQi00000smD2IMAU (Working) · L4 Demo Dana Brooks 00QQi00000smNw6MAE (Docs Received for Review) · L5 Demo Ellis Morgan 00QQi00000smEb6MAE (Pre-Approval) · L6 Demo Finley Hayes 00QQi00000slxiJMAQ (Working) · L7 Demo Gale Foster 00QQi00000smeaLMAQ (Pre-Approval).
65. Old pilot test data DELETED 2026-10-09 (recycle bin): 5 "Sample TEST - LO Workspace" leads, converted lead Test Testiana + its account 001Qi00001bV0KUIA0 + loan a01Qi00001bUozKIAS, 3 TEST past-client accounts (Paula/Rita/Carl), the pilot's tags on Chris Rey (real realtor, Brandon's account — only the tag + the pilot's Manual AccountShare removed) and Testington Testeroi. Task 00TQi00001dMmOzMAK was already gone with its lead.
- O4b (tour) BUILT + DEPLOYED 2026-10-09 (validation 0AfQi000001UPMzKAO, deploy 0AfQi000001UPQDKA4): static resource LoWsTourAssets (8 poses, hands-on-hips cropped, bran-head, 26 placeholder screens), LWCs loWsTour / loWsTourSteps / loWsTourHooks, hooks in ~19 LWCs, getTourState/saveTourProgress (SYSTEM_MODE). Script deviations: F-03 screenshot-only (no wizard from the tour), J-03 runs on a lead's Log communication, K-03 can't spotlight Volume.
66. Deploy the tour now: yes. 67. Show "Skipped" separately on Oversight (skip ≠ done). 68. Resume a mid-run reload at the last stop. → follow-up package phaseO4c.
69. PD-05 (and B-01, which reuses it) now mentions dragging a card to another column to change status. O4c (Skipped + resume) DEPLOYED 0AfQi000001UPTRKA4; resume verified on the pilot (reload at stop 3 resumed at 3 of 16).
Demo records (cont.): P1 Demo Morgan Ellison 001Qi00001bvdRsIAI (imported-style past client, no loan) · co-borrower Borrower__c a2jQi000002ieevIAA on L3 · Tasks 00TQi00001eFRADMA4, 00TQi00001eF8FpMAK, 00TQi00001eFgc8MAC (open, due today), 00TQi00001eFEBIMA4 (L5, 9 days ago).
Demo realtors (via My Realtors > Add partner as the pilot): R1 Demo Nico Alvarez 001Qi00001bv5zhIAA (Met) · R2 Demo Oakley Bennett 001Qi00001bw2urIAA (Active Partner) · R3 Demo Quinn Harper 001Qi00001bvPASIA2 (Prospect). Events: E1 00UQi00000afl4fMAA (L3, tomorrow) · E2 00UQi00000afHrRMAU (R2, +3 days). Note: the Add partner panel keeps the previous entry's values after Create (minor UX bug).
Demo docs: L4 requests a2dQi00000CWEgrIAH (Review, + ContentVersion 068Qi000015DNOZIA4 dummy PDF), a2dQi00000CWEiTIAX (Requested), a2dQi00000CWElhIAH (Approved). L3 Referral_Source__c = R2 contact 003Qi00001MGhevIAD (buying agent still null). CONVERSION (real path, as the pilot via Login-as): L7 Demo Gale Foster → Person Account 001Qi00001bw14OIAQ + loan a01Qi00001bw14PIAQ "Foster - TRID Application" (owner + LO = pilot). Realtor tags a2lQi0000066pPNIAY / a2lQi0000066pdtIAA / a2lQi0000066plxIAA.
Provisioning script FIXED 2026-10-09: `sf api request rest` has no --json and -b needs '@file' — the create path would have failed on the first real hire; tested with a throwaway Task (created + deleted).

## Screenshots + cleanup 2026-10-09
- 22 real screenshots captured in Chris's Chrome as the pilot (Setup "Login as"), cropped by `phaseO4e/assets/crop-shots.ps1` from `phaseO4e/assets/shots.tsv`; DOM-only edits for texts (Q60), the loans board copies (Q63b), Recent-activity reply row, Application Summary example text (typed, never saved) and the old "Coffee with Outside…" calendar label. SS-PHONE-1..4 remain placeholders (need real phone captures).
- Static resource limit is 5 MB: PNGs were 6.1 MB → screenshots now JPEG q85 (pack 2.35 MB); loWsTour loads `screens/<id>.jpg`. DEPLOYED 0AfQi000001UPq1KAG (phaseO4e). Verified in the tour (Chapter F shows SS-SUBMIT).
- CLEANUP DONE same day (recycle bin): all Demo leads (incl. converted Gale), 5 Demo accounts, loan a01Qi00001bw14PIAQ, 3 tags, 3 doc requests + PDF, co-borrower, 4 tasks, 3 auto notes, 2 demo events, plus the old pilot in-person Campaign 701Qi00001bUKUxIAO ("Coffee with Outside LO · Testington Testeroi", from the pilot's pre-rename name) and its event. Verified 0 Demo leads/accounts, 0 pilot loans/leads/tags/events, 0 emails to example.com, 0 Twilio texts on demo records. Zapier SF→ARIVE task history NOT checked from here (the loan had no ARIVE id).
- Bugs noticed (not fixed): (1) My Realtors "Add partner" panel keeps the previous entry's values after Create; (2) Recent activity rows have a blank title for Tasks not created by LO Workspace logging (e.g. API/other-source Tasks); (3) 94 "Zoom Ingestion Error" Custom_Log__c rows today (vs 28 on Oct 5) — unrelated, worth a look.
70. Owner: fix bugs (1) Add partner stale values and (2) blank Recent-activity titles; REMOVE the phone chapter (M) and its SS-PHONE placeholders for now — may be re-added later. Package phaseO4f (building).
- O4f DEPLOYED 2026-10-09 (0AfQi000001UQ7lKAG): Add partner panel resets on open (verified in Chrome as the pilot: typed values, Cancel, reopen → all fields blank, type Realtor); Recent-activity title fallback Activity_Type__c → Task.Type → Subject minus " on <timestamp>" → "Activity" (covered by PerfectDayHomeServiceTest; not seen live — the pilot has no uncategorised Tasks after cleanup); phone chapter M + SS-PHONE removed (chapters A–L). Pre-existing failing tests: ExternalLoPortalServiceTest + ExternalLoPortalCoverageTest (block any TaskRepository deploy).
- O5: RUNBOOK.md written 2026-10-09 (stages, script commands, manual steps, Day-1 gate, Week-1 checks, admin tools, offboarding, known gaps). Manager page published (private): https://claude.ai/artifact/QuA3pAcyix4F8uUdFnnXSC (source manager-guide.html) — share it with Brandon/Adam from the page's Share menu.
- O4g (test-only) DEPLOYED 2026-10-09: ExternalLoPortalServiceTest + ExternalLoPortalCoverageTest were stale — they ran as Chris (LO_Workspace_Demo → isTagMode) and CoverageTest hit MIXED_DML in @testSetup. Now run as a test-created portal admin (ExternalLoPortalTestHelper.createPortalAdmin, + ConditionPermissions). TaskRepository coverage 75.3% from these alone. OPEN (pre-existing): Harold Ellis (hellis@, RHL Community User) has NO Condition__c read → portal getLoanDetail condition query (USER_MODE) would throw for him; needs a permset fix (e.g. ConditionPermissions) — owner decision, Harold is a real LO.
71. Owner (2026-10-09): Harold Ellis will be switched to LO Workspace later; fix his permissions (Condition__c read) as part of that migration — do NOT touch his portal user now.
