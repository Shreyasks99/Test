// EventLogProcessorBatchTest.cls
// EventLogFile rows cannot be inserted via DML, so this test builds one
// entirely in memory and calls execute()/start()/finish() directly rather
// than going through Database.executeBatch.
@IsTest
private class EventLogProcessorBatchTest {

    private static Blob sampleCsv() {
        List<String> lines = new List<String>{
            '"USER_ID","TIMESTAMP_DERIVED","CLIENT_IP","URI","ENTITY_NAME","OPERATION_TYPE","SESSION_KEY"',
            '"005xx000001Sv6AAA1","2026-07-15T02:12:34.000Z","10.0.0.1","/services/data/v60.0/sobjects","","API","sess1"',
            '"005xx000001Sv6AAA2","2026-07-15T02:13:00.000Z","10.0.0.2","","Account","Query","sess2"',
            '"","2026-07-15T02:14:00.000Z","10.0.0.3","","Contact","Query","sess3"'
        };
        return Blob.valueOf(String.join(lines, '\n'));
    }

    @IsTest
    static void execute_parsesRowsAndSkipsBlankUserId() {
        EventLogFile elf = new EventLogFile(
            LogDate = Date.today().addDays(-1), LogFile = sampleCsv());

        Test.startTest();
        new EventLogProcessorBatch().execute(null, new List<EventLogFile>{ elf });
        Test.stopTest();

        List<Audit_Log_Entry__c> entries = [
            SELECT Event_Type__c, Entity__c, Operation__c, User_Lookup_Key__c,
                   Source_IP__c, Session_Key__c, Export_Status__c, Event_Timestamp__c
            FROM Audit_Log_Entry__c ORDER BY User_Lookup_Key__c
        ];
        System.assertEquals(2, entries.size(), 'the blank-USER_ID row must be skipped');

        Audit_Log_Entry__c rowA = entries[0];
        System.assertEquals('/services/data/v60.0/sobjects', rowA.Entity__c, 'URI wins over ENTITY_NAME when present');
        System.assertEquals('API', rowA.Operation__c);
        System.assertEquals('10.0.0.1', rowA.Source_IP__c);
        System.assertEquals('sess1', rowA.Session_Key__c);
        System.assertEquals('Pending', rowA.Export_Status__c);
        System.assertNotEquals(null, rowA.Event_Timestamp__c);

        Audit_Log_Entry__c rowB = entries[1];
        System.assertEquals('Account', rowB.Entity__c, 'falls back to ENTITY_NAME when URI is blank');
        System.assertEquals('Query', rowB.Operation__c);
    }

    @IsTest
    static void start_returnsAQueryLocatorWithoutError() {
        Database.QueryLocator locator = new EventLogProcessorBatch().start(null);
        System.assertNotEquals(null, locator);
    }

    @IsTest
    static void finish_logsSyncRecordAndChainsSnowflakeExport() {
        // No Pending Audit_Log_Entry__c rows exist in this fresh test
        // transaction, so the chained SnowflakeExportQueueable no-ops
        // without needing an HttpCalloutMock.
        Test.startTest();
        new EventLogProcessorBatch().finish(null);
        Test.stopTest();

        List<Snowflake_Sync_Log__c> logs = [SELECT Status__c, Rows_Pushed__c FROM Snowflake_Sync_Log__c];
        System.assertEquals(1, logs.size());
        System.assertEquals('Success', logs[0].Status__c);
        System.assertEquals(0, logs[0].Rows_Pushed__c);
    }
}