# Phase 10 — Guided Submission Form (all users)

Built 2026-10-05. **Nothing deployed.** Fresh prod copies are in `ref/`. The old flow `Loan_Origination_Submission_Form` (v45 Active) is untouched and stays as the fallback.

## Route chosen: new LWC + Apex service (not a screen component inside the flow)

The screen flow does very little after its screen. All the real downstream work lives in record-triggered automation that fires on **insert of a `Submission_Form__c`**, and that automation is unchanged:

- `Loan_Origination_Submission_Form_Update_Transaction`: copies the form onto the Transaction and the borrower Person Account, then runs DPA AUTO.
- `Update_Transaction_on_Submission_Form_Creation`: sets Status to Open, Submission_Form_Date__c and Channel.
- `Update_Transaction_after_Submission_Form`: runs on the `Submission_Form_Event__e` event.
- `PhoneFormatSubmissionForm`: the phone-format trigger.

The screen flow's own logic is only five things:

1. Build and insert the form.
2. Create "can't find" Accounts and re-point the form's lookups at them.
3. Copy the seller's agent into the appraisal contact.
4. Call `DpaSecondTransactionInvocable` (MANUAL).
5. Publish the event.

`LoanSubmissionWizardController.submit` reproduces those five steps exactly, so every side effect still comes from the same flows.

The alternative would have needed a new version of the 140-field flow, wired to about 80 output variables. It would also have hit the Draft/activation and self-navigation traps. That has more risk and buys no extra fidelity.

The execution model matches the flow's `SystemModeWithSharing`:

- The class is `with sharing`, so reads respect sharing.
- DML runs in system mode.
- A Transaction the user can't see is refused, which is what `Get_Transaction` effectively did.

## Components

| Path | What |
|---|---|
| `force-app/.../classes/LoanSubmissionWizardController(.cls, Test)` | Methods:<br>• `getWizardData` (prefill, borrowers, picklists, lock)<br>• `searchRecords` (SOSL Account/Contact)<br>• `addBorrower`<br>• `submit` |
| `force-app/.../lwc/loanSubmissionWizard` | The 6-step stepper. It is also a `lightning__FlowScreen` component. |
| `force-app/.../lwc/loanSubmissionLookup` | Search-as-you-type picker with a selected chip. |
| `force-app/.../lwc/transactionSubmissionFormAction` | The quick action `Transaction__c.Submission_Form_Modern`. It now hosts the wizard. |
| `force-app/.../lwc/externalLoPortalSubmissionModal` | Used by `externalLoLoans` in Partner Workspace and LO Workspace. It now hosts the wizard. |
| `step2-permsets/` | Class access for the 3 permission sets. |
| `step3-flow/` | New screen flow `Loan_Submission_Wizard_Screen`: one screen holding the LWC, with `allowFinish`/`allowPause` true and no footer. |
| `step3b-activate/` | FlowDefinition that sets `activeVersionNumber` to 1. |
| `step4-action/` | `Transaction__c.Submission_Form_2` repointed to `Loan_Submission_Wizard_Screen`. |

## Steps

1. **Loan.** Fields:
   - Investor (picker) and Channel (chips).
   - Loan Purpose, then Refinance Purpose (only when Refinance).
   - Loan Type, Program Type, Occupancy, New Build/Bank Owned (chips).
   - Property Type, then Condo Review Type (chips, only when Condo). The Limited Review guideline banner shows when Limited Review is picked.
   - Appraisal, Waiving Escrow, DU/LP/Manual (chips).
2. **Borrowers.**
   - A "Borrowers on this file" card lists:
     - the primary borrower;
     - every `Borrower__c` row, with the first one tagged as the co-borrower on this form and the rest tagged "stays on the file";
     - a **+ Add borrower** button.
   - Fields:
     - Borrower first and last name, and Speaks Spanish Only.
     - Co-borrower first name, last name, phone and email.
     - Spouses: "are spouses" first. When that is No, "has a spouse" appears for each person, and then that person's spouse name, phone and email.
