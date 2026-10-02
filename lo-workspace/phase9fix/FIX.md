# Phase 9 fix: default app, Pre-Approval Letter in My Leads, tab styling

Status: built and validated (check-only) on 2026-10-01. **Not deployed.**

- Validation: `0AfQi000001TmyLKAS` succeeded with 4/4 components and 20/20 tests (LeadPreApprovalLetterTest).
- Fresh prod retrieves are in `ref/src/` (2026-10-01). `ref/profile-apps/managed-apps.profile-meta.xml` is the profile retrieved alongside the managed-package apps.
- Only the changed components are in `force-app/`.

## Components
| Component | Change |
|---|---|
| Profile `External Loan Officer Profile` (minimal XML, applicationVisibilities only) | LO_Workspace is visible and the default. The 16 other visible apps are now hidden. |
| PermissionSetGroup `External_Loan_Officer` | `Reach_Mobile_LO` removed |
| LWC `externalLoLeads` | Pre-Approval Letter button and modal, new tab style, `lightning__dynamicComponent` capability |
| LWC `externalLoLoans` | New tab style |

## 1. Default app
**Cause:** the profile had 17 visible apps, so Salesforce reopened the last-used app. The prod profile (retrieved with every app) had these set to visible:
- `Reach_Home_Loans_Lightning`
- standard__: AgentforceStudio, Approvals, DataGovernanceConsole, DataManager, DigitalWallet, ExpressionSetConsole, FlowsApp, LightningSales, MSJApp, OnlineSales, SalesCloudMobile
- Managed: `rcsfl__RingCentral`, `rcsfl__RingCentral_Admin_Ltng`, `rcsfl__RingCentral_Admin_Classic`, `dfsle__DocuSignForSalesforceCore`

All of them are now `visible=false`, and `LO_Workspace` stays `default=true, visible=true`. The profile XML in this deploy holds only applicationVisibilities, so nothing else on the profile changes. RingCentral's softphone utility does not depend on its app being visible. DocuSign is excluded for outside LOs anyway.

**Reach_Mobile_LO:** it grants only three things:
- the Reach_Mobile_LO app;
- `LOMobileTransactionsController`;
- the 5 `LO_Mobile_*` tabs, which exist only for that app.

The only class it grants is already in `External_LO_Access`, line 64. No shell component references the LO_Mobile tabs, and the LO_Workspace nav is Perfect Day only. So outside LOs lose nothing, and the permset was **dropped from the PSG** rather than edited.

Internal LOs are unaffected:
- They hold `Reach_Mobile_LO` by direct assignment: Manuel Anagnostou, Joe Olmsted, Joseph Carey, Zachary Fritz, Martin Rebagliati, Megan Straight, Christopher Lowman, and 2 inactive users.
- The permset itself is not changed.
- The only PSG that contained it was External_Loan_Officer.

**UserAppInfo:** the pilot's row has AppDefinitionId `06mQi000003MX8TIAW`. That is **LO_Workspace itself** (TabSet `02uQi000003MX8TIAW`), so it does not need resetting. If the pilot is switched into another app before the deploy, Salesforce falls back to the default app once that app is hidden. The row was not touched.

## 2. Pre-Approval Letter in the My Leads detail
- The Lead page's "Pre-Approval Letter" quick action (`Lead.Pre_Approval_Letter`) is a Flow action. It runs `Pre_Approval_Screen_Flow`, a single screen that hosts `c:leadPreApprovalLetter` with recordId.
- The new "Pre-Approval Letter" header button, next to "Convert to transaction", opens that **same LWC** in a modal with `record-id` set to the lead Id. The flow wrapper is not used.
- The LWC is loaded with a dynamic `import('c/leadPreApprovalLetter')` through `lwc:is`. The org has Lightning Web Security on (`lockerServiceNext=true`). Loading it on demand means the portal bundle never pulls in the letter or `lightning/actions`, which LWR may not support.
- **Closing the modal:**
  - The letter closes itself on Cancel or after finalize by firing the quick-action and flow close events. The parent listens for both on the element.
  - The modal also has its own Close button, in case those event names differ.
  - On close, the lead detail reloads, because finalizing moves the Lead to Pre-Approval.
- **Portal:** the button is hidden when `isExperienceCloudContext()` is true. Portal users have no Lead access or controller access there.
- **Signer restriction:** confirmed in the prod `LeadPreApprovalLetterController`, which is the same code the modal calls:
  - the `External_LO` custom permission check;
  - `resolveSigner` refuses another signer;
  - finalize rebuilds the card.

  This is the Phase 7 deploy (0AfQi000001TmblKAC), and LeadPreApprovalLetterTest (20/20) passed in this validation. The controller and the VF page `Lead_Pre_Approval_Letter` are both in `External_LO_Access`.

## 3. Tab styling
The two detail tab strips in the shell are the My Leads lead detail (`externalLoLeads`) and the My Loans loan detail (`externalLoLoans`). Both use the same `.detail-tab` classes in per-component CSS. Both files now carry an **identical** block:
- **Tab:** `#e8eef5` pill with a `#d5deea` border, 8px radius, and a 6px gap between tabs.
- **Hover:** `#dbe4ef` background.
- **Active tab:** `#d6e3f5` background, brand blue `#1d63c4` text and border, and a 2px inset underline.
- **Keyboard focus:** a `:focus-visible` ring.

The rules use class selectors only. The Progress period toggle and the Perfect Day goal-period toggle are segmented controls that already have a shaded background, so they were left as they are.

**Portal:** these are the same components, so the portal's lead and loan detail tabs get the same look. This is a harmless style change. Nothing else in the portal changes, because the letter button is hidden there.

## Deploy
From `lo-workspace/phase9fix`:
```
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests LeadPreApprovalLetterTest --wait 60
```
Or quick-deploy: `sf project deploy quick -o Production --job-id 0AfQi000001TmyLKAS`. It must be used within 10 days.

## After deploy
1. Confirm the External_Loan_Officer PSG shows status Updated.
2. **Republish Partner Workspace**, because `externalLoLeads` and `externalLoLoans` changed. Then check that the portal's lead detail has no letter button and that the tabs show the new style.
3. As the pilot, on desktop and phone:
   - Log in and land on LO Workspace.
   - The App Launcher shows no other app.
   - Go to My Leads, open a lead, choose Pre-Approval Letter, then generate and finalize. Check that only their own card is offered and that the modal closes and the lead shows Pre-Approval.
