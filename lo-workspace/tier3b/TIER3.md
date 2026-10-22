# LO Workspace Tier 3: friction (2026-10-20)

Decisions grilled 2026-10-20. Convert: LOs may convert at ANY status (no gate). Q1 hide all processor/closer parts (a). Q5: NO stop on move to Pre-Approval for External LOs. Q8 stale converted-status leads stay hidden (b). Others as recommended.

## 3a: setup and pages — 0AfQi000001VG6LKAW (source `lo-workspace/tier3/`)
- Validation rule `Lead_Rating_and_Loan_Amount_Fields_requr` skips `$Permission.External_LO` (Pre-Approval with no loan amount).
- LO Transaction page: removed LendwizeIframe, Funder/Closer/Post-Closing Action Required, Histories list, "Processing Required Fields" and "2nd Transaction Information" sections. The page's button bar was already limited to Application Summary / Submission / COC / Back Under Contract (Revert to Closing / MERS never showed there).
- Communications tab on LO Lead (desktop + phone) and Transaction pages; new `LO_Workspace_Account_Phone_Record_Page` (Small override, External LO profile).
- Mobile menu: app pages + tabs Log Activity / My Leads / My Realtors / My Loans host the shell with `defaultView` / `startWith=log`; tabs visible via External_LO_Access tabSettings. (Also show in the desktop tab bar: one tab list per app.)
- Payroll_Review_Access added to the External_Loan_Officer group. Joseph: Twilio_User + Wire_Calculator_PDF_Access assignments deleted.

## 3b: code — 0AfQi000001VGJFKA4 (208/208; source `lo-workspace/tier3b/`)
- Conversion releases queued automation for every status (moves to Submitted For Disclosures first, as conversion would).
- Board: Contacting keeps Contact Attempt N; realtor-type leads never taken over; Pre-Approvals View/Back stays in Pre-Approvals; log form no longer remembers the last contact.
- CSV: partial takeover saves with per-row errors; comma/semicolon/tab detected; MobilePhone set; Purpose validated (.csv extension still required).
- Loans: Submission form only at TRID Application / Open (its edit window); COC hidden from Funding on; header joins non-blank parts; Suspended counts as Active.
- Conditions: Closing Disclosure now visible; the closing/TC/final docs/post-close filter applies to Standard (LO Workspace) users only, not Harold's portal.
- Errors shown instead of swallowed: Appraisal panel (+ message dates), In-person Events, texts switch (realtor/agent rows note "off for all Reach loan officers"); failed auto-texts → Custom_Log__c Source 'LoWsAutoText'.
- Speed: badges skip loans + shared-buyer queries; getConnectionIssues runs alongside getGateState; Zoom callout 3s; volume drawer uses COUNT/GROUP BY; My Realtors loads once.
- Wording: time-of-day greeting, Edit-my-plan footnote, Past Clients subtitle, "Unable to load" on read errors, workspace name in toasts.
- Dead code: ExternalLoPortalController.getRealtors deleted; getReasonOptions no longer @AuraEnabled. Kept (still called by tests): ExternalLoWorkspaceController.saveOnboarding / getActivityPlan / getPastClients.

Skipped on purpose: cacheable reads for getMyEvents / getTourState (re-read after saves; caching would show stale data).
Not verified in a browser.
