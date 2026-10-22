# LO Workspace Tier 2: counts that agree (2026-10-20)

Deployed 0AfQi000001VECbKAO (validated 157/157). `ref/` = prod before, `force-app/` = edited, `deploy/` = shipped.
Decisions Q1–Q7 grilled 2026-10-20, all "recommended".

| # | Rule now (one definition everywhere) | Where it lives |
|---|---|---|
| Q1 | Realtor follow-ups due = my tagged realtors (no Other Contacts), my last touch 7+ days ago or never. Snapshot, badge, drawer, partner prompts. | `ExternalLoPromptService.loadDueRealtors` → `ExternalLoPortalService.getPartners('due', …, 'realtor')`; `realtorFollowUpUrgency` now `>= 7` |
| Q2 | Pre-approvals badge / drawer / "Open My Pre-Approvals" = weekly touch due. The tab still lists all. | `getNavBadges`, `getRecordSet('pre-approvals')`, `portalRecordDrawer` LIST_ROUTES |
| Q3 | Pace: expected % = (Mon–Fri workdays before today + today's share of 9–5) / workdays in period; on pace ≥ 90% of expected; ahead = goal met; weekend day never behind. | `ExternalLOBaselineHelper.expectedPercentForPeriod / paceFor / dayPaceStatus`; CategoryScore.pace; LWCs read `pace` |
| Q4 | Score caps each category at its goal; "Perfect day complete" only when every category met. | `ExternalLoActivityRollupBuilder`, `PerfectDayHomeService` |
| Q5 | Weekly touch = call/text Task on the lead, RingCentral call/text by number (any Reach user), meeting, or email on the lead from the borrower or a Reach user's own address (org-wide reachus@ excluded). Email activity Tasks skipped. Address-only email match dropped (table scan). | `LoWsTouchService` |
| Q6 | New leads need contact = New, created 2024+, not deferred, no future meeting. Snapshot, badge, drawer. My Leads > New still lists all. | `PerfectDayHomeService.newLeadsToContact` |
| Q7 | Oversight closed = Funding / PC Review / Post-Closed with Funding_Date__c this month; active excludes them; roster cap 40 with a visible note. Past Clients show/sort Funding_Date__c, falling back to Closing_Date__c (2/3 of old closed loans have no Funding_Date__c; every loan closed in the last 6 months has it). | `LoWsOversightController`, `LoWsPartnerTagService.closedOn` |

Also: banner "complete" casing; snoozes expire and never count as overdue (re-snoozing an expired one moves it to tomorrow); "Activities left today" card scrolls to Today's Plan; returning to Perfect Day reloads home + badges; logging on a realtor page refreshes the list.

Not verified in a browser.
