# Partner Workspace deep dive 01: shell, site, navigation, access, onboarding

Scope: the site container, the single-page shell and its URL state, navigation and badges, the first-run "Perfect Week" setup, and the access model. Source is the fresh prod retrieve in `C:\Apps\Claude Back Up\outside-lo-portal\force-app\main\default\` (paths below are relative to it). Org facts come from read-only queries against Production on 2026-09-28.

Live URL: `https://reachhomeloans.my.site.com/partnerworkspace` (LWR site `Partner_Workspace1`). The companion Visualforce site sits at `/partnerworkspacevforcesite`. Network Id `0DBQi00000017aXOAQ`, created 2026-08-31.

---

## 1. Architecture

### 1.1 Site container

| Piece | Value | Where |
|---|---|---|
| Template | Build Your Own (LWR), `talon-template-byo`, theme `Build_Your_Own_LWR` | `digitalExperiences/site/Partner_Workspace1/sfdc_cms__appPage/mainAppPage/content.json`, `sfdc_cms__theme/Build_Your_Own_LWR/content.json` |
| Authentication | `AUTHENTICATED`. Every route uses `pageAccess: UseParent`, so nothing is public except the login-family pages | `sfdc_cms__site/Partner_Workspace1/content.json` |
| Locker / CSP | Locker on, `isRelaxedCSPLevel: false` (strict CSP) | `mainAppPage/content.json` |
| Theme layouts | `scopedHeaderAndFooter` (Inner, empty header/footer sections) and `snaThemeLayout` (Service Not Available) | `sfdc_cms__themeLayout/*` |
| Global CSS | `styles.css` removes the builder's padding and max-width so the shell fills the viewport; `print.css` | `sfdc_cms__styles/*` |
| Head markup | Default SLDS and DXP stylesheet links. The `<title>` is still the template default, "Welcome to LWC Communities!" | `mainAppPage/content.json` `headMarkup` |
| Language | en_US only | `sfdc_cms__languageSettings` |

### 1.2 Routes and views

| Route (url) | View | What the view hosts |
|---|---|---|
| Home (`/`) | `home` | One component: `c:externalLoPortalShell`. This is the whole app. |
| Login (`/login`) | `login` | `c:partnerLogin` x4 (variants hero, welcome, help, footer, ours) around the standard `community_login:loginForm` |
| Forgot Password (`/ForgotPassword`) | `forgotPassword` | Site logo + standard `community_login:forgotPassword` |
| Check Password (`/CheckPasswordResetEmail`) | `checkPasswordResetEmail` | Standard `community_login:checkEmail` |
| Register (`/SelfRegister`) | `register` | Standard `community_login:selfRegister` (self-registration is off at the network, see 5) |
| Error, Service Not Available, Too Many Requests | standard | Rich text / HTML editor only |
| News Detail (`/news`) | `newsDetail` | Empty section. Template leftover. |

There are no object or record pages. Anything that tries to navigate to `standard__recordPage` or `standard__objectPage` inside the site has nowhere to land (relevant to `portalRecordDrawer`, see 6).

### 1.3 The single-page shell

`lwc/externalLoPortalShell` is the only thing on Home. It renders a sidebar (desktop), a hamburger drawer (mobile), and one content component chosen by `activeView` (`externalLoPortalShell.html:62-129`). Views are not routes: they are values in the page's URL state.

View ids are defined once in `lwc/portalUtils/portalUtils.js:6-17`:

| View id | Nav label | Component rendered | Setup-gated? |
|---|---|---|---|
| `perfectDay` | Perfect Day | `c-perfect-day-home` | no (always shown) |
| `progress` | My Progress | `c-external-lo-progress` | yes |
| `perfectWeek` | My Perfect Week | `c-external-lo-perfect-week` (hosts the setup wizard) | no (always shown) |
| `realtorProspects` | Realtor Prospects | `c-external-lo-realtor-prospects` | yes |
| `realtors` | My Realtors | `c-external-lo-realtors` | yes |
| `pastClients` | Past Clients | `c-external-lo-past-clients` | yes |
| `importData` | Import Data | `c-external-lo-import-data` | yes |
| `leads` | My Leads | `c-external-lo-leads` | yes |
| `preApprovals` | My Pre-Approvals | `c-external-lo-pre-approvals` | yes |
| `loans` | My Loans | `c-external-lo-loans` | yes |

URL state (`portalUtils.js:35-66`):

