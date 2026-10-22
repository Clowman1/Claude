# LO Workspace upgrades (grilled + shipped 2026-10-21)

Code 0AfQi000001VJqbKAG (165/165) + permission set 0AfQi000001VJsDKAW (LoWsSearchService access).
Deploy lesson: never deploy External_LO_Access in the same package as tests that assign the External_Loan_Officer
group — the group recalculates ("Updating") and every such test fails. Permset goes in its own deploy.

Decisions: Q1a credit by who was contacted; Q2a/Q13a outbound RingCentral calls+texts only (RC records no
answered/missed signal); Q3a 15-minute count-once; Q5b realtor production per LO; Q8a anniversary prompts + rate
filter (default 6.5%, LO types own rate); Q9a pre-approval expires at 90 days; Q11a search own records only.
Skipped: unlogged-call queue, tag-your-referrers, nurture call list, bulk actions, away mode.

| Feature | Where |
|---|---|
| Perfect Day credit: explicit workspace category wins; else open consumer lead → consumer-conversation, closed-loan borrower → past-client-call, realtor (Group__pc / BD_Industry__c / tag / Realtor-RT lead) → realtor-outreach, else none. Contact from WhoId/WhatId, else the dialled number. Outbound RC only; RC desktop duplicate + manual log within 15 min count once; emails earn no credit. | `LoWsActivityCreditService` (new), `ExternalLoActivityRollupBuilder.activityKeyFor`, `TaskRepository` |
| Oversight "No activity 7d" pill | `LoWsOversightController`, `loWsOversight` |
| My Realtors: referrals / closed loans / last referral per tag (this LO only; Referral_Source__c is a Contact → PersonContactId), producers first in "due", Producers chip | `ExternalLoPortalService.getPartners/applyProduction`, `externalLoRealtors` |
| Anniversary prompt 7 days before through the day, key `anniversary:<accountId>:<year>` | `ExternalLoPromptService.anniversaryPrompts` |
| Past Clients rate (Rate_1st_TD__c) + "Rate at or above X%" + Start call list | `LoWsPartnerTagService.myClosedLoans`, `externalLoPastClients` |
| Pre-approval "Issued N days ago" / Expired ≥ 90 days (Pre_Approval_Date__c), Expired chip, Re-issue letter (opens leadPreApprovalLetter in place), Move to Nurture ('Nurture - Preapproval') | `ExternalLoPortalService` PreApprovalRow, `externalLoPreApprovals` |
| Header search: own leads, borrowers/past clients, tagged partners, loans; name/email/phone (full or last 4); 5 SOQL per search; LO Workspace only | `LoWsSearchService` (new), `loWsSearch` (new), `externalLoPortalShell` |

Heads-up at go-live: 157 of 225 open pre-approvals are already past 90 days. Not verified in a browser.
