# Partner Workspace deep dive, part 03: Pipeline (My Leads, My Pre-Approvals, My Loans)

Read-only review done 2026-09-28 against prod source and prod data. No deploys, no anonymous Apex, no DML.

**Where the paths point.** Paths are relative to `C:\Apps\Claude Back Up\outside-lo-portal\force-app\main\default\` unless marked otherwise.

**Three classes are missing from the local source.** `LeadRepository`, `LoanRepository` and `PersonAccountRepository` are not in `outside-lo-portal`. The portal depends on them, so I pulled their current prod bodies through the Tooling API into `scratchpad\deepdive\src\`. Line numbers for those three refer to those copies. All three were last modified by Nimbus Development (LeadRepository on 2026-09-15, LoanRepository on 2026-08-31). **Retrieve them into the project before you edit anything.** A deploy of the portal folder as it stands does not include them.

---

## 0. Top findings (read this first)

| # | Severity | Finding |
|---|---|---|
| 1 | **Critical (security)** | `logCommunication` writes a Task, and optionally an Event, in SYSTEM_MODE against **any** record Id the caller sends. There is no ownership or visibility check. An outside LO can attach activities to any Lead, Account or Transaction in the org. `ExternalLoCommunicationService.cls:5-59, 89-102` |
| 2 | **Critical (cross-area)** | `CallInsightListController` is `without sharing` and uses a dynamic query with no WITH clause and no owner filter. It is granted to the portal profile and to `External_LO_Perfect_Day_Access`. Any portal user who calls `getCallInsights(anyLeadOrAccountOrTransactionId)` gets the full call transcripts and AI summaries for that record. The Lead detail "Calls" tab uses this class. |
| 3 | **High (cross-area)** | `Lead_Document_Request__c` has external OWD **Public Read/Write**, and `External_LO_Perfect_Day_Access` grants full CRUD on it. Any outside LO can read, edit or delete all 330 document requests org-wide through the standard UI/record APIs. |
| 4 | **High (data)** | My Loans reads dead-twin fields. `Loan_Amount__c` is set on 3 of 37 active files, `Interest_Rate__c` on 3 of 37 and `Lock_Exp_Date_1st_TD__c` on 0 of 37. Every loan row therefore shows amount "—", and the drawer shows Rate "—" and a blank Lock expires. On all 6 of Harold Ellis's live loans the amount is null. Tests seed the dead fields, so they pass. |
| 5 | **High (functional)** | Leads and Pre-Approvals filter on `OwnerId = portal user` only. Manual shares and `Loan_Partner__c` are ignored. In prod the only active real outside LO (Harold Ellis) owns **0 leads**, so both views are empty for him. The only portal-owned lead in the org is the test lead "Testington Testerillo", owned by Reach Admin. |
| 6 | **Medium** | The lead stage mapping does not match prod `Lead.Status` values. "Nurturing" (29,076 open consumer leads) becomes the slug `nurturing`, so the **Nurture** chip never matches it. "Contact Attempt 1/2", "Contacted/Call Back", "Documents Requested", "Application" and others fall into neither **Working** nor **Nurture**. |
| 7 | **Medium** | Two loan filters are dead. **Clear to close** tests for `Status__c == 'Clear to Close'` and **In process** includes `'Underwriting'`. Neither value exists in the picklist, and neither is in `ACTIVE_LOAN_STATUSES`, so **Clear to close** is always 0. |
| 8 | **Medium** | The pre-approval statuses are mislabelled. "Docs outstanding" means "no *RingCentral* call or SMS in 6 days". Outside LOs use their own phones and portal logs do not stamp those fields, so almost every file will show this. "Expiring soon" means the credit has **already expired** (`<= TODAY`). |
| 9 | **Medium** | Goal credit is misrouted. A borrower call logged from My Leads is stored as `Activity_Type__c = 'Call - Active Agent'`. The rollup takes the first catalog entry by sort order, which is Realtor Outreach (sort 1), not Consumer Conversation. The modal still tells the user it "credits your consumer conversations goal". |
| 10 | **Medium** | "Open in Arive" never works. `External_LO_Baseline__mdt.Default.Arive_Base_Url__c` is null in prod, so every click shows an error toast that wrongly blames the lead ("This lead has no Arive ID yet"). |
| 11 | **Medium (test quality)** | Every pipeline test runs as the deploying **System Administrator**, not as a Customer Community Plus user. None of the USER_MODE, SYSTEM_MODE or license behaviour is exercised. There is no negative test proving LO A cannot see LO B's lead or loan, and no test of the cross-record logging hole. About 60 assertions are `assertNotEquals(null, ...)` on list returns, which can never fail. |
| 12 | **Ops risk** | Both active portal users hang off one shared Account ("Customer Community User", `001AJ0000047qQ8YAI`), and that account is **owned by the Nimbus Development user**. Check what happens to portal-account ownership and role before you deactivate that user. |

---

## 1. The three views

### 1.1 Shared plumbing

**Shell.** `externalLoPortalShell` renders one view at a time: `c-external-lo-leads`, `c-external-lo-pre-approvals` or `c-external-lo-loans` (`externalLoPortalShell.html:104-128`). Each gets `embedded-in-shell`, `filter-key`, `record-id` (Leads and Loans only) and `refresh-key`. Navigation is a bubbling `portalnavigate` event (`portalUtils.js:80-88`) that the shell turns into URL state: `c__view`, `c__filter` and `c__recordId` (`portalUtils.js:35-66`). The record Id for a detail view therefore comes from the URL and is user-controllable. The Apex for leads and loans re-checks ownership, so that part is fine.

**List layout.** `portalListLayout` is a dumb renderer: header, search box, filter chips with counts, skeleton, empty state, and rows with action buttons. `rowType` is accepted but ignored, because `isGenericRows` always returns true (`portalListLayout.js:31-33`). It has no paging, sorting controls or virtualisation. Every row returned by Apex is rendered.

**Search.** Each keystroke changes `search`, which re-fires **two** cacheable wires per view: the filtered list and an 'all' list used for chip counts (for example `externalLoLeads.js:122-150`). There is no debounce. Search runs in Apex *after* the capped query, as a case-insensitive substring match over three fields (`ExternalLoPortalService.cls:814-820`).

**Nav badges.** `getNavBadges` (`ExternalLoPortalService.cls:147-154`) re-runs the full `getLeads('new')`, `getRealtors('due')`, `getPreApprovals('all')` and `getLoans('all')` queries just to count them. It is cacheable, wired once in the shell (`externalLoPortalShell.js:119-125`), and only refreshed via the refresh key.

**Error handling.** `ExternalLoPortalController.toAura` (`ExternalLoPortalController.cls:234-257`) forwards only DomainException and DML messages. Everything else becomes a generic message. The read methods (`getLeads`, `getLoans` and so on) are **not** wrapped, so an unexpected exception there reaches the client as a raw Aura error.

**Sharing keywords.** All classes on this path are `with sharing`. Each query sets its own mode, summarised below.

| Query | Class:line | Mode | Row filter |
|---|---|---|---|
| Leads list | LeadRepository:245-261 | **SYSTEM_MODE** | `OwnerId = me AND IsConverted = false AND RecordType IN (Consumer_Lead_record_type, Consumer_Under_Contract_Lead_Record_Type)`, ORDER BY CreatedDate DESC, LIMIT 500 |
| Lead detail | LeadRepository:286-305 | **SYSTEM_MODE** | `Id = :id AND OwnerId = me AND IsConverted = false` (no record-type filter) |
| Lead duplicates | LeadRepository:330-370 | SYSTEM_MODE | the owner's 500 newest open consumer leads, matched in Apex on name substring, phone digits or email; max 10 |
| Pre-approvals | LeadRepository:372-390 | **SYSTEM_MODE** | `OwnerId = me AND IsConverted = false AND Status = 'Pre-Approval' AND consumer RT`, ORDER BY Pre_Approval_Date__c DESC, LIMIT 500 |
| Loans list | LoanRepository:143-158 | **USER_MODE** | `(Loan_Officer__c = me OR OwnerId = me) AND Status__c IN ACTIVE_LOAN_STATUSES`, ORDER BY Closing_Date__c ASC NULLS LAST, LIMIT 500 |
| Loan detail | LoanRepository:160-176 | **USER_MODE** | `Id = :id AND (Loan_Officer__c = me OR OwnerId = me)` (no status filter) |
| Lead activity history | TaskRepository:180-196 | USER_MODE | `OwnerId = me AND Status = 'Completed' AND (WhoId = lead OR WhatId = lead)`, LIMIT 50 |
| Lead open tasks | TaskRepository:198-212 | USER_MODE | `OwnerId = me AND IsClosed = false AND WhoId = lead`, LIMIT 50 |

`ACTIVE_LOAN_STATUSES` (`ExternalLOBaselineHelper.cls:31-45`) contains: TRID Application, Open, Disclosures Out, Pre-Processing, Processing, Submitted, Conditionally Approved, Re-Submitted, Approved, Waiting On Loan Officer, Closing, Funding, **PC Review**. Suspended is excluded. PC Review is post-closing (see our status-pipeline note), yet it is treated as active here.

### 1.2 My Leads (`lwc/externalLoLeads`, Apex `getLeads`, `getLeadDetail`, `findLeadDuplicates`, `createLead`)

**Which records.** Open (unconverted) consumer-record-type Leads where **OwnerId is the portal user**. Nothing else ties a lead to the LO: `Loan_Partner__c` and LeadShare rows are never consulted. Because the query is SYSTEM_MODE, the Lead OWD (Private) and the missing Lead object permission on the Customer Community Plus licence do not matter. The owner filter is the only gate, and it is sufficient.

**Row content** (`ExternalLoPortalService.cls:358-383`, `externalLoLeads.js:175-196`):
- Title: Name.
- Badges: `Status` raw label, plus "Never contacted" when `LastActivityDate` is null.
- Primary line: `Loan_Purpose__c · Loan_Amount__c · Loan_Program__c`.
- Meta line: raw 18-character Salesforce Id (`idLabel = leadRecord.Id`, line 373), LeadSource, "Assigned &lt;CreatedDate&gt;" (it is the created date, not an assignment date), "Last activity &lt;LastActivityDate&gt;".
- Row actions: **Log communication** and **View**.

**Filters** (`externalLoLeads.js:10-16`; server side `ExternalLoPortalService.cls:733-770`):

| Chip | What it actually matches |
|---|---|
| All | everything |
| New | `Status = 'New'` |
| Working | Status in Working, Contacted, Qualified, Pre-Approval. **Contacted and Qualified do not exist in prod**; the only prod value that matches is Working (15 leads) |
| Nurture | blank Status, or a lead whose Status is unrecognised *and* `LeadSource = 'Past Client'`. **Status "Nurturing" (29,076 leads), "Nurture - Preapproval" (1,110) and "Nurture-Pre-Approval" (622) are not matched** |
| Never contacted | `LastActivityDate == null` |

The chip counts are computed client-side and use different rules from the server filter (`externalLoLeads.js:300-309`). The Working count excludes pre-approval and the Nurture count excludes past-client, so a chip's count can differ from the rows you get when you click it.

**Sorting and limits.** CreatedDate DESC, hard LIMIT 500. There is no paging and no "more than 500" warning, and the count labels silently cap at 500.

**Lead detail page.** This is a full-page detail inside the shell, not the drawer (`externalLoLeads.html:2-171`).
- Header: name, status *slug* (`detail.summary.status`, line 12; the list shows the label instead), primary line, Id, source, created date.
- Buttons: **Log communication** and **Open in Arive**.
- **Overview tab**:
  - Loan scenario (`ExternalLoPortalService.cls:422-435`): purpose, program, amount, down payment, estimated payment, property type, "Buying timeline" (which is actually `Rating` = Hot/Warm/Cold), city/state, purchase price, and the realtor from `Realtor_Buying_Agent__r.Name`.
  - `Description` shown as scenario notes.
  - Activity history: only Tasks the LO owns. Internal team activity is never shown.
  - Contact card: tel:/mailto: links.
  - Open tasks.
- **Documents tab**: embeds the internal `c-document-viewer`, which calls `DocumentViewerController` (`without sharing`, but its reads are USER_MODE).
- **Document requests tab**: embeds the internal `c-lead-portal-document-request-manager`, which calls `LeadDocumentRequestController`/`Service`. It is heavily SYSTEM_MODE and is part 0 finding 3's territory.
- **Calls tab**: two `c-call-insight-list` components (RingSense and Zoom), which call `CallInsightListController` (part 0 finding 2).
- None of these three components is in the portal source folder. They are internal-org components reused as-is.

**Actions and what they write:**

1. **Add lead** drawer (`externalLoLeads.html:195-223`). It has only 5 inputs: name, phone, email, loan amount and purpose. Program, source, market and notes are hardcoded in the JS defaults (`externalLoLeads.js:110-120`): `loanProgram = 'Conventional'`, `leadSource = 'Realtor referral'`, `market = ''`, `notes = ''`.
   - `findLeadDuplicates` runs on every keystroke in name, phone or email and only shows a warning.
   - `createLead` is always called with `forceCreate: true` (`externalLoLeads.js:416`), so the server's duplicate block (`ExternalLoLeadService.cls:15-17`) is unreachable from the UI.
   - The server inserts one Lead in **SYSTEM_MODE** (`ExternalLoLeadService.cls:47`). Values written:
     - RecordType `Consumer_Lead_record_type`, Status 'New', OwnerId = portal user.
     - The name is split on the first whitespace. A single-word name becomes FirstName = the word and LastName = "Borrower".
     - `Company = "<Last> Household"`.
     - Phone, Email, `Loan_Purpose__c` (a **multi-select picklist** receiving free text), `Loan_Amount__c`, `Loan_Program__c` (a text field that is effectively dead: 1 non-null in the last 90 days), LeadSource, City, Description.
   - No assignment rules are applied. The org's Lead triggers still run. On the one prod example, `Loan_Partner__c` came back null.
2. **Log communication**, from a row or the header. Opens `c-portal-communication-modal` with `object-api-name="Lead"` (section 1.5).
3. **Open in Arive**. The URL is built from `Arive_Base_Url__c`, which is null in prod, so this always shows the "not linked" toast (`externalLoLeads.js:455-465`).
4. Everything the embedded document, request and call components can do. That includes approving, rejecting and deleting document requests and sending request emails. **None of this is gated by portal-specific code.**

There is **no** edit of lead fields, no status change and no convert anywhere in this view.

### 1.3 My Pre-Approvals (`lwc/externalLoPreApprovals`, Apex `getPreApprovals`)

**Which records.** The same owner-only basis as Leads, plus `Status = 'Pre-Approval'` (LeadRepository:372-390). Pre-approval **conditions** (`Lead_Document_Request__c`) are **not** read here at all, even though "Docs outstanding" suggests they are.

**Row content** (`ExternalLoPortalService.cls:385-404`, `externalLoPreApprovals.js:125-143`):
- Title: borrower Name.
- Badges: status badge, plus "Weekly touch due".
- Primary line: amount · program. Program comes from Lead `Loan_Program__c`, which is 0 of 319 populated on prod pre-approvals; the live field is `Loan_Type_1st_TD__c`, at 201 of 319.
- Meta line: raw Lead Id · realtor name · "Expires &lt;Credit_Expiration_Date__c&gt;" (or "Expiration unknown", which is 209 of 319 in prod) · "Last touch &lt;LastActivityDate&gt;".
- `App_Summary_Credit__c` (the AI credit summary) is sent to the browser as `credit` but is never rendered. Drop it from the payload.

**Status derivation** (`ExternalLoPortalService.cls:721-731`, `ExternalLOBaselineHelper.cls:291-304`):

| Key | Label shown | Actual rule |
|---|---|---|
| expiring | "Expiring" chip, "Expiring soon" badge | `Credit_Expiration_Date__c <= TODAY`, which means **already expired**. That is 93 of 319 in prod. |
| docs-outstanding | "Docs outstanding" | `Last_Call_Attempt_RingCentral__c` **and** `Last_SMS_Attempt_RingCentral__c` are both null or more than 6 days old. This has nothing to do with documents. |
| ready-to-review | "Ready to review" | anything else |

**Weekly touch due**: `LastActivityDate` is null or more than 7 days ago.

**Filters**: All, Ready to review, Docs outstanding, Expiring, Weekly touch due. Chip counts are computed client-side and match the server rules.

**Sorting and limits**: Pre_Approval_Date__c DESC, LIMIT 500, no paging.

**Actions**: **View** only. It routes to the **My Leads** detail page for that Lead (`externalLoPreApprovals.js:168-177`). There is no log button on the pre-approval row itself (the drawer set has one).

### 1.4 My Loans (`lwc/externalLoLoans`, Apex `getLoans`, `getLoanDetail`)

**Which records.** Transactions where `Loan_Officer__c = me OR OwnerId = me`, in the active status list, queried in **USER_MODE**. Visibility therefore needs **both** the filter match **and** a real share row:
- Owner share: the LO owns the file.
- Manual share on `Transaction__Share`: the active flow `Re_create_Transaction_Share_Record_Upon_Owner_Change` creates a Manual **Edit** share for `Loan_Officer__c` when the owner changes. The flows that shared on a Loan Officer change (`Transaction_Sharing_Loan_Officer`, `Loan_Officer_Transaction_Sharing_Rule`) are **inactive**.

A loan whose `Loan_Officer__c` is set to an outside LO while an ops user owns it, with no owner change afterwards, is invisible in My Loans. The Loan Officer field alone is not enough.

**Row content** (`ExternalLoPortalService.cls:406-420`):
- Title: `Borrower_Name__r.Name`.
- Badges: milestone = `Status__c`, plus "Needs update".
- Primary line: `Loan_Amount__c` (**dead twin**; use `Loan_Amount_1st__c`) · `Loan_Program_1st__c`.
- Meta line: Name · "Closing &lt;Closing_Date__c&gt;" · processor name.
- `realtorLabel` exists on the DTO and is read by the LWC, but it is never populated: dead.

**Needs update** (`ExternalLOBaselineHelper.cls:310-317`): Status is "Waiting On Loan Officer", **or** `Current_Status_Since__c` is 3 or more days old. That flags every PC Review file after 3 days, even though the LO cannot act on it (3 of Harold's 6 live loans are PC Review).

**Filters** (`externalLoLoans.js:8-13`, `ExternalLoPortalService.cls:801-812`):

| Chip | Rule |
|---|---|
| All | everything |
| Needs update | the rule above |
| In process | Status is Processing, Underwriting or Submitted. **Underwriting is not a Status value.** |
| Clear to close | Status is 'Clear to Close'. **Not a Status value, so always 0.** |

**Sorting and limits**: Closing_Date ASC NULLS LAST, then LastModifiedDate DESC; LIMIT 500. The search placeholder says "borrower, ID, or milestone", but milestone is not searched (search covers borrower, Name and the always-null realtorLabel).

**Loan detail page** (`ExternalLoPortalService.cls:455-477`; `externalLoLoans.html`). A read-only field list:

| Field shown | Source | Note |
|---|---|---|
| Current milestone | Status | |
| Status since | Current_Status_Since__c | |
| Closing date | Closing_Date__c | |
| Processor | Processor__r.Name | |
| Loan amount | Loan_Amount__c | **dead twin** |
| Purchase price | Purchase_Price__c | |
| Rate | Interest_Rate__c | **dead twin**; use `Rate_1st_TD__c` |
| LTV / DTI | LTV__c / DTI_Back_End__c | shown as raw Decimal + '%' |
| Property | Property_Address__c | |
| Lock expires | Lock_Exp_Date_1st_TD__c | **0% populated**; use `Rate_Lock_Exp_Date__c` |

The loan detail has **no actions**: no log communication, documents, conditions or status change. The only way to log against a loan is the Perfect Day drawer's "milestone-loans" set.

### 1.5 Communication modal (`lwc/portalCommunicationModal`, Apex `logCommunication`)

**Where it opens from:**
- My Leads row and header, with `objectApiName = "Lead"`, phone and email.
- The Perfect Day record drawer, with the object from the record set: Lead, Account or Transaction__c.

**The form.** Channel (call / text / email / in-person / video), outcome (a per-channel list), notes (at least 3 characters, enforced client- and server-side), and follow-up (tomorrow, the default / 3 days / next week / none).

**What it writes** (`ExternalLoCommunicationService.cls:5-114`):
- **One Task**, inserted in **SYSTEM_MODE**:
  - OwnerId = portal user, Status 'Completed', Priority 'Normal', ActivityDate today.
  - Description = notes.
  - Subject = "&lt;Channel&gt; - &lt;outcome slug with hyphens replaced by spaces&gt;", for example "Call - left voicemail".
  - `Activity_Type__c` is derived from the channel: call → 'Call - Active Agent'; text → 'Text'; email → 'Email'; in-person and video → 'Meeting (Active Agent)'.
  - WhoId = recordId when objectApiName is 'Lead'; otherwise WhatId = recordId.
  - `Activity_Category__c` is **not** set.
- **One Event** unless follow-up is 'none', also SYSTEM_MODE: Subject 'Follow up', 09:00 on the target day in the running user's time zone, 15 minutes, the same Who/What.
- Because follow-up defaults to "tomorrow", **every save creates an Event** unless the user changes it.

**What it does not do:**
- It does not update Lead Status, the RingCentral last-attempt fields or anything else. As a result the Pre-Approvals "Docs outstanding" state never clears from portal logging.
- It does not verify that recordId belongs to the user, or even that it is an Id of the named object (see section 2).

**Smaller bugs:**
- The template uses `{hasContact}` (`portalCommunicationModal.html:15`), but no such getter exists in the JS. The phone/email strip never renders, so the phone and email passed from My Leads are dead inputs.
- Notes bind on `onchange` (`portalCommunicationModal.html:57`). That fires on blur. It works when the user clicks Save, but it is fragile, for example with keyboard submit.
- The goal-credit copy is wrong (top finding 9). "Call - Active Agent" credits Realtor Outreach first. Email credits Social Engagement. In-person and video credit Partner Meeting. Only Text credits Consumer Conversation.

### 1.6 Record drawer (`lwc/portalRecordDrawer`, Apex `getRecordSet`, not cacheable)

The drawer is opened from Perfect Day Home tiles and priorities (`perfectDayHome.html:261-266`). Record sets are defined in `ExternalLoPortalService.cls:201-310`:

| Key | Contents | Log button | Opens |
|---|---|---|---|
| new-leads | `getLeads('new')`: every lead with Status New (the Perfect Day home uses a different selector, `selectNewLeadsToContact`) | yes (Lead) | My Leads detail |
| pre-approvals | `getPreApprovals('all')` | yes (Lead) | My Leads detail |
| milestone-loans | `getLoans('update')` | yes (Transaction__c) | My Loans detail |
| realtor-follow-ups | `getRealtors('due')` | yes (Account) | My Realtors |
| overdue-tasks, activities-remaining, completed-today, goal-&lt;period&gt;-&lt;key&gt; | Task rows | no (`LOGGABLE_SETS`, `portalRecordDrawer.js:8-13`) | toast only |

Each drawer card shows name, primary, secondary and a tag, with **Log communication** and **Open record** buttons. Outside the shell, "Open record" falls back to `standard__recordPage` navigation (`portalRecordDrawer.js:193-203`). On an LWR site that page probably does not exist, but the shell always embeds the drawer, so the fallback is effectively dead code.

---

## 2. What an external user can see

### 2.1 Leads and Pre-Approvals

- The Apex runs `with sharing`, but the queries are **SYSTEM_MODE** (ADR-0001 comment, LeadRepository:1). Sharing and FLS are bypassed, and the explicit `OwnerId = UserInfo.getUserId()` filter is the only gate.
- **Another LO's leads: no.** Every selector used by these views, including detail, is owner-filtered. The detail Id comes from the URL, but `selectPortalLeadDetail` re-checks `OwnerId`.
- **Fields they shouldn't see.** Only the fields listed in the selectors are returned. Internal notes (`Description`) are shown, but these are the LO's own leads. `App_Summary_Credit__c` goes to the browser unnecessarily. No comp or pricing fields are on the lead path.
- **Activity history** is limited to Tasks the LO owns (USER_MODE plus `OwnerId = me`). Internal staff Tasks on the same lead are not visible.

### 2.2 Loans

- **USER_MODE** with the `Loan_Officer__c = me OR OwnerId = me` filter. Sharing and FLS are both enforced.
- The portal permission set gives Transaction__c Read (Create comes from the profile; there is no Edit). FLS read is granted on every field the loan views select. I checked all 14.
- **Another LO's loans: no.** A Transaction__Share alone does not get a loan into the list without the LO/Owner match. The LO/Owner match alone does not work without a share row.
- **Comp and internal fields**: none are selected on this path.

### 2.3 Writes from this area

- `logCommunication` is **SYSTEM_MODE with no authorization check**. Given any Lead, Account, Transaction, Opportunity or Contact Id (Who/What accept many types), an outside LO can create completed Tasks and Events on it.
  - Those activities then appear on internal timelines, update `LastActivityDate` on the target, and fire the org's Task and Event automation.
  - The object-name allow-list (`ExternalLoCommunicationService.cls:23, 32`) is not tied to the Id type.
  - **Fix:** re-query the target with the same owner/LO filter as the read path before inserting, and reject on no match. Also add a test that runs as a second user.
- `createLead` inserts in SYSTEM_MODE, but the owner is forced to the caller, so the only thing at risk is data quality: free text in a multi-select picklist, and hardcoded source and program.

### 2.4 Holes via components embedded in the Lead detail (verified in prod metadata)

**CallInsightListController (`without sharing`).** Its dynamic SOQL has no mode clause and no owner filter; the prod body was pulled to `scratchpad\deepdive\src\CallInsightListController.cls`, lines 1-33.
- It returns `Transcript__c`, `Summary__c`, `Next_Steps__c` and more for **any** Lead, Account or Transaction Id.
- `getZoomRecordings` returns Zoom `Play_URL__c` and `Play_Passcode__c` for any meeting Id.
- It is granted by the portal profile **and** by `External_LO_Perfect_Day_Access`.
- It is exploitable by calling the Apex action directly with another record's Id; the UI does not need to expose it.

**Lead_Document_Request__c.**
- External OWD is ReadWrite, and `External_LO_Perfect_Day_Access` grants Read, Create, Edit and Delete on it.
- The Apex service behind the Requests tab is also mostly SYSTEM_MODE (`LeadDocumentRequestService` lines 392-755 and elsewhere). Hand this to whoever owns the document-requests area. It needs its own review of `initializeData`, `saveRequests` and `deleteRequest` with a foreign lead Id.

**Apex class access.** The portal profile (`X00eAJ000000LsqrYAC`, "RHL Community User") grants **1,358 Apex classes**, and the permission set another 44. Any `@AuraEnabled` method on any of those classes is callable from the portal. A full audit of `without sharing` plus `@AuraEnabled` classes in that grant list is warranted.

---

## 3. How data reaches the portal user (prod, 2026-09-28)

**Portal users.** Ten users are on the RHL Community User profile (Customer Community Plus licence). Only **two are active**:

| User | Id | Contact / Account | Role | Last login |
|---|---|---|---|---|
| Harold Ellis | 005AJ000000Ig20YAC | 003AJ000003gDBbYAM / 001AJ0000047qQ8YAI "Customer Community User" | Customer Community User Customer User (Worker) | 2026-09-24 |
| Reach Admin (outsidelo@reachhomeloans.com, the test user) | 005Qi000005FLvhIAG | 003Qi00000NcpqfIAB / same Account | same role | 2026-09-28 |

**Shared account.** The two users share one Account and one role, and that Account is owned by **Nimbus Development**. The Customer Community Plus peers are in the same Worker role, so role hierarchy does not expose one to the other. If anyone is ever promoted to a Manager role or made a super user on that shared account, they would see every other outside LO's owned records.

**Permission sets.**
- Harold: profile, `Condition_Files_Permissions`, `External_LO_Perfect_Day_Access`.
- Reach Admin: the same, plus `Account_Follow_Up_Access` and `ConditionPermissions`.
- The portal test helper assigns `Lead_Access` and `All_Leads`, which the real users do not have.

**Mechanism.** No sharing sets are involved; Customer Community Plus uses role-based sharing.
- **Leads**: ownership only. Nothing in prod assigns leads to community users. They get leads by creating them in the portal, through the CSV import (a different area), or by an admin changing OwnerId.
- **Transactions**: ownership, plus Manual shares created by the owner-change flow.
- **Accounts**: ownership.

**Real counts:**

| | Harold Ellis | Reach Admin |
|---|---|---|
| Leads owned (all) | **0** | 1 (test "Testington Testerillo", New, created in the portal 2026-09-15) |
| LeadShare rows | 0 | 1 (Owner) |
| Leads with Loan_Partner__c = user | 0 | 0 |
| Transactions as LO or Owner | 136 (81 + 5 Post-Closed, 43 + 1 Cancelled, 3 PC Review, 2 Conditionally Approved, 1 Closing) | 0 |
| **Visible in My Loans (active statuses)** | **6** (3 PC Review, 2 Conditionally Approved, 1 Closing; all owned by Harold) | 0 |
| Transaction__Share | 130 Owner, 6 Manual Read (created 2026-07-16 and 07-31; all on Post-Closed or Cancelled files owned by ops users) | 0 |
| AccountShare | 190 Owner | 17 Owner |
| Tasks owned | 2 open | 43 completed (all RingCentral "Called Reach" imports; none came from the portal) |
| Events owned | 6 | 0 |

What each view shows today:
- **Harold**: My Leads 0, My Pre-Approvals 0, My Loans 6. Every one of the 6 shows amount "—". The 3 PC Review files show "Needs update" once they are 3 or more days in status.
- **Reach Admin**: 1 lead, 0 pre-approvals, 0 loans.
- **Nobody has ever logged a portal communication in prod.** No Task with a portal `Activity_Type__c` and no Event was created by either user. The logging path has never run in production.

---

## 4. Risks, bugs, dead code, limits, tests

### 4.1 Bugs and correctness

1. The cross-record write hole in `logCommunication` (section 2.3).
2. **Dead-twin fields on loans** (`ExternalLoPortalService.cls:411, 467, 469, 475`; LoanRepository:149, 166-168). Population on 37 active files:

   | Field the portal reads | Populated | Use instead | Populated |
   |---|---|---|---|
   | Loan_Amount__c | 3 | Loan_Amount_1st__c | 36 |
   | Interest_Rate__c | 3 | Rate_1st_TD__c | 36 |
   | Lock_Exp_Date_1st_TD__c | 0 | Rate_Lock_Exp_Date__c | 26 |

3. **Dead field on leads**: Lead `Loan_Program__c` is populated on 0 of 319 pre-approvals, so the program column is always blank; `Loan_Type_1st_TD__c` is at 201 of 319. The Add lead form writes 'Conventional' into this dead text field.
4. Lead stage mapping versus real Status values (top finding 6). `'Contacted'`, `'Qualified'`, `'Closed'` and `'Closed - Not Converted'` do not exist in prod (`ExternalLoPortalService.cls:733-754`).
5. The loan filters "Clear to close" and "Underwriting" can never match (`ExternalLoPortalService.cls:808-811`; `externalLoLoans.js:165-173`).
6. PC Review is treated as active and "needs update" (`ExternalLOBaselineHelper.cls:44, 310-317`).
7. The pre-approval labels are misleading ("Docs outstanding", "Expiring soon"), and "Docs outstanding" depends on RingCentral fields that outside LOs never touch.
8. The client and server filter rules for Working and Nurture differ, so chip counts do not match the rows shown.
9. The Arive base URL is null in prod, so the button always errors with misleading copy.
10. `hasContact` is undefined in the modal, so the contact strip never renders.
11. Goal credit is mis-attributed (top finding 9). Only Text lands on Consumer Conversation.
12. `forceCreate: true` is hardcoded, so the server-side duplicate block is dead from the UI. The duplicate check is also scoped to the LO's own leads only, and so does not catch the same borrower already in the org under an internal LO.
13. Free text is written into the `Loan_Purpose__c` multi-select picklist in SYSTEM_MODE.
14. The lead detail header shows the status slug; the list shows the label.
15. "Assigned &lt;date&gt;" is actually CreatedDate.
16. Raw 18-character Salesforce Ids are displayed as "ID" in lead and pre-approval rows.
17. The "Buying timeline" label is mapped to `Rating` (Hot/Warm/Cold).
18. LTV and DTI print raw Decimal precision.

### 4.2 Dead or half-finished

- `LoanRow.realtorLabel` is never set.
- `CreateLeadRequest.referringPartnerId` is never set by the controller. If it ever were, it would write an Account Id into `Lead.Loan_Partner__c`, which is a User lookup, and the insert would fail (`ExternalLoLeadService.cls:43-45`).
- `PreApprovalRow.credit` is never rendered.
- `portalListLayout.rowType` is ignored.
- The "outside shell" branches in all three LWCs (`CurrentPageReference` parsing and `standard__objectPage`/`recordPage` navigation) are unused, because the site only uses the shell. The lead/loan views are also exposed as `lightning__AppPage` targets.
- The loan detail has no actions: no logging and no documents.
- The Add lead form has no inputs for program, source, market or notes, even though Apex accepts them.
- LeadRepository and LoanRepository carry commented-out Owner-field blocks and legacy `SELECT *`-style dynamic methods from 2020 (LoanRepository:1-3, 9-42, 50-66).
- No TODO or FIXME markers exist in these files.

### 4.3 Hardcoded values

- `ACTIVE_LOAN_STATUSES`, `CONSUMER_LEAD_RECORD_TYPES` and the thresholds (6 days, 3 days, 7 days) are constants in `ExternalLOBaselineHelper.cls:9-45`.
- Lead status strings are hardcoded in `deriveLeadStage` and the loan statuses in `matchesLoanFilter`.
- The follow-up time is 09:00 in the user's time zone, with a 15-minute duration.
- Channel-to-Activity_Type mapping: `ExternalLoCommunicationService.cls:67-76`.
- Record type: `Consumer_Lead_record_type` via inline SOQL (`ExternalLoLeadService.cls:19-25`), duplicating `LeadRepository.selectConsumerLeadRecordTypeId`.
- Form defaults: 'Conventional' and 'Realtor referral'. Prod stored the latter as 'Realtor Referral'.

### 4.4 Governor limits and performance

- **No paging anywhere.** 500-row caps are silent. A heavy LO would lose rows without knowing.
- Each search keystroke causes 2 Apex calls per view. Each call re-queries up to 500 rows and filters them in Apex.
- `LeadRepository` and `LoanRepository` do a `Schema.getGlobalDescribe()` field-map walk in their static initialisers (LeadRepository:6-19; LoanRepository:9-42, which covers Transaction, all Account fields and User). That CPU cost is paid on every portal request that touches them, including the nav badges.
- `getNavBadges` runs four full list queries to produce counts.
- `countSharedBuyers` and the realtor path (`getRealtors`, which runs inside the badges) add more queries.
- Tests assert fewer than 50 and fewer than 100 SOQL queries, so there is headroom, but CPU time is untested.

### 4.5 Test quality

`ExternalLoPortalServiceTest` (598 lines), `ExternalLoPortalCoverageTest` (397 lines) and `ExternalLoPortalTestHelper`:
- **They run as the deploying admin.** `currentUser()` is used as `testUser` everywhere, with `System.runAs(currentUser)`. The helper's `createCommunityOrStandardImporter` looks for the profile name 'Customer Community Plus User', which does not exist; ours is 'RHL Community User'. So even that path falls back to a standard user.
- **Nothing proves the security model**: no two-user test, no "cannot see another owner's lead or loan", and no "cannot log on a foreign record".
- **Test data seeds the dead fields** (`Loan_Amount__c`, `Interest_Rate__c`, `Lock_Exp_Date_1st_TD__c`, Lead `Loan_Program__c`), so the tests stay green while prod shows blanks.
- **Assertion quality.** About 52 `assertNotEquals(null, …)` in ServiceTest and 7 in CoverageTest; several whole test methods are pure coverage calls. Examples:
  - `controllerMethods_exposePortalData` (ServiceTest:114-146)
  - `repositoryMethods_supportPortalAndLegacyPaths` (ServiceTest:483-555)
  - `portalFiltersAndRecordSets_coverRemainingBranches` (CoverageTest:273-296), which calls 15 methods and asserts one non-null.
- **Real behaviour assertions** exist for: lead filter count, detail Id, the bulk 200-lead path, 1 loan and 1 pre-approval visible, task and event creation on log, validation messages, and house-lock logic.
- Last recorded runs (2026-09-23): the CoverageTest methods passed after an earlier failing run the same day. Coverage aggregates in prod currently read 0 (stale). Per our deploy notes, use RunSpecifiedTests.

---

## 5. Manual test checklist

**Setup.** Use the Reach Admin test portal user (outsidelo@reachhomeloans.com). Create test records as an admin in prod, or better in a Developer sandbox with a copy of the site. Have an internal admin tab open to verify writes. Note the new leads you create so you can clean them up.

| # | Steps | Expected (and current actual where it differs) |
|---|---|---|
| L1 | Log in and open My Leads. | "Testington Testerillo" is listed with badge "New" and "Never contacted". The meta line shows a raw 00Q… Id and "Realtor Referral". |
| L2 | As admin, create a consumer lead owned by another user and give Reach Admin a Manual LeadShare. Reload My Leads. | **Not listed** (owner-only by design). Confirms that shares are ignored. |
| L3 | As admin, set OwnerId of a test consumer lead with Status "Nurturing" to Reach Admin. Click the Nurture chip. | Expected: listed. **Actual: not listed** (bug 4). It appears only under All. |
| L4 | Same with Status "Contact Attempt 1", then click Working. | **Not listed** under Working (bug 4). |
| L5 | Type part of a name in search. | The list narrows. Chip counts update. Two Apex calls per keystroke are visible in the network tab. |
| L6 | Add lead with name "Test Single" (one word "Single" as well), phone, amount 300000, purpose "Purchase". | The lead is created. The internal record shows Owner = Reach Admin, RT Consumer, Status New, LeadSource "Realtor Referral", `Loan_Program__c` "Conventional", a single-word name stored as First = word and Last = "Borrower", and Company "&lt;Last&gt; Household". Check `Loan_Partner__c` and which Lead automations fired. |
| L7 | Add lead again with the same phone. | A "Possible duplicate" warning appears, but the save still succeeds (forceCreate is hardcoded). |
| L8 | Add lead with no phone and no email, or amount 0. | Error "Add a phone number or email…" or "Enter an estimated loan amount." |
| L9 | Open a lead (View). | Detail loads. The overview shows the scenario, activity history (own Tasks only) and open tasks. The status badge shows the slug. |
| L10 | Change `c__recordId` in the URL to an internal user's lead Id. | Toast "Lead could not be found or is not visible", then back to the list. |
| L11 | Click Open in Arive. | **Actual: error toast "Arive is not linked"** (CMDT URL null), even if the lead has an AriveId__c. |
| L12 | Log communication on a lead: Call, "Left a voicemail", note, Tomorrow. | Success toast. Internal check: a Task (Completed, Subject "Call - left voicemail", `Activity_Type__c` "Call - Active Agent", Owner Reach Admin, WhoId the lead) and an Event "Follow up" tomorrow 09:00. Also check whether org automation rewrote the Task Subject. On Perfect Day, check which goal got the credit. **Expected by the copy: Consumer convos. Likely actual: Realtor outreach.** |
| L13 | Log communication with a 2-character note. | "Add a short note…" appears, and nothing is written. |
| L14 | In the log modal, look for the phone/email strip. | **Not shown** (the `hasContact` bug). |
| L15 | Open the Documents, Document requests and Calls tabs on your own lead. | Each component loads without error for the community user. Record any "insufficient access" error. |
| P1 | As admin, set a test lead owned by Reach Admin to Status "Pre-Approval" with `Credit_Expiration_Date__c` = yesterday. Open My Pre-Approvals. | Listed with badge "Expiring soon". The meta line shows "Expires &lt;yesterday&gt;". **Note: it is already expired.** |
| P2 | Same lead with a future expiration and no RingCentral dates. | Badge "Docs outstanding", regardless of any document requests. |
| P3 | Log a communication on that lead via My Leads, then return. | "Weekly touch due" clears (LastActivityDate updates). "Docs outstanding" **does not** clear. |
| P4 | Click View on a pre-approval. | You land on the My Leads detail for that lead. |
| O1 | Log in as Harold (only with his consent, or reproduce with the test user owning a copy loan) and open My Loans. | 6 loans. **Amount shows "—" on every row** (dead twin). |
| O2 | Click the "Clear to close" chip. | Count 0, empty list (bug 5). |
| O3 | Open a loan. | Detail fields listed. **Loan amount "—", Rate "—", Lock expires blank.** There are no action buttons. |
| O4 | As admin, set `Loan_Officer__c` = test user on a Transaction owned by an ops user, without changing the owner. | **Not visible** in My Loans (no share row). Change the owner and it becomes visible, via the flow's Manual Edit share. |
| O5 | Put `c__view=loans&c__recordId=<a Transaction not yours>` in the URL. | "Loan could not be found or is not visible." |
| D1 | From Perfect Day Home, open each drawer set: new leads, pre-approvals, milestone loans, realtor follow-ups, overdue tasks, completed today. | Titles and subtitles match. The Log button appears only on the four loggable sets. Open record routes to the right view. Task rows show the toast. |
| D2 | Log from the drawer on a milestone loan. | The Task has WhatId = Transaction and the drawer reloads. Check that the loan's "Needs update" state **does not** change (logging does not touch Status). |
| S1 (security, sandbox only) | Using the browser devtools console or an Apex-action replay as the portal user, call `logCommunication` with a Lead Id owned by an internal LO. | **Current: succeeds** (the hole). After the fix it must fail. |
| S2 (security, sandbox only) | Replay `CallInsightListController.getCallInsights` with an internal lead Id that has Call_Insight__c rows. | **Current: returns transcripts.** It must return nothing. |
| S3 (security, sandbox only) | As the portal user, read or update a `Lead_Document_Request__c` on an internal lead through the UI API (`getRecord` or `updateRecord`). | **Current: allowed** (OWD ReadWrite plus CRUD). |

---

## 6. Suggested first fixes, smallest first

1. **Ownership check in `logCommunication`.** Re-select the target with the read path's filters: Lead through `selectPortalLeadDetail`; Transaction through `selectPortalLoanDetail`; Account through the partner selector. Throw DomainException when nothing matches. Add a two-user test.
2. **Lock down `CallInsightListController`.** Switch it to `with sharing` plus `WITH USER_MODE`, or add an owner check for portal users. Remove it from the portal profile if the Calls tab is not needed.
3. **Close the Lead_Document_Request__c exposure.** Set external OWD to Private, or remove the CRUD from `External_LO_Perfect_Day_Access` and route everything through owner-checked Apex.
4. **Swap the dead twins.** `Loan_Amount__c` → `Loan_Amount_1st__c`, `Interest_Rate__c` → `Rate_1st_TD__c`, `Lock_Exp_Date_1st_TD__c` → `Rate_Lock_Exp_Date__c`, and Lead `Loan_Program__c` → `Loan_Type_1st_TD__c`. Update the tests to seed the live fields.
5. **Fix the status maps.** Base the lead stages on the real Status values and remove the Clear to Close / Underwriting filters or remap them, for example Clear to Close → `Clear_to_Close_Date__c != null`. Decide whether PC Review belongs in "active".
6. **Rename the pre-approval states**, or base them on real signals: `Lead_Document_Request__c` open count and `Credit_Expiration_Date__c` within N days.
7. Either set `Arive_Base_Url__c` or hide the button.
8. Add the `hasContact` getter and set `Activity_Category__c` on logged Tasks so goal credit is deterministic.
