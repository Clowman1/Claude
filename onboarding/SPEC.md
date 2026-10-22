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

**P3: branch, renewals, offboarding** (the NV hire is ~1 month out)
1. Branch template: from the xlsx sub-tabs + NV Division of Mortgage Lending branch license + NMLS branch sponsorship.
2. Load current active staff (list reviewed first), then generate the 2026 renewals. Renewals generate every year on Oct 15: one task per licensed state + NMLS CE + BSA/AML + handbook re-acknowledgment.
3. Offboard button: xlsx offboarding items + deactivate the SF user, reassign Leads/Transactions, RingCentral/ARIVE/UWM removal, termination notice, KB Tech Outlook shutdown.

## Later / not now
Assignees outside the three, the new hire's own self-service view, Teams notifications, a permission-set bundle offer on user link, OneDrive links.

## To verify at build time
Whether the Default BusinessHours has the Holiday records attached (TRID may be the one that has them).
