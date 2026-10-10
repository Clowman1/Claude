# LO Recruiting — grilled 2026-10-09 (nothing built yet)

Source list: `FL-Retail-LO-Recruit-List-FINAL-2026-10-08.xlsx` — Recruit List (589) + Consumer Direct (20). Excluded (96) and County Coverage NOT imported.

## Org facts found (prod, 2026-10-09)
- Lead record type `Loan_Officer_Lead_Record_Type` (012AJ0000004JojYAE): 3,897 leads. Ben Bondarevsky 2,886, Alex Saludes (inactive) 996. NMLS__c / LinkedIn__c / Instagram__c / Company exist.
- 451 of 609 rows already match: 446 NMLS -> 594 LO leads (≈150 in-org dupes); 45 NMLS on old Person Accounts (John Swift 2018 set).
- Legacy, leave alone: Recruit__c (229, 2020-21), Recruit_Account RT (65), BizDev_Expansion RT (23).
- Candidate Person Account RT -> flow Candidate_Checklist_Creator builds the onboarding checklist.
- Lead custom fields 217/500. OWD Lead Private. No assignment/auto-response rules.
- Insert traps: ManualLeadOwnerNotification emails owner per lead (use LeadRecycleContext.silent); LeadLoanPartnerAssignment stamps owner's Loan_Partner__c (Adam has one, Fred none). ActiveCampaign Lead sync: UNVERIFIED — check before import.
- Fred 005Qi00000iOSkzIAG; Adam 005f2000009BuuaAAC (System Administrator, Management role).

## Decisions
| # | Decision |
|---|---|
| Adam | Co-worker, full edit. One recruiter = Lead Owner. Day one: everything owned by Fred; Adam takes as he engages. |
| Scope | Import all 609. The 20 Consumer Direct get `Possible In House` checkbox (also hand-editable). |
| Home | Lead, existing Loan Officer record type. |
| Ben | Done recruiting. His leads matching the list -> Fred, history kept. His other ~2,400 untouched. |
| Tab scope | Only LO leads owned by a recruiter (Fred/Adam); tagged `Recruit List = FL Retail 2026-10` for future lists. |
| Stages | New field Recruit Stage: New, Contacted, Conversation, Meeting Set, Met, Offer Out, Hired, Not Now, Not Interested. Lead Status untouched. Auto: first touch New->Contacted, Zoom/event -> Meeting Set. Met/Offer/Hired manual. |
| Legacy map | New->New; Contacted/Call Back, Contact Attempt 1-6 -> Contacted; 30 Day + Follow Up -> Not Now; Meeting Set -> Meeting Set; Meeting Complete -> Met; "Active" -> list for Chris to classify. |
| Dupes | Merge to one lead per NMLS before import (keeper = most activity, then newest). Person Account matches ignored. |
| Overwrite | List wins on every field; replaced values saved to a note "Previous contact info, replaced <date>". |
| Company switch | Keep RETR company; show warning chip with flag text; recruiter fixes by hand. |
| Fields | All "Keep" columns + Segment-free; derived: Possible Company Switch, Remote LO, Possible In House, Recruit List. Volume always shown with period ("$49.9M · 12mo"). Agent partner = text only. |
| Cadence | Next Touch date set by Log touch: New today; Contacted +3 then +7; Conversation/Meeting Set/Met/Offer +3; Not Now +90; Not Interested none (sets DoNotCall + HasOptedOutOfEmail). |
| UI | New "LO Recruiting" tab (permset-gated), reusing BD pieces. Today feed: Due/overdue, Fresh call queue (New by volume desc), Meetings this week. Recruiter filter Mine/Fred/Adam/All. Split workspace + board toggle. |
| Workspace | Header (name, company, NMLS, volume·period, Branch Mgr badge, switch chip); Call/Text/Email/Zoom/Log touch/Mark Hired/Not Interested; LinkedIn/IG/Website/RETR links; office, county, recent agent partner; full timeline incl. legacy history. |
| Hired | Creates Candidate Person Account (fires existing checklist flow), linked from the lead. |
| Outreach | 1:1 only (call, Twilio text, email, Zoom, invites). No bulk email/SMS. No email templates for now. |
| Stats | KPI strip + funnel on the tab (by recruiter) + "LO Recruiting" dashboard in Loan Officer Lead Reports folder. Fred's BD home stays partner-only. |
| Mobile | Not yet. |
