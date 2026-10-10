# U8 review – Zapier (read 2026-10-08 via the Zapier web API, read-only)

184 Zaps in the account; 81 touch Salesforce. Only three **live** Zaps have a Salesforce trigger:

| Zap | Trigger | Would a recycled lead fire it? | Action needed |
|---|---|---|---|
| 169907490 **SF to Arive on New Lead** (on) | Salesforce *New Record* on **Lead** | Yes, the trigger fires. The filter then **stops** if `AriveId__c` exists, and continues only if FirstName, LastName, Email and Loan_Purpose__c exist (and LeadSource doesn't contain Newconstruction2022). | **Must** be blocked or it creates a second ARIVE loan. Copying `AriveId__c` from the original lead already stops it. Belt and braces: add a filter rule "Recycled_From_Transaction__c does not exist" (editor in the browser; the API is read-only). |
| 359372859 **Docs Requested Salesforce -> GHL** (on) | Salesforce *Updated Field* Lead.Status → Pre-Approval / Documents Requested | Possibly on insert (Zapier field-update triggers can treat a new record's value as a change); filtered to LeadSource = **Consumer Webinar** only. | Pushes a GoHighLevel opportunity, which can start GHL follow-ups to the borrower. Add the same "Recycled_From_Transaction__c does not exist" filter. |
| 269745368 SF Status to Arive Stage (on) | Transaction__c.Status__c updated | Not by the lead. The cancel itself already fires it; it deliberately skips Cancelled. | None. |

ARIVE → Salesforce Zaps that find a Lead **by AriveId**:
- 375862952 Credit Pull Date (writes Credit_Order_Date__c only when Lead IsConverted = false).
- 382464123 Application Fields to Lead.

With a copied AriveId these would update the **recycled** lead (the only unconverted one), which is the desired behaviour.