3. **Partners.**
   - No Realtor.
   - Buyer's agent: picker, or a "Can't find" toggle that shows first, last, cell and email. Required only when the loan is a Purchase and No Realtor is not set.
   - Buyer's assistant: picker, or Can't find. When Can't find is on, all 4 fields are required.
   - Seller's agent and seller's assistant: same pattern. The seller's assistant picker searches **Contacts**, because the field is a Contact lookup.
   - Title company: picker (always required), or Can't find with company, phone and email.
   - HOA (only when Condo): name, company, phone.
   - Contact for appraisal entry: "Same as Seller's Agent", or name, phone and email.
4. **Pricing & lock.**
   - Expected Cash To Close.
   - Rate Buydown, then Contributor and Buydown (only when Yes).
   - DPA/Grant, then program name, household persons and household income.
   - Attached 2nd (only when DPA is Yes): investor, loan type, rate, amount, program.
   - Commitment date, Closing date, Rate Lock Status, then Lock Exp Date (only when Locked).
5. **Notes & needs.**
   - Income and Assets (multi-select chips).
   - Intentions for Current Home.
   - General Notes, Pending Documents Requested, Credit Notes.
6. **Review & submit.** A compact summary per step, with an **Edit** link that jumps to that step. A red edge and a "N required answers missing" note flag incomplete steps.

How it behaves:

- The header shows "Step n of 6 · x%". The percentage is the share of currently-required answers that are filled in.
- Back and Next sit in a sticky footer. You can click any step you have already reached.
- Next validates the current step inline: a "Required" message, or an email-format message.
- Submit validates every step and jumps to the first step with an error.
- The server re-applies the same visibility and required rules before saving. Hidden fields are dropped, as the flow's hidden fields were.
- A field carries a "Prefilled" tag while its value still matches what was loaded. Every field stays editable.

## Prefill sources

