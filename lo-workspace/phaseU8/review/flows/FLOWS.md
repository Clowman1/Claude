# U8 review: active Lead record-triggered flows that fire on insert

Read-only review, 2026-10-08. Source: `sf project retrieve start -o Production` of the 29 Create/CreateAndUpdate flows plus `Lead_Create_Scheduled_Message_On_Status_Pre_Approval`, in `force-app/main/default/flows/`. Every flow I spot-checked (17) has ActiveVersion = LatestVersion, so the retrieved XML is the active version.

Scenario: Apex inserts a clone of a converted Lead with Status = `Pre-Approval`, OwnerId = Transaction.Loan_Officer__c, Loan_Partner__c carried over, and `Recycled_From_Transaction__c` set. All other fields are copied.

## How often the copied fields arm a flow (counts from the 3,092 converted Leads in prod)

| Copied value on the original converted Lead | Count | Flow it arms |
|---|---|---|
| `Arive_Status__c = 'LOAN_SETUP'` | **1,670 (54%)** | Convert_Lead_to_Person_Account_on_TRID_Date (auto-converts and creates a NEW Transaction) |
| `AriveId__c` not null | 1,882 | (no flow, but ARIVE/Zap matching risk, see notes) |
| `Appointment_Date_Time__c` not null | **1,816 (59%)** | Lead_to_Event_for_Appointments |
| `Realtor_Buying_Agent__c` not null | 2,279 | Branch, Lawrence share, Last Referral Date, Referred By, Status-change SMS |
| LeadSource = Realtor Referral and agent set | 1,875 | Lead_Status_Change_Message_Sends (if IsChanged is true on create) |
| `CommSent_Pre_Approval__c = true` | 1,184 | suppresses the agent's "is Pre-Approved" SMS on the leads that have it |
| `ReferralFormSourceEmail__c` not null | **491** | Update_Lead_Information_on_New_Referral, New_Lead_from_Realtor_Intake_Form, New_Referral_..._Queue, Realtor_Lead_Placeholder_Email |
| `Preferred_LO__c` not null | 120 | Update_Lead_Information_on_New_Referral emails the Preferred LO and their Loan Partner |
| LeadSource contains "Website" | 24 | Website_Lead_Internal_Notification (Twilio SMS) |
| `Initial_Docs_Requested_Date__c` and agent set | 3 | Lead_Notify_Buyers_Agent_Docs_Requested (Twilio SMS to the agent) |
| LeadSource = Past Client and `Follow_Up_Account__c` set | 5 | Lead_Assign_Follow_Up_Lead_to_Transactions |
| `Company` not null | 0 | none |

## Inventory

Classes: **(a)** harmless data stamp, let it run. **(b)** outreach, notification, assignment or a dangerous side effect: must skip. **(c)** needs a judgment call. **n/a**: can't match an insert in Pre-Approval.

