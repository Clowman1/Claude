# Nimbus user offboarding: dependency audit

Audit date: 2026-09-30. Org: Reach Home Loans LLC Production (`00Df2000000BonwEAC`).
Method: read-only. SOQL (data and tooling API), plus a metadata retrieve of every Apex class and trigger, workflow, CustomSite, Network, NamedCredential, ExternalCredential, AuthProvider, ConnectedApp, CustomMetadata, CustomLabels, EmailServicesFunction, assignment, auto-response and escalation rules, queues, LWC, Aura, VF, custom objects (with validation rules, formulas and list views) and Settings (Case, Flow, Communities, LeadConfig, WebToX and others). All 329 flows were grepped. Nothing was changed.

Search terms used everywhere: `nimbus`, `0055x00000Bs3rB` / `0055x00000Bs3rBAAR`, `005Qi00000OPWID` / `005Qi00000OPWIDIA5`.

| User | Id | Username | Email | Profile | Last login |
|---|---|---|---|---|---|
| Nimbus Development | `0055x00000Bs3rBAAR` | reach@nimbuscloudsolutions.com | development@nimbuscloudsolutions.com | System Administrator, role Management | 2026-09-30 15:00 UTC |
| Nimbus Development - Outside | `005Qi00000OPWIDIA5` | reachoutside@nimbuscloudsolutions.com | aivsitedev@gmail.com | Read Only, no role | never (0 LoginHistory rows) |

Verdicts, in short:

- **Nimbus Development - Outside: safe to deactivate now.**
- **Nimbus Development: NOT safe to deactivate until checklist steps 1-9 in section (c) are done.**

Details are in section (d).

---

## (a) Dependencies by user

### A1. Nimbus Development (`0055x00000Bs3rBAAR`)

"Setup/Meta/Data" in the last column means: **UI** = a Setup UI step, **Meta** = can be done by metadata deploy, **Data** = can be done by a data update, **Ext** = has to be done in the outside system.

#### Scheduled jobs (56 CronTriggers, all state WAITING)

Evidence: `SELECT CronJobDetail.Name, CronJobDetail.JobType ... FROM CronTrigger WHERE OwnerId IN (...)` returned 56 rows, all owned by `0055x00000Bs3rBAAR`. By type: 34 Scheduled Apex (7), 9 Scheduled Flow (6), 7 report notifications/subscriptions (A), 3 Experience sitemap full (E), 3 sitemap incremental (G). Apex classes come from `AsyncApexJob WHERE JobType='ScheduledApex' AND Status='Queued'` joined by CronTriggerId.

