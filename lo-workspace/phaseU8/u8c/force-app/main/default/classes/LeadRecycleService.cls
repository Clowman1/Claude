/**
 * U8 (decided 2026-10-08): a purchase loan the borrower walked away from goes back to the LO as a
 * pre-approval lead, cloned from the borrower's original (converted) lead.
 *
 * Fires when Transaction__c.Status__c is Cancelled and the borrower reason qualifies (checked on the
 * status change and on a later reason edit, so the order the processor fills them in doesn't matter):
 * - Loan_Purpose__c = Purchase, not a DPA 2nd
 * - Borrower_Withdrawal_Reason__c set and not a lender switch (EXCLUDED_REASONS)
 * - Withdrawn_Reason__c not a denial
 * - Loan_Officer__c is an active standard user (otherwise nothing happens: go-live forward only)
 * - no lead was recycled from this loan yet (idempotent)
 *
 * The clone keeps every field except the ones that would re-run intake (BLANKED), keeps AriveId__c
 * and the original Pre_Approval_Date__c, and is owned by the loan's LO. It is written with
 * LeadRecycleContext.silent = true and Recycled_From_Transaction__c set, which the U8b guards on
 * flows, the Process Builder, triggers and Zaps use to stay quiet. The LO gets one bell notification.
 *
 * When a recycled loan is un-cancelled, its open recycled lead moves to Nurturing, stamped
 * Recycle_Reactivated_At__c (the flows' silent marker), with a note.
 */
