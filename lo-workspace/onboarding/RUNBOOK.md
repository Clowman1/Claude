# LO Workspace loan officer: onboarding and offboarding runbook

For outside loan officers on full Salesforce licences in **LO Workspace**: profile "External Loan Officer Profile", role "External Loan Officer", permission set group `External_Loan_Officer`. The profile and role names are backend only; LOs see "Loan Officer".

| Owner | Does |
|---|---|
| **Manager** (Brandon, Adam) | Sends the hire details. Runs the Week 1 checks. |
| **Bianca + IT** | Creates the Microsoft 365 mailbox. |
| **Chris** (admin) | Zoom user, RingCentral user and extension, the Salesforce user, waivers, resets, offboarding. |
| **Marketing** | Builds the LO's landing page. |
| **The LO** | Day 1: first login, connections, goal-setting Q&A, tour. |

Decisions behind this runbook: [ONBOARDING-GRILL.md](ONBOARDING-GRILL.md). Tour script: [TOUR-SCRIPT.md](TOUR-SCRIPT.md).

---

## Stage 1: Before the hire

### 1.1 Manager sends the hire details (email or Teams)

```
First name:
Last name:
RHL email (from IT, once created):
NMLS #:
Licensed states (2-letter codes):
Mobile:
Office phone (optional):
Start date:
Uses Reach's RingCentral? (yes/no)
Needs the Twilio texting window? (almost always no)
Headshot URL (optional):
Email signature (optional, HTML ok):
```

Never send: a Loan Partner, or a request to add the LO to internal sharing groups or queues. Outside LOs never get either, and the script refuses both.

### 1.2 Accounts created outside Salesforce

| Step | Who | Done when |
|---|---|---|
| Microsoft 365 mailbox `first.last@reachhomeloans.com` | Bianca + IT | They can sign in to Outlook |
| Zoom user on **Reach's company Zoom account**, same RHL email | Chris | Zoom invite accepted. This is required: only meetings on Reach's account bring recordings and transcripts into Calls/Zooms and Application Summary. |
| RingCentral user and extension (only if "yes") | Chris | Extension number known |
| Confirm NMLS and licensed states (NMLS Consumer Access) | Manager | Matches the hire details |

---

## Stage 2: Day 0 (Chris)

### 2.1 Check licence headroom

There are 24 Salesforce licences and about 3 spare (Oct 2026). Twilio seats: 1 of 20 free. The script checks both and stops if none are free.

### 2.2 Run the provisioning script

1. Copy `hire.example.json` to `hire-<name>.json` and fill it in.
2. Run it without changes first:

   ```bash
   node lo-workspace/onboarding/provision-external-lo.js lo-workspace/onboarding/hire-jane.json
   ```

3. Read the PLAN and the WARNINGS, then make the changes:

   ```bash
   node lo-workspace/onboarding/provision-external-lo.js lo-workspace/onboarding/hire-jane.json --apply
   ```

The script does the following:

