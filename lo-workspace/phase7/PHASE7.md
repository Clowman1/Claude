# Phase 7: Pre-Approval Letter signer, licensing fields, LO Workspace nav, phone Lead page, Lead Notes

Status: built and validated (check-only) on 2026-10-01. **Not deployed.**

- **Validation:** `0AfQi000001TmWvKAK` succeeded with 13/13 components and 23/23 tests: LeadPreApprovalLetterTest (20) and EnhancedNoteControllerTest (3).
  - LeadPreApprovalLetterController coverage is 288/364 lines (79%).
  - The earlier validations (`0AfQi000001Tm8jKAC`, `0AfQi000001TmK1KAK`, `0AfQi000001TmOrKAK`) are superseded. Do not quick-deploy them.
- **Source:** fresh prod retrieves are in `ref/src/` (2026-10-01). Only changed or new components are in `force-app/`.
- **Rebuild script:** `scripts/build-phone-lead-page.js` regenerates the phone Lead page from `ref/`.

## Components in this deploy
| Component | Change |
|---|---|
| ApexClass `LeadPreApprovalLetterController` | Outside-LO signer restriction (below) |
| ApexClass `LeadPreApprovalLetterTest` | 5 new tests |
| CustomField `User.Licensed_States__c` | New |
| Layout `User-User Layout` | Licensed States added after NMLS # |
| PermissionSet `External_LO_Access` | Read-only FLS on Licensed_States__c |
| PermissionSet `LO_Licensing_Admin` | New: edit on NMLS__c and Licensed_States__c. **Not assigned.** |
| MutingPermissionSet `External_Loan_Officer_Muting` | Mutes edit on Lead.Pre_Approval_Letter_HTML__c; read is kept |
| PermissionSetGroup `External_Loan_Officer` | Adds the muting set. Components unchanged. |
| Profile `External Loan Officer Profile` (minimal XML) | User.NMLS__c is read-only (was edit) |
| CustomApplication `LO_Workspace` | Nav is Perfect Day only; phone Lead page assignments added |
| CustomTab `LO_Workspace` | Relabeled "Perfect Day" |
| FlexiPage `LO_Workspace_Lead_Phone_Record_Page` | New |
| LWC `externalLoLeads` | Notes tab on the My Leads lead detail (LO Workspace only) |

## A. Pre-Approval Letter
**Real components.**
- The quick action LWC `leadPreApprovalLetter` calls `LeadPreApprovalLetterController` in three steps: `getContext`, then `saveDetailsAndBuildLetter`, then `finalizeLetter`.
- VF `Lead_Pre_Approval_Letter`, via `LeadPreApprovalLetterPdfExtension`, renders the stored `Lead.Pre_Approval_Letter_HTML__c`.
- Today's signers are Brandon Brotsky (the default) and the Lead Owner.
- The legacy VF page `Preapproval_Letter` prints `$User` only. It is not in External_LO_Access, and it was not changed.

**For outside LOs (custom permission `External_LO`)**, all enforced in Apex:
- **Signer list:** `getContext` and `buildSignerOptions` return only their own card. There is no Brandon and no Lead Owner.
- **Signer choice:** `resolveSigner` refuses any other `signerId`.
- **Finalize:**
  - Their card sits between invisible HTML-comment markers.
  - `finalizeLetter` rebuilds the card from their User record, so typing in the editable preview cannot change the name, NMLS or photo.
  - If the markers are deleted, finalize refuses.
- **Saving the letter:**
  - `finalizeLetter` already saves with `Database.update(..., AccessLevel.SYSTEM_MODE)` for every user. So muting the field's edit permission does not affect it, and no save code changed.
  - A new test proves this with the real permission set group (including the muting set) assigned.

**Internal users:** unchanged. They get the same signer list, no markers, and finalize stores exactly what was typed.

**LO_Workspace_Demo (Brandon):**
- Nothing is restricted on the server.
- His own card is the default signer when it is in the list. It already was, because he is the Brandon default.

**Signature card:**
- The LO's `User.NMLS__c` (Text 255, verified) was already on the card.
- New: a "Licensed in FL, GA" line, only when `Licensed_States__c` is filled. Cards stay unchanged until it is filled.
- "Company NMLS #2266637" is unchanged.

