# External Loan Officer: Apex / Visualforce access inventory

Read-only research against prod (`Production`), 2026-09-30. Source retrieved to a scratch project; nothing was deployed or changed.

## 0. Read this first: sharing on these objects is wide open

Before the Apex findings: several objects these pages show are **Public Read/Write** at the org-wide default. For an internal user such as an External LO, a `with sharing` class does not protect these objects, and a `without sharing` class does not add any access on top.

| Object | Internal OWD | What an External LO sees today with no Apex at all |
|---|---|---|
| Call_Insight__c | **Public Read/Write** | Every call/Zoom transcript, summary and AI score in the org |
| Zoom_Meeting__c / Zoom_Recording__c | **Public Read/Write** | Every meeting, join URL, recording play URL + passcode |
| Enhanced_Note__c | **Public Read/Write** | Every loan note |
| Lead_Document_Request__c | **Public Read/Write** | Every pre-approval document request |
| Checklist__c, Appraisal_Order__c | **Public Read/Write** | Every checklist / appraisal order |
| Lead, Account, Transaction__c | Private | Only owned/shared records (good) |
| Condition__c, Condition_Comment__c | Controlled by Parent (Transaction) | Follows Transaction (good) |

Fix: add **Restriction Rules** on those six objects scoped to the External Loan Officer role or profile, for example "records whose Lead__c / Transaction__c / Account__c owner or Loan_Officer__c = $User.Id". This leaves internal users alone. Changing the OWDs would also work but affects everyone. The Apex fixes below only matter once this is done.

## 1. Which record pages Loan Officer Profile users get

Only the Person Account page is assigned per profile. Lead and Transaction use the org default, and no app overrides them for this profile.

| Object | Desktop | Phone (Reach Mobile LO / SF mobile) | Where the assignment comes from |
|---|---|---|---|
| Lead | `Lead_Expandable_Record_Page` | `Lead_Record_Page` | Lead object org default (Large / Small) |
| Transaction__c | `Transaction_Expandable_Record_Page` | same page | Transaction__c org default (both form factors) |
| Person Account (RT PersonAccount) | `Person_Account_Record_Page` | standard default (no custom page) | profileActionOverride in `standard__LightningSales` (the LO default app), `Reach_Home_Loans_Lightning` and `Reach_Home_Loans_CEO` |
| Reach Mobile LO app tabs | `LO_Mobile_Dashboard`, `LO_Mobile_Pre_Approved_Leads`, `LO_Mobile_Active_Transactions`, `LO_Mobile_Closed_Transactions`, `LO_Mobile_Doc_Review` | | App page tabs |

Page layouts assigned to the profile: `Lead-Consumer Lead Layout`, `Transaction__c-Transaction Layout`, `PersonAccount-Person Account Layout`. Their highlight-panel actions show only where the FlexiPage has a highlights panel: the Lead phone page and the Transaction page. The Lead desktop page uses `leadRecordHero` and `leadQuickActions` in its place.

No component on these pages has a profile or permission visibility filter. **`transactionDocuSign` will render for External LOs** and error without its class. Give it a `$Permission` visibility rule tied to DocuSign_Transaction_Access.

### Components per page (custom only, children included)

| Page | Custom components |
|---|---|
| Lead desktop | leadRecordHero, leadQuickActions, leadActivityAssistant, borrowerPanel, callInsightList (x2), documentViewer → documentThumbnailDatatable, leadDocumentRequestManager, zoomMeetingAssistant, homeToolsDrawer → homeToolsSidebar, smsAutomationOptOutPill, EnhancedNotes (Aura) → NoteRow → ReInitEvent, TwilioSF:TwoWayMessages (managed), flow `Lead_Related_Scheduled_Messages` |
| Lead phone | same minus hero/quick actions/activity assistant/Twilio; plus highlights panel (layout actions) |
| Transaction | transactionQuickActions, borrowerPanel, callInsightList, documentViewer, fileUploader, homeToolsDrawer, EnhancedNotes, **transactionDocuSign (exclude)**, Aura: ConditionsViewer (x2) → ConditionRow, ConditionsDocumentViewer, ConditionsEmailModal, ConditionsInit, ConditionRowEvent, RefreshEvent, actionButton → lucideIcons, messageNotification, formattedField, conditionComments → chat → chatAction, heroIcon, enhancedSwitcher, consoleLogger; AppraisalOrder, Checklist (x2), SubmissionQualityChecklist, ActionRequired, CloserActionRequired, PostClosingActionRequired, LendwizeIframe, richTextMessage; flows `Assign_the_form_to_the_recipient`, `Transaction_Templated_Messages` |
| Person Account | accountRecordHero, accountActivityAssistant → leadActivityAssistant, callInsightList (x2), zoomMeetingAssistant, homeToolsDrawer, smsAutomationOptOutPill, EnhancedNotes, TwilioSF:TwoWayMessages, flow `Account_Related_Scheduled_Messages` |
| Reach Mobile LO | loanOfficerLeads, loanOfficerTransactions, pendingReviewUtility |