- `parsePortalState(pageRef)` reads `c__view`, `c__filter`, `c__recordId` from `CurrentPageReference.state`. An unknown or missing `c__view` falls back to `perfectDay`. A missing filter gets `defaultFilterForView` (`portalUtils.js:153-168`: leads/preApprovals/loans `all`, realtors `90`, realtorProspects `prospects`, others null). `c__filter` and `c__recordId` are passed through without validation.
- `portalHomePageRef(view, filter, recordId)` builds `{ type: 'comm__namedPage', attributes: { name: 'Home' }, state: { c__view, c__filter?, c__recordId? } }`. So a deep link looks like `/partnerworkspace/?c__view=leads&c__filter=new&c__recordId=00Q...`.
- `portalStatesEqual` compares the three values as strings.

Shell flow (`externalLoPortalShell.js`):

1. `@wire(CurrentPageReference)` stores the parsed state as `pendingNav` (`:113-117`).
2. `@wire(getOnboardingState)` loads setup state (`:127-137`). Nothing renders until it arrives (loading label, or the error text with no retry).
3. `applyPendingNav` (`:203-218`) runs once both exist. It passes the request through `gateView` (`:228-238`), which forces `perfectDay` for any view other than `perfectDay`/`perfectWeek` while setup is incomplete. If the gated state differs from the URL, it rewrites the URL.
4. Child components ask to move by dispatching a bubbling, composed `portalnavigate` event (`portalUtils.js:80-88`) with `{view, filter, recordId}`; the shell's `handlePortalNavigate` (`:245-248`) and `navigateTo` (`:250-265`) update state and call `syncUrl` (`:267-274`), which does `NavigationMixin.Navigate` to the Home page ref. Browser back/forward therefore works through the `CurrentPageReference` wire.
5. Filter and record id are handed to children only when that child is the active view (`:181-201`).

Shared plumbing:

| Module | Role | Notes |
|---|---|---|
| `portalUtils` | View ids, URL state, `reduceApexError`, `showPortalToast` (lightning/toast), `dispatchPortalNavigate`, `toGenericListRow`, `loadPortalFont` (loads `InterFont` static resource once per page) | Imported by 16 components. `isExperienceCloudContext` and `shouldUseFlowNavigation` (`:26-33`) have no callers left in this folder. |
| `portalNavList` | Renders nav groups, emits `navselect {view}` | Stateless. |
| `portalIcon` + `lucideIcons.js` | Inline-SVG lucide icons (48 shapes) | Header says generated from lucide 0.577.0, "Regenerate, do not hand-edit". Generator is not in the repo. |
| `portalSharedStyles` | CSS-only module of design tokens and shared primitives, `@import 'c/portalSharedStyles'` | |
| `portalListLayout` | Generic list page: title, search, filter chips, skeleton, empty state, rows with actions. Emits `searchchange`, `filterchange`, `rowaction` | `rowType` is accepted but ignored; `isGenericRows` always returns true (`portalListLayout.js:14,31-33`). |
| `portalRecordDrawer` | Slide-over list for a Perfect Day "record set" key, via `ExternalLoPortalController.getRecordSet`; can open the communication modal | Only used by `perfectDayHome`. |

---

## 2. Navigation

Groups and items are hard-coded in `NAV_GROUPS` (`externalLoPortalShell.js:40-69`). Labels are custom labels (`ExtLO_Nav_*`).

- My activity: Perfect Day, My Progress, My Perfect Week
- Business development: Realtor Prospects, My Realtors (badge), Past Clients, Import Data
- Pipeline: My Leads (badge), My Pre-Approvals (badge), My Loans

**Setup gate.** Until `onboardingState.complete === true`, `navGroups` (`:151-168`) keeps only Perfect Day and My Perfect Week, and `gateView` redirects every other view, including deep links, to Perfect Day. `perfectDayHome` also receives `setup-complete` to change its own content. The gate is client-side only; the Apex behind the hidden views does not check onboarding, so a user could call it directly. That is harmless (they only ever see their own records) but worth knowing.

**Badges.** One wire: `ExternalLoPortalController.getNavBadges` (`cacheable=true`, `ExternalLoPortalController.cls:125-128`), which calls `ExternalLoPortalService.getNavBadges` (`ExternalLoPortalService.cls:147-151`). Each badge runs the full list query for that view and counts the rows:

| Badge | Field | What it counts |
|---|---|---|
| My Leads | `newLeads` | `getLeads('new')`: leads owned by the user with `Status = 'New'` (`deriveLeadStage`, `:733-737`) |
| My Realtors | `dueRealtors` | `getRealtors('due')`: non-prospect partners whose last touch by this user was 7+ days ago (`:330`). Partners never touched are NOT counted, even though `ExternalLOBaselineHelper.realtorFollowUpUrgency(null)` calls them orange. |
| My Pre-Approvals | `preApprovals` | `getPreApprovals('all')`: every pre-approval the user owns, not just the ones needing action |

