/**
 * Send with DocuSign from a Transaction, through the DocuSign Apps Launcher (dfsle) Apex Toolkit.
 * The sender picks a DocuSign template (TEMPLATE_IDS) and/or files on the Transaction; borrower, co-borrower (Person Account __pc fields)
 * and optionally the assigned LO (Loan_Officer__c, never OwnerId) are added as signers. The envelope
 * is created as a draft and opened in DocuSign's sender view, where the sender places the tabs.
 * The signed PDF is written back to the Transaction's Files on completion.
 */
public with sharing class TransactionDocuSignController {

    private static final Set<String> SENDER_PERMSETS = new Set<String>{ 'DocuSign_User', 'DocuSign_Administrator', 'DocuSign_Sender' };

    // DocuSign template name -> template ID. Their roles must be named exactly 'Borrower' and 'Co-Borrower'.
    // ponytail: hardcoded; a new template needs a deploy. Move to custom metadata if they start changing often.
    @TestVisible
    private static final Map<String, String> TEMPLATE_IDS = new Map<String, String>{
        'Address LOX' => '4169ccb1-79d8-4078-9552-bd20af9b32af',
        'Credit Inquiry LOX' => '8a55e4e2-495d-469e-aed0-886635bcfa0d',
        'No HOA LOX' => 'f002fae7-9bab-4f2a-96d4-83f9e3ff762d'
    };

    public class FileOption {
        @AuraEnabled public Id versionId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public Datetime modified;
    }

    // File types DocuSign can turn into a signable document; notes (.snote), xml etc. are hidden.
    private static final Set<String> SIGNABLE = new Set<String>{ 'pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'tif', 'tiff', 'xls', 'xlsx', 'txt', 'rtf' };

    public class Signer {
        @AuraEnabled public String role;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    public class Envelope {
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String sender;
        @AuraEnabled public Datetime sent;
        @AuraEnabled public Datetime completed;
    }

    public class Data {
        @AuraEnabled public Boolean canSend = false;
        @AuraEnabled public List<String> templates = new List<String>(TEMPLATE_IDS.keySet());
        @AuraEnabled public List<FileOption> files = new List<FileOption>();
        @AuraEnabled public Signer borrower;
        @AuraEnabled public Signer coBorrower;
        @AuraEnabled public Signer loanOfficer;
        @AuraEnabled public List<Envelope> envelopes = new List<Envelope>();
    }

    @AuraEnabled
    public static Data getData(Id transactionId) {
        Data d = new Data();
        d.envelopes = new StatusReader().envelopes(transactionId);
        d.canSend = ![
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.NamespacePrefix = 'dfsle' AND PermissionSet.Name IN :SENDER_PERMSETS
            LIMIT 1
        ].isEmpty();
        if (!d.canSend) {
            return d;
        }

        for (ContentDocumentLink l : [
            SELECT ContentDocument.LatestPublishedVersionId, ContentDocument.Title, ContentDocument.FileExtension,
                   ContentDocument.LastModifiedDate
            FROM ContentDocumentLink WHERE LinkedEntityId = :transactionId
            ORDER BY ContentDocument.LastModifiedDate DESC
        ]) {
            String ext = (l.ContentDocument.FileExtension ?? '').toLowerCase();
            if (!SIGNABLE.contains(ext)) {
                continue;
            }
            FileOption f = new FileOption();
            f.versionId = l.ContentDocument.LatestPublishedVersionId;
            // Titles often already carry the extension ("x.pdf"); don't double it.
            String title = l.ContentDocument.Title;
            f.title = title.toLowerCase().endsWith('.' + ext) ? title : title + '.' + ext;
            f.extension = ext;
            f.modified = l.ContentDocument.LastModifiedDate;
            d.files.add(f);
        }

        Transaction__c t = loadTransaction(transactionId);
        Account b = t.Borrower_Name__r;
        if (b != null) {
            d.borrower = signer('Borrower', b.Name, b.PersonEmail);
            String coName = ((b.First_Name_Co_Borrower__pc ?? '') + ' ' + (b.Last_Name_Co_Borrower__pc ?? '')).trim();
            if (String.isNotBlank(coName) || String.isNotBlank(b.Email_Co_Borrower__pc)) {
                d.coBorrower = signer('Co-Borrower', coName, b.Email_Co_Borrower__pc);
            }
        }
        if (t.Loan_Officer__r != null) {
            d.loanOfficer = signer('Loan Officer', t.Loan_Officer__r.Name, t.Loan_Officer__r.Email);
        }
        return d;
    }

    /** Creates the draft envelope and returns its dfsle__Envelope__c record Id. */
    @AuraEnabled
    public static String createDraft(Id transactionId, List<String> templateNames, List<Id> versionIds, Boolean includeCoBorrower, Boolean includeLoanOfficer) {
        templateNames = templateNames ?? new List<String>();
        versionIds = versionIds ?? new List<Id>();
        for (String name : templateNames) {
            if (!TEMPLATE_IDS.containsKey(name)) {
                throw error('Unknown template: ' + name);
            }
        }
        if (templateNames.isEmpty() && versionIds.isEmpty()) {
            throw error('Pick a template or at least one file to send.');
        }
        Data d = getData(transactionId);
        if (!d.canSend) {
            throw error('You are not set up as a DocuSign sender.');
        }
        if (d.borrower == null || String.isBlank(d.borrower.email)) {
            throw error('The borrower has no email address on their account.');
        }

        List<Signer> signers = new List<Signer>{ d.borrower };
        if (includeCoBorrower == true && d.coBorrower != null) {
            if (String.isBlank(d.coBorrower.email)) {
                throw error('The co-borrower has no email address. Add it on the borrower account, or untick the co-borrower.');
            }
            signers.add(d.coBorrower);
        }
        if (includeLoanOfficer == true && d.loanOfficer != null) {
            signers.add(d.loanOfficer);
        }

        Transaction__c t = loadTransaction(transactionId);
        dfsle.Envelope env = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(transactionId));
        List<dfsle.Recipient> recipients = new List<dfsle.Recipient>();
        for (Signer s : signers) {
            recipients.add(dfsle.Recipient.fromSource(s.name, s.email, null, s.role,
                new dfsle.Entity(s.role == 'Loan Officer' ? t.Loan_Officer__c : t.Borrower_Name__c)));
        }
        // Template roles are filled by matching recipient role names; unmatched template roles are dropped.
        List<dfsle.Document> docs = new List<dfsle.Document>();
        for (String name : templateNames) {
            docs.add(dfsle.Document.fromTemplate(dfsle.UUID.parse(TEMPLATE_IDS.get(name)), name));
        }
        if (!versionIds.isEmpty()) {
            docs.addAll(dfsle.DocumentService.getDocuments(ContentVersion.getSObjectType(), new Set<Id>(versionIds)));
        }
        env = env
            .withRecipients(recipients)
            .withDocuments(docs)
            // DocuSign caps the subject at 100 characters.
            .withEmail(('Reach Home Loans: ' + (templateNames.isEmpty() ? 'documents for your signature' : String.join(templateNames, ', '))).abbreviate(100),
                'Please review and sign the attached documents.')
            // Remind at 2 days then every 2 days; expire at 14 days, warn 2 days before.
            .withNotifications(new dfsle.Notifications(true, 2, 2, true, 14, 2, false))
            .withOptions(new dfsle.Envelope.Options(
                false,
                new dfsle.Document.WriteBack(transactionId, dfsle.Document.WRITE_BACK_ENVELOPE_STATUS_PDF, true, false),
                new Map<String, Map<String, Object>>(),
                new Map<String, Map<String, Object>>()));

        // sendEnvelope saves the package's envelope records, so the sender-view callout must run in a
        // separate transaction (getSenderView) or Salesforce throws "uncommitted work pending".
        return dfsle.EnvelopeService.sendEnvelope(env, false).id;
    }

    /** DocuSign's sender-view URL for a draft created by createDraft (envelopeId = dfsle__Envelope__c Id). */
    @AuraEnabled
    public static String getSenderView(Id transactionId, Id envelopeId) {
        dfsle__Envelope__c e = [SELECT dfsle__DocuSignId__c FROM dfsle__Envelope__c WHERE Id = :envelopeId];
        Url back = new Url(Url.getOrgDomainUrl().toExternalForm() + '/' + transactionId);
        return dfsle.EnvelopeService.getSenderViewUrl(dfsle.UUID.parse(e.dfsle__DocuSignId__c), back).toExternalForm();
    }

    private static Transaction__c loadTransaction(Id transactionId) {
        return [
            SELECT Borrower_Name__c, Borrower_Name__r.Name, Borrower_Name__r.PersonEmail,
                   Borrower_Name__r.First_Name_Co_Borrower__pc, Borrower_Name__r.Last_Name_Co_Borrower__pc,
                   Borrower_Name__r.Email_Co_Borrower__pc,
                   Loan_Officer__c, Loan_Officer__r.Name, Loan_Officer__r.Email
            FROM Transaction__c WHERE Id = :transactionId
        ];
    }

    private static Signer signer(String role, String name, String email) {
        Signer s = new Signer();
        s.role = role;
        s.name = name;
        s.email = email;
        return s;
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    // Anyone who can open the Transaction may see its envelope history, whoever sent it.
    private without sharing class StatusReader {
        List<Envelope> envelopes(Id transactionId) {
            List<Envelope> out = new List<Envelope>();
            String id18 = String.valueOf(transactionId);
            for (dfsle__EnvelopeStatus__c s : [
                SELECT dfsle__EmailSubject__c, dfsle__Status__c, dfsle__SenderName__c, dfsle__Sent__c, dfsle__Completed__c
                FROM dfsle__EnvelopeStatus__c
                WHERE dfsle__SourceId__c IN (:id18, :id18.left(15))
                ORDER BY CreatedDate DESC LIMIT 50
            ]) {
                Envelope e = new Envelope();
                e.subject = s.dfsle__EmailSubject__c;
                e.status = s.dfsle__Status__c;
                e.sender = s.dfsle__SenderName__c;
                e.sent = s.dfsle__Sent__c;
                e.completed = s.dfsle__Completed__c;
                out.add(e);
            }
            return out;
        }
    }
}