### Actions launched from those pages that pull in more components

| Action (launched from) | Target | Components / Apex it brings in |
|---|---|---|
| Lead.Pre_Approval_Letter (leadQuickActions, Lead layout) | flow `Pre_Approval_Screen_Flow` | screen LWC `leadPreApprovalLetter` → LeadPreApprovalLetterController; VF `Lead_Pre_Approval_Letter` |
| Lead.Leads_Notes_Form (Application Summary) | Aura `LeadNotesForm` | LeadNotesFormController |
| Lead.Manual_lead_convert | flow `Convert_Lead` (runs SystemModeWithoutSharing) | invocable ConvertLeadsInvocable |
| Lead.Realtor_Convert (Realtor RT only) | LWC `realtorLeadConvertAction` | RealtorLeadConvertController |
| Lead.Document_Requests | LWC `leadDocumentRequestsQuickAction` → leadDocumentRequestManager | as below |
| leadDocumentRequestManager "create" | flow `Lead_Document_Requests_Creator` | screen LWCs leadConditionBorrowerPicker (LeadDocumentRequestService), leadPresetConditionSelector (LeadPresetConditionSelectorController), leadConditionChoiceCards, leadInitialBundleDetailsCards, leadManualConditionEntry; invocables LeadDocRequestCreateInvocable, LeadDocumentRequestReferenceInvocable |
| Transaction.Submission_Form_Modern (transactionQuickActions) | LWC `transactionSubmissionFormAction` → flow `Loan_Origination_Submission_Form` | **no Apex imports**; flow calls invocable DpaSecondTransactionInvocable; no custom screen components |
| Transaction.Wire_Calculator | Aura `WireCalculator` | LoanController; VF `Wire_Calculator_PDF` |
| Transaction.Application_Template | Aura `TransactionNotesForm` | TransactionNotesFormController |
| Transaction.Create_Title_Agent | Aura `createTitleAgentAction` | **PipelineCommandCenterController** (see risk table) |
| Transaction.Order_Appraisal_Direct | Aura `ValueLinkOrderAction` | ValueLinkController |
| Transaction.Clone_Transaction (layout) | Aura `CloneTransaction` | TransactionController |
| Transaction.Closing_Portal | flow `Share_Documents` | Aura `ShareBorrowerDocument` → ShareBorrowerDocumentController |
| Transaction.Commitment_Letter | flow `Commitment_Letter` | `inputRichTextFSC` (unlocked package, no namespace) |
| Transaction.Update_Data_From_UWM | flow `UWM_Loan_Info` | invocables UWM_Conditions_Invocable, UWM_Insights_Invocable |
| Transaction.Fetch_ValueLink_Reports | flow | invocable ValueLinkDataFetchQueueable |
| Change_of_Circumstances, Back_Under_Contract, Revert_To_Closing, Create_DPA_Second, Cancel_Loan, etc. | flows / update actions | no custom components |

Many of the Transaction actions are processor/closer tools (ValueLink, Title Agent, Closing Portal, Revert to Closing, MERS). Cut the ones External LOs should not run from the button bar, which reads the profile name, before granting their classes.

## 2. Apex allow-list

Only the `@AuraEnabled` entry class needs class access. Classes it calls internally do not. Service classes that appear as inner types in a method signature are listed separately. Nimbus already grants them in existing permsets, so grant them too to be safe, then confirm with a test user.