A badge shows only when the count is a number > 0 (`externalLoPortalShell.js:157-163`). Because the wire is cacheable, badges refresh only when the user navigates to Perfect Day, finishes an import, or finishes setup (`:261-263, 282-289`). Logging activity in other views does not refresh them. `getNavBadges` has no try/catch, so a failure throws a raw error and the badges silently stay empty (the shell ignores `result.error`).

**Logout.** `handleLogout` navigates to `comm__loginPage` with `actionName: 'logout'` (`:301-303`). No custom logout URL on the network, so the user lands on the login page.

---

## 3. Onboarding ("Set up your Partner Workspace" / My Perfect Week)

### 3.1 Where it lives

The shell always shows My Perfect Week. `externalLoPerfectWeek` shows the wizard (`c-external-lo-onboarding`, embedded) while `setupState.complete === false`, and a read-only "This week" progress panel afterwards (`externalLoPerfectWeek.js:39-41`, `.html:8-50`). Finishing fires `completed` (bubbling, composed); the shell stores the returned state, bumps refresh keys, refreshes onboarding and badges, and routes to Perfect Day (`externalLoPortalShell.js:276-285`).

### 3.2 Steps (`lwc/externalLoOnboarding/externalLoOnboarding.js`)

Steps are `STEPS` at `:21-28`. The stepper lets you click back freely and forward only if every step in between is valid (`:302-335`).

| # | Step | What the LO enters | Validation |
|---|---|---|---|
| 1 | Focus | One focus from `state.focuses` (active `External_LO_Focus__mdt`). Choosing one overwrites all weekly targets with that focus's presets (`:229-248`). | Required |
| 2 | Activities | Toggle each active activity on/off | At least one on |
| 3 | Targets | Weekly target per enabled activity, stepper or typed, clamped 0-200 on blur (`:263-300`). Shows "N per working day" using the current workdays (default 5). | Each 0-200 |
| 4 | Rhythm | Workdays per week: 3, 4, 5 or 6 only (`WORKDAYS`, `:30`) | none |
| 5 | Review | Read-only summary | none |
| 6 | Import | Embeds `c-external-lo-csv-import`; the CSV import writes immediately, before setup is saved | none |

"Skip for now" and "Finish setup" call the same `handleFinish` (`.html:181-184`), which calls `ExternalLoWorkspaceController.saveOnboardingV2(businessFocus, workdaysPerWeek, completeOnboarding=true, goalsJson)` (`.js:368-400`). The controller takes primitives plus a JSON string on purpose: an Aura DTO parameter bound as an empty object and silently dropped the focus (`ExternalLoWorkspaceController.cls:58-68`).

### 3.3 Server side (`ExternalLoOnboardingService.saveV2`, `:47-82`)

1. Loads the user through `UserRepository.selectPortalProfile` (USER_MODE query).
2. **Locks the plan:** if `External_LO_Onboarding_Complete__c` is already true, throws "Your weekly plan is locked. Ask an admin if you need to change it." (`:110-114`).
3. Validates focus against active focus labels, or any focus label including inactive legacy ones (`isAllowedFocus`, `:126-131`).
4. Clamps workdays to 1-7 (`ExternalLoGoalMath.clampWorkdays`).
5. Builds one goal row per active activity; missing input gets the activity default; weekly target must be 0-200.
6. Updates the User in SYSTEM_MODE: `Business_Focus__c`, `ExtLO_Workdays_Per_Week__c`, `External_LO_Onboarding_Complete__c = true` (`:73-79`). SYSTEM_MODE is needed because the permission set gives the LO read-only FLS on those fields.
7. Upserts `External_LO_Activity_Goal__c` on `Unique_Key__c = <userId>:<activityKey>`, `OwnerId = User__c = user`, SYSTEM_MODE (`ExternalLoActivityGoalWriter.cls:5-32`).
8. Returns a fresh state.

### 3.4 Where it is stored

| Data | Storage |
|---|---|
| Focus label (free text, 80) | `User.Business_Focus__c` |
| Workdays | `User.ExtLO_Workdays_Per_Week__c` (Number 1,0) |
| Complete flag | `User.External_LO_Onboarding_Complete__c` (checkbox, default false) |
| Weekly target + enabled per activity | `External_LO_Activity_Goal__c` (OWD Private, owned by the LO): `User__c`, `Activity_Key__c`, `Weekly_Target__c`, `Is_Enabled__c`, `Unique_Key__c` (unique, 80) |
| V1 daily goals (legacy) | `User.Calls/Texts/Emails/Meetings/Open_House_Daily_Goal__c`. Only the legacy `saveOnboarding` writes them; no UI calls it now. |

