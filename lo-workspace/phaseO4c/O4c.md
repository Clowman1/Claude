# Phase O4c: tour follow-ups (Q67 skipped state, Q68 resume)

`ref/src` = prod copies retrieved 2026-10-09 after the O4b deploy (0AfQi000001UPQDKA4); identical to O4b apart from trailing newlines. Nothing deployed, no data changed.

**Check-only validation: 0AfQi000001UPRpKAO** (32 tests, 0 failures; LoWsOnboardingGateService 96%, ExternalLoWorkspaceController 84%).
Deploy: `sf project deploy quick --job-id 0AfQi000001UPRpKAO -o Production --wait 30`. No permset/field change.

- No new field. Two tokens go into `LoWs_Tour_Chapters_Seen__c` alongside the chapter ids:
  - `PD-SKIPPED`: the full run was skipped (Q67).
  - `PD@<stopId>`: where the first-login run was left (Q68).
- Apex: `skipTour()` and `saveTourResume(stopId)` (stop id must match `PD-xx`), with delegates in ExternalLoWorkspaceController.
  - TourState gains `skipped` and `resumeStopId`; `chaptersSeen` excludes the tokens.
  - `autoLaunch` is now also false after a skip.
  - Finish and Skip both clear the resume point.
  - A skip no longer stamps `LoWs_Tour_Completed_At__c`.
- Roster: `RosterRow.tourSkipped`. The Oversight tour column shows badges: Done (green), Skipped (yellow), Not yet (grey).
- `loWsTour`:
  - The auto-launched run starts at `resumeStopId` and saves its position on every Next/Back.
  - Menu replays always start at stop 1 and never save a position.
  - Skip calls `skipTour`.
- Tests: `skippingIsNotDoneButStopsAutoLaunch`, `firstRunResumesWhereItWasLeftUntilFinished`; the O4b skip test was replaced.