| Job(s) | What it runs | What breaks on deactivation | Replacement | How |
|---|---|---|---|---|
| Create Twilio Messages 1-8, 10-12 (11 jobs, every 5 min; **#9 at :40 does not exist**) | `NCS_GetTwilioMessagesSchedulable` | Scheduled Apex runs as its owner. With the owner inactive, the jobs cannot be trusted to run. Inbound Twilio SMS stop landing, and this is the highest-volume job (1,856 future calls in 7 days). The new owner also needs a TwilioSF seat. | Abort, then re-schedule under the new integration user | Data/Apex: `System.abortJob` + `System.schedule` while logged in as the new user |
| RingCentral Fetch SMS Job #1-#12 | `RingCentralFetchSMSJob` | Same risk. SMS logging to Task stops (Tasks created by Nimbus in the last 30 days: 9,707). | Re-schedule under the new user | Data/Apex |
| RingCentral Fetch Call Job #1, #2 | `RingCentralFetchCallJob` | Call logging stops | Re-schedule | Data/Apex |
| RingCentral Token Refresh - Daily | `RingCentralTokenRefreshJob` | RC token expires, which breaks every RC job | Re-schedule | Data/Apex |
| RingCentral Message Scheduler - Hourly | `RingCentralSmsScheduler` | Scheduled_Message__c SMS stop sending | Re-schedule | Data/Apex |
| UWM Conditions Sync 1775742248067 | `ScheduleConditions` → `UWM_Conditions_API_Batch` | UWM condition sync stops | Re-schedule | Data/Apex |
| Insights Job | `ScheduleInsights` → `UWMInsightsPipelineBatch` | UWM EASE Insights pipeline stops | Re-schedule | Data/Apex |
| Get Order Status | `ValueLinkOrderStatusBatchable` | ValueLink appraisal status polling stops | Re-schedule | Data/Apex |
| Weekly Transaction Summary - Tuesday / Friday 11AM | `WeeklyTransactionNoteSummary` | LO weekly note summaries stop (already sends from reachus@) | Re-schedule | Data/Apex |
| Stagnant Lead Alerts | `LeadStagnantAlertScheduler` | Stagnant lead reminders stop (already sends from reachus@) | Re-schedule | Data/Apex |
| RingSense Silence Alert | `RingSenseSilenceAlertScheduler` | Silence alert stops | Re-schedule | Data/Apex |
| Account_Send_Anniversary_Text-9, Account_Send_Birthday_Text-20, Contact_for_Review_Task_Creation-4, Create_Task_to_Verify_TRID_Holidays-1, Daily_Send_Referral_Message_to_Lead-1, Employee_Pay_Period_Creator-4, Lead_Appointment_Report_Email_Scheduled_Flow-4, Loan_Commitment_Date_Create_Event-2, Rate_Lock_Expiration_Daily_Schedule-1 | Schedule-triggered flows of the same names. Each active version was created and activated by Nimbus (tooling `Flow WHERE Status='Active'`). | The CronTrigger is owned by Nimbus, but the records these flows create are **CreatedBy Adam Stephens** (for example "Contact for Review" Tasks at 14:00 UTC on 2026-09-11, and Pay_Period__c at 04:00 UTC). So they run as the Default Workflow User, not as Nimbus. Deactivating Nimbus probably does not stop them, but the scheduler entry still belongs to an inactive user. | Re-own the schedule by deploying each FlowDefinition at activeVersionNumber 0 and then back to N as a Reach admin (two-step deploy, see memory "Flow deploys land as Draft"), or deactivate and reactivate in Flow Builder | Meta |
| 7 report subscriptions/notifications (UUID names; CronTrigger Ids `08eAJ000000CCVVYA4`, `08eAJ000000CCZWYA4`, `08eAJ000002DeahYAC`, `08eAJ000000CCcGYAW`, `08eAJ0000035LenYAE`, `08eAJ000000CCXVYA4`, `08eQi00000AMEpoIAH`) | Report subscriptions that Nimbus set up | Subscriptions owned by an inactive user stop sending | Check in Setup > Scheduled Jobs which reports they are. Re-subscribe as a Reach person, or drop them. | UI |
| CommSitemapJob / CommIncrementalSitemapJob for `0DMAJ00000002FG` (Reach_Home_Loans_Transactions1), `0DMQi0000000Fjq` (Closing_Portal1), `0DMQi0000000GMY` (Lead_Intake_Form_Wemert_Group1) | Experience Cloud SEO sitemap (system job) | Sitemap generation may stop. Low impact. | Re-publish those three sites as a Reach admin, which re-creates the jobs | UI |

Non-cron async pattern: `AsyncApexJob` created by Nimbus in the last 7 days also includes `PS_ScheduledDispatcher`/`PS_QueueableRollup` (Rollup Helper, rh2). These are started by whichever user's transaction fires, and 11 other users start them too, so they are not a Nimbus dependency. `DpaSecondTransactionStatusSync` and `ValueLinkDataFetchQueueable` are queued from the Nimbus-owned jobs and move with them.

#### Integrations authenticated as Nimbus

Evidence: `OauthToken WHERE UserId IN (...)` and `LoginHistory` for the last 30 days, grouped by Application.

| Integration | Evidence | What breaks | Replacement | How |
|---|---|---|---|---|
| **Zapier** | OauthToken since 2022-10-12, UseCount 2,564, last used 2026-09-30 14:06. 68 logins in 30 days. | Every Zap whose Salesforce connection is the Nimbus account stops. Salesforce cannot show which Zaps these are. | In Zapier > Connections, find the Salesforce connection authorised as reach@nimbuscloudsolutions.com and reconnect it as the new integration user. Re-test each Zap, since field lists come from the connected user's FLS. | Ext |
| **RingSense** | OauthToken since 2025-11-24, UseCount 300, last used 2026-09-28. 34 logins in 30 days. | RingSense stops writing to Salesforce (Tasks and Call_Insight__c) | Reconnect the RingSense Salesforce connector as the new integration user | Ext |
| hutte.io | 354 logins in 30 days, last used today | Nimbus's dev tooling. Stops. | Nothing to replace. Revoke. | UI |
| Bitbucket CI | 31 logins in 30 days, last 2026-09-30 07:16 | Nimbus CI deploys to prod. Stopping them is intended (see memory "Nimbus deploys roll back our components"). | Revoke | UI |
| Salesforce CLI, Gearset Deploy, Browser | CLI 29 logins, Gearset 3, Browser UI logins with MFA today from 68.41.31.99 | Nimbus staff access. Stops. | Nothing to replace | none |
| AuthProvider `UWM_ConditionsAuth` and `UWM_InsightsOAuth` | `<executionUser>reach@nimbuscloudsolutions.com</executionUser>` (registration handler "Execute As") | Re-authenticating the UWM named credentials (`UWMConditions`, `UWMInsights`, NamedUser OAuth) runs the handler as an inactive user and fails. Existing tokens may keep working until they need re-authentication. | Set executionUser to the new integration user | Meta (AuthProvider) or UI |
| Email service `EmailToSalesforce`, address `emailtosalesforce10` | runAsUser reach@nimbuscloudsolutions.com, authorizedSenders development@nimbuscloudsolutions.com | This address only accepts mail from Nimbus, so it is obsolete | Deactivate or remove the address | Meta or UI |
| Email service `FedExService` (localPart `fedexservice`, class `ApprovalEmailService`) | runAsUser reach@nimbuscloudsolutions.com | Inbound FedEx emails fail to process | Change runAsUser to the new integration user | Meta or UI |
| Connected apps with client-credentials Run As | `CPQIntegrationUserApp` and `Encompass_Integration` have no `oauthClientCredentialUser` | none | none | none |
| NamedCredential / ExternalCredential | None reference a Nimbus user or address (grep of all 6 NCs and 2 ECs) | none | none | none |

#### Sites and Experience Cloud

Evidence: `SELECT Name, AdminId, GuestRecordDefaultOwnerId FROM Site` and the CustomSite metadata.

| Site (CustomSite) | siteAdmin | siteGuestRecordDefaultOwner | Evidence that the guest owner is live |
|---|---|---|---|
| Borrower_Portal | Nimbus | Nimbus | |
| Borrower_Portal_v2 | Nimbus | Nimbus | |
| Closing_Portal | Nimbus | Nimbus | |
| **Integrations** | Nimbus | Nimbus | 1,616 Call_Insight__c in 30 days created by Integrations Site Guest User and owned by Nimbus |
| **Lead_Intake_Form** | Nimbus | Nimbus | 101 Tasks, 158 TwilioSF__Message__c and 53 Lead_Event__c in 30 days created by the guest user and owned by Nimbus |
| Lead_Intake_Form_Wemert_Group | Nimbus | Nimbus | |
| Lead_Portal | Nimbus | Nimbus | Portal uploads (memory: guest-uploaded files are owned by Nimbus) |
| Partner_Workspace | Nimbus | Nimbus | |
| Reach_Home_Loans_Transactions | Nimbus | hellis@ (Harold Ellis) | |
| Ring_Central_Auth_Site | Nimbus | Nimbus | |
| TitleAgentsShippingLabel | Nimbus | Nimbus | |
| Title_Confirmation | Nimbus | Nimbus | |
| ValueLink_Webservice | Nimbus | Nimbus | |
| Reach_Login_Panel | clowman@ | clowman@ | (not affected) |

What breaks: the guest record default owner must be an active user. Salesforce refuses to deactivate a user who is a site's guest-record default owner or site contact. If it did let the deactivation through, every guest insert (RingSense webhook into Call_Insight__c, lead intake form, portal uploads) would fail.
Replacement: set siteAdmin and siteGuestRecordDefaultOwner to the new integration user on the 13 sites. **Leave Reach_Home_Loans_Transactions' guest owner as it is. Change only its siteAdmin.** How: Meta (CustomSite) or UI (Setup > Sites, or Experience Workspaces > Administration > Preferences).

Network email sender: see section (b).

#### Record ownership

Evidence: a `COUNT()` loop over `OwnerId IN (both Ids)` for 20 standard objects and all 141 custom objects. Only the non-zero results are listed. Every one belongs to Nimbus Development. The Outside user owns nothing.

| Object | Owned | New in last 30 days | Action |
|---|---|---|---|
| Call_Log__c | 48,616 | 1,977 (RC jobs) | Historical, so it can stay. New rows follow the job owner. |
| Custom_Log__c | 29,893 | 902 | Can stay |
| Call_Insight__c | 23,066 | 1,616 (Integrations guest) | Can stay. New rows follow the site guest owner. |
| TwilioSF__Message__c | 12,757 | 164 | Can stay |
| Lead_Event__c | 11,130 | 53 | Can stay |
| Enhanced_Note__c | 3,322 | 3 | Can stay |
| Task | 1,815 | 101 | Can stay. Optionally move open ones. |
| Scheduled_Message__c | 1,242 (981 Sent, 228 Blocked, **32 Scheduled, 1 Overdue**) | 137 | Transfer the 33 pending ones to the new user (Data) |
| Transaction_Condition_Reference__c | 1,180 | 0 | Can stay |
| Loan_Event__c | 658 | 25 | Can stay |
| Lead_Document_Request_Reference__c | 75 | | Can stay |
| UWM_Loan_Info__c 53, Marketing__c 35, Submission_Form__c 32, Candidate_Checklist__c 28, ContentDocument 14, Appraisal_Order__c 13, Employee_Pay_Period__c 13, Checklist__c 5, Pay_Period__c 2, Transaction_Expense__c 1, User_Action__c 1, Macro 1 | | | Can stay |
| EmailTemplate | 46 | | Can stay (templates work with an inactive owner) |
| Contact | 30 | | Transfer (Data). 7 of them sit under the "Customer Community User" account. |
| **Account** | 24 | | Transfer (Data). This includes `001AJ0000047qQ8YAI` "Customer Community User", the account that holds **2 active and 7 inactive "RHL Community User" portal users**. A portal account owner has to be an active user with a role before new portal users can be created or managed. The other 23 are staff and test person accounts (Sender__c on SMS enrolment falls back to Account.OwnerId). |
| Lead | 7 (all open: 6 Nurturing, 1 Contacted) | 0 | Transfer to a real LO (Data) |
| Opportunity 3, Case 3 | | | Transfer (Data) |
| **Dashboard** (running user) | **25 dashboards** with RunningUserId = Nimbus (23 SpecifiedUser, plus "Activities Dashboard" owned by Nimbus) | | A dashboard whose running user is inactive stops refreshing. Change the running user to a Reach admin. Folders involved: Management, Outside Sales, Biz Dev Dashboard, RingCentral Dashboards, Loan Officer Lead Dashboards, New Dashboards 2024, Activities. UI, or Meta (Dashboard runningUser). |

#### Lead Loan Partner default

Evidence: `LeadLoanPartnerAssignmentService.stampFromOwnerAssignments` (called by trigger `LeadLoanPartnerAssignment`) copies the owner's `User.Loan_Partner__c` onto `Lead.Loan_Partner__c` on insert and on owner change. `SELECT Id, Name FROM User WHERE Loan_Partner__c IN (...)` returns **one row: Christopher Lowman (`005f2000009OtLnAAK`) has `Loan_Partner__c = 0055x00000Bs3rBAAR`.** So the "default Nimbus Loan Partner" is not hard-coded anywhere. It applies only to Leads owned by Chris.

- What breaks: the Loan Partner gets an automatic Manual LeadShare (memory "Lead OWD is Private"). Inserting a share for an inactive user fails, so any Lead that is created or reassigned to Chris will probably throw once Nimbus is inactive.
- Replacement: clear or change Chris's `User.Loan_Partner__c`, and clear `Lead.Loan_Partner__c` on the 4 leads that hold Nimbus. They are all test leads: `00QQi00000lPUKnMAO`, `00QQi00000lvgyjMAA`, `00QQi00000m8MqvMAE`, `00QQi00000n83EEMAY`. How: Data.

#### Other items

| Item | Where | Breaks? | Action | How |
|---|---|---|---|---|
| TwilioSF package seat | UserPackageLicense. TwilioSF 19 of 20 used. | The new job owner needs a seat or the Twilio jobs fail | Assign the spare seat to the new user, or move Nimbus's seat after deactivation | UI |
| Permission sets | 25 assigned (including Twilio_User, Twillio_Administrator, UWMPermissions, RingSense_Webhook_Admin, Zoom_Meeting_Sync_Access, Loan_Partner_Reassignment, DocuSign_Administrator). PSLs: SalesUserPsl, EinsteinGPTGroundingStructuredDataPsl. | none | Give the same set to the new integration user, but **leave out Lead_Source_Change** (memory "Lead Source lock") | Data (PermissionSetAssignment) |
| Public group `Admins` + 3 CMS workspace roles (Experience/Content Admin) | GroupMember | none | Add the new user if needed | UI |
| Custom setting user-level rows | `ValueLink_Prod_Creds__c` `a1TAJ0000001dnE2AQ` (same Username as the org default), `RingCentralUserAuth__c` `a20AJ0000003DWWYA2` | none. `ValueLinkDataFetchQueueable` falls back to the org default, and the RC jobs use `RingCentralApiAdminToken__c`/`RingCentralAppAuth__c` org defaults. | Optionally delete later | Data |
| Hardcoded names in Apex | `CEOIntelligenceController` and `PipelineCommandCenterController` exclude "Nimbus Development" by name from rosters | none | Add the new integration user's name to the same exclusion sets | Meta |
| Hardcoded Id in a flow | `Update_Outbound_Message_Owner` filters TwilioSF messages owned by `0055x00000Bs3rBAAR` | none. The flow is inactive (FlowDefinitionView IsActive=false). | none | none |
| List views | Transaction__c `Open_Pipeline`, `Open_Pipeline1`, `Copy_of_Open_Pipeline_Processor`, `X1_Application` filter out owner "Nimbus" | Cosmetic | Optional | Meta |
| Validation rules, formulas, custom metadata, queues, assignment/auto-response/escalation rules, approval processes, sharing rules | grep of the retrieved metadata | **No references** | none | none |
| Approvals pending | `ProcessInstanceWorkitem WHERE ActorId IN (...)` | 0 rows | none | none |
| Manager / delegated approver | `User WHERE ManagerId/DelegatedApproverId IN (...)` | 0 rows | none | none |
| Automated Case User / default case owner | Case settings: `defaultCaseUser` = `defaultCaseOwner` = astephens@ | Not Nimbus | none | none |
| Default Workflow User | No metadata type exposes it. Inferred as **Adam Stephens**, because the Nimbus-activated schedule-triggered flows create records as Adam. | Not Nimbus (inferred) | Confirm in Setup > Process Automation Settings | UI |
| Web-to-Lead default creator | Not exposed in metadata. No Leads created by Nimbus in the last 30 days. | Unlikely | Confirm in Setup > Web-to-Lead | UI |
| 21 Developer sandboxes | `SandboxInfo`: all created by Nimbus, 19 with AutoActivate=true | Nothing breaks in prod | Consider deleting the Nimbus sandboxes after offboarding | UI |
| External Nimbus-hosted service | `ARIVE_NmlsCallReportController` posts to `https://callreportgenerator.herokuapp.com` with hardcoded Basic auth `admin` / `nimbus123` (Remote Site Setting present) | NMLS call report generation stops when Nimbus turns off the Heroku app. This has nothing to do with the user record. | Ask Nimbus whether the app stays up, or rebuild it. Treat the credential as exposed. | Ext |

### A2. Nimbus Development - Outside (`005Qi00000OPWIDIA5`)

| Dependency | Where | Breaks on deactivation | Action |
|---|---|---|---|
| 8 permission set assignments (UWMPermissions, Condition_Files_Permissions, Pipeline_Command_Center_Pilot_Access, Realtor_Referral_Source_Access, Borrower_Rating_Access, Application_Summary_Access, Lead_Team_Access, Zoom_Meeting_Sync_Access) | PermissionSetAssignment | nothing | none (they stay on the inactive user) |
| Name hardcoded in exclusion lists | `CEOIntelligenceController`, `PipelineCommandCenterController` | nothing | none |

These all came back empty for this user: CronTrigger, OauthToken, LoginHistory (0 rows ever), record ownership on every object in the loop, Loan_Partner__c on User or Lead, dashboards, sites, email services, auth providers, group membership, package licenses. Its role was already cleared.

---

## (b) Emails currently sent from Nimbus addresses

There is exactly one OrgWideEmailAddress: `0D2AJ000000001i0AA`, reachus@reachhomeloans.com, "ReachUs", allowed for all profiles.

### b1. Explicit Nimbus sender: Experience Cloud networks (8)

Every Network has `emailSenderAddress = development@nimbuscloudsolutions.com`. These cover welcome emails, password resets, and any portal notification.

| Network (metadata name) | Network Id | emailSenderName |
|---|---|---|
| Reach Home Loans Transactions | 0DBAJ00000000N54AI | Reach Home Loans Transactions |
| Lead Intake Form | 0DBAJ00000000ai4AA | Lead Intake Form |
| Closing Portal | 0DBQi0000000cJpOAI | Closing Portal |
| Lead Intake Form - Wemert Group | 0DBQi0000000cq5OAA | Lead Intake Form - Wemert Group |
| Borrower Portal | 0DBQi0000000ocjOAA | Borrower Portal |
| Borrower Portal v2 | 0DBQi0000000p8zOAA | Borrower Portal v2 |
| Lead Portal | 0DBQi0000000vkfOAA | Lead Portal |
| Partner Workspace | 0DBQi00000017aXOAQ | Partner Workspace |

How to switch: in Experience Workspaces > Administration > Emails, set Sender Email to reachus@reachhomeloans.com and Sender Name to "ReachUs" (or keep the site names). Alternatively, retrieve `Network:<name>`, edit `emailSenderAddress`/`emailSenderName`, and deploy. A non-verified sender address can trigger a verification email, and reachus@ is already a verified org-wide address. After the change, publish the LWR/Aura sites.

### b2. Implicit Nimbus sender: email sent as the running user while Nimbus is the running user

Any email whose sender is "current user" goes out From development@nimbuscloudsolutions.com when the transaction runs as Nimbus. Nimbus is the running user for the 34 scheduled Apex jobs, for Zapier writes, and for RingSense writes. Once those move to a new user, these emails come from that user's address instead. The permanent fix is to pin each one to the org-wide address.

Direct evidence: `EmailMessage WHERE FromAddress LIKE '%nimbus%'` (last 90 days) returned 3 rows: "A UWM Loan failed to update from UWM Insights batch", sent by `UWM_Insights_PipelineUpdateWebservice`. Emails from workflow alerts and `emailSimple` are not logged as EmailMessage, so the real volume is higher.

**Apex that sends without an org-wide address and runs in a Nimbus-owned context:**

| Class | Invoked by | Fix |
|---|---|---|
| `UWM_Insights_PipelineUpdateWebservice` | UWM Insights pipeline | `setOrgWideEmailAddressId(<reachus Id>)` |
| `UWM_Conditions_API_Batch` | UWM Conditions Sync job (error mail to `UWMSettings__c.Emails_For_Notifications__c`) | same |
| `RingSenseSilenceAlertService` | RingSense Silence Alert job | same |
| `GetRingCentralCallLog`, `RingCentralLogSMS`, `RingCentralUpdateCallLogsBatch` | RingCentral fetch jobs (error mail to label `Ring_Central_Error_Addresses`) | same |
| `ValueLink_Webservice` | ValueLink site (runs as the guest user) | same |

Look up the Id at runtime with `[SELECT Id FROM OrgWideEmailAddress WHERE Address='reachus@reachhomeloans.com']` rather than hardcoding it. These are the classes that already use the org-wide address, which is the pattern to copy: LeadStagnantAlertBatch/Service, WeeklyTransactionNoteSummary, LeadSmsOptOutScheduledMessagesService, RealtorLeadConvertService, LeadNoteTeamNotifier, TxnPostCloseZapierSweep. The 145 EmailMessages created by Nimbus in the last 30 days all show From reachus@.

**Workflow email alerts with `senderType = CurrentUser` (24 of 25):**
Event.An_event_starts_in_15_minutes; Lead.Email_to_send_Realtor_Meeting_Thank_You_Card, Email_when_lead_is_nurture_turndown_Realtor_Referral, Email_when_lead_is_pre_approved_Biz_Dev_Carey, Email_when_lead_is_pre_approved_Biz_Dev_Saludes, Email_when_lead_is_pre_approved_Realtor_Referral, Email_when_lead_is_under_contract_Biz_Dev, Email_when_lead_is_under_contract_Realtor_Referral, **Email_when_new_lead_is_created_from_Twilio**, SMS_Opt_In; Task.Email_when_task_is_escalated; Transaction__c.**Email_to_close_out_file**, **Email_when_3_days_until_rate_lock_exp_date**, **Email_when_5_days_until_rate_lock_exp_date**, **Email_when_Closing_Package_Is_Not_Dispositioned**, **Email_when_day_of_rate_lock_exp_date**, **Email_when_transaction_CD_Request_Date_is_populated**, **Email_when_transaction_CD_Send_By_Date_is_approaching_with_no_CD_Sent_Date**, **Email_when_transaction_Closing_Move_to_Docs_is_populated**, Email_when_transaction_Conditionally_Approved_Biz_Dev, Email_when_transaction_Conditionally_Approved_Realtor_Referral, **Email_when_transaction_closing_date_changes**, **Submission_Form_Complete_Alert**, Transaction_Loan_Commitment_Date_approaching.

The alerts in bold are fired by active automation: the process `Lead_Automation`; the flows `Rate_Lock_Expiration_Daily_Schedule`, `Send_Closing_Package_Follow_Up_Email`, `Submission_Form_Complete_Notification` and `Transaction_CLA_Automation_1`; and the active workflow rules "CD Send notification", "Email Alert To Close Out File" and "Transaction Closing Date change". Of these, `Email_when_new_lead_is_created_from_Twilio` is the one most likely to fire in Nimbus context today, because Twilio inbound runs through the Nimbus-owned job.
How to switch: in each `<alerts>` block of `workflows/Lead|Task|Event|Transaction__c.workflow-meta.xml`, set `<senderType>OrgWideEmailAddress</senderType><senderAddress>reachus@reachhomeloans.com</senderAddress>` and deploy (Meta). `Transaction__c.Email_when_new_transaction_is_created` already does this.

**Active flows whose `emailSimple` has no sender set (sender = running user):**
Alert_Message_Owner_of_New_Reply (one of its two actions), Brokered_Transaction_Notification, Closing_Date_Change_Notification, Closing_Package_is_Dispositioned, COC_Request (screen flow), COC_Request_Case_Notify_Creator_On_Status_Change, COC_Request_Case_Notify_Management, Condition_Notify_Assignee_On_Review, Lead_Appointment_Report_Email_Scheduled_Flow (scheduled, so it runs as the Default Workflow User), New_Task_Created_Alert_Adam, Shark_Tank_New_Lead. `Create_Condition_Comment` explicitly uses `CurrentUser` on one action. `Convert_Lead_to_Person_Account_on_TRID_Date` uses `DefaultWorkflowUser`.
How to switch: add `senderType = OrgWideEmailAddress` and `senderAddress = reachus@reachhomeloans.com` input parameters, which is the same pattern 26 flows already use. Deploy, then activate with the second FlowDefinition deploy (Meta). Caveat: the flow files are the latest version. Where the latest version is not the active one (for example `Account_Property_Sold_SOC_Notification`), open the active version before editing.

### b3. Nimbus address as a recipient (stop sending to it)

| Location | Value |
|---|---|
| Custom label `RingSense_Silence_Alert_Addresses` | clowman@…, development@nimbuscloudsolutions.com |
| Custom label `Ring_Central_Error_Addresses` | i.ostrovskyi@neo.polytech.software, development@nimbuscloudsolutions.com, o.halushka@…, s.kostyhin@… (also other outside contractors) |
| Flow `Closing_Package_is_Dispositioned` (active) | emailAddresses `rickie@reachhomeloans.com,development@nimbuscloudsolutions.com` |
| Apex hardcoded To: `LeadSmsOptOutScheduledMessagesService`:192, `LeadStagnantAlertBatch`:268, `LeadStagnantAlertService`:295, `RealtorLeadConvertService`:380, `UWM_Insights_PipelineUpdateWebservice`:35, `ValueLink_Webservice`:88 (the last two also include adamstephens250@gmail.com) | development@nimbuscloudsolutions.com |
| Email service `EmailToSalesforce` address `emailtosalesforce10` | authorizedSenders development@… |
| Lead Team notifications | `LeadNoteTeamNotifier` emails the Loan Partner, which is Nimbus on the 4 leads above |

Not a Nimbus sender: EmailTemplates (no hits), custom metadata, custom settings values (no field value contains a Nimbus address; only audit fields and the two user-level rows above), Case settings, auto-response rules.

---

## (c) Cut-over checklist

**Recommendation: create a dedicated Reach-owned user, "Reach Integration", on a full Salesforce license (2 spare).** Profile System Administrator, role Management, Email reachus@reachhomeloans.com (whoever monitors reachus@ clicks the verification link). Do not assign the jobs to a person.
Reasons:
- A person leaves, and then this same audit has to be repeated.
- A person's own mail would carry every "current user" email.
- The work needs things a Salesforce Integration license cannot give cleanly: owning scheduled Apex (Author Apex / System.schedule), being a site contact and guest-record default owner, being a dashboard running user, holding a TwilioSF seat and managed-package permission sets, and taking part in role-based sharing.
- With Email = reachus@, anything that still slips through as "current user" in integration context goes out as reachus@.

Optional hardening for later: put the pure-API OAuth connections (Zapier, RingSense) on a separate Salesforce Integration license user (5 available) for least privilege. That needs FLS and permset testing, and package permsets often cannot be assigned to Integration users, so it should not be on the critical path.

Ordered steps:

1. **Create "Reach Integration"** (UI). Assign the same 24 permsets as Nimbus minus MFA-specific ones as needed, **excluding Lead_Source_Change**. Assign the SalesUserPsl PSL, the spare **TwilioSF** seat, and the `Admins` group. Authorise the CLI as this user.
2. **Fix the Loan Partner default** (Data): change `User.Loan_Partner__c` on Christopher Lowman (`005f2000009OtLnAAK`) to a real user or blank. Clear it on the 4 test leads.
3. **Sites** (Meta or UI): set siteAdmin and siteGuestRecordDefaultOwner to Reach Integration on the 13 sites listed in A1 (siteAdmin only on Reach_Home_Loans_Transactions). Publish the Experience sites. Check that a lead-intake submission and a RingSense webhook still insert.
4. **Emails** (Meta), per section (b):
   - 8 Network sender addresses → reachus@.
   - 24 workflow alerts → OrgWideEmailAddress.
   - 11 active flows → OrgWideEmailAddress, then activate.
   - 7 Apex classes → `setOrgWideEmailAddressId`. Deploy with RunSpecifiedTests (memory "Prod Apex deploy test level"), deploying only the changed classes.
   - Remove development@nimbuscloudsolutions.com from the 2 labels, 1 flow and 6 Apex recipient lists. Remove the polytech.software addresses too if they are no longer wanted.
5. **Email services and auth providers** (Meta): FedExService runAsUser → Reach Integration. Remove or deactivate `emailtosalesforce10`. `UWM_ConditionsAuth` / `UWM_InsightsOAuth` executionUser → Reach Integration. Then run a UWM Conditions and Insights callout to confirm the named credentials still authenticate. Re-authenticate if they do not.
6. **Re-point OAuth integrations** (Ext): reconnect the Zapier Salesforce connection and every Zap on it, and the RingSense Salesforce connector, as Reach Integration. Watch OauthToken until Nimbus's Zapier and RingSense LastUsedDate stop moving.
7. **Scheduled Apex** (Data/Apex, logged in as Reach Integration): for each of the 34 jobs, record the name and cron expression (`cron.csv` in the scratch folder has them all), `System.abortJob`, then `System.schedule` with the same class and cron. Do the Twilio and RingCentral jobs in one quiet window, because the 5-minute jobs overlap. Decide whether to add the missing "Create Twilio Messages 9" (:40).
8. **Scheduled flows** (Meta): for the 9 flows, deploy FlowDefinition activeVersionNumber 0, then N, as a Reach admin, so that the CronTrigger is re-created under a Reach user. Recreate or drop the 7 report subscriptions (UI). Re-publish the 3 sites that own sitemap jobs.
9. **Dashboards and records** (UI/Meta and Data):
   - Change the running user on the 25 dashboards.
   - Transfer the 24 Accounts (especially "Customer Community User" `001AJ0000047qQ8YAI`), 30 Contacts, 7 Leads, 3 Opportunities, 3 Cases, and the 33 pending Scheduled_Message__c to Reach Integration or the right LO.
   - Historical logs, insights, tasks and messages can stay owned by the inactive user.
   - Add "Reach Integration" to the Apex name-exclusion lists.
10. **Verify** (read-only): `CronTrigger WHERE OwnerId='0055x00000Bs3rBAAR'` returns 0 rows. `Site WHERE AdminId = … OR GuestRecordDefaultOwnerId = …` returns 0. `Dashboard WHERE RunningUserId = …` returns 0. No new `OauthToken`/`LoginHistory` activity for Zapier or RingSense for 24 hours. New Tasks, TwilioSF messages and Call_Insight__c rows appear with the new owner and creator. Confirm in Setup that the Default Workflow User (expected Adam Stephens) and the Web-to-Lead default creator are not Nimbus.
11. **Freeze** Nimbus Development (reversible) and watch for 1-2 business days. Revoke its remaining OAuth tokens (hutte.io, Bitbucket CI, Gearset, CLI).
12. **Deactivate** Nimbus Development. Afterwards, the TwilioSF seat can be reclaimed, and the 21 Nimbus sandboxes can be deleted if they are no longer needed.

Outside step: ask Nimbus about `callreportgenerator.herokuapp.com` (ARIVE NMLS call report) before their access ends.

---

## (d) Verdicts

**Nimbus Development - Outside (`reachoutside@nimbuscloudsolutions.com`): safe to deactivate now.** It has no jobs, no tokens, no logins ever, no owned records, no site, dashboard, email service or Loan Partner references, and no role. The only effect is losing 8 permset assignments.

**Nimbus Development (`reach@nimbuscloudsolutions.com`): NOT safe to deactivate until steps 1-9 are done.** Salesforce will very likely refuse the deactivation while the user is site contact and guest-record default owner on 13 sites (step 3). If it went through, these would break:

- inbound Twilio, RingCentral SMS and call sync, the UWM Conditions and Insights syncs, ValueLink order status, the RingSense silence alert, weekly summaries and stagnant-lead alerts (34 scheduled Apex jobs, step 7);
- Zapier and RingSense writes (step 6);
- RingSense webhook and lead-intake-form inserts (guest owner, step 3);
- FedEx inbound email (step 5);
- 25 dashboards (step 9);
- Lead creation or reassignment for leads owned by Chris (Loan Partner share, step 2).

Steps 4 and 8 are needed to meet the stated goal of no email sent from Nimbus, and to clean up schedules that belong to an inactive owner. They are not what blocks the deactivation itself.

---

## Evidence queries (all run 2026-09-30 against `Production`)

- `SELECT Id, Username, Name, Email, IsActive, Profile.Name, LastLoginDate FROM User WHERE Username LIKE '%nimbus%' OR Email LIKE '%nimbus%' OR Name LIKE '%Nimbus%'`: 2 users
- `SELECT Id, CronJobDetail.Name, CronJobDetail.JobType, CronExpression, NextFireTime FROM CronTrigger WHERE OwnerId IN (…)`: 56 rows (full list in `scratchpad/nimbus-audit/cron.csv`)
- `SELECT CronTriggerId, ApexClass.Name FROM AsyncApexJob WHERE JobType='ScheduledApex' AND CreatedById IN (…) AND Status='Queued'`: 34 rows
- `SELECT ApexClass.Name, JobType, COUNT(Id) FROM AsyncApexJob WHERE CreatedById IN (…) AND CreatedDate = LAST_N_DAYS:7 GROUP BY …`
- `SELECT AppName, UserId, LastUsedDate, UseCount FROM OauthToken WHERE UserId IN (…)`
- `SELECT Application, LoginType, Status, COUNT(Id), MAX(LoginTime) FROM LoginHistory WHERE UserId IN (…) AND LoginTime = LAST_N_DAYS:30 GROUP BY …`
- `SELECT Id, Name, AdminId, GuestRecordDefaultOwnerId FROM Site`, plus `CustomSite` and `Network` metadata
- `SELECT Id, Title, RunningUserId FROM Dashboard WHERE RunningUserId IN (…) OR OwnerId IN (…)`: 26 rows (25 Nimbus-dependent)
- `SELECT Id, Name, Loan_Partner__c FROM User WHERE Loan_Partner__c IN (…)`: Christopher Lowman
- `SELECT COUNT() FROM <object> WHERE OwnerId IN (…)` over 161 objects; `CreatedById`/`OwnerId` counts for the last 30 days on 23 objects
- `SELECT CreatedBy.Name … FROM Call_Insight__c / Task / TwilioSF__Message__c / Lead_Event__c WHERE OwnerId='0055x00000Bs3rBAAR' AND CreatedDate = LAST_N_DAYS:30`: guest-user creators
- `SELECT CreatedBy.Name, Subject FROM Task WHERE Subject LIKE '%Review%' AND HOUR_IN_DAY(CreatedDate)=14`: Adam Stephens (Default Workflow User inference)
- `SELECT FromAddress, Subject FROM EmailMessage WHERE FromAddress LIKE '%nimbus%' AND CreatedDate = LAST_N_DAYS:90`: 3 rows
- `SELECT Id, Address, DisplayName FROM OrgWideEmailAddress`: 1 row (reachus@)
- `SELECT … FROM GroupMember / PermissionSetAssignment / PermissionSetLicenseAssign / UserPackageLicense / ProcessInstanceWorkitem WHERE … IN (…)`
- `SELECT NamespacePrefix, AllowedLicenses, UsedLicenses FROM PackageLicense`: TwilioSF 19/20
- `SELECT Name, TotalLicenses, UsedLicenses FROM UserLicense`: Salesforce 22/24, Salesforce Integration 0/5
- `SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName IN (…)` for every email-sending flow
- `SELECT SandboxName, AutoActivate, CreatedBy.Name FROM SandboxInfo` (tooling)
- `SELECT FIELDS(ALL) FROM <each of 57 custom settings>`, scanned for Nimbus Ids and addresses (managed protected settings were not readable)

Not verifiable from the API, so confirm these in the UI: the Default Workflow User (inferred Adam Stephens), the Web-to-Lead default creator, which reports the 7 report-subscription jobs belong to, which Zaps use the Nimbus connection, and the contents of protected managed settings (TwilioSF__TwilioConfig__c, rcsfl__Install_Settings__c, smagic, dfsle).
