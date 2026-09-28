# Partner Workspace deep dive 02: Perfect Day home, activity logging, goals, prompts, progress

Scope: the portal home page ("Perfect Day"), the two logging modals, the activity catalog and goal model, prompts ("Up next for you"), and My Progress. Read-only review of prod source retrieved into `outside-lo-portal/force-app/main/default/` plus read-only SOQL against Production on 2026-09-28.

Paths below are relative to `C:\Apps\Claude Back Up\outside-lo-portal\force-app\main\default\`. Three classes this area depends on are **not in the local source tree** at all: `LeadRepository`, `LoanRepository`, `PersonAccountRepository`. I pulled their bodies from prod (tooling `ApexClass.Body`) into the scratchpad (`deepdive/src/`). Any retrieve of this project for development must add them, or the package will not compile in a scratch/sandbox org.

All classes in this area were last deployed by Nimbus Development on 2026-09-14 (`ExternalLoCommunicationService` on 2026-09-01).

---

## 0. The short version

- The feature has **never been used for real**. No Task or Event has been created by a portal user since April 2025. Zero portal-logged activities exist. The only goal rows are five rows for the "Reach Admin" test user, written 2026-09-15.
- The model is: **one completed Task per log**, scored by `Activity_Category__c` (or, if blank, by `Activity_Type__c` via `Credit_Activity_Types__c`), times `Activity_Count__c`, against **per-user weekly targets** in `External_LO_Activity_Goal__c` (defaults from `External_LO_Activity__mdt`).
- Nothing sends a message. Both modals only write Task (and optionally Event) records.
- Biggest bugs, all verified in code: goal drill-downs are broken for every category (key split on `-`); week boundaries are wrong on Sundays (and a unit test fails every Sunday); "snooze until tomorrow" actually hides a prompt indefinitely and then turns into an overdue task with a raw key as its subject; the Communication modal credits every call to **Realtor outreach**, even a call to a borrower; the Up Next card, defer and complete flows are fully built in Apex but **not rendered** anywhere.

---

## 1. What the Perfect Day home shows, and where every number comes from

### Entry point and data load

- `lwc/perfectDayHome` is embedded in the shell (`externalLoPortalShell.html:63-68`), receiving `setup-complete` and `refresh-key`.
- One cacheable wire: `PerfectDayHomeController.getPerfectDayHomeData(cacheBust)` (`PerfectDayHomeController.cls:6-14`) -> `PerfectDayHomeService.getHomeData()` (`PerfectDayHomeService.cls:11-173`). `cacheBust` is only a wire cache key (a String, because `Date.now()` overflows Apex Integer). Refresh is `refreshApex` (`perfectDayHome.js:751-767`) or a new `refreshKey` from the shell.
- First-run vs dashboard: `showFirstRun` / `showDashboard` (`perfectDayHome.js:171-189`) use the shell's `setupComplete` if provided, else `User.External_LO_Onboarding_Complete__c`. First run shows only a "Start my setup" card that navigates to Perfect Week.

### Time zone and date windows

Everything uses `Date.today()` / `System.now()` in the **running user's time zone**. Both active portal users are `America/New_York`, `en_US`. Windows are computed once in `PerfectDayHomeService.cls:23-35`:

| Window | Definition | Code |
|---|---|---|
| Today | `Date.today()` | service :23 |
| Week | `toStartOfWeek().addDays(1)` .. +6 (intended Mon-Sun) | `ExternalLoGoalMath.cls:35-42` |
| Month | `toStartOfMonth()` .. end of month | service :26-27 |
| Query range | min(week start, month start) .. max(week end, month end) | service :28-35 |

**Sunday bug.** `toStartOfWeek()` is Sunday in `en_US`. On a Sunday it returns that same Sunday, so `+1` gives **tomorrow's Monday**. On Sundays the "week" is next week: today's logs fall outside it, weekly partner meetings read 0, and weekly prompt suppression (below) looks at the wrong week. `ExternalLoGoalMathTest.weekBoundsAreMondayThroughSunday` asserts `monday <= today` (`ExternalLoGoalMathTest.cls:40`), so **that test fails whenever tests run on a Sunday**, which would block a Sunday deploy. Fix: `today.addDays(-Math.mod(Date.newInstance(1900,1,1).daysBetween(today), 7))` (1900-01-01 is a Monday), or use a `Datetime.format('u')` day-of-week.

### Task source for all scoring

One query, `TaskRepository.selectCompletedActivitiesByOwnerForDateRange` (`TaskRepository.cls:6-21`): `OwnerId = me AND Status = 'Completed' AND ActivityDate in range`, `WITH SYSTEM_MODE`, **no LIMIT and no ORDER BY**. It returns every completed task the user owns, not only portal logs. The service then slices it in memory into today/week/month (`PerfectDayHomeService.cls:42-44, 175-189`) by `ActivityDate`.

### Section by section (as rendered in `perfectDayHome.html`)

| # | Section (html lines) | What it shows | Source |
|---|---|---|---|
| 1 | Welcome banner (53-90) | Date label; "Good morning, {first name}"; pace badge; "Focus: {Business_Focus__c}"; "{goalsCompleted} of {goalsTotal} activity goals met today"; daily %; progress bar | See 1a |
| 2 | Summary metrics (93-122) | Four cards: Daily Score, Goals Completed, Overdue Tasks, Activities Remaining | `PerfectDayHomeBuilder.buildSummaryMetrics` (`PerfectDayHomeBuilder.cls:8-66`) |
| 3 | Today's Plan (124-127, `externalLoTodayPlan`) | One row per enabled category: "{completed} of {goal} {unit} today/this week", pace chip, Log button | `todayScore.rows` (service :117-123, 137) |
| 4 | Up next for you (129-133, `externalLoActivityPrompts`) | Up to 8 prompt cards with Log and "Tomorrow" buttons | `ExternalLoPromptService.build` (service :161-169). See section 3 |
| 5 | Recent activity (135, `externalLoRecentLog`) | 8 newest completed tasks: label, contact name, date, xcount | `buildRecentLog` (service :191-219) |
| 6 | Pipeline snapshot (138-180) | Five queue counts with urgency | `PerfectDayHomeBuilder.buildPriorities` (:68-84). See 1b |
| 7 | Goal Progress (182-233) | Today / This week / This month tabs; per-category bars; extra "Overdue tasks, target 0" row on Today | `buildGoalProgress` (:187-197) + `perfectDayHome.js:347-412` |
| 8 | Quick links (235-255) | Realtor Prospects, My Realtors ("N follow-ups due"), Past Clients, My Leads ("N new to contact") | `perfectDayHome.js:271-292`, counts from priorities |
| 9 | Record drawer (261-266) | Opens `portalRecordDrawer` for a record-set key when a metric/priority/goal row is clicked | `ExternalLoPortalService.getRecordSet` |

#### 1a. Banner and metric numbers

- `dailyCompletionPercent` = `todayScore.percent` = floor(sum completed / sum goal x 100), capped at 100 (`ExternalLOBaselineHelper.completionPercent`, `ExternalLOBaselineHelper.cls:205-211`). Note the cap is on the total, not per row, so over-delivering one category makes up for another.
- `goalsCompleted` = count of today rows where `completed >= goal` and goal > 0 (service :138-146). `goalsTotal` = number of enabled rows, including rows with a 0 target (which can never be "met").
- `paceStatus` (`ExternalLOBaselineHelper.cls:213-239`): "Perfect day complete" if total done >= total goal; otherwise compares % to a linear 9:00-17:00 expectation (`hour` in user TZ, whole hours only), giving "Behind pace" or "On pace".
- Summary cards:
  - **Daily Score** = daily %. Drill `completed-today` = **all** completed tasks today, including ones that earn no credit.
  - **Goals Completed** = "X of Y". Same drill.
  - **Overdue Tasks** = `selectOpenOverdueByOwner` (`TaskRepository.cls:99-115`): open tasks with `ActivityDate < today`, `WITH SECURITY_ENFORCED`, LIMIT 500. "Oldest overdue N days" uses the first row.
  - **Activities Remaining** = max(0, total goal - total completed) (service :157). The card's caption is hardcoded "Scheduled before 5:00 PM" (`PerfectDayHomeBuilder.cls:58`), and its drill (`activities-remaining`, `ExternalLoPortalService.cls:283-300`) lists **open tasks due today or earlier**. The number, the caption and the drill are three unrelated things.

#### 1b. Pipeline snapshot (priorities)

| Queue | Query | Filters | Urgency |
|---|---|---|---|
| New leads need contact | `LeadRepository.selectNewLeadsToContact` (prod body) | Owner = me, not converted, `Status='New'`, created >= 2024-01-01, `Appointment_Date_Time__c` null or past, consumer record types; then drops leads with a future Event (`selectLeadIdsWithFutureEvents`) | red if any lead is older than 15 min (`NEW_LEAD_SLA_MINUTES`), else orange |
| Realtor follow-ups due | `PersonAccountRepository.selectRealtorPartnersByOwner` | Owner = me, person account, `Group__pc IN ('Realtor','Realtor Prospect')`, LIMIT 500 | Last touch = latest completed task with `WhatId = account` and owner = me (`TaskRepository.cls:133-163`), merged with `Account.LastActivityDate` (service :73-89). No touch = orange, >7 days = orange, >=14 days = red |
| Pre-approvals need review | `selectPreApprovalsToReview` | `Status='Pre-Approval'`, consumer RTs | red if `Credit_Expiration_Date__c <= today`; orange if **both** `Last_Call_Attempt_RingCentral__c` and `Last_SMS_Attempt_RingCentral__c` are null or older than 6 days |
| Loans require milestone updates | `LoanRepository.selectLoansNeedingMilestoneUpdates` | `Loan_Officer__c = me OR OwnerId = me`, active status list, and (`Waiting On Loan Officer` or status unchanged for 3+ days), `WITH USER_MODE` | red: WOLO and stale; orange: WOLO fresh or other stale |
| Overdue tasks | as above | | red if any |

"Contacted" is **never** derived from activity. A new lead leaves the queue only when its Status changes, its `Appointment_Date_Time__c` moves into the future, or a future Event exists. Logging a call with "No follow-up" leaves the lead in "New leads need contact" indefinitely.

Pre-approval freshness depends on the RingCentral stamp flow (`RingCentral_Stamp_Last_Call_SMS_Attempt`, fires only for RingCentral tasks with `rcsfl__CALL_UNIQUE_ID__c`). Calls logged in the portal never stamp those fields, so for an outside LO **every pre-approval is always "stagnant"** and always listed.

Minor inconsistency: the realtor queue merges `LastActivityDate` into the last touch, but the realtor description/urgency (`PerfectDayHomeBuilder.cls:299-320, 415-431`) and the partner prompts use the task-only map, so a realtor can be counted by one rule and coloured by another.

#### 1c. Goal Progress tabs

- Rows come from `todayScore`, `weekScore` (periodDays 7, weekly target), `monthScore` (periodDays = days in month, target `round(weekly x days / 7)`) (service :117-136, 159).
- The LWC re-labels rows (`perfectDayHome.js:361-393`): complete if done >= goal, "On pace" if >= **55%**, else "Behind pace". This is a third, different definition of "pace" (see Risks).
- Clicking a row opens record set `goal-{today|week|month}-{activityKey}` (`perfectDayHome.js:527-535`). **This is broken**, see Risks #1.

---

## 2. Activity logging

### What the LO can log

Two different modals write two different kinds of Task.

| | Log activity (`portalActivityModal`) | Log communication (`portalCommunicationModal`) |
|---|---|---|
| Opened from | Banner "Log activity", Today's Plan "Log", prompt "Log" (`perfectDayHome.js:512-521, 633-650`) | Leads list, Realtors list, record drawer. **Not reachable on the home page** (see Risks #5) |
| Apex | `ExternalLoPortalController.logActivity` (`:153-180`) -> `ExternalLoActivityLogService.logActivity` (`:18-56`) | `ExternalLoPortalController.logCommunication` (`:130-151`) -> `ExternalLoCommunicationService.logCommunication` (`:5-21`) |
| Picks | Category (enabled plan rows only), channel (Call, Text, Email, Meeting, Open house), count 1-50, optional contact (lead or partner search), notes | Channel (Call, Text, Email, In person, Video), outcome (per-channel list), notes (required, 3+ chars), follow-up (Tomorrow, 3 days, Next week, None) |
| Contact required | Only if catalog `Requires_Contact__c` (all except Social posts) | Always (the host record) |

### Record written: Log activity

`ExternalLoActivityLogService.cls:29-43`, one Task, `Database.insert(..., AccessLevel.SYSTEM_MODE)`:

| Field | Value |
|---|---|
| OwnerId | running portal user |
| Status / Priority | Completed / Normal |
| ActivityDate | `Date.today()` (user TZ) |
| Activity_Category__c | catalog `Category_Api_Name__c` (e.g. `Realtor_Outreach`) |
| Activity_Type__c | channel mapping: call -> `Call - Active Agent`, text -> `Text`, email -> `Email`, meeting -> `Meeting (Active Agent)`, open-house -> `Open House` (`:164-188`). Falls back to the category's first credit type if no channel |
| Activity_Count__c | clamped 1-50 |
| Prompt_Key__c | the prompt key when logged from a prompt |
| Subject | shortLabel, or "+N {unit}" when count > 1 (`:190-195`) |
| Description | notes |
| WhoId / WhatId | Lead or Contact -> WhoId; anything else (Account, Transaction__c) -> WhatId (`:197-206`) |

The modal always defaults the channel to Call (`portalActivityModal.js:174-176`), so a Social post logged without touching the channel is stored as `Activity_Type__c = 'Call - Active Agent'`. Scoring is unaffected (category wins), but any internal report on `Activity_Type__c` will count it as a call.

If the log came from a prompt, the service then closes any open Task with the same `Prompt_Key__c` (`:208-219`, SYSTEM_MODE update).

### Record written: Log communication

`ExternalLoCommunicationService.cls:43-59`: one completed Task, owner = user, `ActivityDate = today`, `Description = notes`, `Subject = "{Channel} - {outcome with dashes replaced}"`, `Activity_Type__c` from channel (in-person/video -> `Meeting (Active Agent)`, anything unknown -> call). **No `Activity_Category__c`, no `Activity_Count__c`** (the field default of 1 applies). Lead -> WhoId, Account/Transaction -> WhatId.

Unless follow-up is "none", it also inserts an **Event** (`:89-102`): `Subject 'Follow up'`, 15 minutes at 9:00 AM local, tomorrow / +3 / +7 days, same Who/What. A null `followUpOption` (direct API call) also creates one, because the check is `!= 'none'`.

The **outcome is stored only in `Subject`**. There is no outcome field. `ExternalLoPortalService.mapActivities` (`:487-499`) reads it back from `Subject` as the "outcome" in the activity history. See section 7 on Subject rewriting.

### How credit is counted

`ExternalLoActivityRollupBuilder.activityKeyFor` (`:125-146`):

1. If `Activity_Category__c` matches a catalog category, use it.
2. Otherwise loop `activeActivities()` in `Sort_Order__c` order and take the **first** whose `Credit_Activity_Types__c` contains the task's `Activity_Type__c`.

Credit = `Activity_Count__c` (null or < 1 counts as 1) (`:148-154`).

With the prod CMDT (`customMetadata/External_LO_Activity.*.md-meta.xml`) the fallback resolves as:

| Activity_Type__c | Credits | Why |
|---|---|---|
| Call - Prospecting, Call - Active Agent | **Realtor outreach** (sort 1) | Consumer (2) and Past client (4) also list calls but are never reached |
| Text | Consumer convos (sort 2) | |
| Email | Social posts (sort 3) | |
| Meeting (New/Active Agent), Open House | Partner meetings (sort 5) | |

Result: every call logged through the **Communication modal**, including a call to a borrower from the Leads page (whose modal text says "credits your consumer conversations goal", `externalLoLeads.html:234`), is credited to **Realtor outreach**. Past-client calls can only ever be credited through the Activity modal. The fallback also silently credits any completed task the user owns that happens to carry one of these types.

### Daily / weekly / monthly math

`ExternalLoActivityRollupBuilder.build` (`:53-110`) with `ExternalLoGoalMath`:

| Period | Target per category | Tasks counted |
|---|---|---|
| Today, daily cadence | `ceil(weekly / workdays)`; workdays = `User.ExtLO_Workdays_Per_Week__c` clamped 1-7, default 5 | today |
| Today, weekly cadence (Partner meetings) | full weekly target | whole Mon-Sun week |
| Week | weekly target | Mon-Sun |
| Month / Quarter | `round(weekly x daysInPeriod / 7)` | calendar month / quarter |

Notes: `ceil` rounds daily targets up (weekly 12 over 5 days = 3/day = 15/week, so the days add up to more than the week). The daily target applies on Saturday and Sunday too, with no workday check. Month and quarter targets count weekend days.

Weekly targets come from `ExternalLoActivityPlanService.getPlan` (`:35-68`): the user's `External_LO_Activity_Goal__c` row per `Activity_Key__c` (read `WITH SYSTEM_MODE`, `ExternalLoActivityGoalRepository.cls:15-26`), else the CMDT `Default_Weekly_Target__c` with enabled = true. Goals are written only by onboarding (`ExternalLoOnboardingService.cls:80` -> `ExternalLoActivityGoalWriter.upsertGoals`, upsert on `Unique_Key__c = userId:activityKey`, owner = user, SYSTEM_MODE). The portal permission set grants goal **read only**, so there is no in-portal goal editing outside onboarding. The home page footnote says "Only an admin can change them".

There is a second, **legacy goal model still alive**: onboarding also writes `User.Calls/Texts/Emails/Meetings/Open_House_Daily_Goal__c` (and requires them, `ExternalLoOnboardingService.cls:33-37`), backed by `External_LO_Baseline__mdt`. Scoring ignores those fields entirely. `ExternalLOBaselineHelper.ActivityMetrics`, `goalsCompletedCount`, `applyUserGoals`, `weeklyMultiplier`, `monthlyMultiplier` are dead.

---

## 3. Prompts ("Up next for you")

Built inside `getHomeData` (service :161-169) by `ExternalLoPromptService.build` (`ExternalLoPromptService.cls:158-174`). `getPrompts(userId)` (`:80-95`) is the same thing, but only tests call it.

### Sources and triggers (in priority order, with per-type caps; max 8 total)

| Order / cap | Trigger | Data | Fires when | Credits |
|---|---|---|---|---|
| 1 / 2 | `under-contract:{leadId}` | `ExternalLoPromptSelector.selectUnderContractLeadsByOwner` (RT `Consumer_Under_Contract_Lead_Record_Type`, LIMIT 50) | always, for every such lead | Consumer convos |
| 2 / 2 | `milestone:{loanId}` | same list as the milestone queue | `loanMilestoneUrgency` is not blank | Consumer convos |
| 3 / 2 | `recurring-partner:{accountId}` | realtor accounts + task-only last touch | no touch, or > 7 days | Realtor outreach |
| 4 / 1 | `past-client:{leadId}` | Leads with `LeadSource='Past Client'` | anniversary month, or `LastActivityDate` null or 60+ days ago | Past clients |
| 5 / 1 | `escrow-analysis:{loanId}` | `selectFundedLoansByOfficer` (funded in last 18 months, LIMIT 200) | funded 11-13 months ago | Past clients |

**Anniversary bug.** `anniversaryMonths` (`:355-367`) returns {this month} if **any** of the LO's funded loans funded in this calendar month. It is not linked to the client. If one loan funded this month (including a loan funded last week), **every** past-client lead gets the "Closing anniversary is this month" script. Harold Ellis has 41 loans funded in the last 18 months.

Other notes: milestone prompts show `Transaction__c.Name` as the borrower name (`:229`). Past-client prompts need Leads, but past clients in this org are mostly Person Accounts. Harold owns zero leads, so he will never see a past-client prompt.

### Suppression

`snoozedKeysFor` -> `TaskRepository.selectPromptTasksByOwner` (`:65-78`: owner = me, `Prompt_Key__c != null`, `ActivityDate >= LAST_N_DAYS:400`, LIMIT 500) -> `suppressedKeysFrom` (`:110-138`):

- **Any open** prompt Task hides its key, whatever its due date.
- A completed Task with an `under-contract:`, `past-client:` or `escrow-analysis:` key hides that key **forever** (400-day window).
- A completed `milestone:` or `recurring-partner:` key hides it for the current Mon-Sun week (wrong on Sundays).

### Acting on a prompt

- **Log**: opens the Activity modal preloaded with the prompt's category, record and key. The save writes a completed Task with `Prompt_Key__c` and closes any open snooze Task for that key (section 2).
- **Tomorrow** (snooze): `ExternalLoActivityLogService.snoozePrompt` (`:62-91`) inserts an **open** Task, `ActivityDate = tomorrow`, `Subject = 'Follow up — ' + promptKey`, `Prompt_Key__c = key`, related to the record. The toast says "We will bring this back tomorrow."

**Snooze is broken end to end.** The class header says "Open snooze Tasks hide a prompt until their due date" (`:2-3`), but the code hides on any open Task (`:121-123`), and the unit test codifies that (`suppressedKeys_openSnoozeHidesEveryTrigger`). So:

1. The prompt does not come back tomorrow. It stays hidden while the snooze Task is open.
2. From day two, the snooze Task is overdue. It appears in "Overdue tasks" and in its drill with the subject `Follow up — recurring-partner:001...`, a raw key shown to the LO.
3. If the LO completes that overdue task, it becomes a completed prompt Task. For under-contract, past-client and escrow keys this **suppresses the prompt permanently**. The LO never logged a real conversation.

---

## 4. Communications modal: does it send anything?

**No.** `portalCommunicationModal` calls only `logCommunication`. `ExternalLoCommunicationService` does only two SYSTEM_MODE inserts, one Task and optionally one Event. There is no RingCentral callout, no `Messaging.SingleEmailMessage`, no EmailMessage, no Twilio, and no `tel:`/`mailto:` link in either modal. It is a "log what you did elsewhere" form.

The phone/email strip at the top of the modal never renders: the template checks `{hasContact}` (`portalCommunicationModal.html:15`) and the JS defines no such getter.

---

## 5. Progress view (My Progress, `lwc/externalLoProgress`)

- Wire `ExternalLoPortalController.getActivityRollup(cacheBust)` (`:218-226`) -> `ExternalLoProgressService.getProgress` (`ExternalLoProgressService.cls:16-58`).
- One task query spanning the earliest to the latest of week/month/quarter starts and ends (the same unbounded `selectCompletedActivitiesByOwnerForDateRange`), sliced in memory.
- Periods: Week (Mon-Sun, weekly target), Month (calendar, `round(weekly x days / 7)`), Quarter (calendar quarter, same formula). Scoring is identical to the home page's week/month scores. There is no "today" view, and the weekly-cadence special case does not apply here.
- UI (`externalLoProgress.js:99-118`): per row, >= 100% "Goal met", >= 70% "On pace", else "Behind pace" with the catalog coaching note. There are "Winning" and "Coaching focus" summary cards, plus overall % of plan.
- "Pace" here is progress against the whole period's target, **not** against elapsed time. On Monday morning every row reads "Behind pace", and on the 1st of the month every monthly row does.

---

## 6. Data volume reality check (Production, 2026-09-28)

Portal users (`Profile.Name = 'RHL Community User'`): 10, of which **2 are active**:

| User | Id | Last login | Owned Tasks | Owned Events | Goal rows |
|---|---|---|---|---|---|
| Harold Ellis | 005AJ000000Ig20YAC | 2026-09-24 | 2 (both open, from 2025-04 and 2026-05, so 2 overdue) | 6 (internal meetings created by others) | 0 |
| Reach Admin (test) | 005Qi000005FLvhIAG | 2026-09-28 | 43 completed (RingSense/RingCentral-style "Called Reach on..." rows created by Nimbus Development, last 2026-07-10) | 0 | 5 (all created 2026-09-15 18:24) |

- Tasks **created by** any RHL Community User: 2 in total, the newest on 2025-04-25. Events created by them: 0.
- Tasks since 2026-08-31 whose Subject matches the portal's patterns ("Follow up — %", "+N touches", the five short labels): **0**.
- Harold's scoring inputs today: 0 leads, 23 realtor person accounts (owner = one of the two), 6 loans in active statuses, and 41 loans funded in the last 18 months. His home page would show realtor follow-ups, milestone loans, 2 overdue tasks, milestone/partner/escrow prompts, and 0% on every goal (the CMDT defaults, since he has no goal rows).
- One of Harold's overdue tasks already shows the Subject rewrite: `Call - Prospecting on 2025-04-26 14:41:00Z on 4/25/2025 9:41:29 AM` (the suffix has been appended twice). That is the string the (hidden) Up Next card and the overdue drill would display.

**Reporting blind spot.** `Task.Activity_Category__c`, `Activity_Count__c`, `Prompt_Key__c`, all `External_LO_Activity_Goal__c` fields and `User.Business_Focus__c` are readable **only** through the permission set `External_LO_Perfect_Day_Access` (verified via `FieldPermissions`). My admin CLI user got "Invalid field" on all of them. No internal user can report on portal activity categories or goals until those fields are added to an internal permission set.

`ApexCodeCoverageAggregate` shows 0 covered lines for `ExternalLoActivityLogService`, `ExternalLoProgressService`, `ExternalLoCommunicationService`, `TaskRepository` and `ExternalLOBaselineHelper`. That table only reflects the last org test run, not these classes' tests, so do not rely on it. Re-run the specified test classes before the first deploy.

---

## 7. Risks, bugs, dead code, hardcoding, tests

### Bugs (verified in code)

1. **Goal drill-downs are broken for every category.** `ExternalLoPortalService.buildGoalRecordSet` splits `goal-today-realtor-outreach` on `-` and takes `parts[2]` = `realtor` (`ExternalLoPortalService.cls:519-527`). `activityByKey('realtor')` is null, so the title reads "Goal - today" and `matchesGoal` falls to the legacy `calls/texts/...` matcher and returns nothing. Every catalog key contains a hyphen. Tests only exercise legacy keys (`goal-today-calls`, `ExternalLoPortalServiceTest.cls:144`; `ExternalLoPortalCoverageTest.cls:285-289`). Fix: `recordSetKey.split('-', 3)`.
2. **Sunday week boundary** (section 1), plus the Sunday-failing test.
3. **Snooze hides indefinitely and then leaks** into overdue tasks, can suppress forever (section 3).
4. **Communication-modal calls credit Realtor outreach**, whoever was called (section 2).
5. **Up Next card is not rendered.** The JS has the whole Up Next flow (`hasUpNext`, `handleDefer`, `handleComplete`, `handleOpenRecord`, `handleLogCommunication`, `undoUpNextComplete`, the defer modal state: `perfectDayHome.js:315-333, 552-627, 691-694`) and the CSS has 28 `up-next` rules, but no template element binds any of it. The defer modal markup (`perfectDayHome.html:296-338`) and the communication modal (`:281-294`) can never open on this page. `PerfectDayHomeController.deferUpNextItem` / `completeUpNextItem` and the service code behind them (`PerfectDayHomeService.cls:241-361`) are unreachable from the UI but fully tested. Decide: restore the card or delete it.
6. **Pace badge colour never changes.** The LWC compares against `'Perfect Day Complete'` / `'Behind Pace'` (`perfectDayHome.js:220-240`), but Apex returns `'Perfect day complete'` / `'Behind pace'` (`ExternalLOBaselineHelper.cls:215, 222`). The badge always has the on-track style.
7. **Anniversary prompt not tied to the client** (section 3).
8. **Contact strip in the communication modal never shows** (`hasContact` undefined).
9. `logGoalCredit` reads `upNext.goalCreditLabel`, which does not exist in `UpNextItem` (`perfectDayHome.js:471-473`), so the text is always "your daily goals" (dead anyway because of #5).
10. Recent log: sorts by `ActivityDate` only (`PerfectDayHomeService.cls:221-239`), so same-day order is arbitrary and today's newest log may not be first. It covers up to about 6 weeks, not "today" as the empty state says, and it includes non-credit tasks (label falls back to `Activity_Type__c`, which can be blank).
11. **Three definitions of "pace"**: banner = time-of-day linear 9-17; Goal Progress rows = >= 55%; Today's Plan and My Progress = < 70% is behind. At 8 AM with nothing logged, the banner says "On pace" while every plan row says "Behind pace".
12. Activities Remaining number, caption and drill disagree (section 1a).
13. Partner meetings on the Today tab are scored on the whole week, but the drill for that row (once #1 is fixed) would list today only.
14. `followUpOption` null creates a follow-up Event (`ExternalLoCommunicationService.cls:12`).

### Data-integrity and security

- **No ownership check on `recordId` when logging.** `logActivity` and `logCommunication` insert in SYSTEM_MODE against any `recordId` the client sends. `objectApiName` is trusted from the client rather than derived with `recordId.getSObjectType()`, and when it is blank `validate` skips the allow-list (`ExternalLoActivityLogService.cls:143-146`). A portal user can attach Tasks and Events to any Lead, Account or Transaction in the org, which bumps its `LastActivityDate` and appears in internal activity timelines. Nothing is read back, so there is no data leak, but it is a write-anywhere hole. Fix: derive the type from the Id and check ownership (or the partner link) before insert. `snoozePrompt` has the same gap.
- **Task.Subject is used as data.** Communication outcome lives only in `Subject` and is displayed as "outcome" (`ExternalLoPortalService.cls:493`). Prompt snooze Subjects embed the key. Overdue and drill rows display `Subject`. Org automation appends " on <date time>" to Subject on every update (confirmed on Harold's task). Matching logic is safe: all prompt matching uses `Prompt_Key__c`, never Subject. But any update to a portal task (completing it from the drawer, `completeUpNextItem`, `completeMatchingPromptTask`) will corrupt the displayed outcome and label. Move the outcome to a real field (e.g. `Activity_Outcome__c` on Activity) before go-live.
- **RingCentral association.** The last touch for realtors is `WhatId = account AND OwnerId = me` (`TaskRepository.cls:133-163`). For outside LOs this relies almost entirely on their own portal logs, which set WhatId correctly. RingCentral auto-logged calls, where they exist, are unreliably associated (they may land on a duplicate account or a Lead) and are also owner-scoped to the LO. The number-match approach used in `PipelineCommandCenterController` is not used here. Pre-approval freshness depends solely on RingCentral stamps (section 1b).
- **Lead defer writes `Appointment_Date_Time__c`** (`PerfectDayHomeService.cls:347-361`, SYSTEM_MODE). That is the org's real appointment field, read by the Pipeline Command Center and appointment flows. A "remind me in an hour" would make internal users think an appointment exists. It is unreachable today (#5), but it must not be revived as is. Use a dedicated `Perfect_Day_Deferred_Until__c`.
- Portal-inserted Events will fire org Event automation. `EventTrigger` only queries `Zoom_Meeting__c` on update/delete, and the portal only inserts, so this is safe today. If portal code ever updates Events, the community user needs `Zoom_Meeting__c` object access (it has none).

### Governor and performance

- `getHomeData` runs about 15-21 SOQL queries (profile 1-3, range tasks, overdue, new leads, future events, pre-approvals, realtors, last touch, milestones, goals, under-contract, past-clients, funded, prompt tasks, and up to 5 in the name resolver). This is fine. The bulk test asserts <= 16 (`PerfectDayHomeServiceTest.cls:236`).
- `selectCompletedActivitiesByOwnerForDateRange` has no LIMIT. `activityKeyFor` calls `ExternalLoActivityCatalog.activities()`, which rebuilds the whole CMDT list on every call, one or more times per task, once per period. That is trivial for portal users. `UserRepository` notes that "Internal Home/App pages reuse Perfect Day", and for an internal LO with RingCentral volume (thousands of completed tasks a month) this becomes a CPU and heap concern. Cache the catalog in a static.
- `selectLastActivityDatetimeByWhatIds` pulls up to 5,000 rows to find one max per account. An aggregate `MAX()` would do it.

### Dead code (within this project; no other local project references these)

- `TaskRepository.selectRecentLoggedActivitiesByOwner`, `selectOpenPromptTasksByOwner`, `countOpenOverdueByOwner`.
- `ExternalLoPromptService.getPrompts` (tests only). `ExternalLoActivityPlanService.weeklyTargetsByKey`. `ExternalLoActivityCatalog.categoryForActivityType`.
- `ExternalLOBaselineHelper.ActivityMetrics`, `goalsCompletedCount`, `applyUserGoals`, `weeklyMultiplier`, `monthlyMultiplier` (the legacy channel-goal model). `UserRepository` still selects the five `*_Daily_Goal__c` fields.
- `PerfectDayHomeService.deferUpNextItem(Id, String)` overload. The entire Up Next UI path (#5). `perfectDayHome.js` getters `goalsSummaryLabel` (hardcoded "target 85% by 5:00 PM"), `completeButtonLabel`, `actionStatus`, `upNextActionLabel`, `hasUpNextContact`, `showUpNextLog`, `logGoalCredit`, and about 28 `up-next` CSS rules.
- `RecentLogEntry.subject` and `notes` are sent but not rendered.
- `ExternalLoActivityCatalog.defaultActivities/defaultFocuses` are hardcoded fallbacks that duplicate the CMDT. They are harmless, but they are a second place to update.

### Hardcoded values

15-min lead SLA, 7/14-day realtor cadence, 6-day pre-approval stagnation, 3-day loan staleness, 9-17 workday (`ExternalLOBaselineHelper.cls:9-15`); 2024-01-01 minimum lead date (`PerfectDayHomeService.cls:9`); 13 active loan statuses (`ExternalLOBaselineHelper.cls:31-45`); prompt caps and max 8 (`ExternalLoPromptService.cls:51, 161-165`); 60-day past-client gap, 11-13 month escrow window, 18-month funded lookback; defer times 13:30 and 09:00; follow-up time 09:00; "Good morning" regardless of time (`perfectDayHome.js:195-198`); channel -> `Activity_Type__c` mappings in two separate classes with different channel sets (Activity modal has `open-house` and `meeting`; Communication has `in-person` and `video`).

### Test-class quality

| Class | Verdict |
|---|---|
| `ExternalLoGoalMathTest` | Real behaviour asserts (ceil, round, clamps). The week-bounds test is date-dependent and **fails on Sundays** |
| `ExternalLoActivityLogServiceTest` | Good: asserts category, type, count, subject, prompt close-out, contact rule |
| `ExternalLoPromptServiceTest` | Good on suppression rules, but it **asserts the snooze bug as intended behaviour**. No test ties anniversary to a client |
| `PerfectDayHomeServiceTest` (18 tests) | Mostly behavioural, including a governor/bulk test and pace at 16:00. A large share tests the unreachable Up Next defer/complete path |
| `PerfectDayHomeBuilderTest`, `ExternalLoActivityCatalogTest`, `ExternalLoActivityPlanServiceTest`, `ExternalLoActivityGoalRepositoryTest` | Reasonable behaviour asserts |
| `ExternalLoProgressServiceTest` | One test. Asserts non-null periods plus one back-credit. No period or target math |
| `ExternalLoCommunicationService` | **No dedicated test.** Covered from `ExternalLoPortalCoverageTest` / `ExternalLoPortalServiceTest`, which assert only that validations throw and that ids are non-null. No field values, no Event time |
| `ExternalLoPortalCoverageTest` | A coverage-padding class by name and nature (for example, `getRecordSet('goal-x')` with no assertion) |
| Missing | No tests for `ExternalLoActivityRollupBuilder` directly (covered indirectly), `ExternalLoActivityNameResolver` beyond a smoke test, `TaskRepository`, hyphenated goal drill keys, Sunday dates, or `recordId` ownership |

No TODO/FIXME markers exist in this area. "Half-finished" shows up instead as the unrendered Up Next card, the dual goal models, and the Activities Remaining card.

---

## 8. Manual test checklist

Use a sandbox with a community user holding `External_LO_Perfect_Day_Access` who has completed onboarding (goal rows exist) and owns: 1 New consumer lead, 1 Pre-Approval lead, 1 Under-Contract lead, 1 Past Client lead, 2 realtor person accounts (one touched 10 days ago, one never), 1 loan in Waiting On Loan Officer, 1 loan funded 12 months ago, and 1 open task due 3 days ago. Log in to the portal as that user.

| # | Steps | Expected (current code) |
|---|---|---|
| 1 | Open Perfect Day | Banner shows today's date, first name, Focus, and "0 of 5 activity goals met today, 0%". The pace badge reads "On pace" before 9 AM and "Behind pace" after 9 AM with nothing logged |
| 2 | Check Pipeline snapshot | New leads = 1 (red if the lead is > 15 min old); Realtor follow-ups = 2 (red/orange); Pre-approvals = 1 (orange, stagnant); Milestone loans = 1; Overdue tasks = 1 (red, "Oldest is 3 days past due") |
| 3 | Check Today's Plan | 5 rows; Partner meetings reads "of N meetings this week", the rest "today". Targets = ceil(weekly / workdays) |
| 4 | Today's Plan > Realtor outreach > Log. Leave channel Call, count 3, pick realtor A, Save | Toast "3 touches logged". Row shows 3 of X. Recent activity shows "Realtor outreach, {realtor A}, today, x3". Realtor follow-ups drops to 1. In SF: one Task, Completed, Category Realtor_Outreach, Type Call - Active Agent, Count 3, WhatId = account, Subject "+3 touches" |
| 5 | Banner > Log activity, choose Consumer convos, no contact, Save | Error "Choose a contact for Consumer convos." |
| 6 | Log activity, Social posts, no contact, Save | Succeeds. Task has no Who/What and **Type = Call - Active Agent** (known issue) |
| 7 | Count stepper: type 99, then 0 | Clamped to 50 / 1 |
| 8 | Prompts: find the "Check in with {under-contract lead}" card, Log, Save | Card disappears and **never returns** for that lead. Task has `Prompt_Key__c = under-contract:{id}` |
| 9 | Prompts: click Tomorrow on the partner card for realtor B | Toast "Saved for tomorrow". Card gone. Check SF: open Task due tomorrow, Subject "Follow up — recurring-partner:{id}". Set its ActivityDate to 2 days ago in SF: the card **stays hidden** and Overdue tasks goes up by 1 showing the raw key (known bug) |
| 10 | Log a second prompt snooze on the same key | "This prompt is already scheduled for later." with no second Task |
| 11 | If any loan funded this calendar month, open prompts | The past-client card says "Closing anniversary is this month" regardless of the client (known bug) |
| 12 | Goal Progress: switch Today / This week / This month | Rows re-score; week uses the weekly target, month uses round(weekly x days / 7). Today has an extra "Overdue tasks, target 0" row |
| 13 | Click a Goal Progress category row | Drawer titled "Goal - today" with **no records** (known bug #1). Expected after fix: the category's completed tasks |
| 14 | Click Overdue Tasks card | Drawer lists the overdue task(s). Completing one moves it to Completed with ActivityDate = today (if the drawer supports it) |
| 15 | Click Activities Remaining | Number = goal minus done, but the drawer lists open tasks due today or earlier (known mismatch) |
| 16 | Leads page > a lead > Log communication: Call, "Left a voicemail", note "tried", follow-up In 3 days | Toast "Call logged successfully." SF: completed Task "Call - left voicemail", Type Call - Active Agent, WhoId = lead, **no category**; Event "Follow up" 3 days out at 9:00. Perfect Day: **Realtor outreach** +1 (known), and the lead leaves "New leads need contact" (future event) |
| 17 | Same, but follow-up "No follow-up" | Lead stays in "New leads need contact" |
| 18 | Communication modal: note "ab" | "Add a short note so the activity history stays useful." |
| 19 | Communication modal header | Phone/email strip is **absent** even when the lead has both (known bug) |
| 20 | Confirm no message is sent | No SMS or email reaches the lead's phone/inbox. Only Task/Event records exist |
| 21 | Edit the logged Task's Description in SF, then view the lead's activity history in the portal | The outcome now reads "Call - left voicemail on {date time}" (Subject rewrite) |
| 22 | My Progress: Week / Month / Quarter | Same completed counts as Perfect Day week/month. Early in a period every row is "Behind pace" |
| 23 | Refresh button, and returning to Home after logging on another page | Numbers update without a full page reload |
| 24 | Run all tests in this area on a Sunday (or set the org date) | `ExternalLoGoalMathTest.weekBoundsAreMondayThroughSunday` fails (known bug #2) |
| 25 | Log in as an internal admin and report on Task.Activity_Category__c | Field not available (FLS only in the portal permset) |
| 26 | Security: from the browser console, call `logActivity` with the Id of a lead owned by someone else | Currently succeeds (write-anywhere). Expected after fix: rejected |
