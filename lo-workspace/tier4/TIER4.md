# LO Workspace post-fix review fixes (2026-10-21)

Deployed 0AfQi000001VJgvKAG (validated 138/138). `ref/` = prod before, `force-app/` = edited.

- Validation rule `Lead_Rating_and_Loan_Amount_Fields_requr` now fires only on create, Status change or Loan_Amount__c change. Before, an External LO's amountless Pre-Approval lead blocked every later save by anyone without External_LO (Loan Partners, Zapier, flows, the STOP handler).
- `LoWsTouchService`: RingCentral-by-number Task query looks back 30 days (unindexed number fields; 90 days = ~57k Task rows scanned).
- `LoWsAutoTextService.optedOut`: if the STOP lookup on TwilioSF__Message__c (unindexed, ~155k rows) ever throws, fail closed (skip those texts, Custom_Log__c 'LoWsAutoText') instead of failing the Lead/Transaction save.
- `TwilioStopKeywordService`: opts out the linked record plus records whose TEXTING number (mobile, or main phone when no mobile) matches — no longer every record sharing an office/landline main phone. Failures → Custom_Log__c Source 'TwilioStopKeyword'.
- `LeadRepository`: LO Workspace nurture page excludes 30 Day + Follow Up on the server so Load more doesn't vanish early (portal keeps it).
- Mobile menu tabs: the shell remembers its own tab (`portalHomePageRef(..., tabApiName)`), so navigating inside My Leads etc. no longer jumps to Perfect Day.
- `leadQuickActions`: External LOs (custom permission) see Convert at any status; internal LOs keep Pre-Approval / Under Contract.
- CSV import: multi-value Purpose ("Purchase;Refinance") maps each part.
- `perfectDayHome`: removed the duplicate refresh (wire cacheBust already refetches on a new key).

Still to do: Fix 2 (activity credit by who was contacted + RingCentral + 15-min dedupe) — part of the upgrade grill (Q1–Q3).
