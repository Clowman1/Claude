public without sharing class TransactionPdfRetentionScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        Database.executeBatch(new TransactionPdfRetentionBatch(), 50);
    }
}