# LO Workspace: External Loan Officer Build Outline

**Status:** draft for approval, 2026-09-30. Nothing here is built.
**Source of decisions:** the design Q&A (Q1–Q38) held 2026-09-29/30, summarized at the end. Every phase below is a separate prod change that gets your sign-off before deploy.

## Goal

Move outside loan officers off the Experience Cloud portal and onto **full Salesforce licenses**, in the existing **External Loan Officer** role. They work in a new Lightning app, **LO Workspace**, whose home page and lists match the portal webpage. Their access comes from normal Salesforce sharing, not the portal's workarounds. The Partner Workspace portal and Harold's older portal stay as they are.

## What changes org-wide (read this first)

Two changes reach beyond the new users. They are the ones that need the most care.

| Change | Who it affects | Safeguard |
|---|---|---|
| Call Insights, Borrowers, Document Requests, Zoom Meetings and Zoom Recordings go from **open to all internal users** to **Private** | Every internal user | New sharing rules give every existing internal role exactly today's access. A before/after record-count check runs as a test user in each role. Rollout happens in a quiet window, with the rollback steps written down first. |
| A **Nurturing-lead takeover path** that can replace Lead Source and reset status to New | Every LO, internal and external | It is a single dedicated Apex path. The Lead Source lock keeps blocking every other change. |

Everything else is additive: a new app, permission sets, components and a webhook, scoped to the External Loan Officer role or a custom permission.

## Phases

### Phase 0: Verify and prepare (no user-visible change)

- **Confirm the loan edit window.** ✅ Done 2026-09-30. Internal LOs have no record-level Edit on Transaction__c: the profile grants Read + Create, and Salesforce reports edit = false on their own loans. All LO edits happen through the Submission Form flow. Ownership is not the mechanism: the LO still owns 70 of 207 recent submitted loans, and no ownership history is tracked.
- **Pilot user.** A Customer Community Plus user **cannot be converted** to a Salesforce license. Create a new internal test user (for example `outsidelo.internal@reachhomeloans.com`) on one of the 3 spare licenses. `outsidelo@` stays as the portal test account.
- **Role cleanup.** "External Loan Officer" holds an inactive LO (Lawrence Lanos) and the contractor account `reachoutside@nimbuscloudsolutions.com`. Move the contractor account out. Confirm the role sits under Management and has no subordinates.
- **Naming.** New components use a `loWs` prefix so nothing collides with the portal's `externalLo*` / `portal*` components, which keep running for Harold.
- **Test harness.** A test utility that creates real External Loan Officer users (the real profile and role, two LOs), so every test proves one LO can't see the other's data. The portal's tests never did this.

### Phase 1: Access model

- **Profile:** reuse the **existing "External Loan Officer Profile"** (Salesforce license, created by Nimbus 2024-07-23, no users ever assigned). Unlike Loan Officer Profile it has **no View All on Account/Contact**; internal LOs can see every account, and outside LOs must not. It already has Lead Read/Create/Edit and Transaction Read/Create. Phase 1 adds the loan-condition objects their tools need, sets LO Workspace as the default app (in Phase 4), and assigns the outside-LO record pages.
- **Permission set group: "External Loan Officer".** It starts from what an internal LO holds and **drops**:
  - `DocuSign_Transaction_Access` and `Pipeline_Command_Center_Pilot_Access`, per your tool decision.
  - `All_Apex_Classes` and `All_Visualforce_Pages`. They open every class and page; outside LOs get only the classes and pages LO Workspace uses.

  It **keeps**:
  - Zoom: `Zoom_Meeting_Assistant_Access`, `Zoom_OAuth_Connection_Access`, `Zoom_Meeting_Sync_Access`.
  - Application Summary: `Application_Summary_Access`, `Application_Summary_Fields`.
  - Documents and borrowers: `Lead_Document_Collection_Access`, `Borrower_Management`.
  - Lead team and realtors: `Lead_Team_Access`, `Realtor_Referral_Source_Access`.
  - Mobile: `Reach_Mobile_LO`.
  - Conditions, UWM and notes, as needed.
