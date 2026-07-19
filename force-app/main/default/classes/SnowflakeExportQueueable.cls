// SnowflakeExportQueueable.cls — push filtered logs to Snowflake
// via its SQL REST API through a Named Credential (OAuth/key-pair).
public class SnowflakeExportQueueable
        implements Queueable, Database.AllowsCallouts {
 
    private final Date forDay;
    public SnowflakeExportQueueable(Date forDay) { this.forDay = forDay; }
 
    public void execute(QueueableContext ctx) {
        List<Audit_Log_Entry__c> pending = [
            SELECT Id, Event_Type__c, Event_Timestamp__c, User__c,
                   Source_IP__c, Entity__c, Operation__c
            FROM Audit_Log_Entry__c
            WHERE Export_Status__c = 'Pending'
            LIMIT 2000                       // chunk; requeue for rest
        ];
        if (pending.isEmpty()) { return; }
 
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Snowflake_API/api/v2/statements');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'statement' => SnowflakeSqlBuilder.bulkInsert(
                               'AUDIT.SF_EVENT_LOGS', pending),
            'database'  => 'COMPLIANCE',
            'schema'    => 'AUDIT',
            'warehouse' => 'ETL_WH'
        }));
 
        HttpResponse res = new Http().send(req);
        String newStatus = res.getStatusCode() < 300
                           ? 'Exported' : 'Failed';
        for (Audit_Log_Entry__c a : pending) {
            a.Export_Status__c = newStatus;
        }
        update pending;
 
        if (newStatus == 'Exported' && !Test.isRunningTest()) {
            // more pending rows? chain another chunk
            if ([SELECT COUNT() FROM Audit_Log_Entry__c
                 WHERE Export_Status__c = 'Pending'] > 0) {
                System.enqueueJob(new SnowflakeExportQueueable(forDay));
            }
        }
    }
}