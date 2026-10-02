# Phase 8: Manager oversight (LO Workspace)

Status: built and validated (check-only) on 2026-10-01. **Not deployed.**

- **Validation:** `0AfQi000001TmrtKAC` succeeded: 14/14 components, 27/27 tests, 0 failures, no coverage warnings.
  - LoWsOversightController: 159/163 lines (97%).
  - ExternalLoPortalService: 526/695 lines (75.7%). That is just over the gate, so always deploy it with both portal suites.
  - The earlier attempts `0AfQi000001TmofKAC` and `0AfQi000001TmqHKAS` failed and are superseded.
- **Source:** fresh prod retrieves are in `ref/src/` (2026-10-01). Only new or changed components are in `force-app/`. `sh run-validate.sh` re-validates and writes `validate.json`.

## Where managers find it
There is a new **LO Oversight** tab (Lightning app page). It sits in the nav right after **BD Overview** in the two internal apps the managers use: **Reach Home Loans Lightning** (Christopher) and **Reach Home Loans CEO** (Adam). Brandon's last-used app was LO Workspace (his demo), but he has both internal apps.

- Only users with `LO_Workspace_Oversight` can see the tab, because the tab visibility comes from that permset. Everyone else in those apps sees no change.
- The LO_Workspace app is **not touched**. Its nav stays Perfect Day only.
- **Why this option:** it copies the BD Overview pattern exactly (tab + AppPage + permset + the same two apps). Putting it inside an existing command center would mean editing the 9.5k-line PCC or the BD LWC, which is a bigger and riskier change.

## What it shows
`loWsOversight` LWC, backed by `LoWsOversightController.getOverview(includeInternal)`. It is one Apex call, and the gate is checked server-side in that method (the only `@AuraEnabled` one). Without the permission, the call throws "You do not have access to LO Workspace oversight."

**Who it covers:** active users in role `External_Loan_Officer`. The **Include internal LOs** toggle adds active users on `Loan Officer Profile`, labelled "(internal)". There is a cap of 25 LOs.

**Reads:** the controller is `without sharing` and runs its SOQL `WITH SYSTEM_MODE`, behind the gate. This matters because the managers have no FLS on the `User.ExtLO_*` goal fields.

| Section | Source |
|---|---|
| **Goals vs activity** | Week and month scores come from Perfect Day's own math: `ExternalLoActivityPlanService.getPlan` + `ExternalLoActivityRollupBuilder.build(plan, tasks, 7 / monthDays, false)` over `TaskRepository.selectCompletedActivitiesByOwnerForDateRange`. These are the same calls `PerfectDayHomeService` uses for its week and month progress. Badges: green at 100% or more, amber at 70% or more, red below that. Clicking a row shows that LO's per-activity week breakdown. The row also shows: setup complete, loans closed vs `ExtLO_Monthly_Unit_Goal__c`, volume closed vs `ExtLO_Monthly_Volume_Goal__c`, and Active Partner tags vs `ExtLO_Target_Realtor_Count__c`. |
| **Pipeline** | Leads by `ExternalLoPortalService.deriveLeadStage` (New / Working / Pre-Approval / Nurture / Converted), using the same 365-day converted window as My Leads. Active loans are `Loan_Officer__c` = LO with Status not Post-Closed, Cancelled or Lost: count, `Loan_Amount_1st__c` volume, and per-status chips in pipeline order. |
| **Realtor tags by stage** | `External_User_Assignment__c.Stage__c` for each LO. A blank stage counts as Prospect. |
| **New landing-page leads (30 days)** | The LO's leads with Lead Source `LO Landing Page` created in the last 30 days, **or** with `LO_Takeover_At__c` in the last 30 days (marked "Taken over"). Newest first, linked to the record. |
| **Setup changes** | The last 100 `External_LO_Plan_Change__c` rows (the snapshot saved on each setup save). |

The LO picker filters every section to one LO.

**"Closed this month" definition:** Status Funding, PC Review or Post-Closed, **and** `Closing_Date__c` in the current month. This matches the portal's Past Client statuses.

