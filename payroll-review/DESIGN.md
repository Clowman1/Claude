# Payroll Review — design (agreed 2026-10-14)

- **Who**: anyone loaded that month. Sep 2026: Harold Ellis, Joseph Carey, Manuel Anagnostou, Joe Olmsted, Zachary Fritz, Martin Rebagliati, Megan Straight, Joey D'Alessandro, Byron Richie. Never processors, Monica, Alexis, Ben, Christopher, Simon, Rhett, Adam.
- **Where**: Command Center (`pipelineCommandCenter`): pops up on load + "Payroll Review" button. LO Workspace (`loWsVolumeDrawer`): section at the top of the Volume drawer, drawer opens itself, amber dot on the tab.
- **Shows**: header `{Month} Payroll · Pay Date · Review closes`; columns Loan, Loan Amount, Biz Dev, Rate Applied, Commission; Total = the paid total from the main tab, always. No flags, notes, plan lines, Channel BPS or loan type.
  - LO rows: the person's block on the main tab.
  - LOA rows (Megan, Joey): every Raw Data file where they are Loan Partner, 4 BPS each, under "As LOA" (Megan also "As Loan Officer"). Differences from the main tab are flagged before publishing.
  - Byron: one line, company-funded units + volume + bonus.
- **Behaviour**: pops up until Looks good or Report an issue; button/drawer until the 11th, then hidden (records kept). A corrected reload replaces rows and makes them review again.
- **Feedback**: free text, emailed to Christopher + Bianca (sent as the employee, Reply-To them), appended to `Feedback__c`, Status → Disputed. Replies happen outside Salesforce; tick **Resolved**.
- **Data**: `Payroll_Review__c` (Private, owned by the loader) + `Payroll_Review_Line__c` (master-detail). Employees reach only their own via `PayrollReviewController` (without sharing, scoped to the running user). Permission sets: **Payroll Review Access** (employees), **Payroll Review Admin** (Bianca: view all, Resolved).
- **Loading**: see [LOADING.md](LOADING.md). Bianca's Claude project produces the workbook; it is loaded in a Claude session.