| Source | Fields |
|---|---|
| **Transaction** | Investor, Channel, Loan Purpose, Refinance Purpose, Loan Type, Occupancy, Program, Property Type, Appraisal, Expected Cash To Close, Contributor, Buydown, DPA program name, Commitment, Closing, Rate Lock Status, Lock Exp Date, Pending Documents (`Conditions_Needed__c`), Buyer's/Seller's agent, both assistants, Title |
| **Transaction checkboxes** | Rate_Buydown__c, DPA__c, New_Build_Bank_Owned__c. Ticked shows Yes. Unticked shows No only once a form has been filed; on the first form it stays blank so the LO has to answer. |
| **Second_Mortgage__r** | Attached 2nd fields |
| **Borrower Person Account** | Primary first and last name (the flow's own default); spouse flags and spouse name/phone/email |
| **Co-borrower** | The first `Borrower__c` row. If there are none, the `*_Co_Borrower__pc` fields (the authoritative source). |
| **Latest previous Submission_Form__c on the loan** | The fields with no Transaction home: Condo Review, Waiving Escrow, DU/LP, Speaks Spanish, HOA, Contact for Entry, DPA household fields, General Notes, Credit, Income, Assets, Intentions |

The flow itself prefilled only these: Investor, borrower first/last, Loan Purpose, Refinance Purpose, Occupancy, Program and Property Type.

## Borrowers

- `BorrowerPersonAccountService.getBorrowers(transactionId)` runs server-side inside `getWizardData`, so portal users don't need access to that class.
- **+ Add borrower** inserts the same `Borrower__c` the borrowerPanel creates (First, Last, Email, Phone, Name, Transaction__c). It runs in USER_MODE, the same as the panel's LDS call.
- If the file had no rows and the co-borrower fields are empty, the new row fills them.
- Extra borrowers are shown and left linked.
- **Co-borrower write-back (owner-approved 2026-10-05):** when the co-borrower fields came from a `Borrower__c` row (`CoBorrowerRowId` in the payload), submit updates that same row with the LO's edits.
  - Only changed fields are written. Comparison is case-sensitive; phones are compared by digits only.
  - Name is rebuilt as "First Last" (max 80), the borrowerPanel rule.
  - Blank names are ignored.
  - Submit never creates or deletes rows.

## Edit window

`lockedMessage()` mirrors VR `Form_Not_Editable_If_Status_Inproper`:

- Admins always pass.
- "Loan Officer Profile (Read Only)" is always locked.
- After `Disclosures_Out_Date__c`, everyone is locked except Processor Profile, Processor Profile (SF) and the Processors and Closers role. joey@ is always locked.

When locked, the wizard is browsable but shows the VR message and Submit is disabled. `submit()` also refuses server-side.

The old flow only ever *inserted* forms, and the VR skips inserts, so the flow did not enforce this. That is why a resubmit after Disclosures Out could reset Status to Open. The wizard now enforces the policy.

**Loan_Partner__c is never written.** It is not in the payload or the form build, and a test asserts the Transaction's Loan Partner is unchanged.

## Field mapping

Flow screen field → `Submission_Form__c` field (Assign_Values_to_Submission_Form_1-6), → Transaction via `…_Update_Transaction`:

| Flow field | Submission_Form__c | Transaction / Account (record-triggered) |
|---|---|---|
| (record type / recordId / "Submission Form") | RecordTypeId (Loan_Origination_Submission_Form), Transaction__c, Name | |
| InvestorLookup | Investor_Lookup__c | Lender_lookup__c |
| Channel | Channel__c | Channel__c |
| Borrower_and_Co_Borrower_are_spouses | Borrower_and_Co_Borrower_Spouses__c | Borrower_and_Co_Borrower_Spouses__pc |
| Borrower_First_Name / Last | Borrower_First_Name__c / Borrower_Last_Name__c | |
| Co_Borrower_First_Name / Last | Co_Borrower_First_Name__c / Co_Borrower_Last_Name__c | First_/Last_Name_Co_Borrower__pc, Has_Co_Borrower__pc |
| BorrowerCoEmail / BorrowerCoPhone | Co_Borrower_Email__c / Co_Borrower_Phone__c | Email_/Mobile_Co_Borrower__pc |
| Borrower_Has_a_Spouse / Co_Borrower_Has_a_Spouse | Borrower_Has_Spouse__c / Co_Borrower_Has_Spouse__c | *_Has_Spouse__pc |
| Spouse_Borrower, SpousePhoneBorrower, SpouseEmailBorrower | Borrower_Spouse_Name/Phone/Email__c | Borrower_Spouse_*__pc |
| Spouse_CoBorrower, SpousePhoneCoBorrower, SpouseEmailCoBorrower | Co_Borrower_Spouse_Name/Phone/Email__c | Co_Borrower_Spouse_*__pc |
| Speaks_Spanish_Only | Speaks_Spanish_Only__c | |
| BuyersNameLookup (or new Person Account) | Buyers_Agent_Lookup__c | Realtor_Buying_Agent__c |
| BuyersCellPhone / BuyersEmail | Buyers_Phone__c / Buyers_Email__c | |
| Buying_Agent_Assistant (or new PA) | Buying_Agent_Assistant__c | Buying_Agent_Assistant__c |
| SellersNameLookup (or new PA) | Sellers_Agent_Lookup__c | Realtor_Listing_Agent__c |
| SellersCellPhone / SellersEmail | Sellers_Phone__c / Sellers_Email__c | |
| Seller_Agent_Assistant (Contact, or new PA's PersonContactId) | Listing_Agent_TC__c | Listing_Agent_TC__c |
| NameTCLookup (or new Business Account) | Title_Company_Name__c | Title_Agent__c |
| CompanyTC / PhoneTC / EmailTC | Title_Company__c / Title_Company_Phone__c / Title_Company_Email__c | |
| NameHOA / CompanyHOA / PhoneHOA | HOA_Name__c / HOA_Company__c / HOA_Phone__c | |
| NameContactForEntry / Phone / Email (or seller's agent if Same_as_Listing_Agent) | Appraisal_Contact_Name/Phone/Email__c | |
| Loan_Purpose / Refinance_Purpose | Loan_Purpose__c / Refinance_Purpose__c | Loan_Purpose__c / Refinance_Purpose_Picklist__c |
| Occupancy / Program_Type / Property_Type | Occupancy__c / Loan_Program__c / Property_Type__c | Occupancy__c / Loan_Program_1st__c / Property_Type__c |
| Loan_Type | Loan_Type__c | Loan_Type_1st_TD__c |
| DU_LP_MANUAL / Condo_Review_Type / Waiving_Escrow | DU_LP_Manual__c / Condo_Review_Type__c / Waiving_Escrow__c | |
| Appraisal | Appraisal__c **and** PIW__c | Appraisal__c |
| Contributor / Buydown / Rate_Buydown | Contributor__c / Buydown__c / Rate_Buydown__c | Contributor__c / Buydown__c / Rate_Buydown__c (bool) |
| New_Build_Bank_Owned | New_Build_Bank_Owned__c | New_Build_Bank_Owned__c (bool), also via the event |
| Expected_Cash_To_Close | Expected_Funds_to_Close__c | Expected_Cash_To_Close__c |
| DPA_Grant | DPA_Grant__c | DPA__c (bool); AUTO 2nd |
| DPA_Grant_Program_Name / Persons / Income | DPA_Grant_Program_Name__c / _Number_of_Persons_in_Household__c / _Household_Income__c | DPA_Grant_Program_Name__c |
| Commitment / Closing | Commitment__c / Closing__c | Loan_Commitment_Date__c / Closing_Date__c |
| Rate_Lock_Status / Lock_Date | Rate_lock__c / Lock_Exp_Date__c | Rate_Lock_Status__c / Rate_Lock_Exp_Date__c (also via the event) |
| General_Notes / Needs_List / Credit | General_Notes_Description__c / Needs_List_Description__c / Credit_Description__c | Needs_List → Conditions_Needed__c |
| Income_Multi / Assets_Multi | Income_4506T_Multi__c / Source_of_Funds_to_Close_Multi__c | |
| (ObjectProvided) Intentions_for_Current_Home__c | Intentions_for_Current_Home__c | |
| InvestorLookup2nd, Loan_Type_2nd, Rate_2nd, Loan_Amount_2nd, Loan_Program_2nd | (DpaSecondTransactionInvocable MANUAL) | 2nd Transaction |
| No_Realtor, Cant_Find_* , Same_as_Listing_Agent | (UI only, as in the flow) | |

The "can't find" Accounts are built as in the flow:

- Agents and assistants: a Person Account (`PersonAccount` record type) with Type__c `Realtor Account`, `Exclude_From_Duplicate_Check__c` = true, and FirstName, LastName, PersonEmail, Phone.
- Title company: a Business Account with Type__c `Title Agent Account`, Exclude = true, and Name.

The event `Submission_Form_Event__e` carries New_Build_Bank_Owned__c, Rate_Lock_Exp_Date__c, Rate_Lock_Status__c and Transaction_Id__c.

## Where the wizard differs from the flow (deliberate)

1. **Partner creation is all-or-nothing.** The flow silently skipped a failed Account create or form update (fault connectors) and saved the form without the link. The wizard creates the partners first, inserts the form once with every lookup set, and rolls the whole save back with a message if anything fails.
2. **The seller's assistant "can't find" now links.** The flow put the new Account's Id into a **Contact** lookup, which always failed silently. The wizard links the new Person Account's `PersonContactId`.
3. **Same as Seller's Agent with a manual seller** stores "First Last". The flow stored only the last name.
4. **A new title company gets no Phone.** In prod, every flow-created title account has Phone = null, and an Account automation copies Phone to PersonMobilePhone, which fails on Business Accounts. The flow also wrote the seller's agent's cell and email there, which was a bug. The entered phone and email still land on the form's Title_Company_Phone/Email.
5. **The edit-window rule is enforced on submit** (see above).
6. **The flow's dead duplicate "Rate Lock Exp Date"** (the ObjectProvided `Get_Transaction` field, never saved) is dropped.

## Flow behaviour I did not change (worth knowing)

- **The 2nd-lien fields are usually ignored, today and now.** On insert, the record-triggered AUTO call creates the DPA 2nd from the first-lien values before the MANUAL call runs, so MANUAL returns SECOND_ALREADY_EXISTS. I kept the same order.
- **Every new form resets Status to Open and stamps Channel.** This comes from `Update_Transaction_on_Submission_Form_Creation`.
- **The Title company is required even on refinances**, as in the flow.

## Entry points

| Entry point | Who | Before | After |
|---|---|---|---|
| `Transaction__c.Submission_Form_Modern` (transactionQuickActions strip at TRID Application; internal pages + LO_Workspace_Transaction_Record_Page) | Internal LOs/processors, LO Workspace | LWC → flow | LWC → wizard (step 1) |
| `externalLoPortalSubmissionModal` in `externalLoLoans` | Partner Workspace + LO Workspace | embedded flow | wizard (step 1); **republish Partner Workspace** |
| `Transaction__c.Submission_Form_2` on "RHL Community Transaction Layout" | Harold Ellis, in the old Aura portal "Reach Home Loans Transactions" `/s/` (26 forms in 180 days, last one today) | flow v45 | flow `Loan_Submission_Wizard_Screen` (steps 3, 3b, 4). An LWC quick action doesn't run in Experience Cloud, hence the wrapper flow. |
| `Lead.Submission_Form` (Realtor Lead Layout), `Transaction__c.Submission_Form` (Legacy) | — | a different legacy flow, `Submission_Form_Screen` | **Not changed.** No forms with that record type in 120 days. |

## Deploy order (from `lo-workspace/phase10form`)

1. Main:

   ```
   sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LoanSubmissionWizardControllerTest
   ```

   - Validated as **0AfQi000001U5EbKAK**: 10/10 tests, class at 94% (466/495).
   - You can quick-deploy it while it is still valid.
   - After this step, publish Partner Workspace: `sf community publish --name "Partner Workspace"`.
2. Permission sets, deployed alone:

   ```
   sf project deploy start -o Production -d step2-permsets/force-app --test-level RunSpecifiedTests --tests AppraisalOrderController_Test
   ```

   - Adds class access on Pipeline_Command_Center_Pilot_Access (all 26 internal LO, processor, manager and admin users), External_LO_Access and External_LO_Perfect_Day_Access (Harold and the portal).
   - Proven together with the class as **0AfQi000001U5HpKAK** (17/17 tests).
3. Harold's portal path:
   - 3. `-d step3-flow/force-app`. It lands as **Draft**.
   - 3b. `-d step3b-activate/force-app`, which activates v1. Then verify with:

     ```
     SELECT VersionNumber, Status FROM Flow WHERE Definition.DeveloperName='Loan_Submission_Wizard_Screen'
     ```
   - 4. `-d step4-action/force-app`.
   - Steps 3 and 4 were validated together with the LWCs as **0AfQi000001U5L3KAK**.

**Rollback:**

- Redeploy the `ref/` copies of `transactionSubmissionFormAction` and `externalLoPortalSubmissionModal`, and of `Transaction__c.Submission_Form_2`.
- The flow `Loan_Origination_Submission_Form` v45 was never touched.

## Not verified

- The wizard has not been clicked through in a browser; the LWCs compiled in validation. Smoke-test after deploy:
  - one internal LO;
  - the Outside LO Pilot (LO Workspace);
  - Harold's portal, or another user on the RHL Community profile.
- Portal users must be able to create `Borrower__c` for **+ Add borrower**. If they can't, they get the error message and the rest of the wizard still works.

## Owner sign-off (2026-10-05)

The owner approved all four open questions:

1. Switch Harold's portal (steps 3–5).
2. Keep the edit-window block.
3. Write co-borrower edits back to the `Borrower__c` row.
4. Prefill from the previous form.
