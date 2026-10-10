# LO Recruiting import — review (2026-10-09, nothing written yet)

Source: 609 rows (589 Recruit List + 20 Possible In House). Detail per person: scratchpad `prep/keepers.json`.

## Step 1 (DONE, prod)
14 Lead fields, Recruit Stage values on the Loan Officer RT, LO Recruiting permset (Fred, Adam, Chris), LeadLoanPartnerAssignmentService skips Loan Officer RT.

## What the import will do
| | Count |
|---|---|
| Already in Salesforce (match by NMLS, all on Loan Officer RT) | 446 people / 594 leads |
| Duplicate copies merged away (Salesforce Lead merge keeps all activity) | 148 (125 people x2, 10 x3, 1 x4) |
| Brand-new Loan Officer leads | 163 |
| Keepers whose phone/email/company/etc. change -> old values saved in a note | 361 |
| Owner change Ben/Alex -> Fred | 589 leads incl. merged copies |

Keeper = copy with most calls/tasks/events (735 total, incl. archived), then newest. Only 3 merges have activity on the losing copy; it moves to the keeper.

Fields changed most: Website 253, Company 159 (mostly moved lenders), City 138, LinkedIn 86, First/Last name 49, Email 48.

## Stage mapping result (446 existing)
Contacted 307 · Not Now 99 · New 34 · Met 5 · Conversation 1. New leads: New 163.
Extra mappings: Nurturing -> Not Now; Scheduling Meeting -> Conversation; Nurturing - Meeting Complete -> Met; Contact Attempt 7 -> Contacted. When copies disagree, the most advanced stage wins.

## Needs a decision
1. "Active" (Ben's status): Karen Brown 1648127, Michelle Stapleton 2167437, Deanna Rivera 327112 (no activity), Benjamin Dykes 472128 (last activity 2025-01-29).
2. Adam already owns 5: Andrew Sassen (Met), Charles Eelman (Met), Jake Labelle (Met), Michael Galante (Conversation), Courtney Douglas (Not Now).
3. Next Touch seeding for the 307 Contacted.

## Safety
- Inserts run with LeadRecycleContext.silent -> no owner-notification emails, no Loan Partner, no attribution.
- No Loan Partner on any matched lead; none flagged Do Not Call / opted out.
- ActiveCampaign: no package job since 2025-11-21 (sync dormant).
- County "Out of State" (restricted picklist) left blank.

## RESULT (executed 2026-10-09)
Chris's calls overrode the stage plan: ALL 609 start at Recruit Stage New + Lead Status New, owner Fred (incl. Adam's 5). Next Touch blank.
- 148 duplicate copies merged into 446 keepers (Recycle Bin, MasterRecordId set; 0 errors).
- 446 updated, 163 inserted (silent: no owner emails, no Loan Partner), 383 "Previous contact info" notes.
- Daniel Deville 2447655 inserted WITHOUT email (sheet had truncated "daniel.deville@38").
- Tag: Recruit_List__c = 'FL Retail 2026-10'. 20 Possible In House.
- Temp static resource LO_Recruit_Import deleted. Import scripts: session scratchpad apex/merge.apex, apex/import.apex.
