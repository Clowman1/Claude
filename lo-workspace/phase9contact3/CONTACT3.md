# Phase 9 contact, round 3

Status: **validated (check-only), NOT deployed.** 2026-10-02. Built from prod after 0AfQi000001TunpKAC. `ref/` = untouched retrieves.

- Main `force-app/`: **0AfQi000001TvQXKA0**. 168 tests, 0 failures.
  - Coverage: LoWsContactService 98%, LoWsBorrowerService 96%, LoWsLeadDetailsService 99%, ExternalLoLeadService 99%, LeadDocumentRequestService 82%, ExternalLoPortalController 84%.
- FLS step `fls-step/` (Borrower__c.Relationship__c + External_LO_Access + Borrower_Management): **0AfQi000001TvVNKA0**, using AppraisalOrderController_Test.

## Deploy order

1. `sf project deploy quick -o Production --job-id 0AfQi000001TvVNKA0`
   - Or the full deploy: `sf project deploy start -o Production -d fls-step --test-level RunSpecifiedTests --tests AppraisalOrderController_Test`.
2. Wait until PermissionSetGroup External_Loan_Officer has Status = Updated. Both permission sets are in the group.
3. `sf project deploy quick -o Production --job-id 0AfQi000001TvQXKA0`
   - If refused, run `run-validate.sh` with `validate` changed to `start`.
4. **Republish Partner Workspace.** It shares portalListLayout, externalLoPreApprovals, leadPortalDocumentRequestManager and loWsAddLeadForm's Apex. The internal Lead page's leadDocumentRequestManager also changes; nothing needs republishing for it.

## NOT built: Status dropdown and Board drag-and-drop

The earlier attempt was blocked by the session's permission check. The approval this round came relayed through the coordinator, not from the user in this session. So both items are left for the user to confirm here directly. The server part is small: an owner-checked `updateStatus` that writes only Status, plus the record type's values with converted statuses excluded.

## Built

1. **Add lead: Lead Source.**
   - When no realtor is picked, an optional Lead Source dropdown appears. It shows the Consumer lead record type's active values (UI API, org order), with Realtor Referral removed.
   - When a realtor is picked, the dropdown is hidden and the source is Realtor Referral.
   - Server (`LoWsLeadDetailsService.checkLeadSource`): blank, or an active LeadSource value. "Realtor Referral" without a realtor is refused.
   - `createLoWorkspaceLead` takes a trailing `leadSource` param.
2. **List shading** (portalListLayout, so every shell list):
   - Zebra stripes: #ffffff / #f3f6fb.
   - A 4px left bar in the row's status colour, taken from the first badge (New blue, Working teal, Pre-Approval purple, Nurture slate, Converted green, warn amber, danger red, stage navy).
   - Hover tint #e8eef5.
   - Also fixed: the initials regex was `/s+/` (it split names on the letter "s").
3. **Raw Ids.** My Leads rows were already clean in prod; the user's screenshot predated the deploy. The Pre-Approvals rows showed the Lead Id; that is removed, and its search placeholder no longer mentions ID. Loans keep `idLabel`, which is the loan Name.
4. **Co-borrowers.**
   - Only first and last name are required. Phone and email are optional, but format-checked when filled in (na@na.com is refused).
   - **New `Borrower__c.Relationship__c`:** restricted picklist with Spouse, Partner, Parent, Child, Sibling, Relative, Friend, Other. The values live only on the field.
   - Pills read "Jane Smith (Spouse)". The relationship shows on the Contact card and can be edited in the Add and Edit forms.
   - **Without an email:**
     - the pill shows "· no email" with a tooltip;
     - the Contact card shows the warning "No email — document requests and condition lists can't be sent to this borrower. Add an email to include them.";
     - the Add borrower form has a hint under the email field.
   - Internal borrowerPanel: Relationship is **not** added. It would need a BorrowerPersonAccountService query change plus panel UI; left as a follow-up.
5. **Document requests** (internal leadDocumentRequestManager and LO Workspace/portal leadPortalDocumentRequestManager, minimal change):
   - A note now lists borrowers without an email: "No email (can't be assigned or emailed until an email is added): …". Before, they were silently dropped from the Borrower picker. lightning-combobox can't disable single options, so they stay out of the picker and are named in the note instead.
   - `sendPerBorrowerRequestEmails` now adds an outcome line, "<Name>: not emailed, no email address. Add an email…", for items assigned to a co-borrower who has no email. Before, they were skipped silently.
   - Internal behaviour is otherwise unchanged (LeadConditionAssignmentTest etc. pass).
   - **Condition lists:** there is no separate co-borrower send path in Apex. ConditionReviewService emails only the Transaction's `Borrower_Email__c`, so there was nothing to change.
6. **Realtor stage bump.** Any stage other than Active Partner, **Dormant included**, becomes Active Partner when the realtor is used on a new lead.

## Tests

- **LoWsLeadDetailsServiceTest:**
  - lead source: accepted, refused (unknown value / Realtor Referral without a realtor), and fixed when a realtor is picked
  - Dormant becomes Active Partner
- **LoWsBorrowerServiceTest:**
  - name-only co-borrower with a relationship gets the pill label, the no-email flag and the warning
  - an email clears the warning
  - bad phone, bad email and unknown relationship are refused
  - a document request send names the no-email co-borrower
  - the picker lists them as not assignable
  - the existing owner/non-owner tests still pass
- **LoWsContactServiceTest:** updated for the new `relationship` param.

## Open questions

1. Status dropdown and Board drag-and-drop: the user needs to confirm directly in this session.
2. Should Relationship be added to the internal borrowerPanel (Apex query + UI)?
3. Document requests: should no-email borrowers appear inside the picker as a greyed "(no email)" entry? That would mean replacing lightning-combobox with a native select in both managers. Today they are listed in a note above the tables instead.
