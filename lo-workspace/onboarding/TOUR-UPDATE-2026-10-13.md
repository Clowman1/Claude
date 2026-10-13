# LO Workspace guided tour: update for 2026-10-13 (for approval before build)

Status: DRAFT 2026-10-13. Document only: nothing built, nothing deployed, no org changes.
Base: `TOUR-SCRIPT.md` (approved 2026-10-09) and the DEPLOYED `loWsTourSteps` (full run PD-01..PD-16 + PD-RC, chapters A-L).
Source: read-only Production retrieve 2026-10-13 into the session scratchpad (`tour-src3`, never into the repo): `externalLoPortalShell`, `loWsCommSettingsModal`, `loWsTextsSwitch` (the per-contact switch; the spec called it `loWsTextsToggle`), `externalLoActivityPrompts`, `perfectDayHome`, `externalLoRecentLog`, `loWsCommunications`, `loWsTour`, `loWsTourSteps`, `loWsTourHooks`, `externalLoLeads`, `externalLoLoans`, `externalLoRealtors`, `loWsPastClientDetail`, `leadPreApprovalLetter`, classes `PerfectDayHomeService`, `LoWsTextsService`, `LoWsCommSettingsController`, `LoWsAutoTextService`, `LeadPreApprovalLetterController`, `LeadDocumentRequestService`, label `LoWs_Twilio_From_Number`.
Rules unchanged: Bran is a mascot, friendly coach voice, "you", text-only bubbles of 1-2 sentences, never "External" / "Outside" ("Partner" / "Portal" are fine). Quoted labels are the on-screen text in prod today unless marked (new).

---

## 0. What changed in prod since the 2026-10-09 script (verified in code)

