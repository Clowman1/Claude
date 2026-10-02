# Phase 9 — Log an activity: picker, notes, logged calls, category matching

Validated (check-only) 2026-10-02: **0AfQi000001TsAvKAK**, 65/65 tests. NOT deployed.
Coverage with the tests below: ExternalLoActivityLogService 94%, ExternalLoCommunicationService 98%, ExternalLoPortalService 85%.

Deploy (from `lo-workspace/phase9log`):

```
sf project deploy quick -o Production --job-id 0AfQi000001TsAvKAK
# or, if the validation expired:
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests ExternalLoActivityLogServiceTest --tests LoWsActivityLogTest --tests ExternalLoPortalServiceTest --tests ExternalLoPortalCoverageTest --tests PerfectDayHomeServiceTest --tests LoWsPartnerTagServiceTest
```

Then republish Partner Workspace (portalContactPicker / portalActivityModal / externalLoLeads / externalLoLoans are in the portal).

`force-app` holds only changed components. Fresh prod copies of everything else read are in `ref/` (not deployed).

## Changed
- Apex: ExternalLoActivityLogService, ExternalLoCommunicationService, ExternalLoPortalService, ExternalLoActivityLogServiceTest (2 tests logged Realtor outreach / Partner meetings against a consumer Lead; now Consumer convos), new LoWsActivityLogTest.
- LWC: portalContactPicker, portalActivityModal, externalLoLeads, externalLoLoans.
- ExternalLoPortalController is unchanged.

## 1. Picker
- Placeholder "Search your leads, partners and past clients"; "Searching…"; the no-match text; helper text under the field when the category needs a contact. The selected state is still only the chip with Clear. Save with a contact-bound category and no pick now says "Pick who you talked to from the search results."
- Tag mode (LO Workspace) search = my leads (5) + my tagged partners (5) + my client Person Accounts (`myClientAccounts`, 5) + borrowers on loans where Loan_Officer__c = me (5). Max 20. The portal keeps 10 leads + partners up to 20.
- Subtitles: `Lead · <status>`, `Partner · <type>`, `Past client`, `Borrower · <loan status>`.
- **Borrowers log against the loan (Transaction__c), not the borrower Person Account.** Outside LOs get Read on their loans (LoanOfficerRecordSharingService) but not on the borrower's account, so RecordAccessGuard would refuse the account.
- Server: logActivity and logCommunication had **no** record-access check (both insert in SYSTEM_MODE). Both now call `RecordAccessGuard.requireRead` for Standard users (LO Workspace, Brandon). Partner Workspace users are skipped: their partner list isn't modelled by Account sharing, so the guard could break portal logging. That portal gap is pre-existing. The service now takes the object type from the Id, not from the client.

