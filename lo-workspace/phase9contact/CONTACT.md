# Phase 9: contact info, Pre-Approval Details, Add lead with realtor, next appointment, colour pass

Status: **validated (check-only), NOT deployed.** 2026-10-02.

- Main package `force-app/`: **0AfQi000001TssTKAS**. 89 tests, 0 failures. Coverage: LoWsContactService 97%, LoWsLeadDetailsService 99%, ExternalLoLeadService 99%, ExternalLoPortalService 86%, ExternalLoPortalController 84%.
- FLS step `fls-step/` (Lead.Buying_Timeline__c + 2 permission sets): **0AfQi000001TsxJKAS**, using AppraisalOrderController_Test.

Sources were retrieved fresh from Production. `ref/` holds the untouched copies. ExternalLoPortalController and ExternalLoPortalServiceTest were re-retrieved after phase9cal (0AfQi000001TscLKAS / 0AfQi000001TsfZKAS), and my changes were merged onto them. ExternalLoPortalServiceTest itself is unchanged.

**Not built: the lead Status dropdown.** The edit was blocked by a tool permission check ("Modify Shared Resources") and needs the user's go-ahead.

## Deploy (two steps, in this order)

The two permission sets are in the External_Loan_Officer PSG. Deploying them puts the PSG into recalculation, and tests that assign the PSG fail until it is Updated. The first validation hit exactly this. So:

```
cd "C:\Apps\Claude Back Up\lo-workspace\phase9contact"
# 1. Field + FLS (non-PSG test)
sf project deploy quick -o Production --job-id 0AfQi000001TsxJKAS
#    or: sf project deploy start -o Production -d fls-step --test-level RunSpecifiedTests --tests AppraisalOrderController_Test --wait 30
# 2. Wait until the PSG is Updated:
#    sf data query -o Production -q "SELECT Status FROM PermissionSetGroup WHERE DeveloperName='External_Loan_Officer'"
# 3. Main package
sf project deploy quick -o Production --job-id 0AfQi000001TssTKAS
#    or: sh run-validate.sh with "validate" replaced by "start" (same test list:
#    LoWsContactServiceTest LoWsLeadDetailsServiceTest LoWsLeadIntakeServiceTest ExternalLoPortalServiceTest
#    ExternalLoPortalCoverageTest LoWsPartnerTagServiceTest LoWsActivityLogTest ExternalLoActivityLogServiceTest PerfectDayHomeServiceTest)
```

`force-app` also contains the field, so step 3 validates on its own. If the quick deploy is refused after step 1 (the org changed since the validation), run the full `deploy start` with the same tests.

**Then republish Partner Workspace.** externalLoLeads, externalLoRealtors, externalLoPastClients, externalLoLoans and portalListLayout are shared with the portal.

Before deploying, re-check `LastModifiedDate` on ExternalLoPortalController, ExternalLoPortalService, ExternalLoLeadService and the 5 bundles. Another package (Calendar / Follow-ups) is editing next to these.

## What shows where (LO Workspace only; the portal keeps its old cards)

| Place | Shows | Edit |
|---|---|---|
| Lead → Overview, **top**: Contact | Next appointment (if any), Phone, Mobile, Email, Mailing address | Owner: Edit → inline form |
| Lead → Overview: **Pre-Approval Details** (was "Loan scenario") | All fields, always, "—" when empty: Loan purpose, Loan program, Loan Amount, Down payment ($ · %), Estimated payment, Property type, Buying timeline, Location, Purchase price, Realtor buying agent (a link to the realtor in the shell when the LO can see them, otherwise just the name) | Owner: one Edit form, one save |
| Lead side card | Renamed "Lead info" (source, assigned, last contact) | none |
| My Leads row | "Next appt Fri, Oct 3, 2:00 PM" badge | none |
| My Realtors → detail: Contact | Company, Phone, Mobile, Email, Mailing address | Owned partner: Edit. Tagged shared partner: read-only + "Shared Reach partner — contact an admin to update." |
| Past Clients → row "Contact" (drawer) | Same card | Imported client I own: Edit. Loan row (borrower on my loan, not mine): read-only + "Borrower on your loan — contact an admin to update." |

