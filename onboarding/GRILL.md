# Employee Onboarding tool: grill log

Started 2026-10-21. Replaces the Nimbus Candidate Checklist build. Seed list: `C:\Users\ChristopherLowman\Downloads\Onboarding Checklist - Salesforce Import.csv` (53 tasks, 5 phases).

## Existing build (to remove)
- `Candidate_Checklist__c` (41 recs, 48 date-stamp fields), Account RT "Candidate" (29 Accounts), active flow `Candidate_Checklist_Creator`, FlexiPage `Candidate_Record_Page`.
- 3 `ChecklistConfiguration__mdt` (Onboarding_Checklist, Investor_Credentials, ARIVE_Account_Setup) + their items.
- KEEP the checklist engine (`NCS_Checklist`, `ChecklistController`, Aura `Checklist`): Opener / Post-Closing / Submission Quality checklists on Transaction use it.
- Onboarding PH-x email templates are NOT in Salesforce (no EmailTemplate match).

## Decisions (round 1)
1. New hire = its own record, User linked later.
2. Assignees = Chris, Bianca, Adam only.
3. Base "All" + role tracks; tasks generated per hire, editable per hire.
4. Due dates = offset from start date; phases Pre-Start / Day 1 / Week 1 / 30 / 90.
5. Offboarding in the data model; onboarding ships first.
6. Sensitive data (DOB, address, background, I-9) MAY live in SF, visible only to Chris/Bianca/Adam.
7. Dedicated Onboarding tab, LWC board + hire timeline + template editor; permset-gated.
8. Daily digest email of due/overdue tasks (no bell).
9. CSV above is the seed.
10. Delete old data.
11. No Candidate Accounts; hire lives on the onboarding record.
12. Branch Onboarding template type: yes. First use: a Nevada branch + a Nevada employee.
13. Immutable completed-by/date, compliance sign-off, regulator PDF; for exams AND renewals.

## Decisions (round 2)
14. Outside-the-three tasks (Angelina, managers) are owned by Bianca/Chris with a free-text "Led by".
15. One master template; tasks tagged Roles (multi, blank=All) + Work Arrangement (blank=All) + Optional flag. Roles: Loan Officer, Branch Manager, Processor, Closer, Opener, Operations/Admin, Manager.
16. Rebuild PH-x templates as SF email templates; Send button on the task completes it with timestamp.
17. Business days (skip weekends + org Holidays; 11 recurring Holiday records already exist).
18. Permanent Employee record; child checklists Onboarding / Annual Renewal / Offboarding; renewals generated Oct 15 yearly.
19. Load all current active staff as Employees (list reviewed by Chris first).
20. Branch template drafted from xlsx sub-tabs + NV licensing items; Employee has Branch lookup.
21. Back up to CSV; check the 29 Candidate Accounts for links; Chris confirms the delete.

## Decisions (round 3)
22. Classic encrypted fields (no Shield in org: TenantSecret unsupported); View Encrypted Data only for the three. Other View-All admins: Jamie Martinez, Brandon Brotsky, "Salesforce Updates" (review / Nimbus cut-over).
23. Store DOB, home address, personal email/phone, emergency contact. NO files (OneDrive holds docs). No SSN.
24. Compliance Approver = Bianca, backup Chris. Click-attestation; sign-off locks the checklist.
25. Exam PDF mirrors TN DFI checklist; saved to the Employee record.
26. Offboard button; tasks from xlsx offboarding + deactivate SF user, reassign Leads/Transactions, RingCentral/ARIVE/UWM removal, termination notice, KB Tech Outlook shutdown.
27. Licensed States multi-select; one renew task per state + shared tasks.
28. Auto-link User by work email + auto-complete "Set up Salesforce user"; permset bundle offer = phase 2.
29. Digest 9 AM weekdays, Bianca + Chris only.
30. App/tab name: People.

## Decisions (round 4)
31. Template bodies from Bianca: `onboarding/Onboarding Emails - Salesforce (Final).docx` (4 templates: Offer/PH-3, Background info/PH-4, Paychex/PH-7, NMLS confirm/PH-8).
32. Send as the clicking user (Bianca's address).
33. No OneDrive links (skip).
34. Master template editable by all three; applies to new hires only.
35. Start date change recalcs open tasks only; warn if any land in the past.
36. NV hire ~1 month out (~late Nov 2026): phase as proposed (P1 core, P2 emails/sign-off/PDF/user link, P3 branch/renewals/offboarding/staff load).
37. Generate 2026 renewals right after the staff load.
38. Employee is master for NMLS/Licensed States; syncs to User when linked.

## Facts
- User already has `NMLS__c` (Text) and `Licensed_States__c` (multi-select).
- Only OWEA: reachus@reachhomeloans.com.
- PH-x template bodies not found anywhere searchable (likely Bianca's Outlook).