**Flows:** invocable actions called from a screen or autolaunched flow do not need Apex class access. The invocables listed above are for reference only. A flow's **screen components** do need their controller classes, and those are included in the table below.

| Apex class | Needed by | Already in a non-"All" permset Zachary holds |
|---|---|---|
| LeadActivityAssistantController | leadActivityAssistant, accountActivityAssistant | no (All_Apex_Classes only) |
| BorrowerPersonAccountService | borrowerPanel | Borrower_Management |
| CallInsightListController | callInsightList (Lead, Transaction, Account) | no |
| DocumentViewerController | documentViewer, leadDocumentRequestManager, pendingReviewUtility | UWMPermissions, Condition_Files_Permissions, Lead_Document_Collection_Access |
| FileUploaderController | documentViewer, fileUploader | same three |
| LeadDocumentRequestController | leadDocumentRequestManager, pendingReviewUtility | Lead_Document_Collection_Access |
| LeadDocumentRequestService | leadDocumentRequestManager, leadConditionBorrowerPicker (+ type carrier) | Lead_Document_Collection_Access |
| LeadPresetConditionSelectorController | leadPresetConditionSelector (flow screen) | Lead_Document_Collection_Access |
| LeadPreApprovalLetterController | leadPreApprovalLetter (flow screen) | Lead_Document_Collection_Access |
| ZoomMeetingController | zoomMeetingAssistant | Zoom_Meeting_Assistant_Access |
| HomeToolsController | homeToolsDrawer, homeToolsSidebar | **only Pipeline_Command_Center_Pilot_Access**, which External LOs will not get, so add it explicitly |
| EnhancedNotesController | EnhancedNotes, NoteRow | Enhances_Notes |
| AccountRecordHeroController | accountRecordHero | no |
| LeadNotesFormController | LeadNotesForm (Application Summary) | Application_Summary_Access |
| LOMobileTransactionsController | loanOfficerLeads, loanOfficerTransactions | Reach_Mobile_LO |
| ConditionCommentController | pendingReviewUtility | UWMPermissions, Condition_Files_Permissions |
| ConditionReviewQueueController | pendingReviewUtility | Condition_Files_Permissions, Lead_Document_Collection_Access |
| LoanConditionController | pendingReviewUtility, ConditionsViewer, ConditionRow, ConditionsEmailModal | UWMPermissions, Condition_Files_Permissions |
| DocumentController | ConditionsDocumentViewer | UWMPermissions, Condition_Files_Permissions |
| BorrowerDocumentPortalController | conditionComments (only `markProcessorCommentUnreadForBorrower`) | no |
| AppraisalOrderController | AppraisalOrder | no |
| ChecklistController | Checklist | no |
| SubmissionQualityChecklistController | SubmissionQualityChecklist | no |
| RealtorLeadConvertController | realtorLeadConvertAction (only if they convert Realtor leads) | no |
| LoanController | WireCalculator (only if Wire Calculator kept) | no |
| TransactionNotesFormController | TransactionNotesForm (only if Application Template kept) | no |
| TransactionController | CloneTransaction (only if Clone kept) | no |
| ValueLinkController | ValueLinkOrderAction (only if Order Appraisal Direct kept) | no |
| ShareBorrowerDocumentController | ShareBorrowerDocument / Closing Portal (only if kept) | no |
| PipelineCommandCenterController | createTitleAgentAction (only if Create Title Agent kept) | Pipeline_Command_Center_Pilot_Access |

Type carriers (inner classes of these appear in `@AuraEnabled` signatures): LeadDocumentRequestService, ConditionCommentService, ConditionReviewQueueService, TransactionCondition, LoanCondition, NCS_Checklist, BPSVerificationService, RealtorLeadConvertService.

**Excluded on purpose:** TransactionDocuSignController (DocuSign) and the Pipeline Command Center LWC's controller. PipelineCommandCenterController comes back only if Create Title Agent is kept.

No-Apex components: leadRecordHero, leadQuickActions, transactionQuickActions, transactionSubmissionFormAction, smsAutomationOptOutPill, documentThumbnailDatatable, the leadCondition* screen cards other than the two above, ActionRequired, CloserActionRequired, PostClosingActionRequired, LendwizeIframe, richTextMessage, and the chat, heroIcon and lucideIcons family.