"Complete" means exactly `User.External_LO_Onboarding_Complete__c = true`. Internal (Standard) users who lack FLS on the portal fields are treated as complete in memory (`UserRepository.cls:17-24, 67-72`) so internal pages that reuse Perfect Day don't show the wizard.

### 3.5 Metadata and goal math

`External_LO_Activity__mdt`, 5 active records (key, default weekly target, credited `Activity_Type__c` values):

| Key | Default/wk | Credit types |
|---|---|---|
| realtor-outreach | 20 | Call - Prospecting; Call - Active Agent |
| consumer-conversation | 10 | Call - Prospecting; Call - Active Agent; Text |
| social-engagement | 15 | Text; Email |
| past-client-call | 5 | Call - Prospecting; Call - Active Agent |
| partner-meeting | 3 | Meeting (New Agent); Meeting (Active Agent); Open House |

Several types credit more than one activity. `ExternalLoActivityCatalog.categoryForActivityType` returns the first match by sort order, so a bare "Call - Prospecting" always resolves to Realtor outreach.

`External_LO_Focus__mdt`: 3 active (Grow new referral partners, Deepen existing partners, Mine my past-client base) and 4 inactive legacy (Realtor Relationships, Purchase Pipeline, Refinance, Past Clients) "kept so existing User values still resolve". Presets map to activity keys through hard-coded field names (`ExternalLoActivityCatalog.cls:183-189`). Adding a sixth activity means adding a `Preset_*__c` field and editing that map.

`External_LO_Baseline__mdt.Default`: V1 daily goals (calls 10, texts 5, emails 5, meetings 1, open house 0), weekly x5, monthly x20, `Business_Focus_Options__c` legacy list, `Arive_Base_Url__c` blank (so Arive deep links show "not linked"). Used for legacy goal overlays and as a fallback; not by the V2 wizard.

`ExternalLoGoalMath` (`classes/ExternalLoGoalMath.cls`):

- daily = `ceil(weekly / workdays)`, workdays clamped 1-7, default 5 (`:22-29`). The wizard's JS copy matches (`externalLoOnboarding.js:32-39`).
- week = weekly target; month/quarter = `round(weekly * days / 7)` (`:44-51`).
- week bounds: `weekStartMonday = toStartOfWeek() + 1` (`:35-42`). **This is wrong on Sundays** (see 6).
- activity count per log clamped 1-50.

Hard-coded SLA constants live in `ExternalLOBaselineHelper.cls:9-15` (new lead SLA 15 min, realtor orange 7 / red 14 days, pre-approval stagnant 6 days, loan stale 3 days, workday 9-17) and the active-loan status list at `:31-45`.

---

## 4. Access model

### 4.1 Who can log in

Network member groups (`networks/Partner Workspace.network-meta.xml:37-40`, confirmed by `NetworkMemberGroup`):

| Profile | Id | License / UserType |
|---|---|---|
| RHL Community User | 00eAJ000000LsqrYAC | Customer Community Plus / PowerCustomerSuccess |
| System Administrator | 00ef2000000tTPaAAM | Salesforce / Standard |

No permission sets are member groups. `allowInternalUserLogin` is true.

**The RHL Community User profile is shared with the older "Reach Home Loans Transactions" portal** (created 2022). Both active portal users are members of both networks.

Current users on the profile (10 total, 2 active):

| User | Username | Active | Last login | Account | Permsets (non-profile) |
|---|---|---|---|---|---|
| Harold Ellis | hellis@reachhomeloans.com | yes | 2026-09-24 | Customer Community User | Condition_Files_Permissions, External_LO_Perfect_Day_Access |
| Reach Admin | outsidelo@reachhomeloans.com | yes | 2026-09-28 | Customer Community User | Account_Follow_Up_Access, ConditionPermissions, Condition_Files_Permissions, External_LO_Perfect_Day_Access |
| Garrett Smith, Chad Gorman, Daniel Hsieh, Elias Handal (gmail), Outside LO Test (gmail), Dennis Ross, Edgard Gonzalez, Angela Amy | | no | 2023-2026 | all but Angela on Customer Community User | |

All contacts except Angela Amy's hang off one shared account, "Customer Community User" (`001AJ0000047qQ8YAI`), and the two active users share the portal role "Customer Community User Customer User" (Worker). Any future sharing rule aimed at that role, or at "Portal Role and Subordinates", would expose every external LO's records to every other.

Onboarding state in prod: only Reach Admin has goal rows (5, created 2026-09-15). Harold Ellis has none, so he will get the setup wizard on first visit (he actively uses the Transactions portal and owns 190 Accounts and 136 loans).

### 4.2 Profile

