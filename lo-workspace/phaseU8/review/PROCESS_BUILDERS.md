# U8 review – Process Builders and workflow rules on Lead (read 2026-10-08)

## Workflow rules on Lead
All four are inactive (Purchase Lead Submitted Biz Dev ×2, TwilioSF Clear Last Message Status/Date, UPDATE SMS). Nothing to do.

## Process Builder `Lead_Automation` (active, evaluates on create and every edit)
Two of its rules fire on INSERT:

| Rule | Criteria | Actions | Would a recycled lead fire it? |
|---|---|---|---|
| New Lead, Mobile is blank | `AND(ISNEW(), ISBLANK(MobilePhone))` | Twilio texts to 10 internal users (Adam, Jay, Joe, Kevin, Lauren, Alex, Chad, Dylan, Ryan, Chris D): "A new lead is waiting!" | **Yes, often**: 705 of 3,092 converted leads (23%) have no MobilePhone. |
| New Lead created from Twilio | `AND(ISNEW(), LeadSource = 'Facebook - Landing Refi')` | Text to the **borrower** ("Thank you for contacting Reach Home Loans!…") + email alert to the LO | Rare: 2 converted leads have that source, and recycle is purchase-only. Still must be guarded. |

The other rules (new call logged, meeting complete, owner change on FB Landing Refi leads) need a change, not an insert.

**Fix:** edit both formulas to `AND(ISNEW(), ISBLANK({!myVariable_current.Recycled_From_Transaction__c}), …)`. This is a Process Builder, deployed as a flow version that then needs activating. Process Builders can't be bypassed from Apex.

## Process Builder `Lead_Automation_Scheduled_Actions` (active)
- Day-2…Day-23 drip texts.
- Only for LeadSource 'Facebook - Landing Refi' with Lead_Claimed__c = true and status New / Contact Attempt / Nurture / Contacted-Call Back.
- A recycled lead is in Pre-Approval, so it can't enter these rules on insert.
- It could enter later if the LO moves it to one of those statuses, which is normal behaviour.
- No change needed.