- **Custom permission `External_LO`.** Code checks it wherever outside-LO behavior differs: the signer list, the takeover rules, lead routing and the hidden tags.
- **Role sharing.** The External Loan Officer role sits under Management, so staff automatically see their records. It does **not** pick up the Loan Officer role's rules: Facebook-refi leads and all Post-Closed loans.
- **Reports:** a read-only "LO Workspace Reports" folder shared to the role. There is no report builder, and sharing limits the reports to their own data.
- **Email:** RHL Outlook with the same Einstein Activity Capture license internal LOs have (`StandardEinsteinActivityCapturePsl`), so borrower email logs as it does today.

### Phase 1b: Fix the sharing-bypass classes (before any outside LO goes live)

About a dozen Apex classes their tools use let any user read or change records they can't see, just by passing a record ID. That's true for internal LOs today too. Eight are fixed with `with sharing`: CallInsightListController, AccountRecordHeroController, LeadNotesFormController, TransactionNotesFormController, SubmissionQualityChecklistController, ChecklistController, AppraisalOrderController and LoanController. Three need real access checks: FileUploadHandler, ConditionReviewService and DocumentViewerController's write methods. BorrowerDocumentPortalController's one needed method moves into ConditionCommentController. Every fix is tested against the internal and portal flows that share the class. Details: `docs/apex-access-inventory.md` §4.

### Phase 2 (REVISED 2026-09-30): Restriction Rules on the open objects

**Replaces the org-wide Private switch.** Eight objects are Public Read/Write for every internal user: Call_Insight__c, Borrower__c, Lead_Document_Request__c, Zoom_Meeting__c, Zoom_Recording__c, Enhanced_Note__c, Checklist__c and Appraisal_Order__c. A **Restriction Rule** on each shows users who hold the `External_LO` custom permission only the records stamped with them. **Internal users are unaffected**: no change to sharing, no recalculation. Available in this Enterprise org, which has 0 rules today.
- A stamped `External_LO__c` user field on each object, filled automatically from the parent lead (owner) or loan (Loan Officer or Loan Partner) when that person is an outside LO, and kept current when those change.
- Verify with the pilot user and a second test LO: each sees only their own records, and an internal LO sees exactly what they did before.

### (Superseded) Phase 2: Private sensitive objects (org-wide, own rollout)

1. **Snapshot.** For each role, record how many Call Insights, Borrowers, Document Requests and Zoom records a test user can see and edit today.
2. **Internal Staff group.** A public group made of every internal role **except** External Loan Officer, plus any role-less internal users (listed and reviewed first).
3. **Rules and OWD.** Add sharing rules that give that group today's Read/Write, then set the five objects to Private.
4. **Outside-LO access.** Apex-managed shares give them access only to records on **their** leads (owner) and loans (Loan Officer, or Loan Partner when they hold that role). The shares follow ownership and assignment changes.
5. **Verify.** Re-run the snapshot, which must match exactly for every internal role. Then run the two-LO test.
- **Known dependency:** every internal user must keep Zoom_Meeting__c access, or Event saves fail ("sObject type not supported").

### Phase 3: Loans

- **The same as your internal LOs** (confirmed in Phase 0, 2026-09-30). The Loan Officer Profile grants Transactions **Read + Create, never Edit**, and no LO permission set adds Edit. LOs change loan data only through the **Submission Form**, a flow that runs with elevated rights and is editable until Disclosures Out. Outside LOs get the same Read + Create, and no new sharing logic is needed.
- **Conversion:** they convert their own leads with the **current** Submission Form (`Loan_Origination_Submission_Form`). Its redesign is a separate later project for all LOs.
- **Sharing:** `LoanOfficerRecordSharingService` already shares each loan with its Loan Officer and Loan Partner.
- **Data:** My Loans reads the **live** fields, not the dead twins (`Loan_Amount__c`, `Interest_Rate__c` and friends).

### Phase 4: The LO Workspace app

The Lightning app **LO Workspace**, with a home page and list views matching the portal webpage. The portal's screens are ported, and the deep-dive bugs fixed on the way.