RHL Community User grants object access to Account (CRE), Contact (CR), Transaction__c (CR), Call_Insight__c (CRUD), Case, Checklist__c, Submission_Form__c, Change_of_Circumstance__c, Transaction_Expense__c and others from the old portal. No Lead object permission. It also grants Apex class access to 1,358 classes (135 unmanaged, the rest managed), which means **every `@AuraEnabled` method in those classes is callable by any external LO**, not only the portal's own.

### 4.3 Permission set `External_LO_Perfect_Day_Access`

Description (`permissionsets/External_LO_Perfect_Day_Access.permissionset-meta.xml:183`): "Lead and Opportunity CRUD are omitted (license); portal Apex reads/writes owned Leads in system mode. See ADR-0001." ADR-0001/0002 are referenced throughout the code but are **not in this repo**.

- Apex: all 45 non-test classes in this folder, plus 9 document-request and viewer classes from other features (CallInsightListController, DocumentViewerController, FileUploaderController, LeadDoc*...).
- Objects: Account CRE, Contact CRE, External_User_Assignment__c CRE, Lead_Document_Request__c CRUD, read on Call_Insight__c, External_LO_Activity_Goal__c, Lead_Document_Request_Reference__c, Transaction__c, Zoom_Recording__c.
- Read-only FLS on the User setup fields and goal fields (so writes must go through SYSTEM_MODE); edit on the Task/Event activity fields; read on a set of Transaction__c fields including `Loan_Amount__c` (0% populated on Transaction__c, see 6).
- User perms EditTask, EditEvent. Flow access `Lead_Document_Requests_Creator`. CMDT access `Default_Document_Folder__mdt` only (the External_LO_* CMDTs are Public, so Apex reads them without it).

**Without this permset a portal user cannot get past the loading screen**: the profile does not grant `ExternalLoWorkspaceController`, so `getOnboardingState` fails and the shell shows only the error text.

**No admin profile or permset has FLS on the portal fields.** `FieldPermissions` shows the three User fields, all five goal fields and `External_User_Assignment__c.User__c/Assigned_Date__c` are granted only by this permset. A System Administrator query on `User.External_LO_Onboarding_Complete__c` fails with "No such column". The "ask an admin to change your plan" path therefore does not work until someone grants admins FLS.

### 4.4 How records reach an external LO

There are no sharing sets (`SharingSet` returns 0). Visibility comes from:

1. **Ownership.** Leads, partner Accounts and goal rows are owned by the LO; list queries filter on `OwnerId = :userId` (for example `ExternalLoPortalService.cls:3-20` via `LeadRepository.selectPortalLeadsByOwner`). Prod: all 207 AccountShare rows for the two users are RowCause Owner.
2. **Loans.** `Transaction__c` rows with `Loan_Officer__c` = the LO; Harold has 130 Owner and 6 Manual `Transaction__Share` rows.
3. **CSV partner linking.** When an imported partner row matches an existing realtor Person Account, `ExternalLoPartnerCsvImporter` (`:186-310`) inserts an `External_User_Assignment__c` (User + Contact, unique `userId:contactId`) and a Manual `AccountShare` with Read access, both through the `without sharing` `ExternalLoPartnerLinkWriter`. Matching uses the `without sharing` `PersonAccountImportSelector`, which searches every Realtor / Realtor Prospect / Title / Insurance Person Account in the org by email or phone. Prod has 0 assignment rows, so this path has never run for real.
4. Detail methods re-check ownership server-side (for example `selectPortalLeadDetail(leadId, userId)`), so a tampered `c__recordId` returns "not found".

`ExternalUserAssignmentRepository.selectContactIdsByUserId` has no production caller (tests only). `AccountShareRepository` is used only by the importer.

### 4.5 with sharing / without sharing / mode usage

| Class | Sharing | Mode notes |
|---|---|---|
| ExternalLoWorkspaceController, ExternalLoOnboardingService, UserRepository, ExternalLoActivityGoalWriter, ExternalUserAssignmentRepository, AccountShareRepository, ExternalLoGoalMath | with sharing | UserRepository queries WITH USER_MODE; User update and goal upsert AccessLevel.SYSTEM_MODE; assignment and share selects WITH SYSTEM_MODE |
| ExternalLOBaselineHelper, DomainException | none declared (inherits) | pure logic |
| ExternalLoPartnerLinkWriter | **without sharing** | Inserts assignments and AccountShares, `allOrNone=false` |
| PersonAccountImportSelector | **without sharing** | Org-wide Person Account match |
| 14 other classes | with sharing | use SYSTEM_MODE (PerfectDayHomeService, TaskRepository, ExternalLoLeadService, ExternalLoCommunicationService and others: see other deep dives) |

---