Fields:
- Lead: Phone / MobilePhone / Email / Street, City, State, PostalCode.
- Person Account: Phone / PersonMobilePhone / PersonEmail / PersonMailing\*. PersonMailing\* is populated on 13.4k of 23.6k person accounts; Billing\* on 2.9k. Billing is a display fallback only. Imports and Add partner put the market in BillingCity.
- `na@na.com` displays as blank, and a blank save never overwrites it.

## Server (all refuse portal users and allow only the listed fields)

| Method (ExternalLoPortalController) | Service | Rule |
|---|---|---|
| getContactInfo / updateContactInfo | `LoWsContactService` (new) | Read: a with-sharing query (a loan Id reads its borrower without sharing). Edit: OwnerId = me (Lead not converted, Account is a person account), phone/email checked lightly, SYSTEM_MODE DML after the ownership check. Profile already has Lead + Account Edit |
| getPreApprovalDetails / savePreApprovalDetails(leadId, json) | `LoWsLeadDetailsService` (new) | Owner only; picklists must be active values (an unchanged legacy value is kept); amounts ≥ 0, % 0–100; realtor must be one of mine (tags + owned partner-type Person Accounts), keeping the current one is allowed. Validation-rule messages reach the LO. LeadSource / Owner / Status / Rating never touched |
| getAddLeadOptions / createLoWorkspaceLead | `LoWsLeadDetailsService` + `ExternalLoLeadService` | Tag mode only. Required: first, last, phone (10 digits), email (format, not na@na.com), loan purpose (active Loan_Purpose__c value: Purchase / Refinance / HELOC). No loan amount. Optional realtor (mine only). Phase 6 decide/takeover/refuse unchanged |

- **Estimated payment** (`Estimated_Monthly_Payment__c`) is a plain currency field. No flow or Apex computes it, so it is editable.
- **Loan program** is a text field, so the input is free text.
- `getLeadDetail` is cacheable. The cards use their own non-cacheable reads and re-read after every save. The lead page patches its summary (log-modal phone/email) and refreshes the list wires. A save on either card refreshes the other, because City and State are on both.

## Referring realtor: which fields, and what the realtor will receive

The new lead mirrors BD's `createReferralLead` and the internal flows:
- `Realtor_Buying_Agent__c` = the realtor Account
- `Referral_Source__c` = the realtor's PersonContactId. This is the attribution field; `Stamp_Referred_By_When_Buying_Agent_is_Filled_In` sets the same value for Realtor Referral leads.
- `LeadSource = 'Realtor Referral'`

Without a realtor, Lead Source is left blank. The old form always sent "Realtor referral". On a takeover, a realtor replaces the source (Phase 6 rule); no realtor keeps the old one. Editing the realtor in Pre-Approval Details does **not** change Lead Source, because of the lock.

What an outside LO's lead with a buying agent sends to the realtor (Twilio, to the agent's PersonMobilePhone):

| When | Flow | Needs Lead Source = Realtor Referral? |
|---|---|---|
| On create | **Nothing.** The "thanks for the referral" text and the borrower intro text need `ReferralFormSourceEmail__c` (Realtor intake form only) | — |
| Status → **Pre-Approval** (once) | Lead_Status_Change_Message_Sends: "<Name> is Pre-Approved. - Reach Home Loans" | Yes |
| Documents first requested (`Initial_Docs_Requested_Date__c` set) | Lead_Notify_Buyers_Agent_Docs_Requested: "Documents have been requested from <Name>…" | **No**, any lead with a buying agent |
| Logging a call with "External message to buyer's agent" filled | Send_Custom_Twilio_SMS_to_Buyer_s_Agent_When_Logging_A_Call | No |

- Contact Attempt 1/2/3, Working and the other status branches in Lead_Status_Change_Message_Sends have no connector, so they send nothing. This corrects the Phase 6 note.
- Also: `Stamp_Last_Referral_Date_on_Account` sets the realtor Account's `Last_Referral_Date__c` (no message). Conversion carries both fields onto the Person Account / Transaction, and the Transaction "to Buying Agent" flows (for example Disclosures Out) then text the agent as for any loan.

