# Phase 10 – Past Client detail (LO Workspace)

Retrieved fresh from prod 2026-10-05; full-file diff against prod re-checked before validation (only our changes).

## Built
- `loWsPastClientDetail` (new LWC): back link → Past Clients, navy header card (name, "Past client" chip,
  Most Recent loan amount / purpose / Purchase_Price__pc, most recent closing date), buttons
  **Log communication** (`portalCommunicationModal`, objectApiName Account) and **New lead for this client**
  (`loWsAddLeadForm` with new `@api prefill` = first/last name, phone, email → `createLoWorkspaceLead`;
  opens the new lead after create).
  Tabs: Overview (Contact card `loWsContactCard`, Loan history = Transactions with Borrower_Name__c = account,
  readable only, status label via `loanStatusLabel`, closing date, amount, purpose, property address; opens
  My Loans detail when I am LO/owner; falls back to imported Most Recent values), Notes (EnhancedNotesController
  with the account id + /apex/AddNewNote New), Calls/Zooms (two `c-call-insight-list` + Logged calls).
- `ExternalLoPortalService.getPastClientDetail` (Standard users only; owner or `RecordAccessGuard.readable`;
  SYSTEM_MODE reads after the check) and `accountWorkspaceView` (routing word only). `loggedCalls` now takes a
  Set so Person Account tasks on the Account (WhatId) or PersonContact (WhoId) both show.
- Controller: `getPastClientDetail`, `getAccountWorkspaceView` (cacheable).

## Routes
- Past Clients: imported client rows `openView` 'record' → 'pastClients' (detail in-workspace). Loan rows unchanged.
- Shell `handlePortalNavigate`: LO Workspace only, an Account id sent to My Realtors is re-routed to Past Clients
  when it is my imported client (owned, Group__pc Client). Covers Perfect Day drawers and Up Next (they already
  send Accounts to My Realtors).
- Calendar `loWsAppointments.openRelatedRecord` Account → shell (past client / realtor in-workspace, anything
  else on its record page via `accountFallback: 'record'`).
- Log activity picker (`portalContactPicker`) never opened record pages; no change.

## Validate
`sh run-validate.sh` → 0AfQi000001U693KAC (112 tests, 0 failures; controller 82.6%, service 86.5%).
Deploy: `sf project deploy quick --job-id 0AfQi000001U693KAC -o Production`.
Partner Workspace: republish (shell / past clients / add lead form bundles changed; portal behaviour unchanged).
