# Phase O4b: LO Workspace guided tour (Bran the Mortgage Man)

Script: `../onboarding/TOUR-SCRIPT.md` (all 75 stop texts copied verbatim, checked by script). Decisions: `../onboarding/ONBOARDING-GRILL.md` 4-17, 31-33, 45, 60-62.
`ref/src` = untouched prod copies retrieved 2026-10-09 after the O2/O2b/O3/O4a deploys; every modified file was built from them.
Nothing deployed, no data changed.

**Check-only validation: 0AfQi000001UPMzKAO** (31 tests, 0 failures; LoWsOnboardingGateService 96%, ExternalLoWorkspaceController 84%).
Tests: LoWsOnboardingGateServiceTest, ExternalLoOnboardingServiceTest, LoWsPartnerTagServiceTest (`sh run-validate.sh`).
Deploy: `sf project deploy quick --job-id 0AfQi000001UPMzKAO -o Production --wait 30`
No permission set change (no PSG recalculation): the tour Apex goes through ExternalLoWorkspaceController, already in External_LO_Access.

## New
- `LoWsTourAssets` static resource (zip): `poses/bran-*.png` (8 poses; hands-on-hips cropped at x=324 to drop the stray hand; originals untouched) + `poses/bran-head.png` (waving, head and shoulders) + `screens/SS-*.png` (26 PLACEHOLDERS). Source + rebuild steps: `assets/`. Replace the placeholders with the real captures (same file names) and re-zip.
- `loWsTourSteps`: the script as data (chapters -> stops: view, record, clicks, hooks, need, after, pose, text, shot). Buttons come from position.
- `loWsTourHooks`: cross-component targeting (below).
- `loWsTour`: overlay engine + chapter menu.
- Apex `LoWsOnboardingGateService.getTourState / saveTourProgress` (+ `TourState`), delegates in `ExternalLoWorkspaceController`, 3 new tests.

## How targeting works
Every component has its own shadow root, so the tour fires a window event `lowstourquery` per hook (`queryTourHook`). Each component that owns hooks calls `registerTourHooks(this)` in `connectedCallback`; its listener looks in its own template for `[data-tour="<hook>"]` and writes the rect into `event.detail` (or clicks the element when asked, or scrolls it into view). A listener removes itself on the next query after its component is gone. Hooks on a child's host element (Up Next, Today's Plan, Recent activity, appointments, in-person events, follow-up picker) are answered by the parent.

Per stop the engine: asks the shell to navigate (`tournavigate` event; the shell passes `view` / `record-id` down) -> for record stops clicks `open-first` (first board card or first list row) -> clicks `clicks` (tabs, modals) -> polls up to 4 s for `need` (data present) and the hooks -> spotlight (one even-odd SVG cut-out per hook) or the stop's screenshot inside the bubble, or a centered bubble. `after` clicks close what it opened. Repositions on resize/scroll. Esc = skip (asks once in the full run) / exit chapter, arrows = back/next, focus trapped in the bubble, `aria-live` text, reduced-motion off.

## Behaviour
- LO Workspace only: the shell renders the tour, the "Take the tour" link and the banner "?" only when `!isExperienceCloudContext()` and setup is complete. Hidden below 1024px (CSS) and never started there.
- Menu: "The full Perfect Day (16 stops)" (17 with RingCentral), then Chapter A-M with "N stops" and a tick once that chapter's Done was reached.
- RingCentral stop (decision 61) `PD-RC` after PD-04 and `A-RC` after A-05, only when `LoWs_RingCentral_Required__c`.
- Auto-launch: `autoLaunch = tour not completed AND LoWs_Gate_Passed_At__c set AND setup complete AND External_LO`. The shell mounts the tour when setup becomes complete (handleOnboardingCompleted sets the state), so it starts right after the Q&A. Existing users never passed the O2 gate, so they never auto-launch. A new LO who closes the tab mid-run gets it again next load until they Finish or Skip.
- Saves (SYSTEM_MODE): chapter Done -> adds its id to `LoWs_Tour_Chapters_Seen__c` (`;` list); full-run Finish -> adds `PD` + stamps `LoWs_Tour_Completed_At__c`; full-run Skip -> stamps the date only (script rule 4: skipping counts as seen).
- Oversight roster "tour done" reads `LoWs_Tour_Completed_At__c` (verified), so a skip shows as done.

## Hooks added (data-tour)
| Component | Hooks |
|---|---|
| externalLoPortalShell | tour-menu (new "Take the tour" link); passes nav `tourId` |
| portalNavList | nav-<view> (e.g. nav-nurtured, nav-preApprovals, nav-pastClients) |
| perfectDayHome | pd-banner, pd-progress, pd-metrics, pd-log-activity, pd-in-person-invite, pd-tour-help (new "?"), pd-pipeline-snapshot, pd-goal-progress; hosts up-next, today-plan, appointments, in-person-events, recent-log |
| externalLoActivityPrompts | up-next-alert (first High alert card), up-next-actions |
| externalLoRecentLog | recent-reply |
| loWsAppointments | appointment-row, appointments-open-calendar, calendar-views, calendar-close |
| portalActivityModal | log-modal-category, log-modal-close |
| portalCommunicationModal | follow-up-picker (host), comm-modal-close |
| externalLoLeads | leads-board, open-first, leads-move-to, leads-layout-toggle, leads-add, lead-status, lead-convert, lead-app-summary, lead-letter, lead-log-communication, lead-tabs, lead-tab-<id>, lead-contact-card, lead-pre-approval-details, lead-zoom, lead-calls, lead-notes-new |
| portalListLayout | list-filters, list-rows, open-first |
| loWsCommunications | comms-subtabs, comms-<tab> (comms-texts), comms-text-row |
| leadPortalDocumentRequestManager | doc-req, doc-req-add, doc-req-send, doc-req-start-review |
| externalLoLoans | loans-board, open-first, loan-milestone, loan-tabs, loan-tab-<id>, loan-submission, loan-coc |
| loWsAppraisalPanel | appraisal-tracker, appraisal-messages |
| externalLoRealtors | realtors-add, realtor-stage, realtor-shared-pipeline, realtor-texts, realtor-zoom |
| loWsPastClientDetail | past-client-new-lead, past-client-zoom |
| externalLoCsvImport | import-consumer, import-partner |
| externalLoPerfectWeek | perfect-week-this-week, perfect-week-edit-plan |
| externalLoProgress | progress-period, progress-coaching |

Hook names differ from the script table where a generic one serves several pages: `list-filters` (preapprovals-filters, realtors-filters, loans-tabs), `list-rows` (realtors-list), `nav-<view id>`.

## Deviations from the script
- F-03 is screenshot-only: the tour never opens the Submission form wizard (it could not close it again, and it must never be submitted).
- J-03 runs on a lead's Log communication (the banner Log activity has no follow-up picker until a contact is picked).
- K-03: the Volume edge tab is not shown on My Progress (shell rule), so only the period tabs + Coaching focus are spotlighted; the text still mentions it. `volume-tab` and `pd-calendar` hooks not added (no stop can reach them).
- Unchanged components: loWsVolumeDrawer, loWsBorrowerPills, loWsLeadDetails, callInsightList, loWsFollowUpPicker, bdUpcomingCard, loanSubmissionWizard (their hooks sit on the parent).

## Not verified
Nothing was run in a browser (no deploy allowed). After the quick deploy, walk the full run + each chapter on the pilot with and without demo data, at 1280 px.
