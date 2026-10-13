# LO Workspace guided tour: script (for approval before build)

Status: REVISED 2026-10-09 after Round 6 (grill decisions 45-59) and the O3 / O4a deploys. Awaiting owner approval (grill decision 32). Document only: nothing built, nothing deployed.
Update 2026-10-13: the owner approved `TOUR-UPDATE-2026-10-13.md` as written and it is merged here (chapter M "Communication settings", stop PD-CS, corrected PD-03/A-02, PD-04, PD-10/E-03, D-01, D-03, H-03, H-05, the `up-next-reply` hook). Built as package `lo-workspace/phaseO4h` (check-only validated, not deployed). Ship it only after the comms flow activation, otherwise PD-CS and M-02 ("from Reach's no-reply number") are not yet true.
Source: read-only Production retrieves from 2026-10-09. The first pass covered `externalLoPortalShell`, `portalUtils`, `perfectDayHome` + children, `externalLoLeads`, `externalLoPreApprovals`, `externalLoLoans`, `externalLoRealtors`, `loWsPastClientDetail`, `loWsAppointments`, `loWsFollowUpPicker`, `portalActivityModal`, `portalCommunicationModal`, `loWsInPersonEvents`, `bdInviteModal`, `loanSubmissionWizard`, `loWsVolumeDrawer`, `loWsConnectGate`, the `LO_Workspace` app, tabs, flexipages, `PerfectDayHomeBuilder` and CustomLabels. A second retrieve after O3/O4a covered `externalLoLeadConversionModal`, `loWsZoomCard`, `zoomMeetingAssistant`, `loWsApplicationSummary`, `loWsCommunications`, `externalLoRecentLog`, `externalLoRealtors`, `externalLoLoans`, `loWsPastClientDetail`, `loWsFollowUpPicker`, `externalLoPortalShell` and `perfectDayHome`. Every quoted label below is the on-screen text in prod today, unless it is marked (new). A (new) label is something the tour build adds.

---

## 1. Intro

### Principles
- Host: **Bran the Mortgage Man**, a mascot. He is never presented as Brandon or any other real person. He speaks in a friendly coaching voice and talks to the LO as "you".
- Text-only speech bubbles, **1-2 sentences per stop**. No audio.
- Desktop only, **LO Workspace only**. The tour is hidden when `isExperienceCloudContext()` is true.
- Wording (decision 51): bubble copy never says "External" or "Outside". "Partner" and "Portal" are fine. The app is always "LO Workspace".
- One pose per stop, from `lo-workspace/onboarding/poses/`:

| Pose file | Use for |
|---|---|
| `bran-waving.png` | Welcome |
| `bran-pointing.png` | "This one's yours" / point at a control |
| `bran-presenting.png` | Introduce a page |
| `bran-thinking.png` | Tip / why it matters |
| `bran-arms-crossed.png` | Rule: don't skip this |
| `bran-hands-on-hips.png` | Your turn: an action for the LO (trim the stray hand fragment first) |
| `bran-thumbs-up.png` | Step done |
| `bran-double-thumbs.png` | Tour finished |

- The tour drives the shell. Each stop names its view, and the tour calls the shell's own `navigateTo(view, filter, recordId)` before it spotlights anything, so the LO never has to find the page.
- Tour text lives in one JS step file (decision 33). The stop IDs below are its keys.

### When it runs
1. First login runs three steps in order:
   - **Step 1 of 3: Get connected** (`loWsConnectGate`).
   - **Step 2**: the setup Q&A ("Start my setup" on Perfect Day). Its steps are Focus, Activities, Targets, Rhythm, Review and Import.
   - **Step 3**: the full Perfect Day run (section 2) starts automatically on Perfect Day.
2. Auto-launch only for LOs who have not finished first-login setup (decision 17). The pilot, Brandon and Chris get the menu only.
3. Replays (decision 45): **"Take the tour"** (new) opens the chapter menu (section 3). There are two entry points, and both open the same menu:
   - a link in the sidebar, under the LO's name and role (`sidebar-user` block). Hook `tour-menu`.
   - a "?" button (new) at the end of the Perfect Day banner actions, after "Log activity" and "In Person Invite". Hook `pd-tour-help`. Tooltip: "Take the tour".
   Progress (completed date + chapters seen) is stored on the User (decision 15).
4. Every stop can be skipped. "Skip tour" asks once: "Skip the tour? You can replay it any time from Take the tour." The buttons are **Keep going** / **Skip**. Skipping still counts the tour as seen for auto-launch.

### Buttons (codes used in every table)

| Code | Buttons |
|---|---|
| F | **Let's go** · Skip tour (first stop of the full run) |
| S | Back · **Next** · Skip tour (a counter such as "3 of 16" is shown) |
| L | Back · **Finish** (last stop of the full run) |
| C | Back · **Next** · Exit chapter (chapter stops) |
| CL | Back · **Done** (last stop of a chapter; returns to the chapter menu) |

### Empty-state stops (decision 31)
A record-level stop needs data on screen, such as a lead card, a loan or an upload. A brand-new LO usually has none. The rule:
- **Data exists**: live spotlight on the real element.
- **No data**: the bubble grows to show an **annotated screenshot** (a callout arrow and label on the element the stop talks about), with the same text. There is no spotlight, but the page is still navigated to.
- Screenshots use **fictional demo records only**. They never show a real borrower, realtor or loan. They are 1280 px wide, captured on the pilot user, and stored as a static resource with the tour step file. Section 6 has the demo data plan.

---

## 2. Full "Perfect Day" run (17 stops + RingCentral)

Hooks are `data-tour="…"` attributes to add in the build (full list in section 7).

