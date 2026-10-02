# Phase 5: realtor and partner tagging (LO Workspace)

Status: **built and validated, NOT deployed.** Final dry-run `0AfQi000001Tl2zKAC` (2026-10-01, after the owner's answers) succeeded: 97 tests, 0 failures, 17 components, no coverage warnings.

Sources were retrieved fresh from `Production` on 2026-10-01. Before deploying, I re-checked `LastModifiedDate` on every touched class and bundle, and none had changed. `reference-prod/` is the untouched retrieve, kept for diffing. `reference-unchanged/` holds the files retrieved for reading only. `force-app/` contains only what changes.

## Data model

**Tag = `External_User_Assignment__c`**, the portal's existing junction object. It had 0 rows. I reused it, as preferred, and added two fields:

| Field | Purpose |
|---|---|
| `User__c` (existing) | The LO |
| `Contact__c` (existing; **changed to not required + SetNull**, was required + Restrict) | The partner's `PersonContactId`. The account is `Contact__r.AccountId`, so no Account lookup was needed. Deleting a duplicate Person Account is no longer blocked: its tags keep a null `Contact__c`, and every read (`myTags`, untag, stage change, lists, badges, the portal repository) filters `Contact__c != null`. A merge reparents tags to the keeper. Untag and stage change act on all of my rows for the account, so a merge that leaves me two rows is still handled |
| `Unique_Key__c` (existing, unique) | `userId:contactId`, same format the portal uses. It makes tagging idempotent |
| **`Stage__c`** (new, restricted picklist, default Prospect) | Prospect / Contacted / Meeting Set / Met / Active Partner / Dormant. Each LO keeps their own stage |
| **`Granted_Share__c`** (new, checkbox) | True when tagging created the LO's Manual AccountShare. Untag deletes the share **only** when this is true |

- OWD is Private (internal and external). The row is owned by the LO, so other LOs never see it. Managers see tags through the role hierarchy and admins through View All.
- A tag gives the LO **Read** on the partner Account through a Manual `AccountShare` (Read; Opportunity and Case None). Read is enough to log Tasks and Events. There is no Edit.
- Untagging removes the tag. It removes the share only when the tag created it. Ownership, sharing rules, a share that existed before the tag, and another LO's tag are never touched.
- The prod org has 0 Manual AccountShares today, so nothing existing is affected.

## What changed

| Component | Change |
|---|---|
| `LoWsPartnerTagService` (new, without sharing) | The tag model: `isTagMode()` (custom permission `External_LO`), `myTags`, `classify` (dedupe decision), `addPartner`, `tagExisting`, `tagAccounts`, `untag`, `setStage`, `industryFor` / `newPartner`, `myClosedLoans`, `consumerConflicts`. It acts only for `UserInfo.getUserId()` |
| `PersonAccountDuplicateService` | New `findMatchesAcrossOrg(emails, phones)`: a bulk, org-wide version with the same normalization, placeholders (`na@`, `tbd@`, 555…) and the same email/Email_2/mobile/phone/phone_2/home/other matching. One query for N inputs, through an inner `without sharing` class. It is **not** `@AuraEnabled`. `findMatches` now shares that code path but still runs **with sharing** with the same LIMIT 200, so Fred's tools and flows are unchanged. `normalizeEmail` and `normalizePhone` are now public |
| `ExternalLoPortalService` | In tag mode: `getRealtors` = my tags (Accounts read **with sharing**, so a row only shows while I can read it); `getPartnerDetail` adds my stage; the `prospects` filter means stage not yet Active Partner; never-touched partners count as **due**; no house lock on tagged rows; partner type comes from `BD_Industry__c`; phone falls back to mobile. `getPastClients` in tag mode = borrowers on my Funding / PC Review / Post-Closed loans (one row per borrower, newest loan, opens the loan) **plus** my imported past clients, i.e. Person Accounts I own with `Group__pc` including Client (opens the record page). Each person appears once. The portal keeps its Lead-based list. `countSharedBuyers` was changed from `USER_MODE` to `SYSTEM_MODE` (deep-dive bug 1; the `OwnerId` filter already scopes it). The DTOs gained `PartnerRow.stage` and `.tagged`, and `LeadRow.openView` |
| `ExternalLoPortalController` | New `tagPartner(accountId, email, phone)`, `untagPartner`, `setPartnerStage`. All three refuse anyone without `External_LO`. The existing method signatures are unchanged |
| `ExternalLoPartnerService` | In tag mode: `createPartner` follows rule 3 (`partnerType` now carries the BD industry) and returns `status` + `matches`. `linkPartner` (search "Link", previously a no-op) now tags a partner-type account the LO can already read |
| `ExternalLoCsvImportService` | **Past-client rows in tag mode (Type contains "past") become borrower Person Accounts, not New Leads.** Fields: RecordType `PersonAccount` (the only person record type borrowers use: 6,039 of 6,422 loan borrowers are `PersonAccount` with `Type__c = Borrower Account`), `Type__c = Borrower Account`, `Group__pc = Client`, Owner = the LO, mobile, email, `BillingCity` = city, `Description` = notes. Other consumer rows are still Leads. In-file repeats get "Same person as an earlier row". Results are reported in file order. Partner rows in tag mode: dedupe the whole file in one query, then tag a partner-type match, refuse any other match with the admin message, or create + tag. In-file duplicates get a row message, and a row needs a phone or email. Consumer rows in tag mode: someone else's lead (any status, Nurturing included, see the TODO), someone else's Person Account or client, or anyone else existing is refused with the admin message; my own lead or client gets "Already in your list (one of your leads / clients)" instead of being dropped silently. The row-count pre-check now ignores newlines inside quoted cells |
| `ExternalLoCsvParser` | Header aliases ("Phone Number", "Mobile", "Cell", "E-mail Address", "Brokerage", "Office", "Full Name", "First"/"Last", "Type"/"Industry", "City"...). An exact canonical column always wins over an alias |
| LWC `externalLoRealtors` | Default filter is All (it was 90 days). Each row shows a stage badge plus a "Change stage" action that opens a drawer. The detail page has a My stage select and "Remove from my list". Add partner gets a partner-type select (Fred's BD industries) and "Tag me" buttons when Reach already has the partner. The wire now has an error branch (it used to fail silently). Copy is per context |
| LWC `externalLoRealtorProspects` | Shows the stage badge. The dead `metaLabel` fallback was replaced |
| LWC `externalLoPastClients` | Loan rows open My Loans. Imported-client rows open the Person Account record page (LO Workspace only). Portal lead rows open My Leads |
| LWC `externalLoCsvImport` | Reads bytes and decodes strict UTF-8, falling back to Windows-1252 (Excel "CSV (Comma delimited)"). Falls back to `readAsText` if `TextDecoder` is missing |
| LWC `portalUtils`, `externalLoPortalShell` | Default Realtors filter changed from `'90'` to `'all'` |
| Fields `External_User_Assignment__c.Stage__c`, `.Granted_Share__c` | New |
| Field `External_User_Assignment__c.Contact__c` | Delete constraint Restrict → SetNull; required → not required |

**Partner-type** means `BD_Industry__c` is set (Fred's industries: Realtor, CPA, Title Agent, Insurance Agent, Financial Planner, Attorney, Builder, Other) **or** any of the org's realtor/title/insurance flags (`Is_Realtor__c`, `Type = Realtor`, `Type__c` Realtor/Title Agent Account, `Group__pc` includes Realtor / Realtor Prospect / Title Agent / Insurance Agent). Anything else counts as a non-partner match. When several partner accounts match, the oldest (the keeper) is offered first.

**New partners** are Person Accounts owned by the LO with these fields: `BD_Industry__c`; `Type__c` from Fred's TYPE_FOR_INDUSTRY map (copied, because it is private there); `Is_Realtor__c` for realtors; `Group__pc` for Realtor, Title or Insurance; `Company__c` and `PersonTitle` both set to the company (the portal reads the first, Fred's tools the second); `PersonMobilePhone`; `PersonEmail`; and `BillingCity` set to the market. `BD_Rep__c` and `BD_Stage__c` are not touched, because they belong to Fred.

## Tests (`LoWsPartnerTagServiceTest`, 10 methods)

The test creates two real outside LOs: profile External Loan Officer Profile, role External_Loan_Officer, and permission sets External_LO_Access + External_LO_Perfect_Day_Access. The test class runs **with sharing**, so every runAs assertion sees only what that LO can see. It proves:

- A partner match returns `match` with no new Account. Tag me grants Read, and tagging twice is a no-op.
- LO B sees 0 tags and 0 rows, cannot read the partner, and cannot change or untag A's tag or tag a partner it cannot see. B's own tag of the same partner keeps a separate stage, and A's stage is unchanged.
- Untagging removes A's Read and leaves B's access. A share an admin created beforehand survives the untag.
- A borrower match (by phone or email) is refused with the admin message and writes no share. A `na@na.com`-only partner is refused.
- A new partner is owned by the LO with the right BD fields, and it becomes a "match" for the next LO.
- The partner CSV with aliased headers, a quoted comma and a quoted newline, an in-file duplicate, and a borrower row produces 1 create + 1 tag; no duplicate Accounts are created.
- The consumer CSV, imported as LO A, produces:
  - own lead → "already in your list";
  - another LO's Nurturing lead → admin message;
  - another owner's borrower → admin message;
  - a new past client → a borrower Person Account owned by A (Type `Borrower Account`, Group `Client`), with no Lead;
  - an in-file repeat → "Same person";
  - a non-past row → a New Lead.
  Re-importing the client as A gives "already in your list". As B it gives the admin message, and no duplicate is created.
- Deleting a tagged partner Account succeeds. The orphaned tag (null `Contact__c`) is left out of My Realtors, Prospects and the badges. Untag or stage change on the deleted Id says "not on your list", and the other tag still works.
- Past Clients include a Post-Closed loan and a Funding loan and exclude a Cancelled one. A client I imported (inserted as the LO) who is also a borrower on my loan shows once. LO B sees nothing.

Existing suites still pass: the portal behavior tests (ExternalLoPortalServiceTest, ExternalLoPortalCoverageTest, ExternalLoCsvImportServiceTest, ExternalLoPartnerCsvImporterTest), PersonAccountDuplicateServiceTest, BdCommandCenterControllerTest, ExternalLoActivityLogServiceTest and PerfectDayHomeServiceTest.

Coverage: LoWsPartnerTagService 95%, PersonAccountDuplicateService 95%, ExternalLoCsvParser 95%, ExternalLoPartnerService 93%, ExternalLoCsvImportService 92%, ExternalLoPortalService 86%, ExternalLoPortalController 83%.

## Deploy command (when approved)

Run it from `C:\Apps\Claude Back Up\lo-workspace\phase5`. `force-app` contains only the 17 changed components.

```
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LoWsPartnerTagServiceTest --tests PersonAccountDuplicateServiceTest --tests BdCommandCenterControllerTest --tests ExternalLoPortalServiceTest --tests ExternalLoPortalCoverageTest --tests ExternalLoCsvImportServiceTest --tests ExternalLoPartnerCsvImporterTest --tests ExternalLoActivityLogServiceTest --tests PerfectDayHomeServiceTest --wait 60
```

`sh run-dryrun.sh out.json` repeats the validation with `--dry-run`. Before deploying, re-check `LastModifiedDate` on the 6 classes, the 6 bundles and the `External_User_Assignment__c` fields. Nimbus has overwritten components before. If any changed after 2026-10-01, re-retrieve and merge.

After deploying, as the pilot user (`005Qi00000iSURvIAO`): add a partner who already exists, tag them, change their stage, untag, import a small CSV, and open Past Clients.

## Portal (Partner Workspace) impact

Tag mode is keyed to the `External_LO` custom permission. Only the internal pilot holds it. The portal users (Harold Ellis, Noah Admin) and Brandon do not. So the portal keeps its partner record set, `createPartner`, `linkPartner`, its CSV importer and its consumer dedupe unchanged, and the old portal tests still pass. The portal does see these changes:

1. **The Realtors list opens on "All partners"** instead of "Last 90 days". The same LWC default serves both contexts. This is the deep-dive bug 7 fix.
2. **`countSharedBuyers` now runs in SYSTEM_MODE**, which fixes the likely live portal failure (deep-dive bug 1).
3. **CSV header aliases, quote-aware row counting and Windows-1252 decoding** apply in the portal too.
4. The Realtors wire now shows an error message instead of an empty list.

Unchanged in the portal: house lock, "due" semantics (touched 7+ days ago), and Prospects = `Group__pc = 'Realtor Prospect'`.

## Owner decisions (2026-10-01)

1. **House accounts** (Biz Dev - Reach / Bondarevsky): outside LOs may tag them. The current behavior stays.
2. **A realtor who is also a borrower** can be tagged for now, because the partner flags win. No change.
3. **Deleting tagged accounts**: `Contact__c` is now SetNull (see Data model). Orphaned tags are ignored and never cleaned up automatically. They are harmless, and an admin can delete rows with a blank Contact.
4. **Imported past clients** are borrower Person Accounts, not New Leads. This fixes deep-dive bug 8 in LO Workspace. The portal keeps its Lead-based import and view.

## Still open

1. **Mixed matches.** When an email or phone matches both a partner and a non-partner (for example a shared office line), the partner is offered and the non-partner is ignored.
2. **FLS on the new fields.** I added no permission-set changes, because all access goes through Apex. Reports or list views on tags (Phase 8 oversight) will need Read FLS on `Stage__c` and `Granted_Share__c` in a manager permission set.
3. **Phase 6 hook.** `LoWsPartnerTagService.consumerConflicts` carries the `TODO Phase 6` marker. Nurturing-lead matches are refused until the takeover path exists. Manual lead add and the webhook are not covered here.
4. **Untag and other Manual shares.** If something else later writes a Manual Read share for the same user and account, Salesforce keeps a single row, and an untag with `Granted_Share__c = true` would delete it. Nothing else creates Manual AccountShares today.
5. **The duplicate check reports names.** Before the LO has access, "Tag me" shows only the matched partner's name and company. It never shows the owner, phone or email. A refused match shows no name.
6. **Imported past clients carry no loan data.** Lead rows keep the CSV purpose and loan amount. A past-client Person Account keeps only name, phone, email, city and notes.
7. **`ExternalLoCommunicationService.logCommunication` still has no RecordAccessGuard check.** It is with sharing, so the Task insert fails without Read on the record. That was outside Phase 1b's scope and is unchanged here.
