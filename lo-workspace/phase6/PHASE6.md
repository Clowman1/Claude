# Phase 6: lead intake, duplicates and takeover (LO Workspace)

Status: **built and validated, NOT deployed.** Check-only validation `0AfQi000001TlpNKAS` (2026-10-01, after the owner answers below) succeeded: 77 tests, 0 failures, no coverage warnings. (The first validation, `0AfQi000001TlfhKAC`, is superseded.)

## Owner answers (2026-10-01), applied

1. A takeover also clears `Biz_Dev__c`, `Scenario_Manager__c` and `Other_Lead_Team_Member__c`. I checked every active Lead flow, validation rule and Apex reference to these fields; none blocks clearing them or puts a value back:
   - `Lead_Default_Scenario_Manager` runs on create only.
   - `New_Lead_from_Realtor_Intake_Form` sets Biz Dev only when the record changes to meet its referral criteria.
   - `Update_Lead_Information_on_New_Referral` runs on create only.
   - Other flows only read the fields.

   The Other member's Manual share goes with the owner change, and the share handler re-creates nothing for a null value. Clearing Biz Dev also means the BDR "LeadQualified" Zap no longer fires on a takeover. The tests assert all three fields are null and that the old team keeps no share.
2. Custom_Log__c access removed from `External_LO_Access` (retrieved fresh; the object entry is now all false, which is how a permission set deploy removes it; the permission set had no Custom_Log__c FLS).
   - I checked all 71 classes in External_LO_Access + External_LO_Perfect_Day_Access, plus every LWC. Only `RealtorLeadConvertService` writes a log, and it uses a plain `insert`, which is system mode.
   - The 4 flows that touch Custom_Log__c are record-triggered or platform-event flows, so they run in system context.
   - The External Loan Officer **Profile** still carries inert Data__c/Errors__c FLS. Without object Read it grants nothing; I left the profile alone (profile deploys are risky here: renamed standard profiles).
3. The webhook keeps accepting any active internal user.
4. **Changed:** admin alerts go to holders of the new custom permission `LO_Workspace_Oversight` (new permission set of the same name). Phase 8 will reuse it. With no holders, the log row is still written and the push is skipped.

Every source was retrieved fresh from `Production` on 2026-10-01 into `ref/` (untouched, for diffing). `force-app/` holds only what changes (30 files).

## What it does

One service, `LoWsLeadIntakeService` (without sharing), makes the duplicate decision for all three intake paths: the landing-page webhook, Add lead, and the consumer CSV import. It matches on email or phone/mobile, against Leads (converted ones included) and Person Accounts. Placeholders such as `na@na.com` never match, because it reuses `PersonAccountDuplicateService.normalizeEmail`.

| Match | Result |
|---|---|
| Someone else's lead in a Nurture status (`Nurtur*` or `30 Day + Follow Up`, the same set as the My Leads Nurture tab) | **Taken over** by `takeOver()`, the only takeover path: Owner = the new LO, Status `New`, `Loan_Partner__c`, `Biz_Dev__c`, `Scenario_Manager__c` and `Other_Lead_Team_Member__c` cleared, Lead Source replaced if a new one is given (blank keeps the old one), `LO_Takeover_At__c` stamped. History stays on the lead. Before updating, it re-checks that the lead is still unconverted and Nurturing. This works in both directions: the webhook accepts any active internal user as the LO |
| Someone else's lead in any other status, a converted lead that isn't mine, or someone else's Person Account (borrower or past client) | Refused with *"This person is already being worked by another Reach loan officer. Contact an admin."* No name is shown. Admins are alerted |
| My own lead or client | "Already in your list" (the Phase 5 messages) |
| Nobody | Created as before |

When several rules match, the order is: blocked, then own, then takeover.

**Admin alert:** one `Custom_Log__c` row (Source `LO Workspace Duplicate Blocked`, which names the matched record Ids and the LO who tried). There is also a custom notification `LO_Workspace_Lead` (desktop + mobile) to **every active holder of the `LO_Workspace_Oversight` custom permission** (found through SetupEntityAccess → PermissionSetAssignment, which works in the Automated Process subscriber), targeting that log row. If nobody holds it, only the log row is written. A CSV import raises one alert for all of its blocked rows. Add lead refuses by throwing, which rolls the transaction back. The alert therefore travels as an immediate-publish platform event (`LO_Workspace_Intake__e`, `kind=alert`), and the Automated Process subscriber writes it.

