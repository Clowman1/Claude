# O4f (2026-10-09) - check-only validated, NOT deployed

Validation: 0AfQi000001UQ4XKAW (36 tests, 0 failures). Deploy: `sf project deploy quick --job-id 0AfQi000001UQ4XKAW -o Production`
Built from org copies retrieved into ref/ on 2026-10-09.

1. externalLoRealtors.js - handleAddOpen now resets form (partner type = page default), partnerSearch, results, errors.
   Root cause: handleAddClose cleared results/errors but never `form` or `partnerSearch`. Same component in the portal; same behaviour there.
2. PerfectDayHomeService.buildRecentLog - title fallback when no catalog activity: Activity_Type__c -> Task.Type -> Subject minus
   " on M/d/yyyy ..." -> "Activity". Type fetched with one fixed query for the <=8 clipped rows (TaskRepository untouched: 43% coverage
   with runnable tests). PerfectDayHomeServiceTest: new fallback test; query budget 19 -> 20.
3. loWsTourSteps - chapter M removed (full run never had phone stops). LoWsTourAssets rebuilt from phaseO4e assets minus SS-PHONE-1..4
   (2.34 MB). TOUR-SCRIPT.md updated.

Not in tests list: ExternalLoPortalServiceTest/CoverageTest fail pre-existing ("Enter the borrower's first and last name", partner visibility).
