# Outside LO Portal (Partner Workspace): Handoff Guide

Taken over from the contract developers ("Nimbus Development") on 2026-09-28. This guide is the starting point; the four area reports in `docs/` have the file:line detail and a manual test checklist each.

| Area | Detail report |
|---|---|
| Site, shell, navigation, access, setup wizard | [docs/01-shell-site-access.md](docs/01-shell-site-access.md) |
| Perfect Day home, activity logging, goals, prompts, progress | [docs/02-perfect-day-activity.md](docs/02-perfect-day-activity.md) |
| Pipeline: My Leads, My Pre-Approvals, My Loans | [docs/03-pipeline.md](docs/03-pipeline.md) |
| Business development: Realtors, Prospects, Past Clients, CSV import | [docs/04-bizdev-import.md](docs/04-bizdev-import.md) |

All findings were made read-only against production on 2026-09-28. None of the security holes below was exercised; they are confirmed from source and org metadata.

## What it is

A workspace for Reach's outside loan officers to manage their leads, clients and referral partners, plan their week and log their activity.

- **Site:** Experience Cloud LWR "Build Your Own" site **Partner Workspace**, URL `https://reachhomeloans.my.site.com/partnerworkspace/`. Network Id `0DBQi00000017aXOAQ`.
- **Built:** 2026-08-31 to 2026-09-23 by the Nimbus Development user.
- **Size:** about 25 LWCs, about 55 Apex classes, 2 custom objects, 3 custom metadata types and 58 `ExtLO_*` labels.
- **Usage so far:** effectively unused in prod. There are 2 active portal users:
  - `outsidelo@reachhomeloans.com` ("Reach Admin") is our **test user**.
  - Harold Ellis is a real outside LO who still works in an **older portal at a separate URL**. Leave him alone until this portal is ready.

## How it is built

- **Login page:** our branded page (`lwc/partnerLogin`). It is used 4 times on the Login view, with `variant` set to hero, welcome, help and footer.
- **Home view:** hosts a single component, `lwc/externalLoPortalShell`. Every page in the portal is a *view inside that shell*. The URL carries the state as `c__view`, `c__filter` and `c__recordId` (see `portalUtils` `parsePortalState` / `portalHomePageRef`).
- **Navigation groups:**

| Group | Views |
|---|---|
| My Activity | Perfect Day, My Progress, My Perfect Week |
| Business Development | Realtor Prospects, My Realtors, Past Clients, Import Data |
| Pipeline | My Leads, My Pre-Approvals, My Loans |

- **Setup gate:** until `User.External_LO_Onboarding_Complete__c` is true, only Perfect Day and My Perfect Week are reachable. The gate is enforced in the browser only.
- **Apex entry points:**
  - `ExternalLoWorkspaceController` covers setup, goals and activity.
  - `ExternalLoPortalController` covers lists, badges and records.
  - `PerfectDayHomeController` serves the home page.
  - Services sit behind them (`ExternalLoPortalService`, `PerfectDayHomeService`, `ExternalLoActivity*`, `ExternalLoPrompt*`, `ExternalLoCsv*`, `ExternalLoPartner*`).
- **Data:**

| Kind | What |
|---|---|
| Objects | `External_LO_Activity_Goal__c` (weekly targets per LO), `External_User_Assignment__c` (LO-to-partner link from import) |
| Custom metadata | `External_LO_Activity__mdt` (activity catalog, credit rules), `External_LO_Focus__mdt` (business focus presets), `External_LO_Baseline__mdt` (defaults, multipliers, Arive URL) |
| Fields | Activity `Activity_Category__c` / `Activity_Count__c` / `Prompt_Key__c`; User `Business_Focus__c` / `ExtLO_Workdays_Per_Week__c` / `External_LO_Onboarding_Complete__c` |

- **Activity:** every log is a completed Task owned by the LO. The Communications window **sends nothing**; it only writes a Task and an optional follow-up Event.

## Access model

- **Profile:** "RHL Community User" (Customer Community Plus). **This profile is shared with the 2022 "Reach Home Loans Transactions" portal, which is likely Harold's current portal.** Any profile change hits both portals. Give new-portal access through permission sets.
- **Permission set:** `External_LO_Perfect_Day_Access` is required. Without it the shell shows only an error.
- **How records reach an LO:**
  - Leads and pre-approvals by `OwnerId`.
  - Loans by `Loan_Officer__c` or `OwnerId`, with a share row.
  - Partners by ownership, plus Manual Read shares created by the CSV import.
  - There are no sharing sets.
- **No Lead object permission:** portal users have none (verified). Any `USER_MODE` Lead query fails for them.
- **Both active portal users sit on one Account** owned by the Nimbus Development user, under a single portal role.

## Priority fix list

### P0: Security (fix before any real LO uses the portal)