## Licensing fields and access
**`User.Licensed_States__c`**
- Type: restricted multi-select picklist of 2-letter codes: 50 states, DC and PR (52 values).
- Why: clean codes for the card and the later landing pages. User has no record types, so the picklist-RT trap does not apply.

**Who can edit licensing info**
- Only admins can edit NMLS__c and Licensed_States__c, through the new `LO_Licensing_Admin` permset.
- Outside LOs can read both:
  - Licensed States is read-only via `External_LO_Access`.
  - NMLS__c is read-only on the profile. No permset in their group grants NMLS edit (checked against FieldPermissions).
- `LO_Workspace_Oversight` is not changed. It stays limited to alerts and the manager tab.
- The letter reads both fields in SYSTEM_MODE, so no one needs FLS for the card to print.

**Assign `LO_Licensing_Admin` to:**

| User | Id | Username | Profile | Admin? |
|---|---|---|---|---|
| Christopher Lowman | 005f2000009OtLnAAK | clowman@reachhomeloans.com | System Administrator | yes |
| Brandon Brotsky | 005f2000009NwSsAAK | bbrotsky@reachhomeloans.com | System Administrator | yes |
| Adam Stephens | 005f2000009BuuaAAC | astephens@reachhomeloans.com | System Administrator | yes |
| Jamie Martinez | 005Qi00000G3Pv7IAF | jmartinez@reachhomeloans.com | System Administrator | yes |
| **Bianca Rodrigues** (spelled with an "s"; no "Rodriguez" exists) | 0055x00000Bf9iaAAB | brodrigues@reachhomeloans.com | **Manager** | **no** (no Modify All Data) |

What the permset does and does not do for Bianca:
- It gives her field edit access, but she can still edit a User record only if her profile allows editing users (Manage Users).
- She is not an admin. Confirm with the owner that she is meant to have this.

**Muting:**
- `External_Loan_Officer_Muting` is in the External_Loan_Officer group.
- Outside LOs keep read on `Lead.Pre_Approval_Letter_HTML__c` but cannot edit it directly. That closes the route of editing the field directly and then opening the PDF page.

## B. App nav and phone Lead page
**Nav (owner decision: Perfect Day only, desktop and phone).**
- `LO_Workspace.app` `<tabs>` is now only `LO_Workspace`, relabeled "Perfect Day".
- `standard-Lead` and `Transaction__c` are removed from the nav.
- The four mobile section tabs, their app pages and their tab grants were dropped and are not in this deploy.
- The `externalLoPortalShell` start-section property and the `perfectDayHome` Log Activity auto-open existed only for those tabs. They were reverted, so no LWC is deployed.

**Checked: removing Lead and Transaction__c from the nav does not break navigation.**
- **Record page assignments:** the app-default and app + profile assignments are keyed on the app, not on its nav items, so they still apply.
- **"Open full loan"** (`externalLoLoans`) and the shell's record links (`portalRecordDrawer`) use `standard__recordPage`. That works without the object tab in the nav. With `isNavAutoTempTabsDisabled=false`, the record opens as a temporary nav item, on both desktop and phone.
- **Inside the shell:** the drawer routes Lead, Transaction and Account to its own sections first (`dispatchPortalNavigate`).
- **List views:** the drawer's `standard__objectPage` list fallback only runs outside the shell, which means the portal. It is not used in LO Workspace.
- Users can still open the Leads and Transactions lists from the App Launcher. Object tab visibility is unchanged.

**Phone Lead page: `LO_Workspace_Lead_Phone_Record_Page`**
- It is a copy of `Lead_Record_Page`, the internal phone page and org default for Small, with `homeToolsDrawer` (the Command Center drawer) removed.
- That page carries no Twilio component, so there was none to strip.
- Everything else is kept, including the "Lead Command Center" text banner.
- It is assigned the same way as 4d, in `LO_Workspace.app`:
  - App default (`actionOverrides`) for Lead, Small.
  - `profileActionOverrides` for Lead, Small, on `External Loan Officer Profile`.

## C. Notes on every outside-LO Lead view
The internal Lead page (`Lead_Expandable_Record_Page`) has a "Notes" tab that holds the **Aura** component `EnhancedNotes`.