**Previous owner:** not notified. The only owner-change email flow (`Lead_Owner_Transfer_Email_Notification`) mails the new owner.

**Child records:** `External_LO__c` is restamped on owner change. `ExternalLoRestampLead` watches `OwnerId` and `Loan_Partner__c` and fires whenever the old or new value is an outside LO. That was verified in the source and runs in the tests.

**Loan Partner access:** clearing the Loan Partner deletes that user's Manual LeadShare (`LeadLoanPartnerShareTriggerHandler`), and an owner change removes Manual shares anyway. The test asserts that the old Loan Partner keeps no share.

**No default Loan Partner for outside LOs:** both stamping automations (the Apex `LeadLoanPartnerAssignmentService` and the flow `Assign_Loan_Partner_on_Lead`) copy the owner's `User.Loan_Partner__c`. When that is blank, the flow clears the field, and both outside-LO users have it blank today. I made **no automation change**. The exemption holds as long as outside-LO users keep `User.Loan_Partner__c` blank, and the webhook test asserts that a new landing-page lead has no Loan Partner. The Nimbus default only ever came from Christopher's own user record.

### Landing-page webhook

- `POST https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/lo-landing-page`. This is the Integrations site, the same one as the Zoom webhook. Confirm the host in Setup → Sites.
- Header `X-Reach-Webhook-Key: <secret>`. The secret is compared case-sensitively against `LO_Landing_Page_Config__mdt` record `Default`, field `Webhook_Secret__c`. This is the same pattern as `Zoom_Webhook_Config__mdt`. With no record or a blank secret, the webhook answers `503` and creates nothing.
- JSON body:
  - `loEmail` (required): the LO's **Username**, or an email that matches exactly one active internal user. A username always wins.
  - `firstName` + `lastName`, or `name`.
  - `email` and/or `phone`.
  - Optional: `leadSource`, `loanPurpose`, `city`, `state`, `notes` (or `message`).
  - A body containing `kind` is refused. That key is reserved for alerts.
- Response codes: `202` accepted, `400` bad body, `401` bad key, `503` not configured.
- **Why there is a platform event:** the guest user can read and create but never update (see `ZoomRecordingWebhook`), and a takeover is an update. So `LoLandingPageWebhook` only authenticates, checks the body and publishes `LO_Workspace_Intake__e`. The trigger `LoWsIntakeEvent` then runs `LoWsLeadIntakeService.handleEvents` as **Automated Process**. It handles one event per run (with a resume checkpoint), because a single lead save fires all 40 flows and 9 triggers.
- Lead Source is `LO Landing Page`, unless the payload sends an **active** Lead Source value, in which case that value is used. An unknown value falls back to `LO Landing Page`. The new value was added to the `LeadSource` standard value set **and** to the Consumer, Realtor and Loan Officer Lead record types (the record-type trap). New leads use the `Consumer_Lead_record_type`, Status New, Owner = the LO, and Company "<Last> Household" (same as Add lead).
- **Every submission is logged** in `Custom_Log__c`:
  - Accepted submissions are logged by the subscriber (Source `LO Landing Page`, with `Lead__c`, the outcome and any `Errors__c`).
  - Rejected calls are logged by the webhook (Source `LO Landing Page Rejected`). The body is never stored when the key is wrong.
  - Success rows keep **no contact details**, because `Custom_Log__c` is Public Read/Write and internal loan officers can read `Data__c` (outside LOs no longer can).
  - Blocked and error rows keep the payload so an admin can act on them.
- **On arrival:**
  - Push: the `LO_Workspace_Lead` custom notification goes to the LO and targets the lead.
  - Email: I built no separate email, because existing automation already sends one. `ManualLeadOwnerNotification` mails the LO "A new Salesforce Lead has been created and assigned to you" on insert. On a takeover, `Lead_Owner_Transfer_Email_Notification` mails "Salesforce Lead transferred to you". Both send from reachus@. A second email would only duplicate these.
  - Blocked: the LO gets a push with the refusal message and no name, and the admins are alerted.
  - Already the LO's own lead: the LO gets a push "(already one of yours)", and the log links that lead.
- **Perfect Day:** `PerfectDayHomeService` puts the LO's landing-page leads first, newest submission first. These are New, unconverted leads with a `LO Landing Page` log in the last 30 days. They are loaded separately, so a taken-over lead created before 2024 still shows. A lead deferred from Perfect Day still waits for its return time. Up Next shows "New lead from your landing page".