## Components (`force-app/`, 14)
| Component | Change |
|---|---|
| ApexClass `LoWsOversightController` | New |
| ApexClass `LoWsOversightControllerTest` | New, 3 methods |
| ApexClass `ExternalLoPortalService` | `deriveLeadStage` changed from `@TestVisible private` to `public`. No other change. |
| LWC `loWsOversight` | New (AppPage target only) |
| FlexiPage `LO_Workspace_Oversight` | New AppPage |
| CustomTab `LO_Workspace_Oversight` | New, label "LO Oversight" |
| PermissionSet `LO_Workspace_Oversight` | Adds class access + tab Visible. The custom permission is unchanged. |
| CustomApplication `Reach_Home_Loans_Lightning`, `Reach_Home_Loans_CEO` | One line each: `<tabs>LO_Workspace_Oversight</tabs>` after BD_Overview. Otherwise exactly as retrieved. |
| ReportType `LO_Workspace_Loans` | New: Transaction__c plus the Loan Officer's role (`Loan_Officer__c.UserRole`). That is the only way to filter loans to outside LOs in a report. |
| ReportFolder `LO_Workspace` | New. Shared in metadata: Manage for clowman@, bbrotsky@ and astephens@. |
| Report `Outside LO Leads by Status` | LeadList, Owner Role = External Loan Officer, grouped by owner and status |
| Report `Landing Page Leads (30 days)` | LeadList, Lead Source = LO Landing Page, last 30 days. Covers any owner, because the webhook accepts internal LOs too. |
| Report `Outside LO Loans by Status` | LO_Workspace_Loans, Loan Officer role = External Loan Officer, not Post-Closed or Cancelled, grouped by LO and status, sum of Total Loan Amount |

**No report on realtor tag stage:** `Stage__c` has no FLS on any profile or permset (deliberately, since Phase 5). A report cannot show it, so it lives on the tab only.

## Tests (`LoWsOversightControllerTest`)
- `managerSeesGoalsActivityPipelineTagsAndHistory`: runs as a new admin with the permset. The data is a real External Loan Officer profile + role user with goals, a landing-page lead and a Nurturing lead, a Waiting On Loan Officer loan, a Funding loan closing today, two tags (one with a blank stage), a plan change and a categorized completed Task. It asserts every section, including the week and month activity credit.
- `internalToggleAddsInternalLoansOfficersOnly`: the toggle adds exactly the active Loan Officer Profile users.
- `everyoneElseIsRefused`: an admin without the permission gets an AuraHandledException.
- The portal suites `ExternalLoPortalServiceTest` and `ExternalLoPortalCoverageTest` still pass. They cover the visibility change.

## Deploy
From `C:\Apps\Claude Back Up\lo-workspace\phase8`:
```
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LoWsOversightControllerTest --tests ExternalLoPortalServiceTest --tests ExternalLoPortalCoverageTest --wait 60
```
Or quick-deploy within 10 days: `sf project deploy quick -o Production --job-id 0AfQi000001TmrtKAC`.

**Before deploying,** re-check `LastModifiedDate`. Nimbus has rolled things back before. At retrieve time the values were:
- ExternalLoPortalService: 2026-10-01 15:02 (Christopher)
- permset LO_Workspace_Oversight: 2026-10-01 16:45
- both apps: 2026-09-29

If any of these moved, re-retrieve and re-apply the one-line change.

## After deploy
1. No permset assignment is needed. `LO_Workspace_Oversight` is already assigned to Christopher, Brandon and Adam (checked 2026-10-01).
2. Open Reach Home Loans Lightning → LO Oversight. Check that the pilot (Outside LO Pilot) is listed, that the toggle adds the internal LOs, and that a non-holder does not see the tab.
3. Reports → LO Workspace folder. Run the three reports. Folder sharing is deployed in metadata, so there is no manual step. If an org setting strips user shares, share the folder by hand with the three users.
4. Optional: pin the folder or add the reports to a dashboard. A dashboard was not built.

## Open questions
1. **"Closed this month"** = Funding/PC Review/Post-Closed with Closing_Date__c this month. Should Funding count before the loan is post-closed, or should it use `Funding_Date__c`?
2. **Internal LOs** = active users on `Loan Officer Profile` (6 today). Brandon, Alaina and Berkeley originate on other profiles and are not included. Internal LOs have no saved activity plan, so their goals are the catalog defaults, and their RingCentral tasks only count if they carry a credited Activity_Type__c. Is that "close enough", or should the toggle be dropped?