## 3. Visualforce allow-list

| VF page | Opened by | Notes |
|---|---|---|
| Lead_Pre_Approval_Letter | LeadPreApprovalLetterController (`getContentAsPDF`, and `pdfPath` `/apex/Lead_Pre_Approval_Letter?id=` returned to the LWC) | standardController Lead + extension LeadPreApprovalLetterPdfExtension. Granted today by Lead_Document_Collection_Access |
| AddNewNote | EnhancedNotes / NoteRow `window.open('/apex/AddNewNote…')` | no controller |
| Wire_Calculator_PDF | LoanController `getContentAsPDF` (Wire Calculator action) | only if kept. Granted by Wire_Calculator_PDF_Access |

Not needed: `LeadBorrowerDocumentPortal` (a borrower portal link built in LeadDocumentRequestService, served by the guest site) and the RingCentral `rcsfl__Phone_Numbers_*` pages (their quick actions are not on the assigned layouts).

## 4. Sharing risk table

How to read it:
- Entry classes with **no sharing keyword** run as `without sharing` when Aura/LWC calls them. This is the default unless the "with sharing for @AuraEnabled implicit sharing" release update is enforced, which does not appear to be the case here.
- `AccessLevel.SYSTEM_MODE` / `WITH SYSTEM_MODE` waive CRUD/FLS only. Sharing still follows the class keyword, so `with sharing` + SYSTEM_MODE is fine for record access.
- Because Lead, Account and Transaction are Private, a with-sharing query or update on them already blocks other users' records.
- Granting a class exposes **every** `@AuraEnabled` method in it, not just the one the component calls.

### High: lets a user read or change records they cannot see