public without sharing class LeadRecycleService implements Queueable {
    @TestVisible
    private static final Set<String> EXCLUDED_REASONS = new Set<String>{
        'Selected an Alternative Lender',
        'Found a More Competetive Interest Rate'
    };
    private static final Set<String> DENIALS = new Set<String>{ 'App Denied', 'Pre-Approval Denied' };
    private static final Set<String> CLOSED_OUT = new Set<String>{ 'Cancelled', 'Lost' };
    private static final String NOTIFICATION_TYPE = 'Lead_Recycled';

    // Never copied: they re-run intake, conversion, appointment or portal automation, or are identity/system fields.
    @TestVisible
    private static final Set<String> BLANKED = new Set<String>{
        'id', 'ownerid', 'status', 'isconverted', 'converteddate', 'convertedaccountid', 'convertedcontactid',
        'convertedopportunityid', 'isunreadbyowner', 'arive_status__c', 'converted_transaction_id__c',
        'referralformsourceemail__c', 'appointment_date_time__c', 'initial_docs_requested_date__c',
        'portal_hash_parameter__c', 'follow_up_account__c', 'recycled_from_transaction__c',
        'recycle_reactivated_at__c', 'jigsaw', 'cleanstatus', 'companydunsnumber', 'dandbcompanyid'
    };

    private final Set<Id> loanIds;

    public LeadRecycleService(Set<Id> loanIds) {
        this.loanIds = loanIds;
    }

    // ---------- Trigger entry (Transaction__c after update) ----------

    public static void onTransactionUpdate(List<Transaction__c> loans, Map<Id, Transaction__c> oldMap) {
        Set<Id> toRecycle = new Set<Id>();
        Set<Id> reactivated = new Set<Id>();
        for (Transaction__c t : loans) {
            Transaction__c old = oldMap?.get(t.Id);
            if (old == null) {
                continue;
            }
            if (t.Status__c == 'Cancelled'
                && (old.Status__c != 'Cancelled'
                    || old.Borrower_Withdrawal_Reason__c != t.Borrower_Withdrawal_Reason__c
                    || old.Withdrawn_Reason__c != t.Withdrawn_Reason__c)
                && qualifies(t)) {
                toRecycle.add(t.Id);
            }
            if (old.Status__c == 'Cancelled' && !CLOSED_OUT.contains(t.Status__c)) {
                reactivated.add(t.Id);
            }
        }
        if (!reactivated.isEmpty()) {
            reactivate(reactivated);
        }
        if (toRecycle.isEmpty()) {
            return;
        }
        // Own transaction so a recycle problem can never roll back the processor's cancel.
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new LeadRecycleService(toRecycle));
        } else {
            new LeadRecycleService(toRecycle).run();
        }
    }

    @TestVisible
    private static Boolean qualifies(Transaction__c t) {
        return t.Loan_Purpose__c == 'Purchase'
            && t.Loan_Type_1st_TD__c != 'DPA 2nd'
            && String.isNotBlank(t.Borrower_Withdrawal_Reason__c)
            && !EXCLUDED_REASONS.contains(t.Borrower_Withdrawal_Reason__c)
            && !DENIALS.contains(t.Withdrawn_Reason__c);
    }

    public void execute(QueueableContext context) {
        run();
    }

    // ---------- Recycle ----------

    @TestVisible
    private void run() {
        Map<Id, Transaction__c> loans = new Map<Id, Transaction__c>([
            SELECT Id, Name, Status__c, Loan_Purpose__c, Loan_Type_1st_TD__c, Borrower_Withdrawal_Reason__c,
                   Withdrawn_Reason__c, Loan_Officer__c, Loan_Officer__r.IsActive, Loan_Officer__r.UserType,
                   Borrower_Name__c, Borrower_Name__r.Name, Loan_Amount_1st__c, CreatedDate
            FROM Transaction__c
            WHERE Id IN :loanIds
        ]);
        // Still cancelled and still qualifying when the job runs; never twice.
        for (Lead l : [SELECT Recycled_From_Transaction__c FROM Lead WHERE Recycled_From_Transaction__c IN :loanIds]) {
            loans.remove(l.Recycled_From_Transaction__c);
        }
        for (Id loanId : new List<Id>(loans.keySet())) {
            Transaction__c t = loans.get(loanId);
            if (t.Status__c != 'Cancelled' || !qualifies(t)
                || t.Loan_Officer__c == null || t.Loan_Officer__r.IsActive != true
                || t.Loan_Officer__r.UserType != 'Standard') {
                loans.remove(loanId);
            }
        }
        if (loans.isEmpty()) {
            return;
        }

        Map<Id, Lead> originals = findOriginalLeads(loans.values());
        Map<Id, Lead> clones = new Map<Id, Lead>(); // loan Id -> new lead
        for (Transaction__c t : loans.values()) {
            Lead original = originals.get(t.Id);
            if (original != null) {
                clones.put(t.Id, cloneFor(original, t));
            }
        }
        if (clones.isEmpty()) {
            return;
        }

        Database.DMLOptions options = new Database.DMLOptions();
        options.duplicateRuleHeader.allowSave = true;
        options.assignmentRuleHeader.useDefaultRule = false;
        options.emailHeader.triggerAutoResponseEmail = false;
        options.emailHeader.triggerUserEmail = false;

        List<Id> loanOrder = new List<Id>(clones.keySet());
        List<Lead> toInsert = new List<Lead>();
        for (Id loanId : loanOrder) {
            toInsert.add(clones.get(loanId));
        }
        List<Database.SaveResult> results;
        LeadRecycleContext.silent = true;
        try {
            results = Database.insert(toInsert, options);
        } finally {
            LeadRecycleContext.silent = false;
        }

        Map<Id, Lead> created = new Map<Id, Lead>(); // loan Id -> inserted lead
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                created.put(loanOrder[i], toInsert[i]);
            } else {
                System.debug(LoggingLevel.ERROR, 'LeadRecycleService: loan ' + loanOrder[i] + ' not recycled: '
                    + results[i].getErrors()[0].getMessage());
            }
        }
        if (created.isEmpty()) {
            return;
        }
        copyCoBorrowers(created, originals);
        addNotes(created, loans, false);
        notifyLoanOfficers(created, loans);
    }

    /**
     * 1) the lead whose Converted_Transaction_ID__c is this loan; 2) otherwise the latest lead converted
     * into the borrower account by the loan's created date + 1 day (right 171/171 times in the U8 review).
     */
    @TestVisible
    private static Map<Id, Lead> findOriginalLeads(List<Transaction__c> loans) {
        Set<Id> loanIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Transaction__c t : loans) {
            loanIds.add(t.Id);
            if (t.Borrower_Name__c != null) {
                accountIds.add(t.Borrower_Name__c);
            }
        }
        String fields = String.join(new List<String>(copyableLeadFields()), ',');
        String extra = ', ConvertedAccountId, ConvertedDate, Converted_Transaction_ID__c'; // Loan_Amount__c is already copyable
        List<Lead> candidates = Database.query(
            'SELECT ' + fields + extra + ' FROM Lead WHERE IsConverted = true AND '
            + '(Converted_Transaction_ID__c IN :loanIds OR ConvertedAccountId IN :accountIds) '
            + 'ORDER BY ConvertedDate DESC LIMIT 1000');

        Map<Id, Lead> byLoan = new Map<Id, Lead>();
        for (Transaction__c t : loans) {
            for (Lead l : candidates) {
                if (l.Converted_Transaction_ID__c == t.Id) {
                    byLoan.put(t.Id, l);
                    break;
                }
            }
            if (byLoan.containsKey(t.Id) || t.Borrower_Name__c == null) {
                continue;
            }
            Date latest = t.CreatedDate.date().addDays(1);
            for (Lead l : candidates) { // newest conversion first
                if (l.ConvertedAccountId == t.Borrower_Name__c && l.ConvertedDate != null && l.ConvertedDate <= latest) {
                    byLoan.put(t.Id, l);
                    break;
                }
            }
        }
        return byLoan;
    }

    private static Set<String> copyableFields;

    @TestVisible
    private static Set<String> copyableLeadFields() {
        if (copyableFields == null) {
            copyableFields = new Set<String>();
            for (Schema.SObjectField f : Lead.SObjectType.getDescribe().fields.getMap().values()) {
                Schema.DescribeFieldResult d = f.getDescribe();
                if (d.isCreateable() && !d.isCalculated() && !BLANKED.contains(d.getName().toLowerCase())) {
                    copyableFields.add(d.getName());
                }
            }
        }
        return copyableFields;
    }

    @TestVisible
    private static Lead cloneFor(Lead original, Transaction__c t) {
        Lead l = new Lead();
        for (String f : copyableLeadFields()) {
            Object v = original.get(f);
            if (v != null) {
                l.put(f, v);
            }
        }
        // Q32: lead amount, else the cancelled loan's Total Loan Amount; with neither, Nurture - Preapproval
        // (the Pre-Approval status requires an amount).
        Decimal amount = original.Loan_Amount__c ?? t.Loan_Amount_1st__c;
        l.Loan_Amount__c = amount;
        l.Status = amount == null ? 'Nurture - Preapproval' : 'Pre-Approval';
        l.OwnerId = t.Loan_Officer__c;
        l.Recycled_From_Transaction__c = t.Id;
        return l;
    }

    private static void copyCoBorrowers(Map<Id, Lead> created, Map<Id, Lead> originals) {
        Map<Id, Id> newLeadByOriginal = new Map<Id, Id>();
        Map<Id, Id> newLeadByLoan = new Map<Id, Id>();
        for (Id loanId : created.keySet()) {
            newLeadByLoan.put(loanId, created.get(loanId).Id);
            newLeadByOriginal.put(originals.get(loanId).Id, created.get(loanId).Id);
        }
        Set<Id> loanIds = newLeadByLoan.keySet();
        Set<Id> originalIds = newLeadByOriginal.keySet();
        List<String> fields = new List<String>();
        for (Schema.SObjectField f : Borrower__c.SObjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            String name = d.getName();
            if (d.isCreateable() && !d.isCalculated()
                && name != 'Lead__c' && name != 'Transaction__c' && name != 'Portal_Hash_Parameter__c') {
                fields.add(name);
            }
        }
        List<Borrower__c> copies = new List<Borrower__c>();
        Set<String> seen = new Set<String>();
        for (Borrower__c b : (List<Borrower__c>) Database.query(
            'SELECT Lead__c, Transaction__c, ' + String.join(fields, ',') + ' FROM Borrower__c '
            + 'WHERE Removed__c = false AND (Transaction__c IN :loanIds OR Lead__c IN :originalIds)')) {
            Id newLeadId = newLeadByLoan.get(b.Transaction__c) ?? newLeadByOriginal.get(b.Lead__c);
            // A co-borrower carried from the lead onto the loan is the same row; copy it once.
            String key = newLeadId + '|' + String.valueOf(b.get('Name'));
            if (newLeadId == null || seen.contains(key)) {
                continue;
            }
            seen.add(key);
            Borrower__c copy = new Borrower__c(Lead__c = newLeadId);
            for (String f : fields) {
                if (b.get(f) != null) {
                    copy.put(f, b.get(f));
                }
            }
            copies.add(copy);
        }
        if (!copies.isEmpty()) {
            Database.insert(copies, false);
        }
    }

    private static void addNotes(Map<Id, Lead> leadsByLoan, Map<Id, Transaction__c> loans, Boolean reactivation) {
        List<Enhanced_Note__c> notes = new List<Enhanced_Note__c>();
        for (Id loanId : leadsByLoan.keySet()) {
            Transaction__c t = loans.get(loanId);
            notes.add(new Enhanced_Note__c(
                Lead__c = leadsByLoan.get(loanId).Id,
                Type__c = 'Note',
                Subject__c = reactivation ? 'Original loan reactivated' : 'Back in pre-approval',
                Body__c = reactivation
                    ? 'Original loan was reactivated (' + t.Name + ' is ' + t.Status__c + '). This lead was moved to Nurturing.'
                    : 'Recycled from cancelled loan ' + t.Name + ' (' + t.Borrower_Withdrawal_Reason__c
                        + '). The borrower is still a buyer; keep them shopping.'
            ));
        }
        // The bell notification is the LO's one alert; don't also send the Lead Team note email.
        LeadNoteTeamNotifier.suppressForLoggedActivity = true;
        try {
            Database.insert(notes, false);
        } finally {
            LeadNoteTeamNotifier.suppressForLoggedActivity = false;
        }
    }

    private static void notifyLoanOfficers(Map<Id, Lead> created, Map<Id, Transaction__c> loans) {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE LIMIT 1
        ];
        if (types.isEmpty()) {
            return;
        }
        for (Id loanId : created.keySet()) {
            Transaction__c t = loans.get(loanId);
            Lead l = created.get(loanId);
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setNotificationTypeId(types[0].Id);
            n.setTargetId(l.Id);
            n.setTitle((t.Borrower_Name__r?.Name ?? 'A borrower') + ' is back in your pre-approvals');
            n.setBody('Loan ' + t.Name + ' was cancelled (' + t.Borrower_Withdrawal_Reason__c
                + '). The borrower is back as a ' + l.Status + ' lead.');
            try {
                n.send(new Set<String>{ t.Loan_Officer__c });
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'LeadRecycleService notification failed: ' + e.getMessage());
            }
        }
    }

    // ---------- Reactivation (Q34) ----------

    private static void reactivate(Set<Id> loanIds) {
        List<Lead> leads = [
            SELECT Id, Recycled_From_Transaction__c FROM Lead
            WHERE Recycled_From_Transaction__c IN :loanIds AND IsConverted = false AND Status != 'Nurturing'
        ];
        if (leads.isEmpty()) {
            return;
        }
        Map<Id, Transaction__c> loans = new Map<Id, Transaction__c>([
            SELECT Id, Name, Status__c, Borrower_Withdrawal_Reason__c FROM Transaction__c WHERE Id IN :loanIds
        ]);
        Map<Id, Lead> byLoan = new Map<Id, Lead>();
        Datetime now = System.now();
        for (Lead l : leads) {
            l.Status = 'Nurturing';
            l.Recycle_Reactivated_At__c = now;
            byLoan.put(l.Recycled_From_Transaction__c, l);
        }
        LeadRecycleContext.silent = true;
        try {
            Database.update(leads, false);
        } finally {
            LeadRecycleContext.silent = false;
        }
        addNotes(byLoan, loans, true);
    }
}
