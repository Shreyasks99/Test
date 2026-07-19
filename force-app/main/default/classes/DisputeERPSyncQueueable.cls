// DisputeERPSyncQueueable.cls — callout-safe, retryable, idempotent
public class DisputeERPSyncQueueable implements Queueable, Database.AllowsCallouts {
 
    private static final Integer MAX_RETRIES = 3;
    private final Set<Id> disputeIds;
    private final Integer attempt;
 
    public DisputeERPSyncQueueable(Set<Id> disputeIds) {
        this(disputeIds, 1);
    }
    private DisputeERPSyncQueueable(Set<Id> disputeIds, Integer attempt) {
        this.disputeIds = disputeIds;
        this.attempt = attempt;
    }
 
    public void execute(QueueableContext ctx) {
        List<Dispute__c> disputes = [
            SELECT Id, Name, Type__c, Disputed_Amount__c,
                   Invoice__r.Invoice_Number__c, ERP_Sync_Status__c
            FROM Dispute__c
            WHERE Id IN :disputeIds AND ERP_Sync_Status__c != 'Sent'
        ];
        if (disputes.isEmpty()) { return; } 
 
        Set<Id> failed = new Set<Id>();
        List<Dispute__c> toUpdate = new List<Dispute__c>();
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
 
        for (Dispute__c d : disputes) {
            // 1 callout per record here for clarity; a real ERP would
            // expose a bulk endpoint — then send one batched payload.
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:ERP_API/posts'); // Named Credential
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Idempotency-Key', d.Id);   // dedupe on ERP side
            req.setTimeout(20000);
            req.setBody(JSON.serialize(new Map<String, Object>{
                'disputeNumber' => d.Name,
                'invoiceNumber' => d.Invoice__r.Invoice_Number__c,
                'type'          => d.Type__c,
                'amount'        => d.Disputed_Amount__c
            }));
 
            Integration_Log__c log = new Integration_Log__c(
                Dispute__c = d.Id, Endpoint__c = 'ERP_API/posts',
                Request_Payload__c = req.getBody(),
                Retry_Count__c = attempt - 1);
            try {
                HttpResponse res = new Http().send(req);
                log.Response_Payload__c = res.getBody().abbreviate(32000);
                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    Map<String, Object> body = (Map<String, Object>)
                        JSON.deserializeUntyped(res.getBody());
                    log.Status__c = 'Success';
                    toUpdate.add(new Dispute__c(Id = d.Id,
                        ERP_Sync_Status__c = 'Sent',
                        ERP_Reference__c = String.valueOf(body.get('id'))));
                } else {
                    log.Status__c = 'Failed';
                    failed.add(d.Id);
                }
            } catch (CalloutException e) {
                log.Status__c = 'Failed';
                log.Response_Payload__c = e.getMessage();
                failed.add(d.Id);
            }
            logs.add(log);
        }
 
        // DML AFTER all callouts (uncommitted-work rule)
        if (!toUpdate.isEmpty()) { update toUpdate; }
        if (!logs.isEmpty()) { insert logs; }
 
        if (!failed.isEmpty()) {
            if (attempt < MAX_RETRIES && !Test.isRunningTest()) {
                System.enqueueJob(
                    new DisputeERPSyncQueueable(failed, attempt + 1));
            } else {
                List<Dispute__c> flags = new List<Dispute__c>();
                for (Id i : failed) {
                    flags.add(new Dispute__c(Id = i,
                        ERP_Sync_Status__c = 'Failed'));
                }
                update flags; // surfaced on a 'Failed Syncs' report + alert
            }
        }
    }
}