/**
 * Async ingest of a RingSense webhook body. Parsing and DML stay in CallInsightIngestionService.
 */
public without sharing class CallInsightIngestJob implements Queueable {
    private String payloadBody;

    public CallInsightIngestJob(String payloadBody) {
        this.payloadBody = payloadBody;
    }

    public void execute(QueueableContext context) {
        CallInsightIngestionService.ingestFromRingSensePayload(payloadBody);
    }
}