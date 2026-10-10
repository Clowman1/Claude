# Phase O2b – O2 follow-ups

`ref/src` holds the prod copies retrieved 2026-10-09 (after O2 deploy 0AfQi000001UOPJKA4). Every change was built from them.

## 1. Zoom check throttled (LoWsOnboardingGateService)

`getConnectionIssues` (Perfect Day banner, after the gate) used to make a live Zoom callout on every LO Workspace load.
Now it calls out only when `LoWs_Zoom_Verified_At__c` is blank or older than `ZOOM_RECHECK_HOURS` (24):
- success: restamps `LoWs_Zoom_Verified_At__c` (SYSTEM_MODE, after the callout);
- failure: the banner shows and the stamp stays stale, so the next load checks again.
The gate itself (`evaluate`, before it is passed) is unchanged and still checks live until Zoom is green.
Note: a failed re-check does not clear the stamp, so the Oversight roster keeps showing Zoom green until the LO reconnects. Clear it on failure if the roster should go red too (one field in the same update).

## 2. LoWsLeadIntakeServiceTest.webhookRejectsBadCalls (test was wrong)

The 503 "not configured" assertion depended on org data: O1 created the real `LO_Landing_Page_Config__mdt.Default`, so the webhook answered 401.
`LoLandingPageWebhook.testSecret` is already a `@TestVisible` seam, and `getSecret()` returns it whenever it is non-null. The test now sets it to `''` first. A blank secret is the "not configured" path, so the real 503 behaviour is still tested.
No change to `LoLandingPageWebhook`.

## 3. ExternalLoCsvImportServiceTest – 4 failures (test was wrong, not the code)

Root cause: the tests ran as whoever runs the tests (Chris), and Chris holds permission set `LO_Workspace_Demo` (as does Brandon). `LoWsPartnerTagService.isTagMode()` is true for `External_LO` **or** `LO_Workspace_Demo`. So these Partner Workspace (portal-mode) tests were running the LO Workspace path:
- an existing own-lead match became a "Same person as an earlier row" error (errorCount 2 instead of 1, and "1 need attention");
- partner rows went through tag classification instead of portal linking (linkedCount 0).

Phone reformatting (FormattingUtility / PhoneFormat*) is NOT the cause. Matching uses `ExternalLoPhoneNormalizer` keys, and once the running user stops holding the demo permission all 10 tests pass.
Fix (test only): `@testSetup` creates a dedicated admin (`csvimp`, same profile as the runner, no `LO_Workspace_Demo`) with portal access, and every test runs as it (`importer()` replaces `ExternalLoPortalTestHelper.currentUser()`).
Separate observation, not changed: in LO Workspace (tag) mode, a row matching the LO's own existing lead is reported as "Same person as an earlier row. Imported once." The wording is wrong for that case (it is an existing lead, not an earlier row).

## Components

| Component | Change |
|---|---|
| `LoWsOnboardingGateService` | 24h Zoom re-check throttle in `getConnectionIssues` |
| `LoWsOnboardingGateServiceTest` | + `bannerRechecksZoomAtMostDaily` |
| `LoWsLeadIntakeServiceTest` | `webhookRejectsBadCalls` sets `testSecret = ''` |
| `ExternalLoCsvImportServiceTest` | dedicated `csvimp` runner |

## Validate / deploy

`sh run-validate.sh` runs LoWsOnboardingGateServiceTest, LoWsLeadIntakeServiceTest and ExternalLoCsvImportServiceTest.
**0AfQi000001UOh3KAG Succeeded: 30 tests, 0 failures.** LoWsOnboardingGateService coverage is 95% (252/264).

Deploy: `sf project deploy quick --job-id 0AfQi000001UOh3KAG -o Production`. Re-validate if more than about 10 days have passed, or if any of these classes changes in prod.