## 5. Guest and login configuration

| Setting | Value | Where |
|---|---|---|
| Login page | Builder (LWR `login` view) with `partnerLogin` branding | network `:45`, `sfdc_cms__view/login` |
| Forgot password | Builder page; login form links to `/ForgotPassword` | network `:43`, login view |
| Change password | Standard | network `:42` |
| Self-registration | **Off** (`selfRegistration false`), but a Register route/view exists and the login form is configured with "Not a member?" pointing at `/SelfRegister` | network `:49`, login view |
| Invitations | Off | network `:20` |
| Welcome email | **On**, template `CommunityWelcomeEmailTemplate` | network `:50, 59` |
| Email sender | **development@nimbuscloudsolutions.com** / "Partner Workspace". Every other network the Network query returned uses the same Nimbus address. | network `:8-9` |
| Site admin, guest record default owner | **reach@nimbuscloudsolutions.com (Nimbus Development, 0055x00000Bs3rBAAR)** | `sites/Partner_Workspace.site-meta.xml:27-28` |
| Guest user | Partner Workspace Site Guest User, profile "Partner Workspace Profile", no Apex class access, guest file access off | queried |
| Logout URL | None set; logout lands on login | shell `:300-303` |
| Clickjack | SameOriginOnly on the VF site | site `:15` |
| CSP trusted sites | None specific to this site. Org-wide entries include Twilio, S3, UWM, Flagstar, `98765.myarive.com`, QuickChart, and a Communities-context entry for `reachhomeloanscommunity.force.com`. Fonts are self-hosted (`InterFont`) to avoid a Google Fonts entry. | CspTrustedSite |
| Other | Chatter tab, direct messages, nickname display enabled (irrelevant in LWR); `enableApexCDNCaching` true | network |

---

## 6. Risks, bugs, dead code

Ordered by how much they matter. Each one was checked against source or prod.

### High

1. **Handover blockers tied to Nimbus identities.** Welcome and password-reset emails go out from `development@nimbuscloudsolutions.com` (network `:8`; every other network returned by the Network query uses the same address). The site admin and guest-record default owner is the Nimbus Development user (`site-meta.xml:27-28`). If Nimbus deactivates that user or the mailbox, the site and portal emails break, and LO replies go to the contractor. Change the sender to a Reach address (it must be verified) and move site admin / guest owner to a Reach user. Don't deactivate Nimbus Development without checking every place it's used; memory notes it is also the Lead Loan Partner default.
2. **Week boundaries are wrong every Sunday.** `weekStartMonday` is `toStartOfWeek().addDays(1)` (`ExternalLoGoalMath.cls:35-38`). For en_US, `toStartOfWeek()` of a Sunday is that same Sunday, so on Sundays "this week" becomes the next Monday to Sunday: My Perfect Week, My Progress, Perfect Day and prompts all show an empty future week, and Sunday activity counts toward the prior week. For a user with a Monday-start locale it would return Tuesday. Five callers: `ExternalLoPortalService.cls:534`, `ExternalLoProgressService.cls:20`, `ExternalLoPromptService.cls:72`, `PerfectDayHomeService.cls:24`. The test `ExternalLoGoalMathTest.weekBoundsAreMondayThroughSunday` (`:34-41`) uses `Date.today()` and asserts `monday <= today`, so **it fails when run on a Sunday**, which will block any prod deploy that runs it that day. Fix: `today.addDays(-Math.mod(Date.newInstance(1900,1,1).daysBetween(today), 7))` (1900-01-01 was a Monday), and fixed-date tests including a Sunday.
3. **The profile exposes about 1,358 Apex classes to external users.** Any `@AuraEnabled` method in them, including `without sharing` ones from the old Transactions portal, can be called directly through the Aura endpoint by an LO. This predates Partner Workspace but now covers a wider audience. Audit which classes the RHL Community User profile needs; ideally give Partner Workspace its own profile rather than sharing the Transactions one.
4. **The CSV partner import can reveal other people's realtors.** `PersonAccountImportSelector` (`without sharing`) matches org-wide by email or phone, and a match grants a Manual Read AccountShare. An LO who uploads a list of emails or phones gets read access to every matching Realtor/Title/Insurance Person Account in the org, including ones owned by internal LOs. It may be intended ("don't duplicate realtors") but it needs a product decision. It has never run in prod (0 assignment rows).
5. **The plan is locked, and admins can't unlock it.** After setup, the server rejects any change (`ExternalLoOnboardingService.cls:110-114`), the Perfect Week page has no edit mode, and no admin has FLS on the fields that would reset it (4.3). Meanwhile the wizard's own copy says "You can change this later" (`labels:265`) and asks "How many days will you work this week?" (`labels:361`) for a setting that is permanent. There is no documented reset procedure. Suggested procedure: grant admins FLS through a small permset, set `External_LO_Onboarding_Complete__c = false`, and the wizard will reopen pre-filled from the saved goal rows.