| Class | Sharing | Evidence | What an External LO could do | Fix |
|---|---|---|---|---|
| CallInsightListController | without | `CallInsightListController.cls:1`; `getCallInsights(recordId)` :10 filters only on the passed Id (:13-19, query :25); `getZoomRecordings(zoomMeetingIds)` :47-59 takes any meeting Ids | Read transcripts/summaries for any Lead/Account/Transaction Id, and recording play URLs + passcodes for any meeting (moot until the OWD is fixed, see §0) | Change to `with sharing`, and after the §0 restriction rule, add `WITH USER_MODE` |
| DocumentViewerController | without | `:1`; `applyUploadDetails(contentVersionIds…)` :236 queries arbitrary ContentVersion Ids `WITH SYSTEM_MODE` :241-246 and updates them :262; `relateFileToCondition` :414 → `FileUploadHandler.updateContentVersions/setLoanConditionToReview` :447-448 (FileUploadHandler is `without sharing`) | Rename or re-folder any file in the org by ContentVersion Id. Flip any Condition__c to Review and stamp files onto it. Rename, move, re-folder or upload a new version of files they can only *read* (reads are USER_MODE-gated at :97-140, writes are SYSTEM_MODE in a without-sharing class: :79, :194, :222, :292, :355) | Change to `with sharing`. In applyUploadDetails, first requery the Ids through `retrieveContentDocs` (USER_MODE). Check `UserRecordAccess.HasEditAccess` on the parent record before any write |
| LoanConditionController → FileUploadHandler | with (controller) / **without** (handler) | `LoanConditionController.cls:598` `contentVersionUpdate(conditionId, contentVersionIds)` → `FileUploadHandler.cls:23-48` inserts ContentDocumentLinks in SYSTEM_MODE for arbitrary ContentVersion Ids | Link **any file in the org** to a condition they can see, and so read it. Real read escalation, used by Aura ConditionRow | In `associateContentVersions`, keep only versions the user can already see (requery in USER_MODE), or run it from a with-sharing class |
| ConditionReviewQueueController / DocumentController → ConditionReviewService | with / **without** | `ConditionReviewService.cls:11` without sharing; `rejectCondition` :22 updates any Condition__c; `approveDocument` :57 sets Status Approved via SYSTEM_MODE. Called straight through with client Ids from `ConditionReviewQueueController.cls:131-230` and `DocumentController.cls:14-40` | Approve or reject conditions and documents on any Transaction by Id, trigger the borrower rejection email, and move or unlink documents | Add an access guard at the top of each public ConditionReviewService method (`UserRecordAccess` on the condition's Transaction__c, or a with-sharing requery of the Condition__c) |
| TransactionController | none | `:1`; `clone(model, recordId)` :4 builds SOQL by **string concatenation** (injection), queries without sharing :6, clones :8-9, updates :23 and Leads :39 | Clone any Transaction, which creates a copy they own and so a full read of someone else's loan, and repoint Leads | Change to `with sharing`, bind the Id (`WHERE Id = :recordId`), and only keep it if External LOs need Clone |
| AccountRecordHeroController | without | `:1`; `createPastClientLead(accountId)` :10 queries any Account :18-27 and inserts a Lead copying name/email/phone/UTMs :36-61 | Pull contact details of any Person Account into a Lead they own | Change to `with sharing`. The Account query then blocks accounts they cannot see |
| LeadNotesFormController | none | `:1`; `getApplicationSummary(recordId)` :65 and `getNotes` :203 read any Lead; `saveApplicationSummary` :132/:153, `saveNotes` :212-215 update any Lead | Read or overwrite Application Summary and notes on any Lead by Id | Declare `with sharing` |
| TransactionNotesFormController | none | `getApplicationSummary` :85, `getNotes` :162, `saveNotes` :171-174 | Same as above, for any Transaction | `with sharing` (or drop Application Template for External LOs) |
| SubmissionQualityChecklistController | none | `getExistingChecklist` :9 (dynamic query :26-29), `saveChecklistAnswers` :49 inserts/updates Checklist__c :61/:81 and updates Transaction__c :92 | Read or write the quality checklist and stamp counts on any Transaction | `with sharing` |
| ShareBorrowerDocumentController | none | `getRenderedHtmlTemplate(templateId, recordId)` :3 renders merge fields for any Transaction :12-14; `sendEmail` :30 queries any Transaction :35 and emails **arbitrary** To/CC addresses :37-44 | Render borrower data from any loan into an email and send it anywhere | `with sharing`, and restrict recipients to the transaction's contacts. Better: remove Closing Portal from External LOs |
| PipelineCommandCenterController | with (inner without) | 10,098 lines, **210 `@AuraEnabled` methods**; inner `without sharing class OpenCocRequestSelector` :3405. Needed only for `createTitleAgentAccount` | Granting it for one action opens the whole PCC API surface, including open-COC Case counts org-wide | Move `createTitleAgentAccount` into a small `with sharing` class, or drop Create Title Agent for External LOs |

### Medium

| Class | Sharing | Evidence | Risk | Fix |
|---|---|---|---|---|
| BorrowerDocumentPortalController | with (inner without) | Component uses only `markProcessorCommentUnreadForBorrower` :174 (→ BorrowerPortalService inner without-sharing writer). Granting the class also exposes `updateLoanConditionOnFileUpload(contentVersionIds, conditionId)` :150 → `PortalUploadWriter` **without sharing** :193 → FileUploadHandler | Same "link any file to any condition" hole as FileUploadHandler, but without even needing to see the condition | Move `markProcessorCommentUnreadForBorrower` into ConditionCommentController and do not grant this class to internal users |
| LeadDocumentRequestService | with (inner without) | `handleInternalFileUpload(requestId, contentVersionIds)` :567 only requires the request to be visible (and Lead_Document_Request__c is Public R/W). Arbitrary `contentVersionIds` go to `BorrowerFileWriter` (**without sharing**, :1829) via `updateContentVersions` :1760-1776 | Re-folder any ContentVersion and tag it to a request. Approve/reject/not-needed are guarded by `ensureCanActOnRequest` :1358 (Owner / Loan Partner / Modify All) | Call `ensureCanActOnRequest` in handleInternalFileUpload, and filter contentVersionIds to files the user can see |
| ChecklistController → NCS_Checklist | none / none | `ChecklistController.cls:5`, `getChecklist(recordId, configurationId…)` :18 → `NCS_Checklist.cls:1` (no keyword, so it inherits without sharing), dynamic queries :53, :82 | Read the configured checklist date fields of any record | `with sharing` on ChecklistController |
| ValueLinkController | none | `getOrderActionModel(recordId)` :63 queries any Transaction; `saveSelectedAppraisalType` :169 updates any Transaction; `createDTORequest` :51 is gated by LoanRepository (with sharing) | Read processor names / FHA case number on any loan, and set the appraisal type | `with sharing` (or drop the action) |

### Low / acceptable

| Class | Sharing | Note |
|---|---|---|
| LoanController | without | `generateWireCalculator` :9 goes through `LoanRepository` (**with sharing**), so an invisible Id throws before the PDF/Attachment insert :18-25. Declare `with sharing` anyway. |
| AppraisalOrderController | none | Every method starts from `LoanRepository.getLoanById` (with sharing) :85, :244, so it is gated. Declare `with sharing`. |
| LoanConditionController `sendConditionsEmail` | with | :181 → InitialItemsNeededSmsService (without sharing) with a client recordId. Worst case is an SMS enqueue on another loan. |
| ZoomMeetingController | with | Reads are sharing-gated (:77, :111, :519, :536). But Zoom_Meeting__c is Public R/W, so `getFreshStartUrl` :518 hands a **host start URL** for any meeting. §0 fixes it. |
| LeadPreApprovalLetterController | with | SYSTEM_MODE DML/SOQL (:123, :166, :174, :362) still honors sharing because the class is with sharing, and Lead is Private. OK. |
| BorrowerPersonAccountService, HomeToolsController, LOMobileTransactionsController, LeadActivityAssistantController, LeadDocumentRequestController, LeadPresetConditionSelectorController, FileUploaderController, ConditionCommentController, EnhancedNotesController, RealtorLeadConvertController | with | No without-sharing helpers on the paths these components use. EnhancedNotesController is fine in Apex but Enhanced_Note__c is Public R/W (§0). |

## 5. Permission set classification (Zachary Fritz's set)

| Permission set | Kind | Can go in a PSG? | Notes |
|---|---|---|---|
| Twilio_User | Managed (TwilioSF) | Yes, but each user needs a **TwilioSF package seat** | **19 of 20 seats used.** Only one External LO can get Twilio without buying seats |
| ActiveCampaign_Standard_User | Managed (ActiveCamp) | Package license is **Disabled** | Dead. Do not assign |
| StandardEinsteinActivityCapturePsl | **Permission Set License**, not a permset | No (assigned separately) | 22 of 100 used |
| All_Apex_Classes, All_Visualforce_Pages | Plain | Yes | **Do not assign.** Replace with the allow-list above |
| DocuSign_Transaction_Access, Pipeline_Command_Center_Pilot_Access | Plain | Yes | Excluded by design. HomeToolsController must then be granted directly |
| Multi_Factor_Authentication_MFA, Enhances_Notes, Wire_Calculator_PDF_Access, ConditionPermissions, UWMPermissions, UserActionsPermissions, Condition_Files_Permissions, Realtor_Referral_Source_Access, Lead_Document_Collection_Access, Borrower_Rating_Access, Property_Sold_Access, Zoom_Meeting_Assistant_Access, Zoom_OAuth_Connection_Access, Application_Summary_Fields, Application_Summary_Access, Reach_Mobile_LO, Lead_Team_Access, Zoom_Meeting_Sync_Access, Borrower_Management | Plain custom, no license | Yes | Zoom OAuth needs both Zoom permsets plus UserExternalCredential CRUD (known). UWMPermissions grants ~50 classes including test classes and UWM API internals; for External LOs, use a trimmed permset in its place |

## 6. Suggested build

1. Restriction rules on the six Public R/W objects (§0), scoped to External LO.
2. One new permset, `External_LO_Apex_Access`, holding the Apex classes in §2 (skipping the optional ones you drop), the type carriers, and the 2–3 VF pages in §3.
3. Fix the High rows before go-live. The one-word `with sharing` changes cover eight of them. FileUploadHandler, ConditionReviewService and DocumentViewerController need real guards.
4. Give `transactionDocuSign` a `$Permission` visibility rule. Trim transactionQuickActions/leadQuickActions for the External LO profile name.
