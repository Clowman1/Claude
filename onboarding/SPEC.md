# People: onboarding, renewals, offboarding, branches

Spec from the grill of 2026-10-21/22 (decisions in `GRILL.md`). Users: Chris, Bianca, Adam.

## Data model
`Checklist__c` is already taken (submission quality), so every new object is prefixed `People_`.

| Object | Purpose | Key fields |
|---|---|---|
| `People_Employee__c` | One per person, permanent | First/Last, Work Email, Personal Email, Role (LO, Branch Manager, Processor, Closer, Opener, Operations/Admin, Manager), Work Arrangement (In-Office/Remote/Hybrid), Manager (User), Branch, Start Date, Status (Candidate/Pre-Start/Active/Offboarding/Terminated/Withdrawn), NMLS ID, Licensed States, User (lookup), Termination Date/Reason. **Encrypted text:** DOB, Home Address, Personal Phone, Emergency Contact |
| `People_Branch__c` | Branch onboarding | Name, State, Address, Branch NMLS ID, Branch Manager (User), Target Open Date, Status (Planning/Licensing/Open/Closed) |
| `People_Template_Task__c` | Master list, editable by all three, field history on | Checklist Type (Onboarding/Renewal/Offboarding/Branch), Order, Phase, Subject, Description, Default Assignee (User), Led By (text), Offset (business days), Roles (multi, blank=All), Work Arrangement (multi, blank=All), Optional, Email Template, Send To (New hire / Manager / fixed address), Exam Section (Regulatory/Systems/Documentation), Active |
| `People_Checklist__c` | One run of a template | Employee or Branch, Type, Renewal Year, Status, Signed Off By/At (locks it) |
| `People_Task__c` | Generated task | Checklist (master-detail), copied template fields, Due Date, Assigned To, Status (Open/Done/N/A), Completed By/At (immutable once set), Notes, Email Sent At |

There are no files. Documents stay in OneDrive. There is no SSN field.

## Access
- All new objects are Private. The `People_Admin` permission set (CRUD + View Encrypted Data + tab + app) is assigned to Chris, Bianca and Adam.
- No profile edits, because of the renamed-profile trap.
- Encryption only deters View-All admins (Jamie Martinez, Brandon Brotsky, "Salesforce Updates"). Reviewing their admin access is a separate item.

## Behaviour
- **Generate:** a new Employee gets the Onboarding template tasks filtered by Role and Work Arrangement. Optional tasks show as "add?" toggles. Due date = Start Date ± offset in business days (weekends and the org Holidays are skipped).
- **Start date moves:** open tasks recalculate and completed tasks keep their dates. A warning shows if any open task lands in the past.
- **Status:** moves on its own: Pre-Start when the offer task is Done, Active on the start date, Terminated when the offboarding sign-off is done. Withdrawn closes all open tasks.
- **Digest:** 9 AM on weekdays, only to Bianca and Chris, listing their own due and overdue tasks. Skipped when there is nothing.
- **Template edits** apply only to checklists created afterwards.

## Screens (one `People` app + tab)
- **Board:** hire cards (initials, role, start date, progress ring, overdue count). Filters: Onboarding / Renewals / Offboarding / Branches.
- **Timeline:** phases Pre-Start / Day 1 / Week 1 / 30 / 90. Each task has a check-off, reassign, notes, and a Send button (phase 2).
- **Template editor:** drag to reorder, plus the tags.
- **New Employee and Offboard modals.**

## Phases
**P1: core**
1. Publish a clickable mockup artifact for review before any code is written.
2. Objects, permission set, app and tab.
3. Generator with business-day logic.
4. Board, timeline and template editor.
5. Seed the master list from the CSV (53 tasks).
6. 9 AM digest.
7. Remove the old build:
   - Back up to CSV.
   - Deactivate `Candidate_Checklist_Creator`.
   - Check the 29 Candidate Accounts for links; Chris confirms the delete.
   - Delete the 41 checklists, the Candidate RT, `Candidate_Record_Page`, the 3 Candidate checklist configs + items, and the object.
   - **Keep** `NCS_Checklist`, `ChecklistController` and the Aura `Checklist` bundle (Transaction checklists use them).

**P2: email, sign-off, exams**
1. SF email templates from Bianca's docx (PH-3 Offer, PH-4 Background info, PH-7 Paychex, PH-8 NMLS confirm). They are sent as the clicking user, and sending completes the task. Merge field "[2 days from send date]" = +2 business days.
2. PH-6, PH-9, PH-10, Day 1 Instructions and Team Announcement go out through DocuSign. Those tasks are ticked manually (Send To still records the recipient).
3. Compliance sign-off: Bianca, with Chris as backup; click-attestation; locks the checklist.
4. Exam PDF in the TN DFI layout, saved to the Employee record.
5. User auto-link by work email. Auto-complete "Set up Salesforce user". Sync NMLS and Licensed States to the User.

**Status (2026-10-22):** P1 and P2 are live in prod.
- P2 deployed: People_PH_3/4/7/8 classic templates (folder "People Onboarding") with Send buttons.
- Sign-off by Bianca or Chris, then the exam PDF (`PeopleExamPdf`) is filed on the Employee.
- `PeopleUserSync` + `PeopleUserTrigger` link the User by work email.
- Change from the grill: the 25/30/90-day items count **calendar days** (rolled off weekends/holidays) and email the assignee 7 days before and on the due date (`Remind__c`).