- **Creates the user:** profile, role, NMLS, licensed states, phone, signature and headshot. It sets "Loan Officer" as the notes role and turns on the intake-form and stale-lead alerts.
- **Assigns access:** the Einstein Activity Capture licence, the `External_Loan_Officer` group, and the `StandardEinsteinActivityCapturePsl` permission set (the group doesn't include it).
- **Adds optional items:** the RingCentral call center plus the "RingCentral required" flag if the hire uses RingCentral, and a Twilio seat if one was asked for.
- **Refuses to continue** if the email is already used by another active user, if no licence is free, or if a Loan Partner or sharing group is included.
- **Handles existing users:** if the username already exists, it only adds missing licences and permission sets, never overwrites fields, and warns about differences.

Don't delete hire files: they're the record of what was provisioned. They hold no secrets.

### 2.3 Manual steps the script prints

1. **Setup → Users → (the LO) → Reset Password.** Users created through the API get no welcome email.
2. **Setup → Einstein Activity Capture → Configurations →** add the user. This can only be done in Setup.
3. **Landing page:** you get an email and a notification ("set up their landing page") when the user becomes active. Send marketing:
   - endpoint `https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/lo-landing-page`
   - header `X-Reach-Webhook-Key`. The secret is in Setup → Custom Metadata Types → LO Landing Page Config → Default. Share it only over a secure channel.
   - body field `loEmail` = the LO's **username**
   - optional fields: firstName, lastName, email, phone, loanPurpose, city, state, notes, leadSource
4. **RingCentral** (if used): confirm the user appears under the RingCentral call center.

### 2.4 Never do this for an outside LO

- Set `User.Loan_Partner__c`. Every lead they get would pick up a default Loan Partner and a share.
- Add them to internal groups or queues (Lead Sharing, Access To Realtor Accounts, LP groups, Openers…). That breaks the isolation model.
- Put them on "Loan Officer Profile". That profile has View All on Accounts and Contacts.

---

## Stage 3: Day 1 (the LO)

On first login LO Workspace walks them through these steps in order. The lock applies **once**, on first login only.

1. **Sign in and set up MFA.** It's required.
2. **Get connected** (lock screen):

   | Row | Required? | How it turns green |
   |---|---|---|
   | Zoom | Required | Live check of their Zoom connection. They connect under Settings → External Credentials → Zoom → Allow Access. |
   | Outlook (email capture) | Required | They connect in Settings → Connected Accounts, then click "I've connected". You confirm later when their emails show on leads. |
   | RingCentral | Required only if set at hire | Extension plus a completed call-log authorisation |
   | Salesforce mobile app | Recommended | Their first login from the app |

   Anything missing shows on the lock screen with "Contact Chris".
3. **Goal-setting Q&A:** goals, workdays and business focus.
4. **Bran's tour:** the full 17-stop Perfect Day run (16 plus the RingCentral stop if they use RingCentral). They can skip it. "Take the tour" under their name, or the **?** on Perfect Day, replays any chapter.
5. When they clear the lock screen, you, Brandon and Adam get **"<Name> is live in LO Workspace"**, which starts Week 1.

**If an LO is stuck:** go to LO Oversight → Onboarding → **Waive** on their row. You must give a reason, and it's logged. Only admins see Waive; Brandon and Adam see the status only.

**If a connection breaks after Day 1:** they get a red banner on Perfect Day, never a lockout. Zoom is re-checked at most once a day.

---

## Stage 4: Week 1 (manager)

Track progress on **LO Oversight → Onboarding**: setup, Zoom, Outlook, RingCentral, mobile and tour (Done, Skipped or Not yet).

- [ ] A test lead from their landing page lands under them, with no Loan Partner, at the top of Perfect Day.
- [ ] They log a call. It shows in Recent activity and counts toward today's goals.
- [ ] They schedule a Zoom from the **Schedule a Zoom** card on a lead, and it appears on their calendar.
- [ ] They send a document request, and a borrower upload shows as the red HIGH ALERT in Up Next.
- [ ] They issue a Pre-Approval Letter on a lead at Pre-Approval or later.
- [ ] They add and tag a realtor (Add partner) and set the stage.
- [ ] They review My Perfect Week and My Progress with you.
- [ ] Oversight shows the tour as **Done**. If it shows **Skipped**, walk them through chapters A–L.
- [ ] You can see their emails on a lead, which confirms Outlook capture.

---

## Admin tools

| Tool | Where | Notes |
|---|---|---|
| Waive a connection | LO Oversight → Onboarding → Waive | Admin only. Reason required. Logged as "LO Workspace Onboarding Waiver". |
| Reset onboarding | LO Oversight → Onboarding → Reset onboarding | Clears setup, connections, waivers and tour. Keeps goals and data. Use it to re-test or re-onboard. |
| Provisioning script | `provision-external-lo.js` | Run without `--apply` first. Reconcile mode for existing users. |
| Pilot test user | `outsidelo.internal@reachhomeloans.com` ("LO Pilot") | Use Setup → Login as. Its email is still clowman@ until IT creates its own mailbox. |

---

## Offboarding (Chris only)

Do these in order, the same day if you can.

1. **Freeze** the user: Setup → Users → (the LO) → Freeze. This blocks login straight away.
2. **Leads they own** go to the manager named at offboarding (Brandon by default). Admins can change the owner past the owner lock. The Loan Partner share follows the rules automatically.
3. **Person Accounts they own** (imported past clients, borrowers) go to the same manager.
4. **Loans in progress:** set `Transaction__c.Loan_Officer__c` to the internal LO the manager picks. The record stamping updates automatically.
5. **Realtor tags:** delete their `External_User_Assignment__c` rows. Then delete the **Manual** AccountShare rows for the user on those realtor accounts; tags they created gave them a manual read share. The realtor records stay.
6. **Open Tasks and Events** go to the new owner, or are closed.
7. **Seats:** remove any Twilio seat (UserPackageLicense) and the Einstein Activity Capture licence, then **deactivate** the user to free the Salesforce licence.
8. **Outside systems:**
   - Chris: remove the Zoom user and the RingCentral user and extension.
   - Bianca and IT: the mailbox.
   - Marketing: take the landing page down. The webhook refuses inactive users anyway.
9. **Check:** the LO no longer shows on LO Oversight, and the reports "LO Workspace Leads/Loans by Status" show no rows for them.

---

## Known gaps (Oct 2026)

- The script's create path has only been tested with a throwaway record. The first real hire is its first real run, so read the PLAN carefully.
- The pilot needs its own mailbox (Bianca and IT) to test Outlook capture and landing-page email matching end to end.
- The RingCentral call-log sync and its authorisation page are Nimbus code with no owner yet. A separate session is fixing a security flaw in its callback.
- The tour's phone chapter was removed on 2026-10-09 and can be re-added later.
