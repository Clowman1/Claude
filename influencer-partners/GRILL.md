# Influencer Partners pipeline — grill decisions (2026-10-23)

Owner: Ernesto Gutierrez (primary manager). Chris, Brandon, Adam: full edit too.
Nothing built yet. Build only after Chris confirms this doc.

## Partner record
- Person Account from day one (Target). Never a Lead.
- New Account fields: `Influencer_Stage__c`, `Influencer_Lost_Reason__c`, `Influencer_Lost_From_Stage__c`,
  `Biggest_Channel__c` (YouTube, Instagram, TikTok, Facebook, Podcast, X, Other), `Channel_URL__c`,
  `Audience_Size__c`, `Offer_Website__c`, `Influencer_Assigned_LO__c` (User), `Influencer_Partner_Code__c` (unique),
  `Agreement_Signed_Date__c`, `Influencer_Monthly_Fee__c`, `Influencer_Last_Touch__c`. Notes = standard ContentNotes.
- Name / Email / Phone = standard Person Account fields.
- Stages: Target, Contacted, Meeting Booked, Follow Up, Marketing Agreement Signed,
  Landing Page Launched & Tested, Active, Lost.
- Manual moves (drag or buttons). Auto: Target → Contacted on first logged touch; → Meeting Booked on a future Event.
- Lost: reason required (No response, Not interested, Audience not a fit, Terms declined, Went with competitor, Other),
  stores the from-stage; Reopen returns to it.
- Type__c: new value "Influencer Partner" for new partners. Existing borrower linked as partner keeps Borrower Account.
  **Everything keys off `Influencer_Stage__c` being set, never Type__c.**
- Add partner: dupe alert on phone/email (ignore na@na.com) → select existing account. No import; Ernesto starts empty.
- Partner code: auto from name (`MARIA-G`, numeric suffix on collision), editable until first lead, then locked.
- Agreement file attached to the account. Fee is flat monthly (RESPA §8 — never per lead/loan).

## Intake
- One generic form, same design as the Realtor Lead intake form: `.../LeadIntakeForm/s/?partner=<code>`.
  No email in the URL (influencers post it publicly).
- Partner recognised (code → account with Influencer Stage set): Lead.Referral_Source__c = partner PersonContact,
  LeadSource = "Influencer Partners", Realtor_Buying_Agent__c stays blank. Skip the realtor branches of
  `Update_Lead_Information_on_New_Referral` (Buying Agent + Realtor Referral / InIt stamp) and
  `New_Lead_from_Realtor_Intake_Form`.
- Form shows only the partner's Assigned LO tile → Owner. Spanish → Martin rule still wins. No LO → normal queue.
- Workspace "New Lead from this Partner" button stamps the same two fields. No retro re-tagging (Lead Source lock).
- "Landing Page Launched & Tested" = link sent + one test lead came through.

## Attribution plumbing
- Add "Influencer Partners" to: Lead.LeadSource (+ Consumer, Loan Officer, Realtor RTs — redeploy RTs),
  Transaction__c.Lead_Source__c (own value list), Account.Type__c "Influencer Partner" (+ PersonAccount RT).
- Conversion flow `Convert_Lead_to_Person_Account_on_TRID_Date` already copies LeadSource + Referral_Source__c.
- Results join Lead → Transaction via ConvertedAccountId = Borrower_Name__c (Transaction Referral Source is thin).

## UI — `influencerPartners` LWC (LO Workspace / BD look, reuse bdStyles + bdLogTouchModal)
- Surfaced as a 3rd master button "Influencer Partners" in Ernesto's webinarMarketingCommandCenter,
  and as its own CustomTab for Chris/Brandon/Adam. Gated by permset/custom permission `Influencer_Partners`
  (Apex without sharing — Lead OWD is Private; views are read-only).
- Views: Pipeline (8-stage kanban, Lost collapsed) | Leads (read-only) | Loans (read-only) | Results.
- Partner side workspace: contact + channel link, agreement + fee, copyable intake link, touch timeline + Log touch,
  that partner's leads/loans/results, New Lead button.
- "Needs a touch": 14 days no touch, all stages except Lost; for Active a new lead also resets it. No digests.
- Desktop only.

## Results math
- Leads by Lead CreatedDate; Pre-Approved = status reached Pre-Approval; Loans = linked Transactions;
  Closed = Post-Closed by Post_Closed_Date__c; Volume = Loan_Amount_1st__c; Cancelled shown separately.
- Conversion % lead → closed. Cost = fee × months from Agreement Signed to today/Lost. Cost per closed loan.
- Filter This Month / Quarter / YTD / All Time (default YTD). Program totals + per-partner leaderboard.

## Build cautions
- Diff bd* files against the org before touching them (other sessions edit them).
- Lead Source lock: only set on insert or blank → value.
- Flow deploys land as Draft — activate via FlowDefinition.
- Prod Apex deploys: RunSpecifiedTests, deploy only changed classes.

## Built + deployed 2026-10-23
- Source: `influencer-partners/force-app`. Apex `InfluencerPartnersController` (+Test), `LeadInfluencerAttribution` trigger/class (+Test),
  `IntakeFormController.getInfluencerPartner`, Aura `IntakeForm` (?partner= mode), LWCs `influencerPartners` + `influencerPartnerPanel`,
  `webinarMarketingCommandCenter` 3rd button (shown via customPermission Influencer_Partners), CustomTab `Influencer_Partners`.
- Permset `Influencer_Partners` assigned: Ernesto, Chris, Brandon, Adam. Guest "Lead Intake Form Profile" got edit on Lead.Influencer_Partner_Code__c.
- Deviations from the plan above: Notes = `Account.Influencer_Notes__c` long text (not ContentNotes). The existing Spanish rule routes to
  **Brandon Brotsky** (005f2000009NwSsAAK, hardcoded in the form), so influencer Spanish leads go to Brandon too.
- The realtor intake flows are untouched: the influencer form never sets ReferralFormSourceEmail__c; LeadInfluencerAttribution stamps,
  routes and sends the LO email + Intake_Form_New_Lead_Created__e SMS itself.
- Unknown ?partner= code = plain form. Verified in prod: form shows "Referred by" + the LO tile; tab, panel, Leads/Loans/Results load.
  End-to-end verified 2026-10-23: two real ?partner= submissions -> stamps, owner = Assigned LO, LO email (reachus@) + RingCentral text both arrived; test records deleted by id. Email send failures now log to Custom_Log__c (Source "Influencer Intake Email Error").
- Deploy tests: RunSpecifiedTests LeadInfluencerAttributionTest, InfluencerPartnersControllerTest, IntakeFormControllerTests.
- 2026-10-23 correction: intake is Ernesto's custom landing page -> Zapier -> Lead (Zap runs as Ernesto, Consumer RT by default).
  No code change was needed: LeadInfluencerAttribution acts on ANY insert carrying Influencer_Partner_Code__c, and overrides the
  Zap's LeadSource. Zap must map the partner code into Lead.Influencer_Partner_Code__c (+ LeadSource = Influencer Partners as a
  safety net). Panel now shows "Partner code" + Copy instead of the form link. Verified with an API insert (test records deleted).
  The ?partner= Salesforce form path still works as a backup.
- 2026-10-23: new-lead alert email (subject "New Influencer Partner Lead: <name>") now goes to the owner LO + their Loan Partner +
  Ernesto (LeadInfluencerAttribution.PROGRAM_MANAGER_USERNAME). Queue-owned leads (no Assigned LO) email Ernesto only. Text stays LO-only.