### The locks: one deliberate exception

`Lead.LO_Takeover_At__c` (DateTime) is new. It has **no FLS on any profile or permission set**, so only system-mode Apex can write it, and `takeOver()` is the only code that does. Four Lead validation rules gained `NOT(ISCHANGED(LO_Takeover_At__c))`:

| Rule | Why it would otherwise block the takeover |
|---|---|
| `Lead_Source_Change_Restricted` | The webhook subscriber (Automated Process) is neither the owner nor the Loan Partner |
| `Loan_Officers_Cannot_Change_Owner` | "External Loan Officer Profile" contains "Loan Officer", so Add lead and CSV takeovers were refused (the first validation caught this) |
| `Calls_Required_for_Status_Change` | 2,846 Nurturing leads on Consumer Purchase/Refinance record types would refuse the Status → New change |
| `Lead_already_claimed` | 41 open "Facebook - Landing Refi" leads |

Every other change to these fields is blocked exactly as before. The test `leadSourceLockStillBlocksEveryoneElse` proves that a non-owner with Edit access is still refused.

## Components (`force-app/`)

| Component | Change |
|---|---|
| `LoWsLeadIntakeService` (new) | decide / takeOver / alertAdmins / webhook subscriber / Perfect Day helpers |
| `LoLandingPageWebhook` (new, `@RestResource /lo-landing-page`) | Guest endpoint: authenticates, checks the body, publishes the event |
| `LoWsIntakeEvent` trigger (new) on `LO_Workspace_Intake__e` (new HighVolume event, PublishImmediately, `Payload__c`) | Subscriber |
| `LO_Landing_Page_Config__mdt` (new) + `Webhook_Secret__c` | Secret. **No record is deployed**, so redeploying never overwrites a secret |
| `Lead.LO_Takeover_At__c` (new) | Takeover stamp and lock bypass |
| 4 Lead validation rules | `NOT(ISCHANGED(LO_Takeover_At__c))` added |
| `StandardValueSet LeadSource` + 3 Lead record types | `LO Landing Page` added (the record-type files carry only the standard picklists, exactly as retrieved, plus the one value) |
| `CustomNotificationType LO_Workspace_Lead` (new) | Desktop + mobile |
| Custom permission + permission set `LO_Workspace_Oversight` (new) | Alert recipients now, the Phase 8 manager tab later |
| Permission set `External_LO_Access` | Custom_Log__c object access removed |
| Permission set `LO_Landing_Page_Webhook_Guest_Access` (new) | Class access + create on the event, for the Integrations guest user only |
| `ExternalLoLeadService` | Add lead in tag mode (`External_LO`): run decide first, then take over / refuse + alert / "already in your list". Portal behaviour is unchanged |
| `ExternalLoCsvImportService` | Consumer rows in tag mode use decide. Takeovers are applied in one update and reported as "Added to your list." A past-client row that matches someone else's Nurturing lead takes the **lead** over with Lead Source `Past Client`. Other rows keep the old source. Two rows hitting the same lead give "Same person". Blocked rows raise one alert |
| `LoWsPartnerTagService` | `consumerConflicts` removed (moved into decide). The Phase 6 TODO is gone |
| `PerfectDayHomeService` | Landing-page leads first, plus the Up Next detail |
| `LoWsLeadIntakeServiceTest` (new, 10 methods), `LoWsPartnerTagServiceTest` | The Phase 5 CSV case now expects the takeover and the new refusal message |

## Tests

`LoWsLeadIntakeServiceTest` runs as two real outside LOs (profile + role + `External_LO_Access` + `External_LO_Perfect_Day_Access`). LO B's default Loan Partner is the admin, so B's leads carry a Loan Partner and a share. The tests cover:

- **Add-lead takeover:** owner, New, source replaced, Loan Partner null, share gone, no duplicate.
- **Refusals:** a Working lead, matched by email and by phone; another owner's borrower Person Account. Each produces the admin message plus one alert log per refused add. An own lead gives "already in your list".
- **Placeholder:** `na@na.com` does not match.
- **The lock still blocks a non-owner.**
- **CSV:** takeover, a same-person row, a blocked row and a new row.
- **Webhook create:** source fallback, no Loan Partner, a log without PII, and Perfect Day order + Up Next as the LO.
- **Webhook takeover:** runs as Automated Process past the lock.
- **Webhook refusals:** blocked, unknown LO, own re-submission; also 503 / 401 (including the wrong case) / 400 ×3, plus the reject logs.