1. **Call transcripts readable org-wide.** `CallInsightListController` is `without sharing`, filters only by the record Id passed in, and is granted to both the portal profile and the permission set. An outside LO can pull transcripts, summaries and Zoom playback links for any record. (Verified.) Because the profile is shared, this also applies to the old portal.
2. **Activities can be written to any record.** `ExternalLoCommunicationService.logCommunication`, `logActivity` and `snoozePrompt` insert Tasks and Events in SYSTEM_MODE against any record Id the browser sends. There is no ownership check.
3. **Document requests open org-wide.** `Lead_Document_Request__c` has external sharing Read/Write, and the permission set grants read, edit and delete. Every outside LO can read, change or delete all 330 requests. (Verified.)
4. **Partner import grants read access across the org.** An uploaded email or phone that matches any realtor, title or insurance Person Account creates a Manual Read share. The import has never run in prod (0 assignment rows).
5. **The profile opens about 1,358 Apex classes to external users.** Every `@AuraEnabled` method in those classes is callable from the portal. It needs an audit, and it should move to a permission set.

### P0: Contractor handover blockers

6. **Emails and site ownership.** Portal emails (welcome, password reset) come from `development@nimbuscloudsolutions.com`, and the Nimbus Development user is the site admin and guest-record owner. The same address is used on the other networks. Move all of it to Reach-owned values **before** the contractor's user or mailbox is shut off.
7. **Shared portal Account.** The Account holding both portal users is owned by the Nimbus Development user. Reassign it before deactivating that user.

### P1: Broken features

- **My Realtors, Prospects, the Realtors badge, the home page's realtor follow-ups and the contact picker** query Leads in USER_MODE. Portal users have no Lead access, so all of these fail and show empty.
- **Week on Sundays:** `ExternalLoGoalMath.weekStartMonday` returns next week on Sundays. Perfect Week, Progress, the home page and prompts all show an empty week, and `ExternalLoGoalMathTest` fails on Sundays, which blocks Sunday deploys.
- **Goal drill-downs** are broken for every category: `ExternalLoPortalService.cls:519-527` splits hyphenated keys. The fix is `split('-', 3)`.
- **Past Clients** lists Leads with Lead Source "Past Client", not Person Accounts with closed loans. Harold has 136 loans, and his list is empty.
- **My Loans** shows dead twin fields (`Loan_Amount__c`, `Interest_Rate__c`, `Lock_Exp_Date_1st_TD__c`), so amount, rate and lock date are blank.
- **Setup locks after the first save.** No admin has permission on the setup fields, so there is no way to reset them. The wizard says "You can change this later".
- **Snooze** can hide prompts permanently, and the anniversary prompt is not tied to the client.
- **"Open in Arive"** always errors because `Arive_Base_Url__c` is null.
- **Duplicate partners:** "Add partner → Create new" can't see the org's other ~8,200 partners, and duplicate blocking is bypassed because the UI always sends `forceCreate: true`.
- **Borrower calls credit the wrong goal.** They credit Realtor Outreach instead of consumer conversations.

### P2: Wrong numbers and labels

- Lead status "Nurturing" (29k leads) never matches the Nurture filter, and the loan "Clear to close" filter is always 0.
- "Expiring soon" on pre-approvals means the credit has already expired. "Docs outstanding" really means no RingCentral contact in 6 days.
- The pace badge never changes colour ("Behind Pace" vs "Behind pace"), and "pace" means three different things across pages.
- The realtor "due" rule skips partners never touched, and the default 90-day filter hides new or imported partners.
- The CSV import has several problems:
  - It is comma-only and assumes UTF-8.
  - Headers must match exactly.
  - Its row count counts newlines inside quoted cells.
  - Imported past clients arrive as New leads.
- A `?c__filter=abc` URL crashes the Realtors list (`Integer.valueOf`).

### P3: Cleanup

- **Dead code:** `saveOnboarding` V1, `getActivityPlan`, `getPastClients`, `linkPartner`, several TaskRepository methods, and the old per-channel goal fields on User. The Up Next card, defer and complete features are built but never rendered.
- **Unreportable data:** activity and goal fields are readable only through the portal permission set, so internal users can't report on them.
- **Tests** never run as a real portal user. `ExternalLoPortalTestHelper` looks for a profile named "Customer Community Plus User", which doesn't exist, so it falls back to an internal user. `ExternalLoPortalCoverageTest` is coverage padding. The ADR-0001/0002 documents the code cites are not in the repo.

## Working on it

- **Source of truth:** this folder, pulled fresh from prod on 2026-09-28. It includes the repositories and `InterFont` that were missing. Always retrieve before editing.
- **Deploy:** `sf project deploy start -o Production -m <Type:Name> ...` Deploy only what changed; Apex needs `RunSpecifiedTests` (see the org notes on the 4 broken test classes).
- **Publish:** any LWC or DigitalExperience change needs `sf community publish -o Production --name "Partner Workspace"`. It goes live in about 30 seconds.
- **Test in prod** as `outsidelo@reachhomeloans.com`. Keep test data under that user, and never touch Harold's data.
- **Logout** (added 2026-09-28) uses `comm__loginPage` / `logout`. The network has no logout URL, so users land back on the login page. It has not been tested by a logged-in user yet.

## Suggested order

1. Handover blockers 6 and 7, while the contractor can still answer questions.
2. Security items 1 to 3: small, contained fixes.
3. Make the tests run as a real portal user, so the P1 fixes are proven.
4. The P1 list, starting with the Lead-access failures and the Sunday week bug.
5. Walk each area's manual test checklist as the test user. Then decide on the setup-reset procedure before inviting real LOs.
