# O4h (2026-10-13) - check-only validated, NOT deployed

Validation: 0AfQi000001UgkPKAS (AppraisalOrderController_Test, 7 tests, 0 failures; no Apex changed).
Deploy: `sf project deploy quick --job-id 0AfQi000001UgkPKAS -o Production`
Built from org copies retrieved into ref/ on 2026-10-13 17:25. Source: onboarding/TOUR-UPDATE-2026-10-13.md (approved as written).
Ship after the comms flow activation (update doc open question 1): PD-CS / M-02 say texts come from the no-reply number.

1. loWsTourSteps - chapter M "Communication settings" (M-01..M-06), PD-CS after PD-RC (full run 17 / 18 with RingCentral),
   corrected PD-03 (= A-02), PD-04, PD-10 (= E-03), D-01, D-03, H-03, H-05. M-03 waits on `comm-settings-edit` (rows loaded).
2. loWsCommSettingsModal - registerTourHooks; hooks comm-settings-intro (header), -groups (.body), -edit (first row only),
   -editor, -cancel, -close. Tour never clicks a switch / Reset / Save.
3. loWsTextsSwitch - registerTourHooks in connectedCallback (LO Workspace only); `texts-switch` was already in the template.
4. externalLoActivityPrompts - reply cards get `up-next-reply`; `up-next-alert` = document alerts only;
   `up-next-actions` no longer on reply cards (A-03 fix). Edge: if Up Next holds ONLY reply cards, PD-03's need
   (`up-next-actions`) misses and PD-03 shows SS-UPNEXT.
5. LoWsTourAssets - phaseO4f set + placeholders SS-SWITCH, SS-REPLY (assets/make-placeholders.ps1), 2.35 MB.
   Rebuild: cd assets/LoWsTourAssets && C:\windows\system32\tar.exe -a -c -f out.zip poses screens, move to the .resource.
   crop-shots.ps1 + shots.tsv copied from phaseO4e/assets for the capture step.
externalLoPortalShell unchanged: `comm-settings` hook + registerTourHooks already deployed.