| Screen | What it does | Notable fixes from the review |
|---|---|---|
| **Perfect Day** (home) | Today's plan, prompts, the new-lead queue (landing-page leads on top), goal progress | Goal drill-downs (split bug); snooze no longer hides prompts forever; pace badge and one consistent "pace" definition |
| **Setup Q&A / My Perfect Week** | The portal's questions **plus** monthly unit goal, loan-volume goal and target realtor count. Editable any time, with change history managers can see | The lock-after-first-save is removed |
| **My Progress** | Goals vs actual by week, month and quarter | The Sunday "next week" bug |
| **My Leads** | Tabs: New / Working / Pre-Approval / Nurture / Converted (your real statuses) | The Nurture filter now matches "Nurturing" |
| **My Pre-Approvals** | Pre-approved leads and their documents | "Expiring soon" and "Docs outstanding" relabeled to what they really mean |
| **My Loans** | Their loans by live status | Live fields only |
| **Realtor Prospects / My Realtors** | Their tagged partners by stage (see Phase 5) | New partners show by default; "due" includes never-touched partners |
| **Past Clients** | Borrowers with closed loans where they were the Loan Officer, plus imported past clients | Past Clients is no longer built from Lead Source |
| **Import Data** | CSV import for partners and past clients | Header aliases, Excel encodings, row counting, and the same duplicate rules as Phase 6 |

- **Activity credit:** manual logs and RingCentral both count. A manual log and a RingCentral call to the same person within 15 minutes count once. RingCentral is optional per LO. The outcome is stored in its own field, never in Task.Subject, which org automation rewrites.
- **Record pages:** outside-LO Lead and Transaction pages with the activity assistant, Document Requests, Application Summary, Pre-Approval Letter and Zoom. There is no DocuSign and no Pipeline Command Center.
- **Mobile (Salesforce app) menu:** Perfect Day, Log Activity, My Realtors, My Leads, My Loans. Perfect Week and Progress are desktop-first.

### Phase 5: Realtor and partner tagging

- **Tag = one row per LO per partner account**, holding that LO's own **stage** (Prospect → Contacted → Meeting Set → Met → Active Partner → Dormant). The tag object is Private and owned by the LO, so **no LO sees another LO's tags**. Managers and admins see all.
- **What a tag grants:** Read on the partner account, plus logging calls, texts, notes and events. There is no editing of the partner's details. An LO can untag themselves.
- **Adding a partner:** it reuses Fred's duplicate check (`PersonAccountDuplicateService`: email and phone, including mobile). A match on a **partner-type** account (Fred's BD industries) offers "tag me". Any other match shows "already exists, contact an admin". No duplicates are created.
- **At launch:** no automatic tagging. They add partners or import them.
- **Data model choice:** extend the portal's unused `External_User_Assignment__c`, or create a clean new tag object. I'll recommend one at build time. Either way it stays off Transaction__c, which has only 5 spare fields.

### Phase 6: Lead intake, duplicates and takeover

- **Landing-page webhook.** Marketing builds a page for each LO, and you wire its data into a new Salesforce endpoint. The LO is identified by their email or by a per-LO endpoint (decided when the first page is built). Every submission is logged.
- **On arrival:**
  - A **mobile push** and an **email** go to the LO.
  - The lead lands at the **top of Perfect Day's queue**.
  - Lead Source is **"LO Landing Page"** unless the page sends one.
  - No Loan Partner is set. Outside LOs' leads are exempt from the auto-assign that defaults to the Nimbus user.
- **Duplicate rules** (email or mobile; the `na@na.com` placeholder is never matched). They apply to the webhook, manual adds and CSV import:
  - **Nurturing match:** the LO takes the lead. **Both directions** (internal ↔ external). History stays, Loan Partner is cleared, Lead Source is replaced with the new LO's source, status becomes **New**, and the previous owner is **not** notified.
  - **Actively worked match** (any non-Nurturing status): "This person is already being worked by another Reach loan officer. Contact an admin." No name is shown, and an admin is alerted.
  - **Converted lead or someone else's past client:** blocked, with the same message and alert.
- The takeover runs through one dedicated path. The Lead Source lock keeps blocking every other Lead Source change.

### Phase 7: Pre-Approval Letter

- For outside LOs the signer list is **only their own signature card**. The Brandon Brotsky default and the lead-team options are removed, and this is enforced on the server, not just hidden in the picker.
- The card shows their NMLS (`User.NMLS__c`) and their **licensed states** (a new User field) alongside Company NMLS #2266637. The same details go on their landing pages.

