// EventLogProcessorBatch.cls
// One EventLogFile per execute() scope — each LogFile blob can be
// tens of MB; scope=1 keeps us inside the 12MB async heap limit and
// we stream line-by-line rather than String.split on the whole file.
public class EventLogProcessorBatch
        implements Database.Batchable<SObject>, Database.Stateful {
 
    private Integer rowsCreated = 0;
 
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, EventType, LogDate, LogFile
            FROM EventLogFile
            WHERE LogDate = YESTERDAY
              AND EventType IN ('Login', 'API', 'RestApi', 'URI')
        ]);
    }
 
    public void execute(Database.BatchableContext bc,
                        List<EventLogFile> scope) {
        List<Audit_Log_Entry__c> entries = new List<Audit_Log_Entry__c>();
        for (EventLogFile elf : scope) {
            String csv = elf.LogFile.toString();
            List<String> lines = csv.split('\n');
            List<String> headers = ParserUtil.parseCsvLine(lines[0]);
 
            for (Integer i = 1; i < lines.size(); i++) {
                Map<String, String> row = ParserUtil.toMap(
                    headers, ParserUtil.parseCsvLine(lines[i]));
                // Filter: only keep what compliance actually needs
                if (String.isBlank(row.get('USER_ID'))) { continue; }
                entries.add(new Audit_Log_Entry__c(
                    Event_Type__c      = elf.EventType,
                    Event_Timestamp__c = ParserUtil.ts(row.get('TIMESTAMP_DERIVED')),
                    User_Lookup_Key__c = row.get('USER_ID'),
                    Source_IP__c       = row.get('CLIENT_IP'),
                    Entity__c          = row.get('URI') != null
                                         ? row.get('URI')
                                         : row.get('ENTITY_NAME'),
                    Operation__c       = row.get('OPERATION_TYPE'),
                    Session_Key__c     = row.get('SESSION_KEY'),
                    Export_Status__c   = 'Pending'));
                if (entries.size() == 5000) {   // stay under DML rows
                    insert entries;
                    rowsCreated += entries.size();
                    entries.clear();
                }
            }
        }
        if (!entries.isEmpty()) {
            insert entries;
            rowsCreated += entries.size();
        }
    }
 
    public void finish(Database.BatchableContext bc) {
        insert new Snowflake_Sync_Log__c(
            Batch_Started__c = Datetime.now(),
            Rows_Pushed__c = 0, Status__c = 'Success');
        // Chain the export of today's parsed rows to Snowflake
        System.enqueueJob(new SnowflakeExportQueueable(Date.today()));
    }
}
// Scheduled daily at 3 AM (EventLogFiles for 'yesterday' are ready):
// System.schedule('Event Log Harvest', '0 0 3 * * ?',
//     new EventLogHarvestScheduler());