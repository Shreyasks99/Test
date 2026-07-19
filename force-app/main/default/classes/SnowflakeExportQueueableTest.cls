// SnowflakeExportQueueableTest.cls
@IsTest
private class SnowflakeExportQueueableTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assertEquals('callout:Snowflake_API/api/v2/statements', req.getEndpoint());
            System.assertEquals('POST', req.getMethod());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"ok"}');
            return res;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"downstream unavailable"}');
            return res;
        }
    }

    private static void seedPendingEntries(Integer count) {
        List<Audit_Log_Entry__c> entries = new List<Audit_Log_Entry__c>();
        for (Integer i = 0; i < count; i++) {
            entries.add(new Audit_Log_Entry__c(
                Event_Type__c = 'Login',
                Event_Timestamp__c = Datetime.now(),
                Source_IP__c = '10.0.0.' + i,
                Entity__c = 'Account',
                Operation__c = 'Query',
                Export_Status__c = 'Pending'));
        }
        insert entries;
    }

    @IsTest
    static void execute_marksAllPendingEntriesExportedOnSuccess() {
        seedPendingEntries(3);
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        new SnowflakeExportQueueable(Date.today()).execute(null);
        Test.stopTest();

        System.assertEquals(3, [SELECT COUNT() FROM Audit_Log_Entry__c WHERE Export_Status__c = 'Exported']);
    }

    @IsTest
    static void execute_marksEntriesFailedWhenSnowflakeRejects() {
        seedPendingEntries(2);
        Test.setMock(HttpCalloutMock.class, new FailureMock());

        Test.startTest();
        new SnowflakeExportQueueable(Date.today()).execute(null);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Audit_Log_Entry__c WHERE Export_Status__c = 'Failed']);
    }

    @IsTest
    static void execute_noPendingEntries_skipsCalloutEntirely() {
        // No mock registered: a real callout attempt here would fail this test.
        Test.startTest();
        new SnowflakeExportQueueable(Date.today()).execute(null);
        Test.stopTest();

        System.assert(true, 'execute() must no-op cleanly when nothing is pending');
    }

    @IsTest
    static void enqueuedJob_processesThroughTheRealAsyncPath() {
        seedPendingEntries(1);
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new SnowflakeExportQueueable(Date.today()));
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Audit_Log_Entry__c WHERE Export_Status__c = 'Exported']);
    }
}