| # | Flow | Trigger | Entry condition | Effect on the recycled insert | Class | Guard |
|---|---|---|---|---|---|---|
| 1 | **Convert_Lead_to_Person_Account_on_TRID_Date** | C+U, after, only when changed to meet criteria (a create still counts) | Formula: `Arive_Status__c="LOAN_SETUP" AND NOT IsConverted AND owner role <> External_Loan_Officer` | **Fires on 54% of recycled leads.** ConvertLeadsInvocable converts the new Lead right away, creates a NEW Transaction__c (status TRID Application, TRID_Date = now, Loan Officer = the owner), re-types the Account, moves Enhanced Notes. On failure it emails the owner "could not convert". The whole recycle is undone at once. | **b (critical)** | Formula: wrap as `AND(ISBLANK({!$Record.Recycled_From_Transaction__c}), <existing>)`. Better still, also do not copy `Arive_Status__c`/`AriveId__c` (see notes) so a later real LOAN_SETUP push can convert it normally. |
| 2 | **Update_Lead_Information_on_New_Referral** | Create, after | `ReferralFormSourceEmail__c IsNull false` | **Reassigns OwnerId** (Spanish intake goes to Martin; InIT Webinar to its dedicated owner; else Preferred LO; else the intake queue). Overwrites LeadSource, Loan_Purpose__c, Realtor_Buying_Agent__c, Realtor_Lead_Source__c and Biz_Dev__c. Sends "Lead Assigned" emails to the Preferred LO and Loan Partner (cc clowman/benjamin), the Cabrera/Fritz emails and the InIT owner email. Publishes `Intake_Form_New_Lead_Created__e`, whose subscriber flow texts the LO. | **b** | Add filter `Recycled_From_Transaction__c IsNull true` (logic `and`). |
| 3 | **New_Lead_from_Realtor_Intake_Form** | C+U, after, only when changed | `ReferralFormSourceEmail__c` not null AND `Realtor_Buying_Agent__c` not null AND `MobilePhone` not null | Twilio SMS to the **borrower** (between 8am and 9pm; otherwise sets `Should_Send_Referral_Message__c=true` for a later send), Twilio SMS to the **agent** ("thank you for your referral"), internal SMS to 954-478-8366. If there is no Preferred LO and the owner is not a user, it also emails insidesales. | **b** | Add filter `Recycled_From_Transaction__c IsNull true` (logic `and`). |
| 4 | **New_Referral_Lead_Send_Notification_When_It_s_Still_In_Queue** | Create, after, **scheduled path +10 min** | `ReferralFormSourceEmail__c IsNull false` | After 10 min it emails insidesales "Unclaimed Aged Lead" if the owner is queue 00GQi0000032d5BMAQ. That is a no-op only if the owner is still the LO, and #2 can move the owner to that queue. | **b** | Add filter `Recycled_From_Transaction__c IsNull true`. |
| 5 | **Lead_Status_Change_Message_Sends** | C+U, after | `Status IsChanged true` AND agent not null AND LeadSource = Realtor Referral | If it fires on create: Status = Pre-Approval and `CommSent_Pre_Approval__c=false` sends the agent a Twilio SMS "<Borrower> is Pre-Approved." About 690 of the 1,875 eligible converted leads have the flag false. Salesforce normally evaluates IsChanged as false on insert, but this is unverified here, and the cost of guarding is zero. | **b** | Add filter `Recycled_From_Transaction__c IsNull true` if later status-change texts on the recycled lead are also unwanted. If they should still go to the agent after the insert, convert to a formula: `AND(ISCHANGED({!$Record.Status}), NOT(ISBLANK({!$Record.Realtor_Buying_Agent__c})), TEXT({!$Record.LeadSource})="Realtor Referral", NOT(AND(ISNEW(), NOT(ISBLANK({!$Record.Recycled_From_Transaction__c})))))`. |
| 6 | **Website_Lead_Internal_Notification** | C+U, after, only when changed | LeadSource not null AND contains "Website" | Twilio SMS "A new Website Lead has been created" to every user with `Website_Lead_Source_Notification__c`. | **b** | Add filter `Recycled_From_Transaction__c IsNull true` (logic `and`). |
| 7 | **Lead_Notify_Buyers_Agent_Docs_Requested** | C+U, after, only when changed | Formula: `Initial_Docs_Requested_Date__c` not blank AND agent not blank | Twilio SMS to the agent: "Documents have been requested from <Borrower>...". Fires when the copied date is present (3 today). | **b** | Formula: `AND(ISBLANK({!$Record.Recycled_From_Transaction__c}), <existing>)`, or don't copy `Initial_Docs_Requested_Date__c`. With the permanent guard, a later real docs request on the recycled lead won't text the agent. Use `NOT(AND(ISNEW(), NOT(ISBLANK(...))))` if that text should still go out later. |
| 8 | **Lead_to_Event_for_Appointments** | Create, after | `Appointment_Date_Time__c IsNull false` | Creates an Event ("Call", Scheduled Appointment) on the new owner's calendar at the **old, past** appointment time. That runs EventTrigger (Zoom object access) and calendar sync. Fires on about 59% of recycled leads. | **b** | Add filter `Recycled_From_Transaction__c IsNull true`, or don't copy `Appointment_Date_Time__c`. |
| 9 | **Assign_Loan_Partner_on_Lead** | C+U, after | Formula: `OR(ISNEW(), ISCHANGED(OwnerId))` | On insert it **overwrites the carried-over Loan_Partner__c** with the owner LO's `User.Loan_Partner__c`, or blanks it if that user has none. This defeats the "Loan Partner carried over" requirement and changes Lead sharing (OWD Private; Loan Partners see leads only through a Manual share). | **b** | Formula: `AND(OR(ISNEW(), ISCHANGED({!$Record.OwnerId})), NOT(AND(ISNEW(), NOT(ISBLANK({!$Record.Recycled_From_Transaction__c})))))`. A later owner change still re-stamps normally. |
| 10 | **Lead_Assign_Follow_Up_Lead_to_Transactions** | C+U, after, only when changed | LeadSource = Past Client AND `Follow_Up_Account__c` not null | Sets `New_Follow_Up_Lead__c` = the recycled lead on **every** Transaction of that account, which fires Transaction automation (about 119 automations). It also misattributes the past-client follow-up. Only 5 converted leads match. | **c, lean b** | Add filter `Recycled_From_Transaction__c IsNull true`. |
| 11 | **Stamp_Last_Referral_Date_on_Account** | C+U, after, only when changed | `Realtor_Buying_Agent__c IsNull false` | Updates the realtor Account `Last_Referral_Date__c` = today, so a recycle looks like a new referral from that agent. The Account update also runs Account automation. | **c, lean skip** | Add filter `Recycled_From_Transaction__c IsNull true`. |
| 12 | **Lead_Branch_Assignment** | C+U, after | Formula: `(ISNEW() AND agent not blank) OR (ISCHANGED(agent) AND not blank)` | Recomputes `Branch__c` from the agent's Realtor_Group__c (Nickley → Orlando, else Boca Raton) and overwrites the copied Branch__c. Usually the same answer as the original, but it differs if the realtor changed groups or Branch was set by hand. | **c** | To keep the copied Branch exactly: `AND(<existing>, NOT(AND(ISNEW(), NOT(ISBLANK({!$Record.Recycled_From_Transaction__c})))))`. Otherwise let it run. |
| 13 | **Stamp_Pre_Approval_Date_when_Status_is_Pre_Approval** | C+U, **before**, only when changed | Status = Pre-Approval | Sets `Pre_Approval_Date__c` = TODAY, overwriting the copied original date. Before-save flows run before Apex before-triggers, so Apex cannot win by setting the value first. A today date counts the lead as a new pre-approval in date-based reports and in pull-through (it is also copied onto the next Transaction on conversion, see #1). | **c** | To keep the original date: add filter `Recycled_From_Transaction__c IsNull true` (logic is `or` with one condition, so change it to `and`). Leave as-is if "re-pre-approved today" is the desired semantics. **Decision needed.** |
| 14 | **Lead_Event_Status_Changed** | C+U, after | Formula: `OR(ISNEW(), ISCHANGED(Status))` | Creates a Lead_Event__c named "Pre-Approval" (status history). This is pure data, but any report built on Lead_Event__c entries will count an extra Pre-Approval entry. | a | None needed. Optionally guard ISNEW for reporting purity. |
| 15 | Set_First_Contact_Date_on_Lead | C+U, before | Formula: First_Contact null, status not New/Contact Attempt, ISNEW or ISCHANGED | No-op if the copied `First_Contact_DateTime__c` is set; otherwise stamps now. | a | None. |
| 16 | Share_Leads_With_Lawrence_Lanos | C+U, after | Formula: ISNEW and any realtor group set, or referral/agent changes | Inserts a Read Manual share to Lawrence Lanos for Nickley Group leads. This mirrors the access he had on the original lead and is not a notification. | a | None (guard if he should not see recycled leads). |
| 17 | Stamp_Referred_By_When_Buying_Agent_is_Filled_In | C+U, after, only when changed | agent not null AND Referral_Source__c null AND LeadSource = Realtor Referral | Fills `Referral_Source__c` from the agent's PersonContact only if it is blank. | a | None. |
| 18 | Lead_Default_Scenario_Manager | Create, before | Formula: Scenario_Manager blank AND consumer record type | Defaults Scenario_Manager__c (Byron) only if the copied value is blank. | a | None. |
| 19 | Realtor_Lead_Placeholder_Email | Create, before | ReferralFormSourceEmail not null AND Email null | Stamps `na@na.com` when Email is blank. | a | None. |
| 20 | Lead_Clear_Phone_and_Mobile_Phone | C+U, before | (Phone or Mobile contains "phone") AND LeadSource contains Website | Strips the literal "phone" text. | a | None. |
| 21 | Flow_to_Force_Company_field_to_Empty | C+U, before | Company changed and not null, non-excluded record type | Blanks Company (0 converted leads have Company). | a | None. |
| 22 | Shark_Tank_New_Lead | Create, after | OwnerId = queue 00G5x000006iXbrEAE | Emails rdaugela. Can't match because the owner is an LO user. | n/a | None, unless Apex falls back to a queue when the LO is inactive. If so, guard it. |
| 23 | Lead_Docs_Received_for_Review_field_update | C+U, after | Status = Documents Received for Review | Doesn't match Pre-Approval. | n/a | None. |
| 24 | Lead_Documents_Received_for_Review_task | C+U, after | same | same | n/a | None. |
| 25 | Lead_Under_Contract_field_update | C+U, after | Status = Under Contract | same | n/a | None. |
| 26 | Lead_Under_Contract_task_record_type | C+U, after | same | same | n/a | None. |
| 27 | Leads_Documents_Requested | C+U, after | Status = Documents Requested | same | n/a | None. |
| 28 | Lead_meeting_complete_biz_dev | C+U, after | Status = Meeting Complete, Realtor record type, 3 owners | same | n/a | None. |
| 29 | Stamp_Pre_Approval_Date_on_Lead_Conversion | C+U, before | Status Under Contract/Submitted For Disclosures AND IsConverted = true | Impossible on insert. | n/a | None. |

Counts: **b = 9** (#1 to #9), **c = 4** (#10 to #13), **a = 8** (#14 to #21), **n/a = 8** (#22 to #29).

## Lead_Create_Scheduled_Message_On_Status_Pre_Approval

- `RecordTriggerType = Update`, after-save. Its entry condition needs `Status IsChanged` AND Status = Pre-Approval AND one of 8 hard-coded owners AND not opted out. **An insert never runs an Update-only flow**, so inserting a lead already in Pre-Approval skips it.
- It can fire later only if the recycled lead's status moves away from Pre-Approval and back while it is owned by one of those 8 users. That is normal behaviour.
- No other retrieved flow creates `Scheduled_Message__c`; it is the only flow in the set that references the object. No create-time flow schedules a Pre-Approval message. The only scheduled path on create is #4 (internal email after 10 min). Apex triggers on Lead were out of scope for this pass; the 9 Lead triggers still need the same review.

## How to add the guard

- **Filter-list entries with logic `and`** (#2, #3, #4, #6, #8, #10, #11, and #5 if a permanent guard is fine): add condition `Recycled_From_Transaction__c` IsNull `true`. The logic stays `and`.
- **Custom logic** (none of the must-change flows use it; #13 uses `or` with a single condition): change it to `and`, or to `1 AND 2`.
- **Formula entries** (#1, #7, #9, #12): a filter row can't be added, so edit the formula.
  - Permanent guard: `AND(ISBLANK({!$Record.Recycled_From_Transaction__c}), <existing>)`.
  - Insert-only guard: `AND(<existing>, NOT(AND(ISNEW(), NOT(ISBLANK({!$Record.Recycled_From_Transaction__c})))))`.
- **Permanent or insert-only.** A filter-list `IsNull` guard suppresses the flow for the life of the recycled lead, including later user edits. Where later behaviour should be normal (#5 status texts, #7 docs-requested text, #9 Loan Partner on owner change, #1 a genuine future conversion), use the insert-only formula. That means converting the entry from filters to a formula.
- Flow deploys land as Draft. Each change needs a second FlowDefinition `activeVersionNumber` deploy.
- Nimbus has rolled back flows from stale copies before. Re-retrieve and diff before deploying.

## Cheaper complement: a copy denylist in the Apex clone

"All fields copied" is what arms most of the dangerous flows. If the Apex clone nulls these, they never match, and future genuine events still fire normally:

- `Arive_Status__c`, `AriveId__c`. Copying them arms #1 on insert. Worse, because #1 is "only when changed", a real future LOAN_SETUP push would **never** convert the recycled lead. The duplicated AriveId__c also makes ARIVE→SF and SF→ARIVE Zap matching ambiguous between the old and the recycled lead.
- `ReferralFormSourceEmail__c` (arms #2, #3, #4, #19), `Appointment_Date_Time__c` (#8), `Initial_Docs_Requested_Date__c` (#7), `Should_Send_Referral_Message__c`.
- `Converted_Transaction_ID__c` (points at the cancelled Transaction), and the `CommSent_*` flags (choose deliberately: copied true suppresses the agent texts).

Guarding the flows is still required for #6 (LeadSource-driven), #9 (ISNEW-driven), #10, #11 and #5. The denylist is defence in depth, not a substitute.

## Risky or surprising

1. **#1 would immediately reconvert 54% of recycled leads into a brand-new Transaction.** This is the biggest hazard.
2. **#9 silently replaces or blanks the carried-over Loan Partner** on every insert, which breaks a stated requirement and Loan Partner access.
3. **#2 reassigns the owner away from the LO** (to the queue, Martin, the InIT owner or the Preferred LO) for any lead that originated from the realtor intake form (491 converted). It also overwrites LeadSource and the agent and sends emails plus a platform-event SMS.
4. **#3 texts the borrower and the agent** for the same 491-lead population.
5. **#8 drops past-dated appointment Events** onto the LO's calendar for about 59% of recycled leads.
6. **#13 restamps Pre_Approval_Date__c to today.** A product decision is needed. Before-save ordering means Apex cannot override it without a flow guard.