| Change | What the LO sees now | Source |
|---|---|---|
| Communication settings | Sidebar link **"Communication settings"** directly under "Take the tour" in `sidebar-user` (and in the mobile drawer). Already carries `data-tour="comm-settings"`. Shown in LO Workspace only (`!isExperienceCloudContext()`). | `externalLoPortalShell` |
| Settings modal | Title "Communication settings". Subtitle: "Automated texts sent for you from the no-reply number (561) 589-4420. Replies show in Up Next; answer them from your own phone." Groups **"To buyer's agents"** (8 messages) and **"To borrowers"** (7). Each row: label, a "when" line, an **On / Off** switch (saves at once), the message preview + locked "No-reply" footer, **"Edit message"**. Editor: textarea, "+ No-reply is always added on its own line", merge-field chips (e.g. `{First Name}`, `{Lead Name}`, `{Borrower Name}`, `{Agent First Name}`, `{LO Name}`, `{Portal Link}`, `{Open Count}`, `{Closing Date}`, `{Letter Details}`, `{Purchase Price}`, `{Loan Amount}`), count "About N of 160 characters with No-reply (names fill in when sent)." (over 160: "…may arrive as more than one text."), **"Reset to default"** (saves at once), "Cancel", **"Save message"**. Edited rows get an "Edited" tag. | `loWsCommSettingsModal`, `LoWsAutoTextService.CATALOG` |
| Per-contact switch | Card block **"Automated texts"** with one row per contact ("Borrower" / "Buyer's agent" role + name) and an On / Off switch. Turning off asks **"Turn off automated texts?"** — "All automated messages to <name> will be turned off until you turn them back on here in the LO Workspace." — **Cancel** / **Turn off**. Turning on needs no confirm. Placed: lead Overview inside the Contact card; Realtor page inside the "Texts" card; Past client page inside the Contact card; Loan page at the top of "Loan details" (borrower + buyer's agent). Template already has `data-tour="texts-switch"`, but the component does NOT call `registerTourHooks`, so the hook is not reachable yet. | `loWsTextsSwitch`, `LoWsCommSettingsController.switchesFor` |
| Reply card in Up Next | Each unhandled reply to the no-reply number is a red card: reason "High alert · Reply to an automated text", title **"Text reply from <name>"**, script `"<first 80 chars>"  Reply from your phone to <their number>`, buttons **"Open thread"** and **"Mark handled"** (toast "Reply marked handled."). These cards come FIRST, above document-review alerts. Open thread goes to the lead / loan on Communications → Texts; agent and past-client replies open their page (realtor page shows its Texts card). The card carries the same `up-next-alert` hook as document alerts. | `LoWsTextsService.replyPrompts`, `PerfectDayHomeService` (line ~179), `externalLoActivityPrompts`, `perfectDayHome.handleReplyOpen` |
| Recent activity | Unchanged: the 3 newest inbound texts of the last 7 days still sit on top as "Text reply" rows with "Reply from your phone: <number>". So replies now show in BOTH places. | `PerfectDayHomeController` → `LoWsTextsService.withReplies` |
| Texts subtab | Unchanged wording: "Texts Reach sent automatically to the borrower and agents, and their replies. Replies can't be sent from here." Inbound rows still show "Reply from your phone: <number>". | `loWsCommunications`, `LoWsTextsService.toItems` |
| Pre-Approval Letter | No status gate (2026-10-12). The button opens at any status; only a converted lead is refused ("This lead has already been converted to a loan, so a new pre-approval letter cannot be issued from it."). Finalizing moves the lead to Pre-Approval (never backwards) and fires the Pre-Approved agent text (again on every new purchase price). The O4a "Pre-approval letters unlock once…" toast no longer exists. | `LeadPreApprovalLetterController` |
| Docs Requested | Any send that includes conditions (any template, single or per-borrower) moves a lead that is still before Docs Requested to Docs Requested. Pre-Approval and later, Nurture and converted never move. | `LeadDocumentRequestService.stampInitialDocsRequested` |
| Add partner | "Add a partner" now opens with a name search ("Search shared partners") over every Reach partner; each result has **"Link"** (toast "Partner linked"). The "Create new" form still offers **"Tag me"** when the name/email/phone matches an existing partner. | `externalLoRealtors`, `LoWsPartnerTagService` |
| Lead intake block | Only another LO's open, non-Nurturing lead blocks a new lead. No deployed stop mentions duplicate leads (B-03 does not), so no copy change. | `LoWsLeadIntakeService.decide` |

---

## 1. New chapter M: Communication settings (6 stops)

Letter M was freed when the phone chapter was removed on 2026-10-09; if the phone chapter comes back it takes N. Menu row: "Communication settings · 6 stops".

| # | Page / view | Highlight (exact label · component · hook) | Pose | Bubble text | Screenshot? | Buttons |
|---|---|---|---|---|---|---|
| M-01 | Perfect Day | Sidebar "Communication settings" link, just under "Take the tour" · `externalLoPortalShell` · `comm-settings` (exists) | pointing | Communication settings, right under your name, controls the automatic texts Reach sends for you to agents and borrowers. Every message starts switched on, so take a minute to make them sound like you. | N | C |
| M-02 | Perfect Day, "Communication settings" modal open (clicks `comm-settings`) | Modal header + subtitle "Automated texts sent for you from the no-reply number (561) 589-4420…" and one row's "No-reply" footer · `loWsCommSettingsModal` · `comm-settings-intro` (new) | thinking | These texts go out from Reach's no-reply number, (561) 589-4420, and always end with No-reply. When someone answers, reach them from your own phone. | N | C |
| M-03 | Modal | Group titles "To buyer's agents" / "To borrowers", each row's when-line and On / Off switch · `loWsCommSettingsModal` · `comm-settings-groups` (new) | presenting | Messages are grouped To buyer's agents and To borrowers, and each one tells you when it goes out. Switch one to Off and it stops on every one of your files. | N | C |
| M-04 | Modal, first row's editor open (clicks `comm-settings-edit`; after: `comm-settings-cancel`, `comm-settings-close`) | Textarea, field chips, character count, "Reset to default", "Save message" · `loWsCommSettingsModal` · `comm-settings-editor` (new) | hands-on-hips | Tap Edit message to write it your way: the field buttons drop in names like {First Name}, and the counter warns you past 160 characters. Save message keeps your version, and Reset to default brings Reach's wording back. | N | C |
| M-05 | Lead page, Overview (record; clicks `lead-tab-overview`) | "Automated texts" row in the Contact card ("Borrower <name>" · On) · `loWsTextsSwitch` · `texts-switch` (exists; needs `registerTourHooks`) | arms-crossed | Need one person left alone? Switch Automated texts to Off here, or on their realtor, past client or loan page, and you'll be asked to confirm. Nothing automatic goes to them until you switch it back on. | Y, SS-SWITCH (new) | C |
| M-06 | Perfect Day | First "Text reply from …" card + "Open thread" / "Mark handled" · `externalLoActivityPrompts` · `up-next-reply` (new) | thumbs-up | When someone replies to one of these texts, a red Text reply card jumps to the top of Up Next. Open thread shows the whole conversation, and Mark handled clears the card once you've called or texted them back. | Y, SS-REPLY (new) | CL |

Step-file notes (for the build, not bubble copy):
- M-02..M-04 each have `clicks: ['comm-settings']` (opening is idempotent) and `after: ['comm-settings-close']`, so Exit chapter or Back never leaves the modal open. M-04 adds `comm-settings-edit` to its clicks and `comm-settings-cancel` before the close. The tour never clicks a switch, "Reset to default" or "Save message" (all three save at once).
- The tour overlay (z-index 100000) already sits above the modal (9100) and the switch dialog (9200).
- M-05: `record: true`, `need: 'texts-switch'`, `shot: 'SS-SWITCH'`. M-06: `need: 'up-next-reply'`, `shot: 'SS-REPLY'`.

New hooks:

| Hook | Component | Element | Build note |
|---|---|---|---|
| `comm-settings` | `externalLoPortalShell` | Sidebar link | Exists; shell already registers hooks |
| `comm-settings-intro` | `loWsCommSettingsModal` | `header.head` | Modal must call `registerTourHooks(this)` |
| `comm-settings-groups` | `loWsCommSettingsModal` | `.body` (both groups) | Only renders after the settings load; the stop's poll covers it |
| `comm-settings-edit` | `loWsCommSettingsModal` | First row's "Edit message" button | Put the hook on the first row only |
| `comm-settings-editor` | `loWsCommSettingsModal` | `.editor` | |
| `comm-settings-cancel`, `comm-settings-close` | `loWsCommSettingsModal` | "Cancel" in the editor, header "×" | |
| `texts-switch` | `loWsTextsSwitch` | "Automated texts" block | Exists in the template; add `registerTourHooks(this)` in `connectedCallback` |
| `up-next-reply` | `externalLoActivityPrompts` | Reply card (`isTextReply`) | Change `tourHook` to `'up-next-reply'` for reply cards and keep `'up-next-alert'` for document alerts only (see D-01 below) |

### Screenshots for chapter M (fictional "Demo" data only, 1280 px, JPEG q85, annotated)

| Shot | Used by | Page | What it shows | How to capture |
|---|---|---|---|---|
| SS-SWITCH (new) | M-05 | Lead page L3 "Demo Casey …", Overview | Contact card with the "Automated texts" row "Borrower Demo Casey …" · On. Inset: the "Turn off automated texts?" dialog with Cancel / Turn off | Click the switch to get the dialog, capture, then **Cancel** (never Turn off). No phone on the lead, as before. |
| SS-REPLY (new) | M-06 | Perfect Day, "Up next for you" | Top card "High alert · Reply to an automated text", "Text reply from Demo Oakley Bennett", a short reply in quotes + "Reply from your phone to 407-555-01xx", "Open thread" / "Mark handled"; a document alert underneath | DOM-only edit of a real card, the same method as the 2026-10-09 texts shots (Q60), so no inbound TwilioSF__Message__c row is inserted. See open question 2. |

M-01..M-04 need no screenshot: the link and the modal render for every LO with no data.

---

## 2. Should it join the full Perfect Day run?

**Yes, one stop.** A new LO must know on day one that Reach texts their borrowers and agents in their name, from a number nobody reads. The detail (templates, switches) stays in chapter M.

Add **PD-CS** right after PD-RC and before PD-05, so all Perfect Day stops stay together before the run moves to My Active Leads. The run becomes 17 stops + RingCentral (counter "N of 17" for most LOs, "N of 18" with RingCentral). Resume is keyed on the stop id, so adding a stop does not break a run already in progress.

| # | Chapter | Page / view | Highlight | Pose | Bubble text | Empty-state screenshot? | Buttons |
|---|---|---|---|---|---|---|---|
| PD-CS | Your automatic texts | Perfect Day | Sidebar "Communication settings" link · `externalLoPortalShell` · `comm-settings` | pointing | Reach texts your borrowers and agents for you at key steps, from a no-reply number, and their answers land at the top of Up Next. Open Communication settings under your name any time to turn a message off or put it in your own words. | N | S |

Chapter menu row 1 becomes "The full Perfect Day (17 stops)". The full run modal is not opened here (no `clicks`), so it stays short.

---

## 3. Stale stops in the deployed `loWsTourSteps`

Only stops whose text is now wrong or missing something the LO needs. Stops that reuse them (A-02 = PD-03, D-04 = PD-09, E-03 = PD-10) pick up the new text automatically.

| Stop | Current text (deployed) | Proposed text | Reason |
|---|---|---|---|
| PD-03 (also A-02) | This is your to-do list, ranked by impact: documents to review sit at the very top as urgent actions, then new leads, follow-ups due today and weekly touches. Follow-ups you set show up here on the day they're due, so work it top to bottom every day. | This is your to-do list, ranked by impact: text replies and documents to review sit at the very top as red High alerts, then follow-ups due today, new leads and weekly touches. Follow-ups you set show up here on the day they're due, so work it top to bottom every day. | Reply cards now come before document alerts (`PerfectDayHomeService`: replies, then document reviews, then due follow-ups, then computed prompts). The order of follow-ups vs new leads was also wrong in the old text. |
| PD-04 | Every call, text, meeting or post goes in with Log activity, and it counts toward today's goals. When a borrower or agent texts back, their reply shows at the top of Recent activity, so check it between calls. | Every call, text, meeting or post goes in with Log activity, and it counts toward today's goals. When a borrower or agent texts back, the reply shows at the top of Recent activity, and a reply to an automatic text also gets its own card in Up Next. | Replies to the no-reply number now raise an Up Next card (Recent activity still lists them, so the old sentence is incomplete rather than wrong). |
| PD-10 (also E-03) | Pre-Approval Letter works once the lead reaches Pre-Approval or any later status; before that, the button tells you exactly what to do to unlock it. A lead that's already been converted to a loan can't get a new letter. | Pre-Approval Letter works at any status, and finalizing it moves the lead to Pre-Approval and lets their agent know. A lead that's already been converted to a loan can't get a new letter. | Status gate removed 2026-10-12; finalize sets Status = Pre-Approval and fires the Pre-Approved agent text (A3), again at each new purchase price. The "unlock" toast no longer exists. |
| D-01 | When a borrower uploads documents, a red High alert lands at the very top of Up Next. There's no timer on it, but it stays on top as your most urgent action until you review them. | When a borrower uploads documents, a red High alert lands at the top of Up Next, right below any text replies. There's no timer on it, but it stays there as an urgent action until you review them. | Reply cards sit above it now. **Also a hook bug:** reply cards carry the same `up-next-alert` hook, so today D-01 can spotlight a text reply instead of a document alert. Fix with the `up-next-reply` hook (section 1). |
| A-03 | Log it done records the touch, Mark complete closes a follow-up, and Tomorrow pushes the card to the morning. Use Tomorrow sparingly: a new lead you push may miss its contact window. | No text change. | Build note only: it spotlights the FIRST card's `up-next-actions`, which is now "Open thread" / "Mark handled" when a reply is waiting. Move the `up-next-actions` hook off reply cards (or skip them) so it lands on a normal card. |
| D-03 | Send Request Email gives each borrower their own list and their own upload link. When they upload, the review shows up at the top of Up Next. | Send Request Email gives each borrower their own list and upload link, and moves a new or working lead to Docs Requested. When they upload, the review shows up at the top of Up Next. | Every send with conditions now moves an early lead to Docs Requested (2026-10-12). It also sends the "Documents requested" texts if they are on in Communication settings; left out to keep it to 2 sentences (chapter M covers it). |
| H-03 | Add partner checks Reach's shared list first. If the agent is already here, tap Tag me instead of creating a duplicate, and they join your list with your own stage. | Add partner starts with a search of Reach's shared list: find the agent by name and tap Link, and they join your list with your own stage. Only create them new if they're not there, and tap Tag me if it spots a match. | Name search + "Link" (2026-10-12) is now the main path; "Tag me" only appears on a Create new match. |
| H-05 | The Texts card shows what Reach texted this agent about your leads and loans, and their replies. Answer from your phone with the number under Reply from your phone. | The Texts card shows what Reach texted this agent about your leads and loans, and their replies; answer from your phone with the number under Reply from your phone. Automated texts at the top of the card turns those texts off for this agent. | The per-contact switch now sits inside this card (`realtor-texts` already spotlights it). |

Checked and still correct: PD-08 / C-06 / G-05 (Texts subtab wording and "Reply from your phone" are unchanged), A-06 (Recent activity still shows replies with the number), PD-05 / B-01 (the Docs Requested column already exists), PD-06 and C-02 (the switch is new inside the Contact card but the copy is not wrong; chapter M covers it), B-03 and I-04 (nothing about duplicate leads), PD-16.

`TOUR-SCRIPT.md` follow-ups when this is approved: replace the chapter E note about the locked-letter toast (section 3) with the converted-lead message only; drop "Inset: the locked toast captured on L1" from the SS-LETTER row; add chapter M, PD-CS, the two new shots and the new hooks; stop counts become full run 17, chapters 61 stops across 13 chapters, 24 shot rows.

---

## 4. Screenshots that now show outdated UI

Folder: `lo-workspace/phaseO4f/assets/LoWsTourAssets/screens/` (22 JPEGs, the deployed set; `phaseO4e` holds the same shots plus the retired SS-PHONE files). Capture list: `phaseO4e/assets/shots.tsv`.

| Shot | Used by | What is outdated | Action |
|---|---|---|---|
| SS-LEAD | PD-06, C-01, C-02, C-04, C-05, C-08 | Contact card has no "Automated texts" row | Recapture (L3 Overview). Can be the same capture as SS-SWITCH, without the dialog |
| SS-REALTOR | H-04, H-05, H-06 | "Texts" card has no "Automated texts" row above the thread | Recapture (R2) |
| SS-PASTCLIENT | I-02 | Contact card has no "Automated texts" row | Recapture (P1) |
| SS-LOAN | G-03, G-04, G-06 | "Loan details" card is missing the "Automated texts" rows (Borrower + Buyer's agent) at its top; visible beside the COC modal | Recapture (N3; it has a borrower, no buying agent, so one row) |
| SS-UPNEXT | PD-03, A-02, A-03 | Not wrong, but the new PD-03 text says replies sit on top and the shot has none | Optional: recapture with a DOM-edited reply card on top (or reuse SS-REPLY for PD-03) |

Still correct: SS-ALERT, SS-RECENT, SS-TEXTS, SS-TEXTS-LOAN, SS-LETTER (the shot is the letter terms modal; no locked-toast inset was ever captured), SS-REALTORS (shows the "Add partner" button only, not the drawer), SS-BOARD, SS-ZOOM, SS-DOCREQ, SS-APPSUM, SS-TRID, SS-PREAPP, SS-SUBMIT, SS-LOANS, SS-CAL, SS-EVENTS, SS-INVESTORS.

Recapture follows section 6 of `TOUR-SCRIPT.md` (Demo records on the pilot, no phone numbers, no buyer's agent, same-day cleanup). Two new cautions: never click "Turn off" or a settings switch on the pilot during capture (both save), and the pilot's own Communication settings must be left at defaults afterwards (`User.LoWs_Comm_Settings__c` blank).

---

## 5. Open questions for the owner

1. **Timing.** The comms flow activation and the daily `LoWsAutoTextDaily` schedule were still pending on 2026-10-13. Until the old shared-number flows are activated with their gate, LO files can still text from the shared number, so PD-CS and M-02 ("from Reach's no-reply number") would be untrue. OK to ship this tour update only after activation?
2. **SS-REPLY data.** DOM-edit a real Up Next card (proposed, nothing is inserted) or insert one inbound demo TwilioSF__Message__c to the no-reply number? Inserting is more faithful, but the spec meant to gate `Route_Twilio_Reply_to_Owner` and the as-built notes only list `Alert_Message_Owner_of_New_Reply` as gated, so an insert could still route or alert.
3. **Chapter letter.** Use M for Communication settings (phone chapter takes N if it returns)?