Coverage: LoLandingPageWebhook 93%, LoWsLeadIntakeService 93%, LoWsIntakeEvent 100%, ExternalLoLeadService 98%, ExternalLoCsvImportService 93%, LoWsPartnerTagService 96%, PerfectDayHomeService 92%.

The portal suites still pass (ExternalLoPortalServiceTest, ExternalLoPortalCoverageTest, ExternalLoCsvImportServiceTest, ExternalLoPartnerCsvImporterTest, PerfectDayHomeServiceTest, including its query budget of 16 or fewer).

## Deploy (when approved)

From `C:\Apps\Claude Back Up\lo-workspace\phase6`:

```
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LoWsLeadIntakeServiceTest --tests LoWsPartnerTagServiceTest --tests ExternalLoPortalServiceTest --tests ExternalLoPortalCoverageTest --tests ExternalLoCsvImportServiceTest --tests ExternalLoPartnerCsvImporterTest --tests PerfectDayHomeServiceTest --wait 60
```

Alternatively, run `sf project deploy quick -o Production --job-id 0AfQi000001TlpNKAS` while the validation is still quick-deployable. `sh run-dryrun.sh out.json` re-validates.

**Before deploying,** re-check `LastModifiedDate`. Nimbus has rolled things back before. At retrieve time the values were:

- ExternalLoCsvImportService / LoWsPartnerTagService / LoWsPartnerTagServiceTest: 2026-10-01 15:28 (Christopher)
- ExternalLoLeadService: 2026-09-01 (Nimbus)
- PerfectDayHomeService: 2026-09-14 (Nimbus)
- The 4 validation rules: Lead_Source_Change_Restricted 2026-09-14, Loan_Officers_Cannot_Change_Owner / Lead_already_claimed 2026-07-20, Calls_Required 2024-05-15

**After deploying** (all three steps are data or Setup work, not metadata):

1. Assign `LO_Landing_Page_Webhook_Guest_Access` to **Integrations Site Guest User** (`005Qi00000FehqSIAR`): `sf data create record -o Production -s PermissionSetAssignment -v "AssigneeId=005Qi00000FehqSIAR PermissionSetId=<id>"`.
2. Setup → Custom Metadata Types → LO Landing Page Config → New → Label/Name `Default`, then paste a generated secret. Give that secret to marketing.
3. Smoke test. Use `loEmail` = `outsidelo.internal@reachhomeloans.com`, which is the pilot's **username**. Its email (clowman@) is shared with Christopher's user, so an email-only match would be ambiguous and refused. Send a test person with a fresh email, then check the lead, the push, the email and the Perfect Day order. The test lead is owned by the pilot, so delete it with the other TEST data.

4. Assign permission set `LO_Workspace_Oversight` to Christopher Lowman `005f2000009OtLnAAK`, Brandon Brotsky `005f2000009NwSsAAK` and Adam Stephens `005f2000009BuuaAAC`.

No flow is changed, so no activation step is needed.

## Outbound side effects found

- **Insert (webhook):** the lead runs the normal Lead stack. Emails go to the LO (see above). There is no Zapier insert hook for a lead with a blank `Biz_Dev__c`. `Website_Lead_Internal_Notification` (Twilio SMS) fires only if the payload sends a `Website*` source.
- **Takeover to New:**
  - `ReachNewLeadWebhook` ("LeadQualified" to Zapier for Biz Dev - Reach + New) no longer fires on a takeover, because Biz Dev is cleared in the same save.
  - The status SMS to buyer's agents (`Lead_Status_Change_Message_Sends`) fires only for Contact Attempt 1/2/3 and Pre-Approval, so it does **not** fire on New. 7,670 Nurturing "Realtor Referral" leads have a buyer's agent. If one is taken over **keeping** that source (Add lead with no source, a CSV non-past row) and the new LO later moves it to Contact Attempt 1, that agent gets the usual texts. The webhook always replaces the source.
  - `LeadStatusWebhook` / `ConsumerWebinarLeadStatusWebhook` do not fire, because the old status is not an early-contact status.
- `Lead_Keep_First_Owner_Assignment` could revert a takeover only for a lead moved off "Intake Form Queue" **today**. Nurturing leads practically never are.
- The tests make no callouts. The Zapier/Twilio paths are not reached with the test data, and email sends are suppressed in tests.

## Open questions

None. All of them were answered on 2026-10-01 (see Owner answers).