## Buying timeline

- New field `Lead.Buying_Timeline__c`: restricted picklist with exactly "In the next 3 months", "3 to 6 months", "6+ months".
- A brand-new field gets its values on every record type ([[picklist-values-need-record-type]] applies to *new values on an existing* field), so no record type redeploy. The test writes the value on the Consumer record type.
- `Rating` is not shown or changed.
- FLS read/edit: `External_LO_Access` (outside LOs) and `Lead_Team_Access` (internal: 25 of 28 active internal users, and it is also in the External_Loan_Officer PSG). Profiles are untouched. The Apex does not depend on FLS.

## Next appointment

- `LoWsContactService.nextAppointments`: earliest Event with OwnerId = me, WhoId = the lead, StartDateTime > now. SYSTEM_MODE. "Next appointment: Fri, Oct 3, 2:00 PM — <subject>".
- Indicator only. The test proves that creating Events doesn't change the lead Status.
- Shown in the Contact card and as a My Leads badge (one extra query per list load, outside the portal).
- Found while testing: **EventTriggerHandler throws "Duplicate id in list" when two or more Events for the same lead are inserted in one DML.** This is pre-existing and not fixed here.

## Colour pass (CSS classes only; also visible in the portal)

- portalListLayout:
  - tinted page (#f4f7fb), a navy top band on the list card, a tinted toolbar (#e8eef5 / #d5deea)
  - zebra rows, plus a hover tint with a navy left bar
  - an initials circle per row (5 brand tones, stable per name)
  - new badge classes: status-pre-approval, status-converted and badge-stage. These were missing, so those badges rendered colourless. Also badge-appt.
- Lead / realtor / loan detail:
  - tinted page, a 6px navy left accent and a soft gradient on the header card
  - tinted card-title strips, and a navy top border on the lead Contact card
  - the loan header gets a milestone chip in the stage colour: closed = navy, clear to close = green, needs update = amber, in process = blue
- Contrast is AA on every new pair.

## Add lead entry points

- My Leads → Add lead.
- My Realtors row → "New lead".
- Realtor detail header → "New lead". This one pre-fills the realtor and locks it; to pick another, close the form and use My Leads.

All three use `loWsAddLeadForm`. On success, the new (or taken-over) lead opens. The portal keeps its old form and server rules.

## Components

- New: LoWsContactService(+Test), LoWsLeadDetailsService(+Test), LWCs loWsContactCard, loWsLeadDetails, loWsAddLeadForm, field Lead.Buying_Timeline__c.
- Changed:
  - ExternalLoPortalController: 8 new methods, merged onto the phase9cal version
  - ExternalLoPortalService: LeadRow.nextAppointment
  - ExternalLoLeadService: the tag-mode Add lead rules, plus the realtor on create and takeover
  - LoWsLeadIntakeServiceTest: Add lead calls updated for the required fields; the placeholder case now asserts that decide() ignores na@na.com and that Add lead refuses it
  - LWCs externalLoLeads, externalLoRealtors, externalLoPastClients, externalLoLoans, portalListLayout
- fls-step: permission sets External_LO_Access, Lead_Team_Access.

## Open questions

1. **Status dropdown not built.** It was blocked by a permission check, as noted at the top. It needs the user's approval before anyone retries it.
2. Changing an email or phone to one that matches another person is not blocked. The duplicate rules run only on Add lead, the webhook and CSV.
3. A lead added without a realtor gets a blank Lead Source. Should Add lead ask for a source, or default to one (for example "Personal Referral")?
4. Editing a lead's buying agent leaves Lead Source as it was, because of the lock. The Pre-Approval agent text needs Realtor Referral; the docs-requested text does not.
5. The realtor picker is a plain select of the LO's partners, capped at 2,000. It should become a type-ahead if an LO passes about 200 partners.
6. Company/brokerage shows on partners but is not editable. Company__c and PersonTitle are both in use (portal vs Fred's tools).
7. The EventTriggerHandler batch bug described under Next appointment.