### Medium

6. **Unvalidated URL filter causes a crash.** `matchesPartnerFilter` ends with `Integer.valueOf(filterKey)` (`ExternalLoPortalService.cls:788`). `?c__view=realtors&c__filter=abc` throws a TypeException, and `getRealtors` has no try/catch (`ExternalLoPortalController.cls:54-56`), so the page shows a generic error. `parsePortalState` accepts any filter. Validate filters per view in `portalUtils`, or default in Apex.
7. **Setup gate and badges are client-only and cached.** Badges don't refresh after activity is logged outside Perfect Day. `getNavBadges` errors are swallowed. Three full list queries run on every shell load.
8. **The "due" realtor badge ignores never-touched partners** (`ExternalLoPortalService.cls:330`), which is inconsistent with the orange urgency helper. The pre-approvals badge counts all pre-approvals, not the ones needing action.
9. **`c/portalUtils` breaks internal Lightning.** Commit 2d60735 (this repo) records that `c/portalUtils` (it imports `lightning/toast` and `@salesforce/community/Id`) fails to load there. Yet `externalLoLeads`, `externalLoLoans`, `externalLoPreApprovals` and `externalLoRealtors` are exposed to `lightning__AppPage`/`HomePage` and import it. Either remove those targets or confirm they render on an internal page in a sandbox.
10. **The local source isn't self-contained.** The `InterFont` static resource (used by `portalUtils.js:3`) is in the org but missing from this retrieve. `LeadRepository`, `PersonAccountRepository` and `LoanRepository` are called here but are not in this folder or anywhere in the repo. ADR-0001/0002 are not in the repo either. Deploying this folder to a sandbox as-is will fail.
11. **Profile and account shared with the Transactions portal.** One portal role and account for all LOs (4.1); a future sharing rule on that role leaks data between LOs.
12. **The drawer's out-of-shell fallback is dead in this site.** `portalRecordDrawer.handleOpenRecord` falls back to `standard__recordPage`/`standard__objectPage` (`portalRecordDrawer.js:151-206`). There are no record pages in this LWR site; it only works because `perfectDayHome` passes `embedded-in-shell`.
13. **`Transaction__c.Loan_Amount__c` is the 0%-populated twin** (see memory "Transaction__c dead twin fields"). It feeds the My Loans amount (`ExternalLoPortalService.cls:411, 467`), so loan amounts will show blank. Flag this to the loans deep dive.

### Low / cosmetic / dead code

- Browser tab title "Welcome to LWC Communities!" (appPage `headMarkup`).
- The login form shows a self-register link config while self-registration is off; the Register view and News Detail route are template leftovers.
- The shell declares the `lightningCommunity__RelaxedCSP` capability (`externalLoPortalShell.js-meta.xml:10-12`) on a strict-CSP site. It works today; if Builder ever refuses to place it, this is why.
- The Targets step shows daily numbers using the default 5 workdays, because Rhythm comes after Targets. Rhythm offers only 3-6 days, while Apex accepts 1-7.
- "Skip for now" and "Finish setup" do the same thing. CSV rows imported in step 6 persist even if the LO never finishes.
- Labels `ExtLO_Onboarding_Title` and `ExtLO_Onboarding_Intro` are imported but never rendered. `ExtLO_Onboarding_Goals_Title` is defined but unused. `Business_Focus__c` description still says options come from the baseline CMDT.
- Dead Apex: `ExternalLoWorkspaceController.saveOnboarding` (V1), `getActivityPlan`, `getPastClients` have no LWC caller. `ExternalUserAssignmentRepository.selectContactIdsByUserId` is test-only. The V1 daily-goal fields and `ExternalLOBaselineHelper.applyUserGoals` only serve legacy code.
- Dead JS: `isExperienceCloudContext`, `shouldUseFlowNavigation` (`portalUtils.js:26-33`); `portalListLayout.rowType`/`isGenericRows`.
- `externalLoPerfectWeek` both wires with `cacheBust: '$refreshKey'` and calls `refreshApex` in the setter (double fetch), and fetches the rollup even while the wizard is showing.
- Mobile nav drawer has no focus trap and no Escape handling. The shell load error has no retry.
- No TODO/FIXME markers and no hard-coded record Ids in this area. Hard-coded names: record type developer names in `ExternalLOBaselineHelper.cls:26-29`, status strings, and focus-preset field-to-key map.

### Test-class quality

