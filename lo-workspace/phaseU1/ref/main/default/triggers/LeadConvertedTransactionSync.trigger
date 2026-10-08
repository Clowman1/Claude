trigger LeadConvertedTransactionSync on Lead (after update) {
    LeadConvertedTransactionSyncService.syncLoanPartnerToConvertedTransactions(Trigger.new, Trigger.oldMap);
    // Freezes the Lead's accumulated Application Summary onto the new Transaction, once.
    ApplicationSummaryService.snapshotOnConversion(Trigger.new, Trigger.oldMap);
}