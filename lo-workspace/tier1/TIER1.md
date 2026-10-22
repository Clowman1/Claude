# LO Workspace Tier 1 fixes (2026-10-20)

Source of findings: the 2026-10-20 deep-dive review. Decisions Q1–Q8 grilled the same day.
`ref/` = prod copies retrieved before editing; `force-app/` = edited; `deploy1/`, `deploy2/` = what shipped.

## Live
| Deploy | Id | What |
|---|---|---|
| Ops | (abort) | Duplicate `LoWsAutoTextDaily` CronTrigger 08eQi00001G7l6w aborted: borrowers got every auto-text twice Oct 14–19. 08eQi00001G7Eqw remains. |
| Batch 1 | 0AfQi000001VDZtKAO | getLeadDetail/getLoanDetail not cacheable (stale detail pages); "30 Day + Follow Up" blocks takeover (Q1); COC savepoint/rollback; Mark complete / Tomorrow on every Task row in Up Next "Open all" + record drawers, overdue oldest first (Q3); after Convert: lists/badges refresh + loan opens with "Fill Submission form" banner (Q5). |
| Q6 step 1 | 0AfQi000001VDbVKAW | Permission set `RingCentral_User` (28 rcsfl classes) deployed + assigned to Manny. |
| Batch 2 | 0AfQi000001VDrdKAG | Auto-texts check every opt-out flag (Lead: LoWs off, Opt_Out_from_SMS_Automation__c, smagic, DoNotCall; Account: LoWs off, SMS_Opt_Out__c, smagic __pc, PersonDoNotCall; converted lead's opt-out) + newest STOP/START keyword texted to any Reach number (Q7, Q8a); Communications `without sharing` after RecordAccessGuard so other users' calls show (Q2); My Leads `active` / `nurture` server scopes, server search on name/email/phone, Nurtured Load more by 200, 300 ms search debounce (Q4). |
| Batch 3 | 0AfQi000001VDtFKAW | Org-wide STOP handler (Q8b): trigger TwilioStopKeyword → Queueable TwilioStopKeywordService sets Lead Opt_Out_from_SMS_Automation__c + smagic flag and Account SMS_Opt_Out__c on the linked record and every open Lead / Person Account with that number. Twilio_Message PB left active. Also: Up Next Open all Tomorrow button was white-on-white, fixed. |
| Q6 step 2 | 0AfQi000001VDurKAG | External Loan Officer Profile grants 0 Apex classes (was 1,329). Verified every class an LO Workspace LWC imports is still granted via permsets (only LoWsOversightController / LoWsOnboardingGateService are not, both manager-only and never on the profile). |

## Not verified in a browser
Batch 1 and 2 UI changes were validated by tests only; check in LO Pilot: Open all → Mark complete; drawer task rows; Convert → banner; Nurtured → Load more; search by phone.
