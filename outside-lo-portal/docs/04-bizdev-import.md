# Partner Workspace deep dive 04: Business Development and Import Data

Scope: Realtor Prospects, My Realtors, Past Clients, Import Data (CSV). Read-only review done on 2026-09-28.

Paths below are relative to `C:\Apps\Claude Back Up\outside-lo-portal\force-app\main\default\`. Three classes the views depend on are **not in that retrieve**: `PersonAccountRepository`, `LeadRepository` and `PersonAccountDuplicateService`. I pulled their bodies read-only from prod (tooling `ApexClass.Body`) into `scratchpad\deepdive\src\`. Line numbers for those three refer to those copies. `ExternalLoPortalService.cls` matches prod exactly (diffed). The code comments cite ADR-0001, ADR-0002 and ADR-0006, but **none of those ADR files exist in the repo**.

---

## 0. Top findings

| # | Severity | Finding | Where |
|---|---|---|---|
| 1 | **High (likely live bug)** | `countSharedBuyers` queries Lead `WITH USER_MODE`. Portal users have **no Lead object permission**: I checked ObjectPermissions for Harold Ellis and there is no Lead row. `LeadRepository` itself says the license has no Lead CRUD. For any LO with at least one partner, the query should throw. That breaks `getRealtors`, so My Realtors, the Realtors nav badge (`getNavBadges`), Perfect Day "realtor-follow-ups" and the activity-log contact picker would all fail. The My Realtors LWC wire has no error branch, so the failure shows up as a silent "No partners in this window". Confirm with one portal login. | `ExternalLoPortalService.cls:83-100`, `externalLoRealtors.js:102-110` |
| 2 | **High** | "Add partner → Create new" duplicate checks run **with sharing**: the name search in `searchSharedPartners` and the email/phone check in `PersonAccountDuplicateService.findMatches`. Account external OWD is Private, so a portal LO only sees their own accounts, and both checks are effectively blind to the other ~8,200 partner accounts. The result is a new duplicate realtor Person Account. The developers found this same visibility problem for CSV import (ADR-0002 comment) and fixed it only there. | `ExternalLoPartnerService.cls:29-45`, `PersonAccountRepository.cls:125-141`, `PersonAccountDuplicateService.cls:16,63-80` |
| 3 | **High** | The CSV partner matcher only looks at `PersonEmail`/`Phone`, and only at records whose multi-select `Group__pc` is **exactly** one of 4 values. **2,419** Person Accounts are flagged as realtors another way (`Is_Realtor__c`, `Type__c`, `Type`) but have none of those Group values. Another **35** have `Realtor` plus another value. All of them are invisible to the matcher, so importing them creates duplicates. Mobile, Email_2, Phone_2 and other alternate fields are ignored too. | `PersonAccountImportSelector.cls:8-23` |
| 4 | **High (functional)** | **Past Clients is not past clients.** It lists **Leads** with `LeadSource='Past Client'` owned by the LO, not Person Accounts with closed `Transaction__c`. Harold Ellis is `Loan_Officer__c` on 136 Transactions and has 0 rows in Past Clients. The only way in is the CSV "Type = Past Client" path. | `ExternalLoPortalService.cls:156-168`, `LeadRepository.cls:392-409` |
| 5 | Medium | "Link" in the Add-partner drawer is a **no-op**. `linkPartner` only reads the record and returns it. It writes no assignment and no share, but the UI still shows "Partner linked". | `ExternalLoPartnerService.cls:14-27`, `externalLoRealtors.js:351-369` |
| 6 | Medium | CSV import lets any portal LO give themselves **Read access** to any non-house-locked partner Person Account in the org, including ones owned by internal LOs. They only need the realtor's email or phone. The code has a without-sharing selector plus a without-sharing Manual AccountShare insert. The "managed by the Reach house team" error also confirms that a phone or email belongs to a house realtor. | `PersonAccountImportSelector.cls`, `ExternalLoPartnerLinkWriter.cls`, `ExternalLoPartnerCsvImporter.cls:84-92,258-323` |
| 7 | Medium | Default Realtors filter is `90` = "touched by me in the last 90 days". Partners with no touch never match 30/60/90/due. Newly created or imported partners appear only under "All partners", so the list looks empty right after an import. Harold has 18 in-scope partners and 0 completed Tasks, so his default view is empty. | `ExternalLoPortalService.cls:772-789` |
| 8 | Medium | Consumer-import leads get `Status='New'`, even when Type is Past Client. `deriveLeadStage` checks Status before LeadSource, so past clients show as **new leads**. They inflate the New Leads badge and flood Perfect Day "New leads need contact". | `ExternalLoCsvImportService.cls:128,136-138`, `ExternalLoPortalService.cls:733-749` |
| 9 | Medium | Consumer import dedupes only against **this LO's own unconverted consumer Leads**. It does not check Person Accounts, converted Leads or other owners' Leads, so importing a book of past clients duplicates existing borrowers. Matched rows are dropped **silently**, with no row outcome at all. | `ExternalLoCsvImportService.cls:66-120`, `LeadRepository.cls:216-243` |
| 10 | Medium | The CSV tests never run as a portal user. `currentUser()` is the admin, and the helper looks up profile `Customer Community Plus User`, but prod uses `RHL Community User`, so it falls back to a Standard User. Findings 1 and 2 are exactly the bugs this blind spot hides. | `ExternalLoPortalTestHelper.cls:4-46` |

Real data: the only portal users are the 2 active ones (8 inactive). There are **0 `External_User_Assignment__c` rows** in the whole org, **0 Manual AccountShares** to either user, and **0 Accounts created through these portal paths**. The import and link features have never been used in prod.

---

## 1. The four views

All Apex entry points are `ExternalLoPortalController` (`with sharing`) or `ExternalLoWorkspaceController.importCsv`. The LO is always `UserInfo.getUserId()`, and no user id is ever taken from the client.

### 1a. My Realtors (`lwc/externalLoRealtors`)

**Record set.** `ExternalLoPortalController.getRealtors(filterKey, searchTerm)` (`classes/ExternalLoPortalController.cls:53-56`) calls `ExternalLoPortalService.getRealtors` (`classes/ExternalLoPortalService.cls:54-81`), which calls `PersonAccountRepository.selectPortalPartnersForUser` (`src/PersonAccountRepository.cls:74-108`):

```sql
-- step 1: every Account/Opportunity/etc. the LO has a COMPLETED task on
SELECT WhatId FROM Task WHERE OwnerId = :userId AND WhatId != null AND Status = 'Completed' LIMIT 5000
-- step 2: ExternalUserAssignmentRepository.selectContactIdsByUserId (SYSTEM_MODE, LIMIT 2000)
SELECT Contact__c FROM External_User_Assignment__c WHERE User__c = :userId AND Contact__c != null
-- step 3 (with sharing, no USER_MODE -> sharing enforced, FLS not)
SELECT ... FROM Account
WHERE IsPersonAccount = true
  AND Group__pc IN ('Realtor','Realtor Prospect','Title Agent','Insurance Agent')   -- multi-select: exact match only
  AND (OwnerId = :userId OR Follow_Up_LO__c = :userId OR Preferred_LO__c = :userId
       OR Id IN :partnerIds OR PersonContactId IN :assignedContactIds)