### Phase 8: Manager oversight

- An oversight tab like Fred's BD Overview, for **Brandon Brotsky, Adam Stephens and Christopher Lowman**, gated by a custom permission.
- **Contents:** each LO's goals vs actual activity, pipeline by stage, new landing-page leads, realtor tags by stage, and a setup-change history.

### Phase 9: Pilot and go-live

1. Deploy phases 1–8 behind the permission set group. No real users are assigned yet.
2. Assign the **internal pilot test user** and walk the manual checklists (ported from the portal deep dive, updated for Salesforce).
3. Run the two-LO isolation checks and the Phase 2 role snapshots one more time.
4. You decide when the first real outside LO is onboarded (license, Outlook mailbox, landing page, and an optional RingCentral seat).

## Out of scope for this build

- Redesigning the Submission Form (a later project for all LOs).
- Moving Harold off his portal, and retiring either portal. Both stay as they are.
- Choosing webhook identification (LO email vs per-LO endpoint). That's decided when the first landing page exists.
- DocuSign and Pipeline Command Center for outside LOs.

## Risks and how they're handled

| Risk | Handling |
|---|---|
| Private-object switch changes what someone internal can see | Per-role before/after snapshot; rollout in a quiet window; rollback steps written first |
| Org automation runs in unknown order (119 automations on Transaction, 9 triggers on Lead) | New logic lives in a few named Apex entry points, tested as the real outside-LO user |
| Lead Loan Partner auto-assign overwrites on insert | An explicit exemption for leads owned by External LOs, with a test |
| RingCentral Tasks attach to the wrong record | Match on from/to phone numbers, never on WhoId/WhatId alone |
| Prod Apex deploys fail under RunLocalTests (4 already-broken classes) | Deploy with RunSpecifiedTests, one phase at a time, only the changed files |
| Transaction__c has 5 spare fields; data storage is at 84% | No new Transaction fields planned; tags and logs live on small new objects |

## Decisions this outline is built on

| # | Decision |
|---|---|
| Q1 | Company login = Option 9B (done, live) |
| Q2 | Sensitive objects are visible only on leads and loans where they are the Loan Officer or Loan Partner |
| Q3 | Keep the "External Loan Officer" role, under Management |
| Q4/12/21/22 | Leads come only from the per-LO landing-page webhook (marketing builds the pages) or are created by the LO; identified by email or per-LO endpoint |
| Q5 + clarification | Full edit on loans **until the Submission Form completes**, then Read, like internal LOs |
| Q6 + Q20 | Port the portal's screens and lists; all internal tools except DocuSign and Pipeline Command Center |
| Q7/29 | Tag = see + log activity, stage per tag, other LOs' tags hidden |
| Q8 | Only partner-type matches can be tagged |
| Q9 | Salesforce mobile app; RingCentral optional |
| Q10 | Both portals stay as they are |
| Q11 | Pilot on a test user first (a new internal user, since licenses can't convert) |
| Q13 | No default Loan Partner; assigned manually |
| Q14/37 | Setup Q&A editable any time, plus unit, volume and realtor-count goals |
| Q15 | Manual + RingCentral credit, deduped within 15 minutes |
| Q16 | No automatic realtor tagging at launch |
| Q17 | Past Client = closed loans as Loan Officer, plus imported past clients |
| Q18 | Mobile menu: Perfect Day, Log Activity, My Realtors, My Leads, My Loans |
| Q19 | Oversight tab for Brandon, Adam and Christopher |
| Q23/25/31/32/33 | Nurturing takeover both ways (Lead Source replaced, status New, Loan Partner cleared, no notice); active or converted matches blocked with no name shown |
| Q24 | On arrival: push, email, Perfect Day queue, "LO Landing Page" source |
| Q26/34 | They convert with the current Submission Form; redesign later for all LOs |
| Q27 | Lead tabs: New / Working / Pre-Approval / Nurture / Converted |
| Q28 | RHL Outlook mailboxes |
| Q30 | App name "LO Workspace" |
| Q35 | Sensitive objects go Private org-wide with rules keeping internal access |
| Q36 + clarification | Their own NMLS and licensed states; **only their own signature card** on the Pre-Approval Letter |
| Q38 | A folder of prebuilt reports, no report builder |