**P3: branch, renewals, offboarding** (the NV hire is ~1 month out)
1. Branch template: from the xlsx sub-tabs + NV Division of Mortgage Lending branch license + NMLS branch sponsorship.
2. Load current active staff (list reviewed first), then generate the 2026 renewals. Renewals generate every year on Oct 15: one task per licensed state + NMLS CE + BSA/AML + handbook re-acknowledgment.
3. Offboard button: xlsx offboarding items + deactivate the SF user, reassign Leads/Transactions, RingCentral/ARIVE/UWM removal, termination notice, KB Tech Outlook shutdown.

**P3 status (2026-10-22): live.**
- Board tabs: Onboarding / Renewals / Offboarding / Branches / Staff.
- Each employee or branch page switches between its checklists.
- **Offboard** button (last day + reason) → Offboarding status, with open Lead/Transaction counts to hand over. Sign-off → Terminated.
- **Renewals:** anchored to Dec 31, one task per licensed state for NMLS submit and approve, plus CE, BSA/AML and handbook. They open every Oct 15 (`PeopleDaily`), or with the "Open 2026 renewals" button.
- **Branches:** New Branch / Edit details; the checklist starts once a target open date is set, and later date moves re-date it.
- Templates seeded by `people/scripts/phase3-templates.apex`: Renewal 6, Offboarding 13, Branch 31.
- **Staff load:** `staff-load/proposed-staff.csv` (23 people, roles guessed from titles) is waiting on Chris's review; `staff-load/load-staff.mjs` loads it, then opens the 2026 renewals.

**P4: employee management** (grilled 2026-10-22, decisions P4-0 to P4-20 in GRILL.md). Admin-only: Chris, Bianca, Adam.

1. **Add existing employee** (Staff tab). No onboarding checklist, Salesforce user optional (many staff never log in), straight to Active. If the year's Annual Compliance has already opened, it opens for them too.
2. **HR fields on People_Employee__c:**
   - Job: Title, Department, Employment Type (W-2 Employee / 1099 Contractor), Schedule (Full-time / Part-time), Hire Date. The work anniversary is derived from Hire Date.
   - Existing fields kept: manager, branch, contact, and the encrypted DOB/address/phone/emergency contact.
   - Shown on the employee page in Job / Contact / Compensation / Licenses sections.
3. **Compensation history:** `People_Compensation__c`, a child of Employee with effective-dated entries.
   - Fields: Effective Date, Pay Type (Salary / Hourly / Commission only / Salary + Commission / Per-file), Base Amount + Per (Year/Hour), LO Comp (bps), Per-Loan Flat, Bonus Plan, Notes.
   - The newest entry is "current". Plain numbers: People_Admin only; full admins can read them, which is acceptable.
4. **Licenses:** `People_License__c`, one per employee per state.
   - Fields: State, License Number, Status (Active / Pending / Inactive / Expired), Issue Date, Expiration Date, Sponsorship (Sponsored / Pending / Removed), Last Renewed.
   - The employee's Licensed States is recalculated from Active/Pending licenses, then copied to the User (existing sync). NMLS ID stays on the employee and is copied to the User. Person Accounts are not used.
   - Backfill: one Active license per state for the 23 loaded staff, numbers blank.
   - Ticking "Confirm {STATE} renewal approved" sets that license's Last Renewed = today and Expiration = Dec 31 next year.
5. **Annual Compliance {year}** replaces "Renewal" in the UI and checklist names (Type value stays Renewal).
   - Contents: CE (Nov 16), per-state submit (Dec 1) and approve (Dec 31), plus BSA/AML, Fair Lending, GLBA privacy, IT security and handbook (Dec 1). No anti-harassment.
   - Bianca ticks each item; an optional certificate link goes in the notes.
   - The 23 open 2026 checklists are renamed, and Fair Lending, GLBA and IT security are added to them.
6. **Compliance tab:**
   - A grid of people against Annual Compliance items (done / due soon / overdue / n/a).
   - Licenses expiring within 60 days.
   - Missing data.
   - CSV export of the grid for examiners.
7. **Missing-data highlighting (in-app only):**
   - A board banner with "N employees need information".
   - An amber marker on Staff rows.
   - On the employee page, a list of exactly what's missing, with the empty fields highlighted.
   - Missing means: no hire date / department / employment type / emergency contact; or, with an NMLS ID, a license with no number or expiration date.

Not now: self-service, background re-checks, annual reviews, anti-harassment.

**P4 status (2026-10-22): live.** `PeopleHrController` + `People_Compensation__c` + `People_License__c`; Compliance tab; Add existing employee; missing-data banner, Staff markers and employee page list. Migration `people/scripts/phase4-migrate.apex`: 32 licenses (numbers/expirations blank), +3 Annual Compliance items on all 23 open 2026 checklists (renamed), 58 per-state tasks tagged. 24 employees currently flagged for missing info (no hire dates, departments, employment types, emergency contacts, license numbers yet).

## Later / not now
Assignees outside the three, the new hire's own self-service view, Teams notifications, a permission-set bundle offer on user link, OneDrive links.

## To verify at build time
Whether the Default BusinessHours has the Holiday records attached (TRID may be the one that has them).
