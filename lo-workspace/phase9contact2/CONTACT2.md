# Phase 9 contact, round 2

Status: **validated (check-only), NOT deployed.** 2026-10-02. Job **0AfQi000001TuCkKAK**: 99 tests, 0 failures.

Coverage: LoWsContactService 98%, LoWsBorrowerService 95%, LoWsLeadDetailsService 99%, ExternalLoLeadService 99%, ExternalLoPortalService 86%, ExternalLoPortalController 84%.

All sources were retrieved fresh from prod after deploys 0AfQi000001Tt0XKAS and 0AfQi000001Tt29KAC. `ref/` holds the untouched copies.

## Deploy (one step, no permission set changes)

```
cd "C:\Apps\Claude Back Up\lo-workspace\phase9contact2"
sf project deploy quick -o Production --job-id 0AfQi000001TuCkKAK
# or: run-validate.sh with "validate" replaced by "start"
```

Then **republish Partner Workspace**, because externalLoLeads is shared with it. In the portal:
- The raw Id is gone from lead headers and rows.
- Pre-Approval and Converted badges now have their own colours.
- My Loans shows the borrower's name instead of an Id.

Everything else listed below is LO Workspace only.

## What changed

1. **No raw Salesforce Id.**
   - Lead header meta is now "Source · Assigned …".
   - My Leads row meta no longer shows the Id.
   - Loan `idLabel` is the loan Name, so it is kept.
   - Bug fixed: My Loans rows and the loan header showed the borrower's raw Account Id. LoanRepository reads loans WITH USER_MODE, so `Borrower_Name__r` was null for outside LOs and the code fell back to the Id. `ExternalLoPortalService.borrowerNames` now reads the names without sharing (the LO can already see the loan), and falls back to "Borrower".
2. **One Phone.**
   - The Contact card shows MobilePhone, falling back to Phone (Person Account: PersonMobilePhone, then Phone).
   - Save writes the value to both fields.
   - Add lead writes the value to both Phone and MobilePhone.
   - `updateContactInfo` is now `(recordId, firstName, lastName, phone, email, street, city, state, postalCode)`. The name is used for co-borrowers only.
3. **Co-borrowers.**
   - The `loWsBorrowerPills` component sits above the Contact card: "<Primary> (Primary)", one pill per Borrower__c, and "+ Add borrower". The Contact card follows the selected pill.
   - Server: `LoWsBorrowerService`. The list reuses `BorrowerPersonAccountService.getBorrowers`, the same query as the internal borrowerPanel.
   - Add, edit and remove are owner-only. They run in SYSTEM_MODE after the ownership check, with the Add lead rules (first and last name, 10-digit phone, real email).
   - **Borrower__c has no relationship field and no address fields**, so a co-borrower shows first and last name, phone and email only.
   - Remove: refused with a clean message while any Lead_Document_Request__c or Condition__c is assigned to that borrower. Otherwise the row is deleted (the panel's hard-delete path).
   - Access: all reads are with-sharing SOQL and all DML is SYSTEM_MODE, so **no permission set step is needed**. Borrower_Management is already in the PSG for the record page panel.
   - Restriction rule: `ExternalLoStampBorrower` stamps `External_LO__c` from the parent lead's owner. Proven by test: the LO sees the row they just added. Rows on leads the LO doesn't own stay invisible, and those calls are refused.
4. **Pre-Approval Details.**
   - Loan Program is a dropdown of the active `Transaction__c.Loan_Program_1st__c` values, in org order, and is stored as text.
   - A legacy value shows as "<value> (current)". The server accepts only a listed value or the lead's current value.
   - "Estimated payment" is now labelled "Preferred Payment".
5. **Add lead "+ New realtor"** (a sub-form with name, phone, email, brokerage and market; type Realtor). One transaction with a savepoint:
   - `LoWsPartnerTagService.addPartner` runs first. If it matches a partner, it returns `realtorMatches` and nothing is created; the form then offers "Tag me and use this realtor" (`tagPartner`, then the lead). If it matches a non-partner, it shows the admin message.
   - The lead is created next. If the lead fails, both the lead and the new realtor roll back (tested).
   - **Stage bump:** any realtor used on an Add lead moves to Active Partner. This covers the My Leads, My Realtors row, realtor page and new-realtor paths, and a takeover. Only Prospect, Contacted, Meeting Set and Met are bumped; it never downgrades, and Dormant is left alone.
6. **My Leads Board / List.**
   - The toggle (LO Workspace only) is remembered in localStorage under `loWorkspace.myLeads.layout`, inside try/catch. Default is List.
   - Board columns: New, Working, Pre-Approval, Nurture, Converted, each with a count and a stage-coloured top bar.
   - Cards show name, amount · purpose, source, realtor (new `LeadRow.realtorName`, read in SYSTEM_MODE for the LO's own leads) and the Next appt badge. Clicking a card opens the lead.
   - Search applies to both layouts; the stage chips aren't shown on Board. No drag.
   - On a phone each column is 85vw and snaps while scrolling.

## Conversion and Loan Program

- Lead.Loan_Program__c is **not** mapped to the Transaction on conversion.
- The Submission Form (`Loan_Origination_Submission_Form`) asks for the program in its own dropdown (ProgramTypeChoiceSet). It defaults from the Transaction, not the Lead, and `…_Update_Transaction` writes it to `Loan_Program_1st__c`.
- Picking from the same list keeps lead values consistent with Transaction values, but conversion doesn't use the lead value today. Pre-filling the Submission Form from `Lead.Loan_Program__c` would be a flow change.

## Tests

- `LoWsBorrowerServiceTest` (new): owner add/see/edit/remove; required fields; non-owner refused; remove refused with a document request assigned; My Loans shows the name, not the Id.
- `LoWsContactServiceTest`: a single-phone save writes both fields (Lead and Person Account).
- `LoWsLeadDetailsServiceTest`:
  - new realtor + lead created together and tagged Active Partner
  - duplicate realtor returns the match with nothing created
  - a refused lead rolls back the new realtor
  - Prospect → Active Partner, and Dormant is untouched
  - Loan Program list, legacy value kept, unknown value refused

## Open questions

1. Co-borrowers have no relationship or address fields on Borrower__c. Should we add them?
2. Should Dormant realtors go back to Active Partner when they refer a lead? Today they are left alone, per "never downgrade".
3. "Tag me and use this realtor" runs in two calls (tag, then lead). If the lead then fails, the tag stays. That is intended and harmless.
4. Should the Submission Form pre-fill Loan Program from the lead? That would be a flow change.
5. The lead Status dropdown is still not built. It is awaiting the user's approval.