**The three Lead views:**

| View | Notes tab |
|---|---|
| `LO_Workspace_Lead_Record_Page` (4d desktop) | Already there: same facet, same `EnhancedNotes`. No change. |
| `LO_Workspace_Lead_Phone_Record_Page` (new) | Already there: inherited from `Lead_Record_Page`, which has a "Notes" tab with `EnhancedNotes`. No change. |
| My Leads lead detail in the shell (`externalLoLeads`) | **Added.** |

**What was added to `externalLoLeads`:**
- An LWC cannot host an Aura component, so `EnhancedNotes` itself cannot be embedded.
- The new tab reuses the same parts instead:
  - The same Apex: `EnhancedNotesController.getNotesRelatedToLoan(leadId)`.
  - The same default filter: Type = Note or blank.
  - The same New button: it opens `/apex/AddNewNote?appId=<leadId>`, the note form the Lead page uses.
- Each note shows its subject, rich-text body, author and date, with a Refresh button.
- The role, user and search filters are not ported.
- The tab is hidden in the portal (`isExperienceCloudContext()`), because the controller and the VF page are not in the portal.

**Access check:**
- `EnhancedNotesController` and the `AddNewNote` VF page are both already in `External_LO_Access`.
- `EnhancedNotesController` and `EnhancedNotesRepository` are both `with sharing`. They do not call `RecordAccessGuard`, and the Phase 1b inventory judged that they did not need to.
- An outside LO only sees notes on records they can see. On top of that, the Phase 2 restriction rule on `Enhanced_Note__c` limits them to notes stamped `External_LO__c` = themselves, which covers the notes on their own leads.
- `LeadNotesFormController` is the Application Summary action, not the Notes tab. It is already in `External_LO_Access` and guarded since Phase 1b.
- `EnhancedNoteControllerTest` is included in the validation.
- **Caveat:** the New button uses `window.open`. That works on desktop, but the Salesforce mobile app may not open a popup. On a phone, use the Lead record page Notes tab.

## Tests (`LeadPreApprovalLetterTest`: 15 existing + 5 new, 20/20 pass)
The new tests use the real External Loan Officer profile and role.
- `outsideLoIsOfferedOnlyTheirOwnCardWithNmlsAndStates`: shows one option, their own, with their NMLS, "Licensed in FL, GA" and the company NMLS, and no Brandon.
- `outsideLoCannotAskForAnotherSigner`: passing another user's Id is refused on the server.
- `outsideLoFinalizePutsTheirOwnCardBackWhateverWasTyped`: a typed-in Brandon card is replaced and the other edits are kept. Missing markers are refused.
- `outsideLoInTheFullGroupCannotEditTheFieldButFinalizeStillSaves`: with the full group calculated and assigned (muting set and profile):
  - The letter field and NMLS__c read as readable and not updateable.
  - Finalize still stores the letter with their own card.
- `internalLettersCarryNoMarkersAndAreNotRewritten`: internal behaviour is unchanged.

## Deploy
From `lo-workspace/phase7`:
```
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LeadPreApprovalLetterTest --tests EnhancedNoteControllerTest --wait 60
```
Or quick-deploy: `sf project deploy quick -o Production --job-id 0AfQi000001TmWvKAK`. It must be used within 10 days.

## After deploy
1. Assign `LO_Licensing_Admin` to the five users above. Bianca only after confirming.
2. Fill NMLS # and Licensed States on the pilot's User record, then generate and finalize a letter as the pilot.
3. Confirm the External_Loan_Officer group shows status Updated after the muting change.
4. As the pilot, on desktop and phone:
   - The nav shows only Perfect Day.
   - "Open full loan" and the record links open the LO Workspace record pages.
   - On the phone, a Lead opens the new phone page with no drawer.
5. **Republish Partner Workspace.** `externalLoLeads` also runs in the portal, where the Notes tab is hidden.
6. As the pilot, open My Leads, then a lead, then Notes. Check that the notes list matches the Lead page Notes tab, and that New opens the note form.

## Open questions
1. **Bianca Rodrigues** has the Manager profile, not System Administrator. Should she still get `LO_Licensing_Admin`? Can her profile edit User records at all?