| # | Chapter | Page / view | Highlight (exact label · component · hook) | Pose | Bubble text | Empty-state screenshot? | Buttons |
|---|---|---|---|---|---|---|---|
| PD-01 | Welcome | Perfect Day (`perfectDay`) | Whole welcome banner (greeting + date) · `perfectDayHome` · `pd-banner` | waving | Hi, I'm Bran, your LO Workspace coach! Give me two minutes and I'll walk you through a Perfect Day from first coffee to wrap-up. | N | F |
| PD-02 | Morning check | Perfect Day | "of N activity goals met today" bar + pace badge, then the metric cards "Daily Score", "Goals Completed", "Overdue Tasks", "Activities Remaining" · `perfectDayHome` · `pd-progress`, `pd-metrics` | presenting | Start every morning right here: this bar shows how many of today's goals you've hit and whether you're on pace. The cards and the Pipeline snapshot below tell you where the money is today. | N (zeros are fine on day one) | S |
| PD-03 | Up Next | Perfect Day | "Up next for you" panel (first cards = red High alerts: "Text reply from …", then "Review documents", when they exist) + "Open all →" · `externalLoActivityPrompts` · `up-next`, `up-next-alert` | pointing | This is your to-do list, ranked by impact: text replies and documents to review sit at the very top as red High alerts, then follow-ups due today, new leads and weekly touches. Follow-ups you set show up here on the day they're due, so work it top to bottom every day. | Y, SS-UPNEXT | S |
| PD-04 | Logging & replies | Perfect Day | "Log activity" button (banner), then "Recent activity" with a "Text reply" row on top · `perfectDayHome`, `externalLoRecentLog` · `pd-log-activity`, `recent-log` | hands-on-hips | Every call, text, meeting or post goes in with Log activity, and it counts toward today's goals. When a borrower or agent texts back, the reply shows at the top of Recent activity, and a reply to an automatic text also gets its own card in Up Next. | Y, SS-RECENT (only when Recent activity has no reply) | S |
| PD-RC | Logging & replies | Perfect Day (only LOs on Reach's RingCentral, `User.LoWs_RingCentral_Required__c`; decision 61) | "Recent activity" · `externalLoRecentLog` · `recent-log` | thinking | Calls you make in Reach's RingCentral log here automatically and count toward your goals. | N | S |
| PD-CS | Your automatic texts | Perfect Day | Sidebar "Communication settings" link · `externalLoPortalShell` · `comm-settings` | pointing | Reach texts your borrowers and agents for you at key steps, from a no-reply number, and their answers land at the top of Up Next. Open Communication settings under your name any time to turn a message off or put it in your own words. | N | S |
| PD-05 | My Active Leads | My Active Leads (`leads`, Board) | Board columns "New", "Contacting", "Working", "Docs Requested", "Docs Received" + one card's "Move to…" · `externalLoLeads` · `leads-board`, `leads-move-to` | presenting | My Active Leads shows every working lead by stage. Open a card to work it, or drag it to another column (or use Move to…) to change its status right from the board. | Y, SS-BOARD | S |
| PD-06 | A lead page | Lead page (first lead in New, otherwise a screenshot) | Status dropdown + "Log communication" + tab bar (Overview, Documents, Document requests, Calls/Zooms, Communications, Notes) · `externalLoLeads` · `lead-status`, `lead-log-communication`, `lead-tabs` | pointing | Everything about one borrower lives here: set the status at the top and tap Log communication after every touch. Overview holds Contact and Pre-Approval Details; the other tabs hold documents, calls, texts, emails and notes. | Y, SS-LEAD | S |
| PD-07 | Schedule a Zoom | Lead page, Overview (right column) | "Schedule a Zoom" card + "Schedule Zoom Meeting" · `loWsZoomCard` (`zoomMeetingAssistant` compact) · `lead-zoom` | hands-on-hips | Book a Zoom with this borrower right from the Schedule a Zoom card: it goes on your calendar and they get the invite. If it ever says Connect your Zoom, follow the steps in the card and click Try again. | Y, SS-ZOOM | S |
| PD-08 | Texts | Lead page → "Communications" → "Texts" | "Texts" subtab (an agent text + a reply with "Reply from your phone") · `loWsCommunications` · `comms-texts` | thinking | Texts shows what Reach texted the borrower and their agent automatically, plus their replies. You can't reply from here, so use the number under Reply from your phone. | Y, SS-TEXTS | S |
| PD-09 | Document review | Lead page → "Document requests" tab | "Add Conditions", "Send Request Email", "Start review" · `leadPortalDocumentRequestManager` · `doc-req` | thinking | Document requests is where you ask for paperwork and review what comes back. Tap Start review, then Approve, Reject or Not Needed, and the borrower gets your comment on anything you reject. | Y, SS-DOCREQ | S |
| PD-10 | Pre-approval letter | Lead page header | "Pre-Approval Letter" button · `externalLoLeads` · `lead-letter` | pointing | Pre-Approval Letter works at any status, and finalizing it moves the lead to Pre-Approval and lets their agent know. A lead that's already been converted to a loan can't get a new letter. | Y, SS-LETTER | S |
| PD-11 | Application Summary | Lead page header | "Application Summary" button (next to "Convert to transaction") · `externalLoLeads` · `lead-app-summary` | presenting | Application Summary is the borrower's story, built from your call summaries. Fix anything that's wrong and add what's missing; later calls add to it and never overwrite what you write. | Y, SS-APPSUM | S |
| PD-12 | Convert to a loan | Lead page header | "Convert to transaction" button (the screenshot shows the "Confirm TRID application pieces" modal) · `externalLoLeads` · `lead-convert` | arms-crossed | Convert to transaction checks six things: Borrower name, Borrower income, Borrower SSN, Subject property, Estimated property value and Loan amount. Whatever's already in Salesforce fills in by itself; mark the rest Info received only when you really have it, then Confirm conversion. | Y, SS-TRID | S |
| PD-13 | My Loans | My Loans (`loans`, My Active Loans, Board) | Board columns "Application" → "Closing" + a "Needs update" badge · `externalLoLoans` · `loans-board` | presenting | Converted files land in My Loans, grouped by milestone from Application to Closing. A Needs update badge means the processor is waiting on you, so open that loan first. | Y, SS-LOANS | S |
| PD-14 | My Realtors | My Realtors (`realtors`) | Stage badge, "Follow-up due" badge, "Log touch" row action · `externalLoRealtors` · `realtors-list` | pointing | My Realtors is your referral engine: set each agent's stage and hit Log touch every time you reach out. Follow-up due shows who's going cold, and your list is yours alone. | Y, SS-REALTORS | S |
| PD-15 | Calendar | Perfect Day | "Upcoming appointments" + "Open calendar" · `loWsAppointments` · `appointments` | thinking | Upcoming appointments shows your next 7 days, including the Zooms you book, and Open calendar gives you the full month. Click any appointment to jump straight to that borrower or realtor. | Y, SS-CAL | S |
| PD-16 | Wrap-up | Perfect Day | Sidebar "Take the tour" link + banner "?" · `externalLoPortalShell`, `perfectDayHome` · `tour-menu`, `pd-tour-help` | double-thumbs | That's a Perfect Day: work Up Next, log every touch, set the follow-up, repeat! Want a refresher? Take the tour under your name, or the ? on this banner, replays any part. | N | L |

My Progress / Volume (previously PD-14) moved to chapter K only. PD-CS (2026-10-13) sits right after PD-RC and before PD-05, so every Perfect Day stop comes before the run moves to My Active Leads; it does not open the settings modal (chapter M does). The run is 17 stops ("N of 17"), 18 with RingCentral. Resume is keyed on the stop id, so a run in progress survives the new stop.

---

## 3. Chapter menu (replays)

The menu is titled **Take the tour**. Each row shows the chapter name, "N stops" and a tick once seen. The first row is **The full Perfect Day (17 stops)** (18 with RingCentral), which is section 2. "= PD-xx" means the stop is reused word for word.

### Chapter A: Perfect Day & Up Next (6 stops)

| # | Page / view | Highlight (label · component · hook) | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| A-01 | Perfect Day | = PD-02 (`pd-progress`, `pd-metrics`) | presenting | = PD-02 | N | C |
| A-02 | Perfect Day | = PD-03 (`up-next`, `up-next-alert`) | pointing | = PD-03 | Y, SS-UPNEXT | C |
| A-03 | Perfect Day | Up Next card buttons "Log it done", "Mark complete", "Tomorrow" · `externalLoActivityPrompts` · `up-next-actions` (never on a Text reply card, whose buttons are "Open thread" / "Mark handled") | thinking | Log it done records the touch, Mark complete closes a follow-up, and Tomorrow pushes the card to the morning. Use Tomorrow sparingly: a new lead you push may miss its contact window. | Y, SS-UPNEXT | C |
| A-04 | Perfect Day | "Pipeline snapshot" list (New leads need contact, Realtor follow-ups are due, Pre-approvals need review, Loans waiting on you, Overdue tasks need resolution) · `perfectDayHome` · `pd-pipeline-snapshot` | presenting | Pipeline snapshot counts what's waiting in each queue, and anything red is urgent. Click a row to open that exact list. | N | C |
| A-05 | Perfect Day | "Log activity" → "Log an activity" modal ("What did you do?") · `portalActivityModal` · `pd-log-activity`, `log-modal-category` | hands-on-hips | Your turn: every call, text, meeting or post goes in with Log activity, and it counts toward today's goals. Calls and texts from your own phone aren't captured automatically, so log them here. | N | C |
| A-06 | Perfect Day | "Today's Plan" (Log buttons) + "Recent activity" (a "Text reply" row with "Reply from your phone") · `externalLoTodayPlan`, `externalLoRecentLog` · `today-plan`, `recent-log` | thumbs-up | Today's Plan splits your weekly targets into today's share, with a Log button on each line. Recent activity shows everything you log, and borrower and agent text replies land at the top with the number to reply from your phone. | Y, SS-RECENT (only when no reply exists) | CL |

### Chapter B: My Active Leads (4 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| B-01 | My Active Leads, Board | = PD-05 (`leads-board`, `leads-move-to`) | presenting | = PD-05 | Y, SS-BOARD | C |
| B-02 | My Active Leads | "List" / "Board" toggle + search box · `externalLoLeads` · `leads-layout-toggle` | thinking | Prefer rows? Switch to List, and LO Workspace remembers your choice. The search box finds any lead by name or source. | Y, SS-BOARD | C |
| B-03 | My Active Leads | "Add lead" → "Add a lead" form ("Referring realtor") · `loWsAddLeadForm` · `leads-add` | hands-on-hips | Met someone at an open house? Add lead takes first and last name, phone, email and loan purpose, and you can pick the referring realtor so they get the credit. | N | C |
| B-04 | Nurtured Leads (`nurtured`) | Nav item "Nurtured Leads" · `portalNavList` · `nav-nurtured` | thinking | Leads you Move to… Nurture leave your active board and wait here. Check in on them now and then, because today's "not yet" is next season's buyer. | N | CL |

### Chapter C: A lead page (8 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| C-01 | Lead page | = PD-06 (`lead-status`, `lead-log-communication`, `lead-tabs`) | pointing | = PD-06 | Y, SS-LEAD | C |
| C-02 | Lead page, Overview | "Contact" card (borrower pills, "+ Add borrower") + "Pre-Approval Details" "Edit" · `loWsBorrowerPills`, `loWsLeadDetails` · `lead-contact-card`, `lead-pre-approval-details` | hands-on-hips | Keep Contact and Pre-Approval Details current, and add every co-borrower with + Add borrower. A borrower without an email can't get document requests. | Y, SS-LEAD | C |
| C-03 | Lead page, Overview (right column) | = PD-07 (`lead-zoom`) | hands-on-hips | = PD-07 | Y, SS-ZOOM | C |
| C-04 | Lead page → "Calls/Zooms" | "Phone calls (RingSense)", "Zoom meetings", "Logged calls" · `callInsightList` · `lead-tab-calls` | thinking | Recorded calls and Zoom meetings with this borrower show up here with their summaries. Anything you logged by hand sits under Logged calls. | Y, SS-LEAD | C |
| C-05 | Lead page → "Communications" | "Calls" / "SMS" / "Emails" / "Texts" subtabs · `loWsCommunications` · `lead-tab-comms` | presenting | Communications shows every call, text and email anyone at Reach has had with this borrower, newest first. Read it before you call so you're never caught off guard. | Y, SS-LEAD | C |
| C-06 | Lead page → "Communications" → "Texts" | = PD-08 (`comms-texts`) | thinking | = PD-08 | Y, SS-TEXTS | C |
| C-07 | Lead page header | = PD-11 (`lead-app-summary`) | presenting | = PD-11 | Y, SS-APPSUM | C |
| C-08 | Lead page → "Notes" | "New" → "New note" (type chips, "Pin to top of notes") · `loWsNoteModal` · `lead-notes-new` | pointing | Tap New to drop a quick note, and pin the important ones to the top. The lead's team gets an email copy, so keep it clear and short. | Y, SS-LEAD | CL |

### Chapter D: Document requests (4 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| D-01 | Perfect Day | First document High alert card in Up Next + "Review documents" · `externalLoActivityPrompts` · `up-next-alert` (document alerts only; reply cards carry `up-next-reply`) | arms-crossed | When a borrower uploads documents, a red High alert lands at the top of Up Next, right below any text replies. There's no timer on it, but it stays there as an urgent action until you review them. | Y, SS-ALERT | C |
| D-02 | Lead page → "Document requests" | "Add Conditions" · `leadPortalDocumentRequestManager` · `doc-req-add` | hands-on-hips | Start with Add Conditions to list what you need from the borrower. Assign each item to the right borrower so nobody gets asked for someone else's paperwork. | Y, SS-DOCREQ | C |
| D-03 | Lead page → "Document requests" | "Send Request Email" · `leadPortalDocumentRequestManager` · `doc-req-send` | pointing | Send Request Email gives each borrower their own list and upload link, and moves a new or working lead to Docs Requested. When they upload, the review shows up at the top of Up Next. | Y, SS-DOCREQ | C |
| D-04 | Lead page → "Document requests" | "Start review" → "Approve" / "Reject" / "Not Needed" · `leadPortalDocumentRequestManager` · `doc-req-start-review` | thinking | = PD-09 | Y, SS-DOCREQ | CL |

### Chapter E: Pre-approvals & the letter (3 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| E-01 | My Pre-Approvals (`preApprovals`) | Nav item + page title "My Pre-Approvals" · `externalLoPreApprovals` · `nav-my-pre-approvals` | presenting | My Pre-Approvals holds every borrower who's approved and shopping. These are your closest deals to a contract, so they get a touch every single week. | Y, SS-PREAPP | C |
| E-02 | My Pre-Approvals | Filter chips "All" / "Weekly touch due" / "On track" · `externalLoPreApprovals` · `preapprovals-filters` | arms-crossed | Weekly touch due means it's been 7 days or more since you last talked to them. Clear this list every week, and they'll show up in Up Next until you do. | Y, SS-PREAPP | C |
| E-03 | Lead page header | = PD-10 (`lead-letter`) | pointing | = PD-10 | Y, SS-LETTER | CL |

The letter has no status gate since 2026-10-12, and the O4a "Pre-approval letters unlock once…" toast no longer exists. Finalizing moves the lead to Pre-Approval (never backwards) and fires the Pre-Approved agent text (again on every new purchase price). On a converted lead the button shows: "This lead has already been converted to a loan, so a new pre-approval letter cannot be issued from it."

### Chapter F: Converting to a loan & the Submission Form (3 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| F-01 | Lead page header | = PD-12 (`lead-convert`) | arms-crossed | = PD-12 | Y, SS-TRID | C |
| F-02 | Loan page header | "Submission form" button · `externalLoLoans` · `loan-submission` | hands-on-hips | After you convert, the Submission form appears on the loan. Complete it once the loan is imported and, if you're locking, locked with the investor you chose. | Y, SS-SUBMIT | C |
| F-03 | Submission Form wizard | "Back" / "Next" + section title · `loanSubmissionWizard` · `submission-nav` | thinking | It walks you through investor, loan, property, borrowers, realtors and title, and anything we already know comes in prefilled. You can come back and edit it until Disclosures Out. | Y, SS-SUBMIT | CL |

### Chapter G: My Loans (6 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| G-01 | My Loans | = PD-13 (`loans-board`) | presenting | = PD-13 | Y, SS-LOANS | C |
| G-02 | My Loans | Tabs "My Active Loans" / "My Closed Loans" / "My Cancelled Loans" · `externalLoLoans` · `loans-tabs` | thinking | Funded files move to My Closed Loans and fall-throughs to My Cancelled Loans. If a purchase cancels for a reason we can still fix, the borrower comes back to you as a Pre-Approval lead. | Y, SS-LOANS | C |
| G-03 | Loan page | Milestone chip + tabs (Details, Notes, Calls/Zooms, Communications, Documents, Conditions, Appraisal) · `externalLoLoans` · `loan-milestone`, `loan-tabs` | pointing | The chip at the top shows exactly where the loan stands. Conditions shows what's still outstanding, and the processor clears them as they come in. | Y, SS-LOAN | C |
| G-04 | Loan page → "Appraisal" | 4-step tracker + "Messages with the appraisal company" · `loWsAppraisalPanel` · `appraisal-tracker`, `appraisal-messages` | presenting | Appraisal shows the order status, the key dates and the property map. Need something from the appraiser? Message them right here and it's saved on the order. | Y, SS-LOAN | C |
| G-05 | Loan page → "Communications" → "Texts" | "Texts" subtab (milestone text to the agent + reply) · `loWsCommunications` · `comms-texts` | thinking | On a loan, Texts shows the milestone updates Reach sends the agent automatically, and anything they text back. Reply from your own phone using the number shown. | Y, SS-TEXTS-LOAN | C |
| G-06 | Loan page header | "Change of circumstance" → "Submit COC" · `externalLoLoans` · `loan-coc` | arms-crossed | Amount, value, rate or program changed? Change of circumstance sends a COC to Reach's COC team. Never make changes with the investor yourself; the lock desk and COC team handle that. | Y, SS-LOAN | CL |

### Chapter H: My Realtors & tagging (6 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| H-01 | My Realtors | = PD-14 (`realtors-list`) | pointing | = PD-14 | Y, SS-REALTORS | C |
| H-02 | My Realtors | Filters "Last 30 days" / "Last 60 days" / "Last 90 days" / "Follow-up due" / "All partners" · `externalLoRealtors` · `realtors-filters` | thinking | Your list builds itself from the touches you log, so keep touching an agent and they stay on it. Follow-up due is the filter to check every morning. | Y, SS-REALTORS | C |
| H-03 | My Realtors | "Add partner" → "Add a partner" ("Search shared partners" + "Link"; "Tag me" on a Create new match) · `externalLoRealtors` · `realtors-add` | hands-on-hips | Add partner starts with a search of Reach's shared list: find the agent by name and tap Link, and they join your list with your own stage. Only create them new if they're not there, and tap Tag me if it spots a match. | Y, SS-REALTORS | C |
| H-04 | Realtor page | "My stage" (Prospect, Contacted, Meeting Set, Met, Active Partner, Dormant) + "Shared pipeline" + "New lead" · `externalLoRealtors` · `realtor-stage`, `realtor-shared-pipeline` | presenting | Move My stage forward as the relationship grows: you can set Active Partner yourself, and it moves there automatically when they send you a lead. Shared pipeline shows every borrower they've sent you. | Y, SS-REALTOR | C |
| H-05 | Realtor page | "Texts" card ("Automated texts" switch, "To <agent>", "Reply from your phone: …") · `externalLoRealtors` → `loWsCommunications` texts-only · `realtor-texts` | thinking | The Texts card shows what Reach texted this agent about your leads and loans, and their replies; answer from your phone with the number under Reply from your phone. Automated texts at the top of the card turns those texts off for this agent. | Y, SS-REALTOR | C |
| H-06 | Realtor page | "Schedule a Zoom" card · `loWsZoomCard` · `realtor-zoom` | hands-on-hips | Want a face-to-face? Schedule a Zoom books it with this agent and puts it on your calendar. Other Contacts in the menu works the same way for title, insurance and other pros. | Y, SS-REALTOR | CL |

### Chapter I: Past clients & CSV import (4 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| I-01 | Past Clients (`pastClients`) | Nav item + list · `externalLoPastClients` · `nav-past-clients` | presenting | Past Clients are the people you've already closed, and they're your easiest next deal and best referral source. Open one to log a call. | N (the page shows its own empty state) | C |
| I-02 | Past client page | "Log communication" + "New lead for this client" + "Loan history" + "Schedule a Zoom" card · `loWsPastClientDetail` · `past-client-new-lead`, `past-client-zoom` | pointing | Thinking of buying again or refinancing? Tap New lead for this client, or book a check-in with Schedule a Zoom, with their loan history right beside you. | Y, SS-PASTCLIENT | C |
| I-03 | Import Data (`importData`) | "Leads & past clients" card + "Choose file" · `externalLoCsvImport` · `import-consumer` | hands-on-hips | Bring your book with you: export a CSV from your old CRM and upload it under Leads & past clients. Use the Type column to mark each row Lead or Past Client. | N | C |
| I-04 | Import Data | "Realtors & partners" card + "Expected columns" · `externalLoCsvImport` · `import-partner` | thinking | Your agents go under Realtors & partners, and PartnerType sorts them into partners and prospects. We check for duplicates and never overwrite anyone else's relationships. | N | CL |

### Chapter J: Calendar, follow-ups & in-person events (5 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| J-01 | Perfect Day | = PD-15 (`appointments`) | thinking | = PD-15 | Y, SS-CAL | C |
| J-02 | Calendar (opened from "Calendar" / "Open calendar") | "Month" / "Week" / "Day" pills + event popover "Open" / "Event" · `loWsAppointments` · `calendar-views` | presenting | Switch between Month, Week and Day, and click any appointment to jump straight to that borrower or realtor. | Y, SS-CAL | C |
| J-03 | "Log an activity" / "Log communication" modal | "Follow-up": "No follow-up" / "General follow-up" / "Exact time" + "Tomorrow" / "In 3 days" / "Next week" / "Pick a date" · `loWsFollowUpPicker` · `follow-up-picker` | arms-crossed | Never end a conversation without a next step: a General follow-up shows up in Up Next on the day it's due, and an Exact time puts an appointment on your calendar. There are no pop-up reminders, so Up Next is where you'll find them. | N (shown inside the open modal) | C |
| J-04 | Perfect Day | "Upcoming In-person Events" card · `loWsInPersonEvents` · `in-person-events` | presenting | Hosting a lunch-and-learn or happy hour? Your upcoming events and who's said yes live right here. | Y, SS-EVENTS | C |
| J-05 | Perfect Day | "In Person Invite" button (banner) → "Invite partners" / "Send invites" · `bdInviteModal` · `pd-in-person-invite` | hands-on-hips | Tap In Person Invite, pick your agents, set the date and place, and hit Send invites. We send a branded invite with Yes / No buttons and the reminders for you. | Y, SS-EVENTS | CL |

### Chapter K: My Perfect Week & My Progress (4 stops)

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| K-01 | My Perfect Week (`perfectWeek`) | "This week" panel ("of plan completed") · `externalLoPerfectWeek` · `perfect-week-this-week` | presenting | My Perfect Week compares what you've done against the weekly targets you set. Glance at it Monday morning and again on Friday. | N | C |
| K-02 | My Perfect Week | "Edit my plan" · `externalLoPerfectWeek` · `perfect-week-edit-plan` | pointing | Business changed? Edit my plan reopens your setup questions so you can change your focus, activities and targets any time. | N | C |
| K-03 | My Progress (`progress`) | Week / Month / Quarter tabs + "Coaching focus", then the "Volume" edge tab · `externalLoProgress`, `loWsVolumeDrawer` · `progress-period`, `volume-tab` | thumbs-up | My Progress shows your actual numbers against your own targets, with a coaching focus where you're behind. Pull out the Volume tab on the edge any time for closed, pre-approved and new-lead totals. | N | C |
| K-04 | Perfect Day | "Goal Progress" with "Today" / "This week" / "This month" · `perfectDayHome` · `pd-goal-progress` | thinking | Goal Progress on Perfect Day is the quick version of all this. Green means goal met, and keep Overdue tasks at zero. | N | CL |

### Chapter L: Approved Investors (2 stops, screenshot only)

Approved Investors is a separate app tab outside the shell. The tour stays on Perfect Day and shows a centered bubble with a screenshot. No hooks and no link inside the shell.

| # | Page / view | Highlight | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| L-01 | Perfect Day (centered bubble) | none | presenting | Approved Investors, the tab next to Perfect Day at the top, lists every investor we can send a loan to, with their products, channels and account executives. | Y, SS-INVESTORS (always) | C |
| L-02 | Perfect Day (centered bubble) | none | thinking | Check it before you pick an investor on the Submission form, so the channel and product match. | Y, SS-INVESTORS (always) | CL |

### Chapter M: Communication settings (6 stops; added 2026-10-13)

Letter M was freed when the phone chapter was removed; if the phone chapter comes back it takes N. Menu row: "Communication settings · 6 stops", after L.

What the LO sees (prod 2026-10-13): sidebar link "Communication settings" under "Take the tour" (LO Workspace only). Modal "Communication settings", subtitle "Automated texts sent for you from the no-reply number (561) 589-4420. Replies show in Up Next; answer them from your own phone.", groups "To buyer's agents" (8) and "To borrowers" (7); each row has a when-line, an On / Off switch (saves at once), the preview with a locked "No-reply" footer and "Edit message". The editor has merge-field chips, a 160-character counter, "Reset to default" (saves at once), "Cancel", "Save message". Per-contact "Automated texts" switch on the lead Overview Contact card, the Realtor "Texts" card, the Past client Contact card and the top of the loan's "Loan details"; turning off asks "Turn off automated texts?". Replies to the no-reply number raise a red "Text reply from <name>" card ("Open thread" / "Mark handled") at the very top of Up Next, and still show in Recent activity.

| # | Page / view | Highlight (exact label · component · hook) | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| M-01 | Perfect Day | Sidebar "Communication settings" link, just under "Take the tour" · `externalLoPortalShell` · `comm-settings` | pointing | Communication settings, right under your name, controls the automatic texts Reach sends for you to agents and borrowers. Every message starts switched on, so take a minute to make them sound like you. | N | C |
| M-02 | Perfect Day, "Communication settings" modal open (clicks `comm-settings`) | Modal header + subtitle "Automated texts sent for you from the no-reply number (561) 589-4420…" · `loWsCommSettingsModal` · `comm-settings-intro` | thinking | These texts go out from Reach's no-reply number, (561) 589-4420, and always end with No-reply. When someone answers, reach them from your own phone. | N | C |
| M-03 | Modal | Group titles "To buyer's agents" / "To borrowers", each row's when-line and On / Off switch · `loWsCommSettingsModal` · `comm-settings-groups` | presenting | Messages are grouped To buyer's agents and To borrowers, and each one tells you when it goes out. Switch one to Off and it stops on every one of your files. | N | C |
| M-04 | Modal, first row's editor open (clicks `comm-settings-edit`; after: `comm-settings-cancel`, `comm-settings-close`) | Textarea, field chips, character count, "Reset to default", "Save message" · `loWsCommSettingsModal` · `comm-settings-editor` | hands-on-hips | Tap Edit message to write it your way: the field buttons drop in names like {First Name}, and the counter warns you past 160 characters. Save message keeps your version, and Reset to default brings Reach's wording back. | N | C |
| M-05 | Lead page, Overview (record; clicks `lead-tab-overview`) | "Automated texts" row in the Contact card ("Borrower <name>" · On) · `loWsTextsSwitch` · `texts-switch` | arms-crossed | Need one person left alone? Switch Automated texts to Off here, or on their realtor, past client or loan page, and you'll be asked to confirm. Nothing automatic goes to them until you switch it back on. | Y, SS-SWITCH | C |
| M-06 | Perfect Day | First "Text reply from …" card + "Open thread" / "Mark handled" · `externalLoActivityPrompts` · `up-next-reply` | thumbs-up | When someone replies to one of these texts, a red Text reply card jumps to the top of Up Next. Open thread shows the whole conversation, and Mark handled clears the card once you've called or texted them back. | Y, SS-REPLY | CL |

Build rules (as built in O4h): M-02..M-04 each click `comm-settings` (opening is idempotent) and close it with `comm-settings-close` on leave, so Exit chapter or Back never leaves the modal open; M-03 waits for the rows (`need: comm-settings-edit`); M-04 also clicks `comm-settings-edit` and leaves with `comm-settings-cancel` then `comm-settings-close`. The tour never clicks a switch, "Reset to default" or "Save message" (all three save at once). M-05 only spotlights the switch; it never toggles it, and with no switch on the page it shows SS-SWITCH. The tour overlay (z-index 100000) sits above the modal (9100) and the switch dialog (9200).

---

## 4. Phone chapter

Phone chapter removed 2026-10-09 at owner request; re-add later as chapter N (M is Communication settings since 2026-10-13).

---

## 5. Screenshots (all captured on the pilot, from the section 6 demo data)

Each shot is 1280 px wide and annotated with a callout arrow and label.

| Shot | Used by | Page | Demo data needed (section 6 IDs) | Annotated |
|---|---|---|---|---|
| SS-UPNEXT | PD-03, A-02, A-03 | Perfect Day, "Up next for you" | L4 doc request in Review (High alert on top), L1 New ("Call …"), L3 follow-up Task due today ("Follow up with …"), L5 weekly touch due | High alert card, "Open all →", "Log it done" / "Mark complete" / "Tomorrow" |
| SS-ALERT | D-01 | Perfect Day, Up Next top card | L4 with a request in Review | Red High alert "Review documents: Demo Dana Docs" + "Review documents" |
| SS-RECENT | PD-04, A-06 | Perfect Day, "Recent activity" | T2 inbound reply (≤ 7 days old) + 2 logged Tasks on L3 | "Text reply" row with "Reply from your phone: …" on top, "Log activity" in the banner |
| SS-BOARD | PD-05, B-01, B-02 | My Active Leads, Board | L1 New, L2 Contacting, L3 Working, L4 Docs Received | Columns, one card's "Move to…" open, List / Board toggle |
| SS-LEAD | PD-06, C-01, C-02, C-04, C-05, C-08 | Lead page L3, Overview | L3 with Pre-Approval Details filled, 1 co-borrower pill, 1 note | Status dropdown, header buttons, tab bar, Contact card, "+ Add borrower", Pre-Approval Details "Edit" |
| SS-ZOOM | PD-07, C-03 | Lead page L3, Overview right column | L3 (nothing is scheduled; empty "No Zoom meetings have been scheduled here yet.") | "Schedule a Zoom" card, "Schedule Zoom Meeting". Inset: the reconnect panel "Connect your Zoom to schedule from here" + "Try again" (capture with the pilot's Zoom access temporarily revoked, or crop from the component in a test view) |
| SS-TEXTS | PD-08, C-06 | Lead page L3 → Communications → Texts | T1 outbound status text to the agent + T2 reply on L3 | "Texts" subtab, "To …" line, "Reply from your phone: …" |
| SS-TEXTS-LOAN | G-05 | Loan page N2 → Communications → Texts | T3 outbound milestone text + T4 reply on N2 | Same callouts as SS-TEXTS |
| SS-DOCREQ | PD-09, D-02..D-04 | Lead page L4 → Document requests | L4 with 3 requests: 1 in Review (with a dummy PDF), 1 Requested, 1 Approved | "Add Conditions", "Send Request Email", "Start review", Approve / Reject / Not Needed |
| SS-LETTER | PD-10, E-03 | Lead page L5, Pre-Approval Letter modal | L5 at Pre-Approval with Pre-Approval Details filled | The letter preview |
| SS-APPSUM | PD-11, C-07 | Lead page L5, Application Summary modal | L5 with summary fields typed in and saved (no Call_Insight__c needed) | "Application Summary" button next to "Convert to transaction", modal sections, "Save" / "Save to Note" |
| SS-TRID | PD-12, F-01 | Lead page L6, "Confirm TRID application pieces" | L6 with name, income and property filled; value and amount blank | Ticked rows, one "Info received" button, the "I confirm…" box, "Confirm conversion" (capture, then **Decline**) |
| SS-PREAPP | E-01, E-02 | My Pre-Approvals | L5 (weekly touch due) + L7 (on track) | "Weekly touch due" chip, both rows |
| SS-SUBMIT | F-02, F-03 | Loan page N1, Submission form wizard, "Investor & channel" | N1 at Application | "Submission form" button, section title, Back / Next (never submit) |
| SS-LOANS | PD-13, G-01, G-02 | My Loans, Board | N1 Application, N2 Processing (Needs update), N3 Conditionally Approved, N4 Clear to Close, N5 Closing | Columns, "Needs update" badge, Active / Closed / Cancelled tabs |
| SS-LOAN | G-03, G-04, G-06 | Loan page N3 | N3 with 2 open conditions + an appraisal order | Milestone chip, tabs, Appraisal tracker, "Change of circumstance" with the COC modal open (never "Submit COC") |
| SS-REALTORS | PD-14, H-01..H-03 | My Realtors | R1 Met (follow-up due), R2 Active Partner, R3 Prospect, all tagged to the pilot | Stage badges, "Follow-up due", "Log touch", filters, "Add partner" |
| SS-REALTOR | H-04..H-06 | Realtor page R2 | R2 as referring realtor on L3 (Shared pipeline), T5 outbound + T6 reply to R2's number | "My stage", "Shared pipeline", "Texts" card + "Reply from your phone", "Schedule a Zoom" card |
| SS-PASTCLIENT | I-02 | Past client page P1 | P1 with 1 closed loan | "New lead for this client", "Loan history", "Schedule a Zoom" card |
| SS-CAL | PD-15, J-01, J-02 | Perfect Day + the calendar | E1, E2 Events in the next 7 days (WhoId L3, R2) | "Upcoming appointments", "Open calendar", Month / Week / Day, one popover with Open / Event |
| SS-EVENTS | J-04, J-05 | Perfect Day, In-person events | V1 in-person event with R1, R2 invited (1 Yes) | The card, the In Person Invite modal with "Invite partners" / "Send invites" (never send) |
| SS-INVESTORS | L-01, L-02 | Approved Investors tab | none (real investor list, no borrower data) | The tab in the nav bar, "Open investor list" |
| SS-SWITCH (new 2026-10-13) | M-05 | Lead page L3, Overview | L3, no phone on the lead | Contact card with the "Automated texts" row "Borrower Demo Casey …" · On. Inset: the "Turn off automated texts?" dialog with Cancel / Turn off (click the switch, capture, then **Cancel**, never Turn off) |
| SS-REPLY (new 2026-10-13) | M-06 | Perfect Day, "Up next for you" | DOM-only edit of a real card (same method as the 2026-10-09 texts shots, Q60); no inbound TwilioSF__Message__c is inserted | Top card "High alert · Reply to an automated text", "Text reply from Demo Oakley Bennett", a short reply in quotes + "Reply from your phone to 407-555-01xx", "Open thread" / "Mark handled"; a document alert underneath |

Recapture needed since 2026-10-13 (the per-contact switch is missing in these shots): SS-LEAD (L3 Overview; can be the SS-SWITCH capture without the dialog), SS-REALTOR (R2, "Automated texts" row above the thread), SS-PASTCLIENT (P1 Contact card), SS-LOAN (N3 "Loan details" top rows). Optional: SS-UPNEXT with a DOM-edited reply card on top. Two capture cautions: never click "Turn off" or a settings switch on the pilot (both save), and leave the pilot's Communication settings at defaults (`User.LoWs_Comm_Settings__c` blank). Until captured, SS-SWITCH and SS-REPLY ship as placeholders (phaseO4h/assets).

Stops that never need a screenshot: PD-01, PD-02, PD-RC, PD-CS, PD-16, M-01..M-04, A-04, A-05, B-03, B-04, I-01, I-03, I-04, J-03, K-01..K-04, and every nav-item stop. In those stops the page itself is the subject.

---

## 6. Demo data plan (decision 50)

All demo records are fictional, owned by the pilot user **outsidelo.internal@reachhomeloans.com** ("LO Pilot"), and named **"Demo …"**. Emails use **@example.com**. **No phone numbers** go on any Lead, Account or Contact, which means no Twilio send and no Zapier phone path can fire. Create them as the pilot through LO Workspace where a UI exists (for example Add lead, Add partner or the TRID modal), so the screenshots show the real path. Use data loads only where there is no UI. They are recaptured whenever a page changes: rebuild from this list, capture, then clean up.

### Records

| ID | Record | Status / setup |
|---|---|---|
| L1 | Lead "Demo Avery New" | New, never contacted |
| L2 | Lead "Demo Blake Contacting" | Contact Attempt 1 |
| L3 | Lead "Demo Casey Working" | Working; Pre-Approval Details filled; co-borrower "Demo Casey Partner" (example.com); Referring realtor = R2; 2 logged Tasks; 1 open follow-up Task due today; 1 note |
| L4 | Lead "Demo Dana Docs" | Docs Received; 3 Lead_Document_Request__c (Review with a dummy PDF, Requested, Approved). Insert the requests directly, do NOT click "Send Request Email" |
| L5 | Lead "Demo Ellis Preapproved" | Pre-Approval; last touch Task dated 8+ days ago (weekly touch due); Application Summary typed + saved |
| L6 | Lead "Demo Finley Convert" | Working; name, income and property filled, value/amount blank (TRID modal, Decline only) |
| L7 | Lead "Demo Gale Preapproved" | Pre-Approval, touched today (on track) |
| N1-N5 | Loans "Demo Harper/Indigo/Jordan/Kai/Lane Loan" | Made by converting demo leads (the real path, so the Submission form appears). Loan_Officer__c = pilot. Status__c: N1 Application, N2 Processing (with a stale milestone so it shows Needs update), N3 Conditionally Approved (2 conditions + an appraisal order), N4 Clear to Close, N5 Closing. No buying agent; Disclosures_Out_Date__c stays blank |
| P1 | Person Account "Demo Morgan Pastclient" | Past client with 1 closed Transaction; no birthdate, no anniversary |
| R1-R3 | Realtor Person Accounts "Demo Nico/Oakley/Quinn Realtor" | Tagged to the pilot. R1 Met + follow-up due, R2 Active Partner, R3 Prospect. Email example.com, no phone |
| T1-T6 | TwilioSF__Message__c | T1/T2 on L3 (outbound to "agent" + inbound reply ≤ 7 days old), T3/T4 on N2, T5/T6 on R2. Numbers are reserved fictional 555-01xx numbers on the message rows only, never on a record. See open question 1 |
| E1-E2 | Events | Next 7 days, owner pilot, WhoId L3 / R2, no invitees. Insert them; do NOT use "Schedule Zoom Meeting" (it creates a real Zoom meeting and emails an invite) |
| V1 | In-person event | R1 + R2 invited, R2 = Yes. Insert it; do NOT click "Send invites" |

### Automation side effects to avoid
- **Lead Loan Partner auto-assign**: every insert overwrites Loan_Partner__c, and the default is the Nimbus Development integration user, which also creates a Manual share. After each lead insert, check that Loan_Partner__c is blank (the landing-page path left it null). If it isn't, clear it as an admin.
- **Status-change agent texts**: Lead_Status_Change_Message_Sends texts the buyer's agent at Contact Attempt 1/2/3 and at Pre-Approval. The docs-requested and log-a-call flows also text the agent. So **no demo lead may have a buyer's agent**. After insert, verify that the buyer's agent field is still blank on L2, L3 and L5. Setting Referring realtor must not fill it. The demo realtors have no phone anyway, as a second guard.
- **Disclosures Out Date** null → non-null texts the buyer's agent and moves status. Never set it on a demo loan. The Submitted / Approved / Appraisal Ordered / Appraisal Received flows text the buying agent too, so no demo loan gets a buying agent.
- **SF → ARIVE status Zap**: demo loans have no ARIVE id. Check the Zap history after the status updates and confirm nothing was pushed.
- **MyHomeIQ Past Client webhook**: confirm it does not fire for P1 before creating it. If it would, skip SS-PASTCLIENT's closed loan and capture the page with history cropped.
- **No phone, no birthdate, no anniversary** on any record: this blocks the referral, birthday and anniversary texts.
- **Emails**: do not press Send Request Email, letter delivery, Submit COC, the Submission form's final submit, Send invites, or Schedule & Send Invitation. Notes and Application Summary "Save to Note" email the lead's team, which is clowman@ (the pilot's shared Email). That is harmless.
- **Conversion** moves the lead's files to the Person Account, and demo loans show in the daily integrity report until they are cleaned up.

### Cleanup checklist (same day as capture)
1. Remove the pilot's realtor tags on R1-R3.
2. Delete T1-T6, E1-E2, V1 and its invitees, all Tasks and notes on demo records, and the L4 requests and dummy file.
3. Delete the appraisal order and conditions on N3, then N1-N5.
4. Delete the borrower Person Accounts created by conversion, P1, and R1-R3.
5. Delete the unconverted leads L1-L7.
6. Records go to the Recycle Bin. Leave emptying it to Chris.
7. Verify that all of these return 0:
   - `Lead`, `Account`, `Transaction__c` WHERE Name LIKE 'Demo %'
   - `Lead`, `Account` WHERE Email LIKE '%@example.com' AND OwnerId = pilot
   - `TwilioSF__Message__c` WHERE External_LO__c = pilot AND CreatedDate = TODAY
8. Check Zapier task history and the Twilio log for anything sent today from demo records (the expectation is none).
9. Reset the pilot's tour progress (Oversight → Onboarding → Reset onboarding) if the capture run touched it.

---

## 7. Open questions for the owner

1. **Demo texts (T1-T6)**: the Texts shots need TwilioSF__Message__c rows carrying a number. The plan inserts them directly (not through TwilioSendSMS), as delivered/received, with fictional 555-01xx numbers on the message rows only.
   - First confirm that a direct insert never makes the package send. The test is one row in a Nimbus Developer sandbox.
   - OK to put fictional numbers on those rows? The alternative is to blur the number in the screenshot.
2. **RingCentral**: should there be a stop shown only to LOs whose manager turned RingCentral on (decision 19)? Nothing is drafted.
3. **Brandon's OK on the Bran likeness** (action item from Round 2, still open).

### Build note
Each target sits in a different LWC with its own shadow root, so the tour cannot simply `querySelector` across components. Instead, each component exposes its hooks, for example through an `@api getTourRect(hook)` method or a `tourtarget` event carrying the element's bounding box. If a hook is missing at runtime, the stop falls back to its screenshot, or to a centered bubble when it has none. The Zoom card's `zoomMeetingAssistant` loads on demand, so its hook must report only after the card has rendered.

---

## 8. Every `data-tour` hook the build needs

| Hook | Component | Element |
|---|---|---|
| `tour-menu` | `externalLoPortalShell` | "Take the tour" link under the LO's name/role in `sidebar-user` (new) |
| `pd-tour-help` | `perfectDayHome` | "?" button at the end of `banner-actions` (new) |
| `nav-perfect-day`, `nav-my-progress`, `nav-my-perfect-week`, `nav-realtor-prospects`, `nav-my-realtors`, `nav-other-contacts`, `nav-past-clients`, `nav-import-data`, `nav-my-leads`, `nav-my-pre-approvals`, `nav-nurtured`, `nav-my-loans` | `portalNavList` (items from shell `NAV_GROUPS`) | Each sidebar nav button (add `tourId` per item) |
| `volume-tab` | `loWsVolumeDrawer` | "Volume" edge tab |
| `pd-banner` | `perfectDayHome` | Welcome banner section |
| `pd-progress` | `perfectDayHome` | "of N activity goals met today" + pace badge |
| `pd-log-activity` | `perfectDayHome` | "Log activity" button |
| `pd-in-person-invite` | `perfectDayHome` | "In Person Invite" button |
| `pd-calendar` | `perfectDayHome` | "Calendar" button |
| `pd-metrics` | `perfectDayHome` | Metric cards grid |
| `pd-pipeline-snapshot` | `perfectDayHome` | "Pipeline snapshot" panel |
| `pd-goal-progress` | `perfectDayHome` | "Goal Progress" panel |
| `up-next` | `externalLoActivityPrompts` | "Up next for you" panel incl. "Open all →" |
| `up-next-alert` | `externalLoActivityPrompts` | First document High alert card (never a reply card) |
| `up-next-reply` | `externalLoActivityPrompts` | First "Text reply from …" card (`isTextReply`) (2026-10-13) |
| `up-next-actions` | `externalLoActivityPrompts` | First non-reply card's action buttons |
| `comm-settings` | `externalLoPortalShell` | Sidebar "Communication settings" link (2026-10-13) |
| `comm-settings-intro` | `loWsCommSettingsModal` | Modal header + subtitle (2026-10-13) |
| `comm-settings-groups` | `loWsCommSettingsModal` | Modal body with both groups (2026-10-13) |
| `comm-settings-edit` | `loWsCommSettingsModal` | First row's "Edit message" (2026-10-13) |
| `comm-settings-editor`, `comm-settings-cancel`, `comm-settings-close` | `loWsCommSettingsModal` | Editor block, its "Cancel", the header "×" (2026-10-13) |
| `texts-switch` | `loWsTextsSwitch` | "Automated texts" block (lead, realtor, past client, loan pages) (2026-10-13) |
| `today-plan` | `externalLoTodayPlan` | "Today's Plan" panel |
| `recent-log` | `externalLoRecentLog` | "Recent activity" panel (first "Text reply" row when present) |
| `appointments` | `loWsAppointments` | "Upcoming appointments" card |
| `calendar-views` | `loWsAppointments` | Month / Week / Day pills in the calendar |
| `in-person-events` | `bdUpcomingCard` (via `loWsInPersonEvents`) | "Upcoming In-person Events" card |
| `log-modal-category` | `portalActivityModal` | "What did you do?" category buttons |
| `follow-up-picker` | `loWsFollowUpPicker` | "Follow-up" fieldset |
| `leads-board` | `externalLoLeads` | Board columns |
| `leads-move-to` | `externalLoLeads` | First card's "Move to…" select |
| `leads-layout-toggle` | `externalLoLeads` | List / Board toggle |
| `leads-add` | `externalLoLeads` | "Add lead" button |
| `lead-status` | `externalLoLeads` | Lead status dropdown |
| `lead-log-communication` | `externalLoLeads` | "Log communication" button |
| `lead-letter` | `externalLoLeads` | "Pre-Approval Letter" button |
| `lead-app-summary` | `externalLoLeads` | "Application Summary" button |
| `lead-convert` | `externalLoLeads` | "Convert to transaction" button |
| `lead-tabs` | `externalLoLeads` | Lead tab bar |
| `lead-tab-calls`, `lead-tab-comms`, `lead-tab-requests` | `externalLoLeads` | Individual tabs (the tour selects them) |
| `lead-contact-card` | `externalLoLeads` / `loWsBorrowerPills` | "Contact" card |
| `lead-pre-approval-details` | `loWsLeadDetails` | "Pre-Approval Details" card |
| `lead-zoom` | `externalLoLeads` | "Schedule a Zoom" card section (wraps `loWsZoomCard`) |
| `comms-texts` | `loWsCommunications` | "Texts" subtab button + list (lead and loan; the tour selects the subtab) |
| `lead-notes-new` | `externalLoLeads` | Notes "New" button |
| `doc-req`, `doc-req-add`, `doc-req-send`, `doc-req-start-review` | `leadPortalDocumentRequestManager` | Whole manager, "Add Conditions", "Send Request Email", "Start review" |
| `preapprovals-filters` | `externalLoPreApprovals` (`portalListLayout`) | Filter chips |
| `loans-board` | `externalLoLoans` | Active loans board |
| `loans-tabs` | `externalLoLoans` | Active / Closed / Cancelled tabs |
| `loan-milestone` | `externalLoLoans` | Milestone chip |
| `loan-tabs` | `externalLoLoans` | Loan tab bar |
| `loan-submission` | `externalLoLoans` | "Submission form" button |
| `loan-coc` | `externalLoLoans` | "Change of circumstance" button |
| `submission-nav` | `loanSubmissionWizard` | Section title + Back / Next |
| `appraisal-tracker`, `appraisal-messages` | `loWsAppraisalPanel` | 4-step tracker, message thread |
| `realtors-list` | `externalLoRealtors` | List rows (stage, Follow-up due, Log touch) |
| `realtors-filters` | `externalLoRealtors` | Window filter chips |
| `realtors-add` | `externalLoRealtors` | "Add partner" button |
| `realtor-stage`, `realtor-shared-pipeline` | `externalLoRealtors` | "My stage" select, "Shared pipeline" card |
| `realtor-texts` | `externalLoRealtors` | "Texts" card section |
| `realtor-zoom` | `externalLoRealtors` | "Schedule a Zoom" card section |
| `past-client-new-lead` | `loWsPastClientDetail` | "New lead for this client" |
| `past-client-zoom` | `loWsPastClientDetail` | "Schedule a Zoom" card section |
| `import-consumer`, `import-partner` | `externalLoCsvImport` | The two upload cards |
| `perfect-week-this-week`, `perfect-week-edit-plan` | `externalLoPerfectWeek` | "This week" panel, "Edit my plan" |
| `progress-period` | `externalLoProgress` | Week / Month / Quarter tabs + "Coaching focus" |

The `investors-*` hooks were dropped: chapter L is screenshot-only.

Stop counts:
- Full run: 17 stops (18 with PD-RC for RingCentral LOs).
- Chapters (2026-10-13): A 6 (7 with A-RC), B 4, C 8, D 4, E 3, F 3, G 6, H 6, I 4, J 5, K 4, L 2, M 6: 61 stops across 13 chapters (62 with A-RC).
- Before 2026-10-13: 12 chapters and 55 chapter stops: 42 new and 13 reused from the full run (A-01, A-02, B-01, C-01, C-03, C-06, C-07, D-04, E-03, F-01, G-01, H-01, J-01; D-04 reuses only the text).
- Screenshots: 24 shot rows since 2026-10-13 (SS-SWITCH, SS-REPLY added); before that 22 (the four SS-PHONE captures went with the phone chapter). The earlier draft had 19 rows.