## 2. Notes → Enhanced_Note__c
- Tag mode only (outside LOs + Brandon's demo permission). Lead → Lead__c, Transaction → Transaction__c, Account → Account__c. Type Note, Subject `<Channel> — <Category>` (for example "Call — Consumer convos"), Body = the notes, HTML-escaped, with line breaks turned into `<br>`. These are the same fields AddNewNote sets.
- **Duplicate avoided:** flow `Create_Enhanced_Note_on_New_Task` already copies a completed Task's Description to an Enhanced_Note__c (Type Call/Text). Those notes are hidden from the Notes tab, which shows only Note/blank. When we write our own note, the Task gets `Create_Enhanced_Note__c = false`. One note per log (tested).
- Stamp verified by test: ExternalLoStampEnhancedNote sets External_LO__c = the LO on a lead they own.
- Side effect: a Type Note on a consumer Lead triggers LeadNoteTeamNotifier, which emails the Lead Owner (the LO, even as author) and the Loan Partner. This is the same thing AddNewNote does.
- Test gotcha: a test user with only External_LO_Access + External_LO_Perfect_Day_Access can't insert a Lead note (EnhancedNoteLeadLastNote → "Variable does not exist: tmpVar1"). The pilot user and a user with the PSG External_Loan_Officer can. Tests assign the PSG.

## 3. Logged calls (Calls/Zooms tab)
- `LeadDetail.loggedCalls` / `LoanDetail.loggedCalls` (ExternalLoPortalService.loggedCalls). These are completed Tasks on the record with `Task.Type` Call/Meeting, or older rows with a call/meeting Activity_Type__c, where `CallType = null`, so RingCentral rows stay in RingSense. All authors are shown. SYSTEM_MODE (Activity_Category__c FLS exists only in the External LO permsets), and the query runs after the record's own visibility check.
- Each row shows Call/Meeting, the category plus outcome, the date and time, "Logged by", and the notes. Subject is never read.
- Both services now set `Task.Type` (Call / Meeting), and logCommunication stores the outcome in `CallDisposition`.
- Shown only outside the portal (the Apex returns an empty list to portal users).
- 4d Lightning record pages: **skipped**. They host the call lists through other components, so this would need a new wrapper LWC.

## 4. Category must match who was contacted
- Root cause (Log communication): the Task had no Activity_Category__c, so ExternalLoActivityRollupBuilder fell back to Activity_Type__c. Call types are listed under Realtor outreach, Consumer convos and Past clients, and Realtor outreach sorts first, so every call credited Realtor outreach.
- The target kind comes from `ExternalLoActivityLogService.targetKind`:
  - Lead → consumer, or client if LeadSource = 'Past Client' or the lead is converted.
  - Transaction → client (borrower).
  - Account in tag mode → partner if `LoWsPartnerTagService.isPartner`; otherwise client (Group Client / Borrower Account / borrower on a loan / converted-lead account) or consumer.
  - Account in the portal → always partner (its old assumption, so portal realtor credit doesn't change).
- Allowed: Realtor outreach + Partner meetings → partner only; Consumer convos → consumer or client; Past clients → client. Social posts and other no-contact categories aren't checked. The catalog has no object-type field, so this is a 4-key map in the service.
- logActivity rejects a mismatch, for example "Realtor outreach must be logged against a realtor or partner. Pick Consumer convos for a lead."
- logCommunication sets the category: partner → Realtor outreach (Partner meetings for in-person/video); Lead → Consumer convos (Past clients for a Past Client lead); Transaction → Consumer convos while open, Past clients once Funding/PC Review/Post-Closed. Choice: the person on a loan is the borrower, and a closed loan's borrower is a past client.
- Activity_Type__c: partner targets keep the channel type (Call - Active Agent). Consumer and client targets take the category's own non-agent credit type for that channel (Call - Prospecting). A consumer or borrower meeting has none, so Activity_Type__c is left blank (credit comes from the category).
- Modal: picking a contact selects its category (lead → Consumer convos, partner → Realtor outreach, past client/borrower → Past clients, open loan → Consumer convos). Contact-bound categories that don't fit are disabled. A no-contact category already chosen is left alone.
- This applies to the portal too. A portal Lead call now credits Consumer convos instead of Realtor outreach (the same bug was there). Portal Accounts still credit Realtor outreach.

## Pilot's mis-credited call (not changed)
Task **00TQi00001dMmOzMAK** on lead 00QQi00000sEQOXMA4 ("Call - connected", Activity_Type__c Call - Active Agent, no category) counts as Realtor outreach today. To correct it, set `Activity_Category__c = 'Consumer_Conversation'` and optionally `Activity_Type__c = 'Call - Prospecting'`, `Type = 'Call'`. Note that the update re-appends a timestamp to Subject (org automation). It is pilot test data on a TEST lead, so the alternative is to leave it and delete it with the test data. Recommendation: correct it only if the owner is watching this week's progress numbers.
The other pilot log, 00TQi00001dNXfcMAG (Realtor outreach on Chris Rey, a Realtor Account), is correct.

---

# Item 5 — Social posts: platform instead of channel/contact

Items 1-4 were deployed by the parent as **0AfQi000001TsFlKAK**.

Validated (check-only) 2026-10-02: **0AfQi000001TsIzKAK**, 41/41 tests, ExternalLoActivityLogService 95%. NOT deployed.

```
sf project deploy quick -o Production --job-id 0AfQi000001TsIzKAK
# or
sf project deploy start -o Production -d force-app/main/default/lwc/portalActivityModal -d force-app/main/default/classes/ExternalLoActivityLogService.cls -d force-app/main/default/classes/LoWsActivityLogTest.cls --test-level RunSpecifiedTests --tests ExternalLoActivityLogServiceTest --tests LoWsActivityLogTest --tests ExternalLoPortalCoverageTest --tests PerfectDayHomeServiceTest
```
Then republish Partner Workspace (portalActivityModal is shared).

- Modal: when Social posts is selected, "How did you reach out?" and "Who did you talk to?" are hidden and a required Platform chip row is shown. The list is the `PLATFORMS` constant at the top of portalActivityModal.js. "Other" opens a 40-character text field. How many? and Notes stay. Switching to Social posts clears any picked contact.
- Save sends no record and no channel, and notes = `Platform: <platform>`, then a new line and the LO's notes.
- Server (logActivity): Social posts with a record is rejected with "Social posts are not logged against a contact. Clear the contact and pick the platform." The channel is ignored, so Task.Type stays blank and the post never appears in Logged calls. Activity_Type__c = the first type the catalog credits to Social posts (Text). Category Social_Engagement. No record, so no Enhanced_Note__c.
- Platform is required in the UI only. The server doesn't parse the Description, because older callers and tests log Social posts without one.
- Test: LoWsActivityLogTest.socialPostHasNoContactNoChannelAndCreditsSocialPosts.