| Test | Verdict |
|---|---|
| ExternalLoOnboardingServiceTest | Good: asserts persisted values, lock behaviour, invalid focus, daily math, the Aura primitive binding, FLS fallback. It depends on live CMDT labels ("Grow new referral partners", "Deepen existing partners"), so renaming a focus record breaks it. It doesn't cover >200 targets, V2 invalid focus, or workday clamping through the service. |
| ExternalLOBaselineHelperTest | Good: pure-function asserts on every helper, uses `nowOverride`/`baselineOverride`. |
| ExternalLoGoalMathTest | Good asserts, but `weekBoundsAreMondayThroughSunday` is date-dependent and fails on Sundays (6.2). |
| ExternalLoPortalTestHelper | Looks for profile "Customer Community Plus User", not the real "RHL Community User", and silently falls back to a Standard user if the community insert fails. So "community" tests may really run as internal users and never exercise portal sharing. Hard-codes `NMLS__c = '1866656'`. |
| ExternalLoPortalCoverageTest | Mostly line coverage. It runs as the admin, not a portal user. `portalFiltersAndRecordSets_coverRemainingBranches` makes 16 calls and asserts once; the repositories test asserts only null-guards. It needs `AesKey__c` and live record types. |

Org `ApexCodeCoverageAggregate` shows 0 lines for several of these classes (ExternalLoGoalMath, ExternalLOBaselineHelper, ExternalLoActivityCatalog, ExternalLoPortalController), so the stored coverage is stale. Run the tests in a sandbox before relying on it. Per memory, prod deploys use RunSpecifiedTests.

---

## 7. Manual test checklist (this area)

Use a sandbox with a fresh RHL Community User on a test contact, holding `External_LO_Perfect_Day_Access`. Grant yourself admin FLS on the portal fields first so you can reset.

| # | Steps | Expected |
|---|---|---|
| 1 | Open `/partnerworkspace/` logged out | Redirects to `/login`; branded hero, welcome, form, help, footer render; tab title noted (currently the template default) |
| 2 | Click "Forgot your password?", submit username | Check-email page; email arrives from the configured sender (today the Nimbus address) |
| 3 | Log in as a new portal user **without** the permset | Shell shows an error, not the workspace (confirms permset is mandatory) |
| 4 | Assign permset, reload | "Loading Partner Workspace..." then shell; nav shows only Perfect Day and My Perfect Week |
| 5 | Paste `?c__view=leads` | URL rewritten to `c__view=perfectDay`; Leads not shown |
| 6 | My Perfect Week: try Continue with no focus; turn every activity off; type 250 and blur | Continue disabled / "Keep at least one activity on" / value clamps to 200 |
| 7 | Pick a focus | Weekly targets change to that focus's presets |
| 8 | Change workdays to 4 on Rhythm | Daily hints recompute as ceil(weekly/4) |
| 9 | Import step: upload a small consumer CSV, then Finish setup | Lands on Perfect Day; full nav appears; imported leads visible in My Leads |
| 10 | Admin: check the User and goal rows | Focus, workdays, complete = true; 5 `External_LO_Activity_Goal__c` rows owned by the LO, keys `<userId>:<activityKey>` |
| 11 | Revisit My Perfect Week | Progress panel, no wizard; no way to edit |
| 12 | Admin sets complete = false; LO reloads | Wizard reopens pre-filled with saved targets; Finish works again |
| 13 | Navigate views, use browser back/forward, reload on `?c__view=loans&c__filter=all` | State follows URL; reload restores the view |
| 14 | `?c__view=realtors&c__filter=abc` | Today: error message (bug 6.6). After fix: falls back to default filter |
| 15 | Create a New lead, then open Perfect Day | My Leads badge increments after landing on Perfect Day (not before) |
| 16 | Realtor with last touch 8 days ago vs never touched | First counts in My Realtors badge; second does not (bug 6.8) |
| 17 | Mobile width (375px): open and close the hamburger, pick a view | Drawer closes on select and backdrop tap; content fills screen |
| 18 | Log out from sidebar and from mobile drawer | Session ends; lands on login; Back doesn't re-enter |
| 19 | On a Sunday (or with a fixed-date test), open My Perfect Week after logging activity | Today: shows next week, empty (bug 6.2). After fix: Mon-Sun week containing today |
| 20 | Log in as System Administrator via the site | Workspace loads as "setup complete" with the admin's own records (FLS fallback); wizard not reachable |
| 21 | Two LOs: each creates a lead; each opens `?c__view=leads&c__recordId=<other's lead>` | "Lead could not be found or is not visible" |
| 22 | Partner CSV with an email matching another LO's realtor | Decide if intended: currently grants Read AccountShare and an assignment row (risk 6.4) |
