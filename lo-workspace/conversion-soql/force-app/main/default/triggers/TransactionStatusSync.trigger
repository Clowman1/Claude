trigger TransactionStatusSync on Transaction__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            // Written on the record itself: an after-insert copy cost a second Transaction save (7 SOQL).
            TransactionUtmCopyService.fillOnInsert(Trigger.new);
        }
        TransactionStatusAgeService.stampCurrentStatusSince(Trigger.new, Trigger.isInsert ? null : Trigger.oldMap);
    }

    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        if (Trigger.isUpdate) {
            TransactionUtmCopyService.copyFromConvertedLeads(Trigger.new, Trigger.oldMap);
        }

        PurchaseDefaultConditionService.ensureForPurchaseTransactions(
            Trigger.new,
            Trigger.isInsert ? null : Trigger.oldMap
        );

        LoanOfficerRecordSharingService.syncTransactionShares(
            Trigger.new,
            Trigger.isInsert ? null : Trigger.oldMap
        );
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        DpaSecondTransactionStatusSync.syncAfterUpdate(Trigger.new, Trigger.oldMap);
        // U8: a cancelled purchase loan sends the borrower back to the LO as a pre-approval lead.
        LeadRecycleService.onTransactionUpdate(Trigger.new, Trigger.oldMap);
    }
}