ORDER BY Name LIMIT 500
```

An account is tied to the LO in five ways: `Account.OwnerId`, `Account.Follow_Up_LO__c`, `Account.Preferred_LO__c`, a completed Task owned by the LO with `WhatId` = the account, or an `External_User_Assignment__c` (User__c = LO, Contact__c = PersonContactId). The query runs with sharing, so every row must also be visible to the portal user through ownership or an AccountShare. Account OWD is Private internal and external (EntityDefinition).

**Row enrichment:**
- Last touch comes from `TaskRepository.selectLastActivityDatetimeByWhatIds` (`classes/TaskRepository.cls:133-163`). It takes completed Tasks owned by the LO on those accounts and uses `CompletedDateTime`, falling back to `ActivityDate` and then `CreatedDate`. Only **your own** touches count, and other staff's activity is ignored.
- Shared buyers come from `countSharedBuyers` (`ExternalLoPortalService.cls:83-100`), a count of the LO's unconverted Leads with `Realtor_Buying_Agent__c` = partner, run `WITH USER_MODE`. See finding 1. Note that it uses `Realtor_Buying_Agent__c`, **not** `Lead.Referral_Source__c`, which is the org's realtor attribution field.
- The row is built by `mapPartner` (`ExternalLoPortalService.cls:312-332`): name, company (`Company__c`), market (`BillingCity`), partner type (from `Group__pc`), phone, email, `daysSinceMyTouch`, `houseLocked`, `followUpDue`.

**House lock** (`ExternalLoPortalService.cls:334-346`). A partner is locked when `Biz_Dev_Designation__c` is `'Biz Dev - Reach'` or `'Biz Dev - Bondarevsky'` **and** the LO is not the Owner, Follow_Up_LO or Preferred_LO. Locked rows are view-only in the UI. There are 6,128 locked Person Accounts in prod.

**"Due"** means `daysSinceMyTouch >= 7` (`ExternalLOBaselineHelper.REALTOR_FOLLOW_UP_ORANGE_DAYS = 7`, `ExternalLOBaselineHelper.cls:10`; `ExternalLoPortalService.cls:330`). A partner you have **never** touched is never due. That threshold is inconsistent with `ExternalLOBaselineHelper.cls:273`, which uses `> 7` for orange. The nav badge `dueRealtors` = `getRealtors('due', null).size()` (`ExternalLoPortalService.cls:150`).

**Filters** (`externalLoRealtors.js:11-17`, server side at `ExternalLoPortalService.cls:772-789`):

| Chip | Rule |
|---|---|
| Last 30 / 60 / **90 (default)** | `daysSinceMyTouch != null && daysSinceMyTouch <= N`. Untouched partners are excluded. |
| Follow-up due | `followUpDue` (touched, and 7 or more days ago) |
| All partners | everything except `Realtor Prospect` |
| (hidden) `prospects` | only `Group__pc = 'Realtor Prospect'`, used by the Prospects view |

Prospects are excluded from every Realtors chip, including "All". The default `'90'` is hard-coded in `externalLoRealtors.js:22,44,52`, `externalLoPortalShell.js:185` and `portalUtils.js defaultFilterForView`. Search is a case-insensitive substring match over name, company and market, done in Apex after the query (`ExternalLoPortalService.cls:814-820`). The component uses two wires, one for the active filter and one for `'all'` to feed the chip counts. Both fire on every search keystroke, because `portalListLayout` does not debounce (`portalListLayout.js:39-45`).

**List columns and badges** (`externalLoRealtors.js:162-187`): title = name. Badges: partner type, "House account" and "Follow-up due". The primary line is company · market, and the meta line is "Last touch N days ago / No communication logged by you · N shared buyers". Locked rows get a note.

**Detail** (`getPartnerDetail`, `ExternalLoPortalService.cls:102-122`) calls `selectPortalPartnerDetail` (`src/PersonAccountRepository.cls:110-123`). That lookup is **by Id only, with sharing**, with no Group or ownership filter, so any visible Person Account opens. The detail shows your own completed activities (`TaskRepository.selectCompletedActivitiesForRecord`, USER_MODE, OwnerId = LO) and the "shared pipeline", i.e. your open consumer Leads with `Realtor_Buying_Agent__c` = partner (`LeadRepository.cls:267-284`, SYSTEM_MODE, OwnerId filter).

**Actions and what they write:**

| Action | Apex | Writes |
|---|---|---|
| Log touch (list) / Log communication (detail) | `logCommunication` → `ExternalLoCommunicationService` (`classes/ExternalLoCommunicationService.cls:5-21`) | Inserts a **Task**, `SYSTEM_MODE`: Owner = LO, Status Completed, ActivityDate today, `WhatId` = account, Subject "Call - <outcome>", `Activity_Type__c` from the channel (call → `Call - Active Agent`, in-person/video → `Meeting (Active Agent)`). Optionally also a follow-up **Event** at 9:00 on +1/+3/+7 days (`:89-114`). There is **no server-side house-lock check**, only the UI hides the button. |
| Add partner → search | `searchPartners` → `PersonAccountRepository.searchSharedPartners` (`:125-141`) | None. It runs with sharing, so it only finds partners the LO can already see. |
| Add partner → Link | `linkPartner` (`ExternalLoPartnerService.cls:14-27`) | **Nothing.** It reads, checks house lock and returns. Dead feature (finding 5). |
| Add partner → Create new | `createPartner` (`ExternalLoPartnerService.cls:29-78`) | Name check via `searchSharedPartners` (with sharing) and email/phone check via `PersonAccountDuplicateService.blockIfDuplicate` (with sharing), both blind (finding 2). Then it inserts a Person Account with RecordType `PersonAccount`, first/last split on the first space (single word → LastName `Partner`), `PersonEmail`, `Phone` (raw), `Company__c`, `BillingCity` = market, `Group__pc` = Realtor/Title Agent/Insurance Agent, Owner = LO and `Follow_Up_LO__c` = LO. The insert goes through `stripInaccessible(CREATABLE)`, so `Follow_Up_LO__c` is **silently dropped** because the permset has it read-only (`permissionsets/External_LO_Perfect_Day_Access` → `Account.Follow_Up_LO__c editable=false`). The form has no PartnerType input (`externalLoRealtors.html:175-194`), so the UI always creates `Realtor`. |

### 1b. Realtor Prospects (`lwc/externalLoRealtorProspects`)

- It calls `getRealtorProspects(searchTerm)`, which is `getRealtors('prospects', term)` (`ExternalLoPortalController.cls:204-207`). It uses the same record set as above, keeping only `Group__pc = 'Realtor Prospect'`.
- Columns: name, a type badge, company · market, and `lastTouchLabel || row.metaLabel`. `metaLabel` never exists on `PartnerRow`, so that fallback is dead (`externalLoRealtorProspects.js:38`).
- There is one action, **Open**. It navigates to the My Realtors detail with `filter:'prospects'` (`:66-72`). The view writes nothing itself.
- A prospect can only get there through CSV `PartnerType` containing "prospect" (`ExternalLoPartnerCsvImporter.cls:401-403`) or an internal user setting the Group. The UI create form cannot make one, and there is no "promote prospect to realtor" action.
- Prospects are also missing from the activity-log contact picker, because `searchLoggableRecords` uses `getRealtors('all', …)`, which excludes prospects (`ExternalLoActivityLogService.cls:123`).
- It inherits finding 1: `getRealtors` computes `countSharedBuyers` for every partner **before** the filter is applied.

### 1c. Past Clients (`lwc/externalLoPastClients`)

- It calls `getPastClientRows` → `ExternalLoPortalService.getPastClients` (`:156-168`) → `LeadRepository.selectPastClientLeadsByOwner` (`src/LeadRepository.cls:392-409`):
  `SELECT … FROM Lead WHERE OwnerId = :ownerId AND IsConverted = false AND LeadSource = 'Past Client' AND RecordType.DeveloperName IN ('Consumer_Lead_record_type','Consumer_Under_Contract_Lead_Record_Type') WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT 500`
- This does **not** use Person Accounts or `Transaction__c` (finding 4). Real closed borrowers never appear, and converting a past-client Lead makes it disappear.
- Columns: name, a status badge (it will say "New" for imported rows, finding 8), purpose · amount · program, and source · last activity.
- There is one action, **Open**, which goes to the My Leads detail (`externalLoPastClients.js:67-72`). Nothing is written from this view.
- Dead duplicate endpoint: `ExternalLoWorkspaceController.getPastClients` (`classes/ExternalLoWorkspaceController.cls:95-102`) is called only from a test.

### 1d. Import Data (`lwc/externalLoImportData` wrapping `lwc/externalLoCsvImport`)

`externalLoImportData` is a static page wrapper. Its `resultLabel` import is unused (`externalLoImportData.js:2,6`). The same `externalLoCsvImport` component is also embedded in onboarding (`externalLoOnboarding.html`). After an import, the shell bumps `dataRefreshKey` and refreshes the badges (`externalLoPortalShell.js:287-290`). See section 2.

---

## 2. CSV import end to end

### 2.1 Entry and limits

- The browser (`lwc/externalLoCsvImport/externalLoCsvImport.js:194-227`) accepts `.csv` by filename only, rejects files over **120,000 bytes**, reads them with `FileReader.readAsText(file)` (**UTF-8 assumed**), and sends the whole text as a string to `ExternalLoWorkspaceController.importCsv(family, csvBody)` (`ExternalLoWorkspaceController.cls:86-93`). There are two drop zones, `consumer` and `partner`.
- The server (`ExternalLoCsvImportService.cls:10-42`) rejects blank input, more than **120,000 characters**, an `estimatedLineCount > 201`, an unknown family, 0 data rows, or more than **200** parsed rows. `estimatedLineCount` (`:231-242`) counts raw `\n`/`\r`, **including newlines inside quoted cells**, so a 150-row file with multi-line notes can be rejected as "over 200 rows".
- The whole import is one synchronous Aura transaction. Any uncaught exception rolls everything back. Row-level DML uses `allOrNone=false`, so the import succeeds partially.

### 2.2 Parser (`classes/ExternalLoCsvParser.cls`)

- It strips a UTF-8 BOM (`:12`) and walks the text one character at a time (`:19-51`). It supports `"quoted, fields"`, `""` escapes, and quoted embedded newlines. It accepts `\r\n`, `\n` or `\r` line endings and skips blank rows.
- It supports **comma only**. Semicolon and tab files become one column.
- There is no error for an unterminated quote: the rest of the file becomes one cell. A stray `"` mid-field (`ab"c`) switches quote mode on silently.
- Headers are normalised with `trim().toLowerCase().replaceAll('[^a-z0-9]','')` (`:94-99`). "First Name", "first_name" and "FIRST-NAME" all become `firstname`. Header matching is exact after normalisation, and there are **no aliases**:
  - Partner keys: `firstname`, `lastname`, `name`, `phone`, `email`, `company`, `market`, `partnertype`.
  - Consumer keys: `firstname`, `lastname`, `name`, `phone`, `email`, `type`, `purpose`, `city`, `notes`, `loanamount`.
  - So "Phone Number", "Mobile", "Brokerage", "Full Name" and "E-mail Address" are all ignored. With a "Brokerage" header, every partner row fails "Add the brokerage or company".
- A duplicate header means the last one wins (`headerIndex`, `:77-83`). Cells are trimmed, and blank cells become null (`:68-75`).
- Encoding: a Windows-1252 "CSV (Comma delimited)" export from Excel with accented names produces U+FFFD replacement characters, because the browser decodes it as UTF-8.
- CPU: 120k iterations of `substring` + `+=` string concatenation. This is probably within the 10 s limit, but it is the likeliest governor risk. Test the maximum size.

### 2.3 Partner family (`classes/ExternalLoPartnerCsvImporter.cls`)

1. **Validation per row** (`:14-56`). The display name is `name`, otherwise `firstname + lastname` (`ExternalLoCsvImportService.resolveName`, `:168-180`). A row needs a name ("Add a first and last name.") and a company ("Add the brokerage or company."). A row with neither email nor phone is **allowed**, and it will always create a new account because it cannot be matched.
2. **Match query**, without sharing (`PersonAccountImportSelector.cls:8-23`):
   `WHERE IsPersonAccount = true AND Group__pc IN (4 values) AND (PersonEmail IN :emails OR Phone IN :phoneVariants) LIMIT 500`
   - Emails are sent as typed. The SOQL comparison is case-insensitive, and the in-Apex maps are lower-cased.
   - Phone: `ExternalLoPhoneNormalizer.soqlVariants` (`classes/ExternalLoPhoneNormalizer.cls:21-58`) turns each phone into about 11 textual formats (raw, digits, `xxx-xxx-xxxx`, `(xxx) xxx-xxxx`, dots, spaces, `1…`, `+1…`). This only matches `Account.Phone` when it is stored in one of those formats. After the query, matching is by 10-digit key (`matchKey`, `:10-19`).
   - It does **not** match on `PersonMobilePhone`, `Email_2__pc`, `Phone_2__c` and similar fields, or on name. It does not match realtors flagged by `Is_Realtor__c`/`Type__c`/`Type` without the exact Group value (2,419 records), or with a multi-value Group (35 records). It does not match borrower Person Accounts (`Group__pc = Client`), so a realtor who is also a past borrower gets a second PA.
   - The query has no `ORDER BY`. When several accounts share an email or phone (the known duplicates), the one that lands last in the map wins (`:64-71`). The import may therefore link the LO to the *losing* duplicate, not the keeper. It also ignores the placeholder filtering that `PersonAccountDuplicateService.normalizePhone`/`normalizeEmail` apply (`tbd@`, `5555555555`, etc.), so a placeholder number in the file links to a random realtor with that placeholder.
   - With `LIMIT 500`, a brokerage main line shared by many agents can truncate results.
3. **Per-row decision** (`:81-123`). Email match first, then phone.
   - Match + house-locked → error "This partner is managed by the Reach house team." (`:84-92`).
   - Match + not locked → **link**. The existing account is **never updated**.
   - No match, but the same email or phone already appeared earlier in the file → an in-file duplicate. It is folded into the earlier row and reported as "Added to your list".
   - Otherwise → **create** a Person Account: RecordType `PersonAccount` (resolved by DeveloperName, `PersonAccountRepository.cls:5-14`), first/last split on the first whitespace, `LastName='Partner'` for a single word, `PersonEmail`, `Phone` (not normalised), `Company__c`, `BillingCity`=market, `Group__pc` from `mapPartnerGroup` (`:389-405`: contains "title" → Title Agent, "insurance" → Insurance Agent, "prospect" → Realtor Prospect, anything else including "Lender" or blank → Realtor), `OwnerId` = LO, `Follow_Up_LO__c` = LO. It does **not** set `Is_Realtor__c`, `Type__c`, `Type` or `Biz_Dev_Designation__c`, so org processes that detect realtors those ways will not see these records.
   - Bug: a row with only a `lastname` of "Doe" becomes FirstName "Doe", LastName "Partner".
4. **Insert** (`:125-146`): `Database.insert(toInsert, false)`. No AccessLevel is given, so it runs in **system mode for CRUD/FLS**, and the ADR comment at `ExternalLoCsvImportService.cls:2-3` ("Partner Account insert stays in user mode") is wrong. The Person Account duplicate rule is set to Allow, so it does not stop anything. Failures are mapped to friendly text by `ExternalLoCsvDmlMessage` (`classes/ExternalLoCsvDmlMessage.cls:7-35`): duplicate, restricted picklist, validation message passthrough, access, otherwise "That row couldn't be saved. Ask an admin for help." An invalid email or an over-long name ends up as that generic fallback.
5. **Link records** (`:186-256`), written through `ExternalLoPartnerLinkWriter` (**without sharing**, `allOrNone=false`):
   - For created **and** linked rows it writes an `External_User_Assignment__c` with `User__c` = LO, `Contact__c` = PersonContactId, `Unique_Key__c` = `"<userId>:<contactId>"` (unique, case-insensitive) and `Assigned_Date__c` = today. It skips existing keys (`ExternalUserAssignmentRepository.selectUniqueKeys`, SYSTEM_MODE).
   - For linked rows whose `OwnerId` ≠ LO, it adds a **Manual AccountShare**: Account **Read**, Opportunity/Case None (`:258-323`). It skips accounts that already have a Manual share (`AccountShareRepository`, SYSTEM_MODE).
6. **Result** (`ExternalLoCsvImportService.cls:216-257`): link outcomes are folded into `successes` and sorted by row number. The summary reads "N added. M need attention." `ImportResult.links` stays `@AuraEnabled` but is always empty (vestigial). A created row whose assignment insert then fails appears in **both** Added and Needs attention.

**Can it overwrite internal users' data?** No. No path in this area updates an existing Account, Contact or Lead. The only changes to records owned by others are the added AccountShare (Read) and the assignment row. The UI footnote "never overwrite another officer's relationships" is accurate. "We de-duplicate against records already in the shared database" is only partly true, per the blind spots above.

### 2.4 Consumer family (`ExternalLoCsvImportService.cls:44-166`)

- Required: a name, plus a phone or an email.
- Dedupe is against `LeadRepository.selectPortalLeadsForImportMatch` (`src/LeadRepository.cls:216-243`): this LO's **own**, unconverted, consumer-RT Leads matched on Email / Phone / MobilePhone. It is also deduped within the file. Matches are skipped with **no row outcome** (`:118-120`).
- It inserts Leads in `SYSTEM_MODE` (`:153`) with: RT `Consumer_Lead_record_type`; FirstName/LastName split (single word → LastName `Borrower`; last-name-only → FirstName = LastName); `Company` = "<Last> Household"; Status `New`; Owner = LO; Phone; Email; `Loan_Purpose__c` = purpose (raw text into what may be a picklist); `Loan_Amount__c` parsed by keeping only `[0-9.]`, so "$450k" becomes 450 and "1.2.3" becomes null; `City`; `Description` = notes; `LeadSource='Past Client'` when Type contains "past".
- These inserts fire the whole Lead automation stack: 9 Lead triggers, the Loan Partner auto-assign that stamps the Nimbus Development integration user, the Lead Source lock, and so on. That has not been tested with portal-owned Leads at 200 rows.

### 2.5 How the LO is linked

- Created records use `OwnerId` = LO. That puts them in the list and gives visibility.
- Linked records get `External_User_Assignment__c` (list membership) plus a Manual `AccountShare` Read (visibility). Both are needed: the list query filters on the assignment, but the query runs with sharing.
- `External_User_Assignment__c` (`objects/External_User_Assignment__c`): OWD Private/Private. `Contact__c` is a required lookup with **deleteConstraint Restrict**, so a realtor PA with an assignment **cannot be deleted** (dedupe cleanup will hit this; check whether merge reparents it cleanly). `User__c` is SetNull. There is no Account lookup. The portal permset gives Read/Create/Edit on the object. Nothing ever deletes assignments or shares, and there is no unlink UI.

### 2.6 Storage and volume

200 rows per upload, but there is no daily cap or rate limit. A created partner is roughly one Person Account (about 2 KB of storage) plus one assignment row (about 2 KB). One file adds at most about 1 MB. Storage is at 84%, which becomes a concern only if the feature is abused or looped. Consumer imports add up to 200 Leads per file, plus whatever records the Lead automation creates.

---

## 3. Security

| Layer | Behaviour |
|---|---|
| Controllers / services | All `with sharing`. `ExternalLoPartnerLinkWriter` and `PersonAccountImportSelector` are deliberately `without sharing` (ADR-0002, not in the repo). |
| Account reads (lists, detail, search) | With sharing, no USER_MODE. Sharing is enforced and FLS is not. With a Private external OWD and all portal users on one shared "Customer Community User" account with the same Worker role, an LO only sees accounts they own or have been shared. `selectPortalPartnerDetail` takes any Id with no ownership check, so visibility depends entirely on sharing. |
| Lead reads | All `SYSTEM_MODE`, always with `OwnerId = :userId`. Safe by filter. The **exception** is `countSharedBuyers`, which is USER_MODE and will throw (finding 1). |
| Task reads | Filtered to `OwnerId = :userId`. LOs never see internal staff's notes on a shared realtor. |
| Writes | Task/Event in SYSTEM_MODE for any `recordId` whose `objectApiName` is Account/Lead/Transaction__c, with no server-side ownership or house-lock check (`ExternalLoCommunicationService.cls:5-41`). Cross-reference access still requires the parent to be visible (the class is `with sharing`), so in practice the LO can log only against visible records, including a visible house-locked one if they call the API directly. |
| CSV import | **Cross-LO exposure path.** The without-sharing email/phone match plus the without-sharing AccountShare insert let an outside LO get Read on any non-house-locked partner owned by an internal LO or another outside LO, and then log Tasks against it. The house-lock error message works as an existence oracle. They **cannot modify** those records. |
| Modify others' records | Not possible through this area. Portal users do have Account Create/Edit (profile + permset), so through the UI API they could edit Accounts **they own**. |

---

## 4. Real data (prod, 2026-09-28)

`SELECT … FROM User WHERE Profile.Name='RHL Community User'` returns **10 users, 2 active**. All use the Customer Community Plus license, role "Customer Community User Customer User" (Worker), and hang off one shared Account `001AJ0000047qQ8YAI` "Customer Community User" (Angela Amy, inactive, is on her own PA).

| User | Id | Last login | Assignments | Manual AccountShares | Accounts created (all time) | Created by portal paths* | In-scope partners (Owner/FollowUp/Preferred) | Completed Tasks on Accounts | Past-client Leads | Transactions as `Loan_Officer__c` |
|---|---|---|---|---|---|---|---|---|---|---|
| Harold Ellis | 005AJ000000Ig20YAC | 2026-09-24 | **0** | 0 (190 Owner rows) | 190 (175 PA + 15 business, 2023-03 → 2026-09-14) | **0** | 18 | 0 | 0 | 136 |
| Reach Admin | 005Qi000005FLvhIAG | 2026-09-28 | **0** | 0 (17 Owner rows) | 17 (14 PA + 3 business, 2024-11 → 2025-03) | **0** | 5 | 27 | 0 | 0 |

\* Every account these users created has `Company__c` null, and the portal create and import paths always set it. The 7 accounts Harold created since 2026-08-31 are borrower PAs with `Group__pc` null, which come from a different flow.

Org-wide, `External_User_Assignment__c` has **0 rows**. Reach Admin owns 1 Lead (Realtor Referral) and Harold owns 0.

---

## 5. Risks, bugs, dead code

**Bugs (verified in code)**
1. `countSharedBuyers` USER_MODE on Lead with no Lead permission (`ExternalLoPortalService.cls:94`). This probably breaks Realtors, Prospects, badges, Perfect Day realtor follow-ups and the contact picker. Fix: `WITH SYSTEM_MODE` (the `OwnerId` filter already scopes it), matching every other Lead query.
2. The My Realtors wire has no error handling (`externalLoRealtors.js:102-110`), so failures render as an empty list.
3. The createPartner duplicate checks are blind because of sharing (`ExternalLoPartnerService.cls:32,42`). Fix: call the without-sharing selector, or run `PersonAccountDuplicateService` without sharing.
4. `linkPartner` writes nothing (`ExternalLoPartnerService.cls:14-27`). It should share the importer's assignment + share logic. Right now that logic lives only inside the importer.
5. `Follow_Up_LO__c` is stripped on UI create but set on CSV create. The two paths disagree.
6. Past-client Leads get Status New, so they show as new leads (`ExternalLoCsvImportService.cls:128`, `ExternalLoPortalService.cls:735`).
7. `estimatedLineCount` counts quoted newlines (`ExternalLoCsvImportService.cls:231-242`).
8. Last-name-only rows produce a wrong name in both families.
9. A row can appear in both Added and Needs attention when the assignment insert fails.
10. Consumer rows that match an existing Lead are dropped silently.
11. The due threshold is `>= 7` here but `> 7` in `ExternalLOBaselineHelper.cls:273`.
12. Prospects are excluded from `getRealtors('all')`, so they cannot be picked in the activity-log contact picker.

**Design gaps / half-finished**
- Past Clients is Lead-based, not Transaction-based.
- The UI create form has no PartnerType, and there is no way to promote a prospect.
- There is no unlink or cleanup for assignments or shares. The Restrict delete constraint will block deleting duplicates.
- Shared buyers uses `Realtor_Buying_Agent__c`, while attribution elsewhere in the org uses `Referral_Source__c`.
- The matcher ignores the org's four realtor flags and alternate phone/email fields, which the existing `PersonAccountDuplicateService` already handles. Reuse it (without sharing) rather than keep two matchers.
- The ADR files cited in comments are not in the repo.

**Dead code**
- `ExternalLoWorkspaceController.getPastClients`.
- `PersonAccountRepository.selectPartnersForImportMatch` (wrapper used only by tests).
- `ExternalLoPartnerCsvImporter.userSafeDmlMessage`.
- `externalLoRealtors.handleFilterClick` (the list uses `filterchange`).
- `row.metaLabel` fallback in Prospects.
- `resultLabel` in `externalLoImportData`.
- `ImportResult.links` in the Aura payload.

**Hard-coded values**
- RecordType DeveloperNames `PersonAccount`, `Consumer_Lead_record_type`, `Consumer_Under_Contract_Lead_Record_Type`.
- Group values `Realtor`, `Realtor Prospect`, `Title Agent`, `Insurance Agent`.
- `Biz_Dev_Designation__c` values `Biz Dev - Reach` and `Biz Dev - Bondarevsky`.
- `Activity_Type__c` values (`Call - Active Agent` for every call, even to a prospect).
- Limits 200 rows / 120,000 chars (duplicated in the LWC), the 7-day due threshold, and the `'90'` default in three places.
- No record IDs are hard-coded.

**Governor limits**
- `getRealtors` = Task scan (LIMIT 5000) + assignment query + Account query (LIMIT 500) + Task last-touch query (LIMIT 5000) + Lead aggregate. It runs twice per keystroke on My Realtors (two wires, no debounce), again for badges, and again in the contact picker.
- An LO with more than 5,000 completed Tasks silently loses partners from the list.
- The parser's character loop is the main CPU risk at 120k characters.
- The import match `LIMIT 500` has no ORDER BY.

**Test quality**
- The tests assert behaviour, not just coverage: in-file dupes, the house lock, phone-only match, name-only no-match, a 200-row bulk run, and a query budget of 20 or fewer.
- But they **never run as a real portal user**. The helper looks up profile "Customer Community Plus User", which does not exist here (prod uses "RHL Community User"), so it falls back to a Standard User. The partner tests run as the admin.
- That is why findings 1 and 2 pass CI.
- `ExternalLoPortalCoverageTest` calls `linkPartner` with no assertion.
- Nothing tests the realtor-flag variants, multi-select Group, Windows-1252 input, or `createPartner` against another owner's realtor.

---

## 6. Manual test checklist

Setup:
- Use Harold Ellis or Reach Admin (log in as the portal user; do not use admin "Log in as" for the sharing tests).
- Have an internal LO own a test realtor PA "QA Realtor A" with `Group__pc = Realtor`, email `qa.a@example.com`, phone `(555) 010-0001`, not house-locked.
- Have a second one, "QA Realtor House", with `Biz_Dev_Designation__c = 'Biz Dev - Reach'`.
- Have a third, "QA Realtor Flag", with `Is_Realtor__c = true` and blank `Group__pc`.
- Prefer a sandbox. If you use prod, clean up afterwards, and note that assignment rows block deletion.

### My Realtors / Prospects / Past Clients

| # | Steps | Expected (per spec) | Watch for (current code) |
|---|---|---|---|
| R1 | Open My Realtors as Harold (18 owned partners, 0 touches) | List loads. The default 90-day chip shows 0 and "All partners" shows 18. | Finding 1: an empty list with no error, a missing nav badge, and a console Aura error "sObject type 'Lead' is not supported" |
| R2 | Click each chip: 30/60/90/Due/All | Counts on the chips match the rows | Untouched partners appear only under All |
| R3 | Log touch on a partner (call, note of 3+ chars, follow-up 3 days) | A Completed Task (WhatId = account, Owner = LO) and an Event at 9:00 on +3 days. The partner moves into 30/60/90. | A note under 3 characters is rejected |
| R4 | Back-date that Task's ActivityDate/CompletedDateTime to 7 days ago (as admin) | The partner shows "Follow-up due" and the badge increments | At 6 days it should not be due |
| R5 | Open a house-locked partner you can see | "House account" badge, no Log button | |
| R6 | Add partner → search "QA Realtor A" (owned by an internal LO) | Found, per the banner "shared across the company" | Not found (sharing) |
| R7 | Add partner → Create new "QA Realtor A", phone `555-010-0001` | Blocked as a duplicate | **Creates a duplicate** (finding 2). Check the Account as admin: Follow_Up_LO__c is empty |
| R8 | Add partner → Link on any search hit | The partner is added to your list | The toast says linked but nothing is written (finding 5) |
| R9 | Search box: type quickly | Results filter | Watch network calls per keystroke |
| R10 | Open a partner detail with an open Lead whose `Realtor_Buying_Agent__c` = partner | It appears under Shared pipeline, and shared buyers = 1 | A Lead that has only `Referral_Source__c` set will not show |
| P1 | Import a partner CSV row with PartnerType "Realtor Prospect", then open Realtor Prospects | Row shown; Open goes to the detail | It does not appear in My Realtors "All" |
| P2 | In the Log activity modal, search for the prospect | Found | Not found (excluded from `'all'`) |
| C1 | Open Past Clients as Harold (136 Transactions as LO) | Closed borrowers are listed | Empty (finding 4) |
| C2 | Consumer-import a row with Type "Past Client" | It shows in Past Clients | It also shows as a **New** lead in My Leads and Perfect Day |

### CSV import (partner family unless noted)

| # | File content | Expected |
|---|---|---|
| I1 | Headers `FirstName,LastName,Phone,Email,Company,Market,PartnerType`, one new realtor | 1 added. A PA owned by the LO, Group Realtor, and 1 assignment row. It shows under All partners. |
| I2 | Row with `qa.a@example.com` (matches QA Realtor A) | "Added" (linked). A Manual AccountShare Read + assignment. QA Realtor A is **unchanged**. It is now visible to the LO. |
| I3 | Same file uploaded again | Still "Added". No new rows or shares. |
| I4 | Row with phone `+1 555.010.0001`, no email | Matches QA Realtor A by phone |
| I5 | Row matching QA Realtor House by email | Error "managed by the Reach house team". Nothing written. |
| I6 | Row matching QA Realtor Flag by email | Should link. **Currently creates a duplicate** (finding 3). |
| I7 | Two rows, same new email, different names | 1 PA created. Both rows "Added". The second row's name is discarded. |
| I8 | Row missing Company | "Add the brokerage or company." Other rows still import (partial success). |
| I9 | Headers `First Name, Last Name, Phone Number, E-mail, Brokerage` | Phone Number and Brokerage are ignored, so every row errors on company. Decide whether aliases are needed. |
| I10 | Only a `Name` column: "Mary Ann Smith", "Cher" | First "Mary" / Last "Ann Smith"; "Cher" becomes LastName "Partner" |
| I11 | Only a `LastName` "Doe" | Currently "Doe Partner" (bug) |
| I12 | Quoted comma: `"Smith, Jr.",...`; quoted newline in Market | Parsed correctly. Also check the row-count estimator with 150 such rows. |
| I13 | Unterminated quote on row 2 | Should error. Currently swallows the rest of the file silently. |
| I14 | Excel "CSV (Comma delimited)" with "José Peña" | Check for mangled characters (encoding). Repeat with "CSV UTF-8". |
| I15 | Semicolon-delimited file | Currently a single column, and every row errors |
| I16 | 200 data rows exactly; 201 rows; 119 KB and 121 KB files | 200 imports; 201 rejected; the 121 KB file rejected client-side. Time the 119 KB file for CPU. |
| I17 | Header only / empty file / `.txt` renamed / `.CSV` uppercase | "no data rows" / "Choose a CSV" / rejected / accepted |
| I18 | Invalid email `bob@` | Row error with the generic fallback text. Other rows fine. |
| I19 | PartnerType "Title", "insurance agent", "Lender", blank | Title Agent / Insurance Agent / Realtor / Realtor |
| I20 | Phone `555-555-5555` (placeholder) matching an existing realtor with the same placeholder | Should not link. Currently links. |
| I21 | Consumer: row matching your existing Lead by phone | Skipped. Note that there is **no message** for it. |
| I22 | Consumer: `LoanAmount` "$450,000", "450k", "1.2.3" | 450000 / 450 / null |
| I23 | Consumer: 200 rows | All inserted. As admin, check the Loan Partner and owner on the Leads, and any automation side effects. |
| I24 | Two browser tabs, same file, upload at once | No duplicate PAs (race). Expect possible duplicates. |
| I25 | As admin, try to delete a PA that now has an assignment | Blocked by the Restrict lookup. Also test merging two such PAs. |
