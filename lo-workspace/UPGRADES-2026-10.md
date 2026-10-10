# LO Workspace upgrades — decisions (grilled 2026-10-08)

U1 (0AfQi000001UIzpKAG), U2 (0AfQi000001UJJBKA4), U3 (0AfQi000001UJsfKAG), U4 (0AfQi000001UK0jKAG), U5 (0AfQi000001ULfxKAG + 0AfQi000001ULjBKAW), U6 (0AfQi000001ULmPKAW), U7 + Volume v2 (0AfQi000001UMAbKAO) deployed 2026-10-08; board label hotfix 0AfQi000001UK7BKAW. U8 not built.
U8a (fields 0AfQi000001UMIfKAO + Is_Recycled 0AfQi000001UMLtKAO) and U8b (guards 0AfQi000001UMNVKA4, flows activated 0AfQi000001UMP7KAO) deployed 2026-10-08; U8c (the recycle) deployed 2026-10-09 (0AfQi000001UNppKAG); Zap 169907490 filter published v20. Plan: UPGRADES-2026-10-BUILD-PLAN.md.

1. **Task reminder pop-up** off for External LOs: code never sets IsReminderSet on their Tasks + user preference default off.
2. **Credit expired** badge/filter/label removed from LO Workspace entirely. Do not read `Credit_Expiration_Date__c` (not reliable).
6. **Needs update** = Status__c "Waiting On Loan Officer" only. Remove all stale-3-days logic and labels.
4. **Loan tabs**: Active / Closed (Funding, PC Review, Post-Closed) / Cancelled (Cancelled, Lost).
8. **Active Loans** defaults to board (grouped buckets ~5 cols), list as alternate, choice remembered per user.
7. **Cancellation recycle** (ALL LOs, automatic, go-live forward, no backfill):
   - Fires when Status__c → Cancelled, purchase loans only, `Borrower_Withdrawal_Reason__c` non-blank and NOT "Selected an Alternative Lender" / "Found a More Competetive Interest Rate", and `Withdrawn_Reason__c` not App Denied / Pre-Approval Denied.
   - New Lead cloned from the converted Lead (all fields), Status "Pre-Approval", owner = Transaction Loan_Officer__c, Loan Partner carried over, `Borrower__c` co-borrowers copied, lookup to the cancelled Transaction.
   - Bypass flag: no new-lead automation/outreach/routing/Zapier. One internal notification to the LO.
   - On reconversion attaches to the existing Person Account (no duplicate).
   - Cancelled loan shows in the LO's Cancelled tab.
5. **Volume drawer** (fixed edge tab, every page):
   - Closed last month + MTD: sum `Loan_Amount_1st__c` ("Total Loan Amount") by `Funding_Date__c` + units.
   - Pre-approved: Leads in status "Pre-Approval" only, sum Lead `Loan_Amount__c` + units.
   - New leads: count, last month + MTD, excluding recycled leads.
   - Realtor partners added/tagged: count, last month + MTD.
9. **Other Contacts** tab: tagged Person Accounts (same many-to-many model as My Realtors) with type: Homeowners Insurance Agent, Title / Escrow Agent, Attorney, Home Inspector, Appraiser, Builder, Financial Planner / CPA, Other.
10. **Conditions** (LO Workspace only): hide Condition__c where Category__c contains Closing, TC, Final Docs or Post Clos. Title and Disclosure stay visible.
12. **Weekly touch**: touch = call, SMS, meeting or EmailMessage to/from the lead's email in last 7 days. Lead appears in Up Next once due (7+ days). Pre-approval list: touch-due first (oldest touch top), then newest created. Up Next gets "Open All" → modal.
3/11. **Notes composer + Appraisal tab** redesign. Mockups: https://claude.ai/artifact/LvBC73nTDw3iYbdZXzzr5T (source `mockups/lo-workspace-upgrades.html`).
   - Picked 2026-10-08: Notes **B** (slim modal: type chips + one textarea + pin). Appraisal **A** (status line, 4-step tracker, key facts, collapsed history) **plus** the existing "comment to the appraisal company" thread kept as a message section.
   - Approved as shown: Up Next "Open all" modal, Communications tab. Volume drawer and Active Loans board: awaiting review.
**Communications tab** (read-only) on LO Workspace Lead, Transaction and Person Account pages: Calls / SMS / Emails subtabs, newest first with counts. Calls+SMS = manual + RingCentral matched by phone number (Call Insight summary link where present); Emails = EmailMessage by address, threaded, expandable. Shows ALL Reach users' communications with that borrower, labelled by sender.

**U8 decisions added 2026-10-08 (during review):** the recycled lead KEEPS `AriveId__c` (ARIVE link stays); its `Loan_Amount__c` comes from the original converted lead's `Loan_Amount__c` , falling back to the cancelled Transaction's `Loan_Amount_1st__c` ("Total Loan Amount") when the lead's is blank (validation rule `Lead_Rating_and_Loan_Amount_Fields_requr` rejects Pre-Approval with a blank amount). Do NOT copy `Arive_Status__c` (would trip Convert_Lead_to_Person_Account_on_TRID_Date).
