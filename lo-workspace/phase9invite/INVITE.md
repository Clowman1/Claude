# Phase 9: In Person Invite for outside LOs (BD invite port)

Status: BUILT and check-only VALIDATED (0AfQi000001TobxKAC, 14/14 tests, BdCommandCenterController at 92%). NOT DEPLOYED.
Source was retrieved fresh from prod on 2026-10-01.

## What was reused and what changed
| Component | Change |
|---|---|
| `bdInviteModal` | Two new @api props: `heading` (default "Schedule invite") and `scope` (blank = BD). `scope` is passed through to createInvite. |
| `bdUpcomingCard` (NEW) | BD's "Upcoming" card moved out of bdCommandCenter as-is. @api `heading` defaults to "Upcoming", and `emptyText` keeps the BD wording. |
| `bdCommandCenter` | Uses `c-bd-upcoming-card`. `eventRow()` moved to `bdUtils` and is shared. BD looks and behaves the same. |
| `bdUtils` | `eventRow` added as an export. |
| `loWsInPersonEvents` (NEW) | Wrapper that holds bdUpcomingCard ("Upcoming In-person Events") plus bdInviteModal ("In Person Invite", scope `lo`) plus the existing bdEventTracker. It has `@api openInvite()` and `hide-card`. It does nothing in the portal (`isExperienceCloudContext`). |
| `perfectDayHome` | Adds an "In Person Invite" button in the banner, after Log activity. Adds the card as the last grid item, which lands in the right-hand column on desktop (after Recent log). Both are hidden in the portal. |
| `externalLoRealtors` | My Realtors list header gets "In Person Invite" before "Add partner". Hidden in the portal. |
| `BdCommandCenterController` | Adds the LO path (below). The BD paths are unchanged. |
| `External_LO_Access` | Gets class access to `BdCommandCenterController`. Every BD entry point still requires BD_Command_Center or BD_Manager. |
| `BdLoInviteTest` (NEW) | Runs as an External Loan Officer Profile/role user, without Marketing User. |

## Outside-LO scoping (server side)
- The LO path is gated by `LoWsPartnerTagService.isTagMode()`, which means External_LO, or LO_Workspace_Demo for Brandon.
- `getLoInviteHome()` returns two things:
  - **Partners:** `myTags()` accounts plus partner-type Person Accounts the LO owns (`isPartner`).
  - **Upcoming:** future Type=Event campaigns where the LO is the Owner or a Campaign_Co_Host__c.
- `createInvite(scope='lo')` re-derives the partner set on the server. If any requested Id is outside it, the whole invite is refused. Without `scope` the call goes down the BD path, which still requires BD_Command_Center.
- `getEvent` and `resendInvite` for non-BD users require the caller to be the campaign's owner or a co-host.
- Co-hosts (owner decision 2026-10-01): in the LO scope, `searchCoHosts` offers only internal Reach staff, meaning active users with UserType Standard who are not in role External_Loan_Officer. `createInvite(scope='lo')` rejects any other co-host before it creates anything. BD reps still get the unfiltered engine search.
- **Host:** the engine's host is Campaign.OwnerId and the co-hosts, and the sender is the running user. The LO creates the Campaign, so the LO is its host. `isRealtorEventHost` is a Pipeline Command Center flag only and is not involved. Nothing changed for internal users.
- **Sharing:** Campaign, CampaignMember and Event writes run through the Apex system-mode engine. RealtorEventWorkspaceController is `with sharing`, but the LO owns the Campaign and can read invitees through a tag's Manual Read share or by owning them. No restriction rule covers Campaign, CampaignMember or Event. The profile already has Campaign Read, which "Open event" needs. No other permissions were needed.

## What an outside LO's invite sends (the same as BD)
1. Calendar Event on the LO's own Salesforce calendar (WhatId = Campaign), which fires EventTrigger. No Zoom meeting.
2. Queueable batches of 10. Each invitee gets a branded HTML email with Yes/No RSVP links, from the LO's name with reply-to the LO's email and their signature card (Headshot, Title, Phone, NMLS__c). Any co-host's card is included too.
3. After a successful email, a Twilio SMS: "Check your email inbox for an invite to our upcoming event from {host first names}". It goes through flow Realtor_Event_Send_Invite_SMS (TwilioSF__TwilioSendSMS), running as the LO.
4. The existing scheduled RealtorEventReminderBatch sends an RSVP reminder 5 days out to non-responders and a "tomorrow" email to attendees. Both come from the Campaign owner, which is the LO.
5. Resend (from the tracker) sends one email and no SMS.
RSVP clicks update the CampaignMember through the existing guest site. No email goes to the host.

## Deploy (from this folder)
```
sf project deploy start -o Production -d force-app --test-level RunSpecifiedTests --tests BdCommandCenterControllerTest --tests BdLoInviteTest --tests RealtorEventRsvpServiceTest
```
or quick-deploy the validation: `sf project deploy quick -o Production --job-id 0AfQi000001TobxKAC`.

After the deploy, republish Partner Workspace (Experience Builder). perfectDayHome and externalLoRealtors are portal components, and LWR serves the bundle from the last publish. The new UI stays hidden in the portal either way.

## Open questions
- The Twilio SMS runs as the LO, and outside LOs hold no Twilio seat or TwilioSF permset. If the action needs one, the text fails, but it is logged on CampaignMember.Invite_SMS_Error__c and the email still goes out. Check this with the pilot's first invite.
- Card placement: kept as built (owner decision).
