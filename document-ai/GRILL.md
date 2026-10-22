# Document AI for borrower portal uploads — grill notes (tabled 2026-10-21)

Nothing built. Resume at "Open questions".

## Decided
1. Scope phase 1: classify + completeness/quality check. Extraction (employer, period, holder) later; underwriting-style analysis last.
2. AI suggests, human decides. Exception (7b): auto re-file to another condition ONLY when a matching condition is open on the same Lead AND confidence is high; never changes status; labelled "re-filed by AI"; one-click undo.
3. "Learning" = accuracy tracking (AI vs human decision) + plain-English rules tuned by people. No custom model training.
4. Data may go to ONE vetted external vendor under contract (ZDR, no training), server-to-server via Named Credential. Never Zapier/middleware.
5. Stage: pre-approval Lead portal first, then Transactions.
6. Borrower sees instant feedback in the portal; never blocks upload.
8. Name on doc vs borrowers on Lead: flag mismatch, never block.
9. AI writes labels/issues only. Later extraction: account numbers last-4 only, never SSN.
10. Approvers: Christopher + the owners.
11. Soft cost cap with alert (volume ~210 files/month, cost trivial).
12. Vendor: Anthropic Claude API.
13. Fix existing OpenAI exposure as a separate piece: plain-text key in OpenAI_Credentials__c used by ChatGPTService (transcripts); move to Named Credential + confirm OpenAI terms/retention, or move to Claude.
14. Check fires per upload (Queueable), portal row shows "Checking…" and polls; ~30 s give-up, result still lands for staff. Unreadable file → "couldn't read", no block.
15. New child object "Document AI Review" per file per run (type, confidence, issues, pages, date range, name match, model, cost, final human decision).
16. New "AI Check Rules" plain-English field on Lead_Document_Request_Reference__c (75 presets); custom requests = classify + readability only.
17. AI badge + issues + "flagged first" sort in pendingReviewUtility (tray + mobile) and documentViewer. Dry-run the Pending Review backlog (549 files on 2026-10-20) staff-only before go-live.
18. Spanish feedback for Spanish Communications borrowers (same call writes both).

## Open questions (round asked 2026-10-20, unanswered)
- Q19 Judge per condition (all unsubmitted files on the request together, cap ~10 files/20 pages) vs per file. Rec: per condition.
- Q20 Model: Sonnet 5.5 (rec) vs Haiku 5.5; model name in custom metadata.
- Q21 Anthropic org account in company name, ZDR in writing + DPA, single Salesforce-only key in admin-only External Credential; second console admin (an owner).
- Q22 Review record master-detail to Lead_Document_Request__c (inherits access), never guest-visible; no document text / raw AI output in logs.
- Q23 Prompt-injection posture: structured output only, no approve ability, re-file rule is the only action, borrower messages length-capped plain text.
- Q24 Rollout gates: backlog dry run → staff badges → borrower feedback at ≥95% type accuracy + owner sample read → auto re-file per type at ≥98% over ≥30 files. Custom-metadata switches double as kill switch.
- Q25 Phase B: Transaction portal upload (lightning-file-upload, broken for guests) — fix after ~1 month of phase 1 data.

## Facts gathered (2026-10-20)
- Lead portal: VF LeadBorrowerDocumentPortal + LWC leadBorrowerPortalDocuments; Apex LeadDocumentPortalController/Service (preapproval-conditions/). Upload inserts ContentVersion with Lead_Document_Request__c, Portal_Upload_Pending__c; submit links to Lead + sets Pending Review. 3.5 MB Apex cap.
- Files owned by integration user → AI writer must run without sharing or write to its own record.
- 90 days: 632 files, 80% PDF (avg 247 KB), rest jpg/png, 2 heic. Income 342 / Asset 194 / Credit 71 / Other 25.
- Existing AI: ChatGPTService (gpt-4.1-mini, key in custom setting); NonUwmOpenAIGateway (PDF → callout:OpenAI, Named Credential missing in prod).
- Unused licences: Einstein Prompt Templates, Agentforce (4), Data Cloud. No Shield.
