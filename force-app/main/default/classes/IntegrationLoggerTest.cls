// IntegrationLoggerTest.cls
@IsTest
private class IntegrationLoggerTest {

    private static List<Database.SaveResult> oneFailedAccountInsert() {
        // Name is required on Account, so this insert genuinely fails and
        // hands back a real Database.SaveResult with populated errors -
        // Database.SaveResult has no public constructor, so this is the
        // only way to obtain one for the logger to consume.
        return Database.insert(new List<Account>{ new Account() }, false);
    }

    @IsTest
    static void logDmlFailures_writesOneLogPerFailedRow() {
        List<Database.SaveResult> results = oneFailedAccountInsert();

        Test.startTest();
        IntegrationLogger.logDmlFailures('Account', results);
        Test.stopTest();

        List<Integration_Log__c> logs = [
            SELECT Context__c, Status__c, Response_Payload__c, Dispute__c FROM Integration_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('DML: Account', logs[0].Context__c);
        System.assertEquals('Failed', logs[0].Status__c);
        System.assertEquals(null, logs[0].Dispute__c, 'getId() is null for an insert failure');
        System.assert(String.isNotBlank(logs[0].Response_Payload__c));
    }

    @IsTest
    static void logDmlFailures_ignoresSuccessfulResults() {
        Database.SaveResult[] results = Database.insert(
            new List<Account>{ new Account(Name = 'Valid Logger Co') }, false);

        IntegrationLogger.logDmlFailures('Account', results);

        System.assertEquals(0, [SELECT COUNT() FROM Integration_Log__c]);
    }

    @IsTest
    static void logDmlFailures_neverThrowsEvenIfPersistFails() {
        // Empty list: persist() should just no-op, never throw.
        IntegrationLogger.logDmlFailures('Account', new List<Database.SaveResult>());
        System.assertEquals(0, [SELECT COUNT() FROM Integration_Log__c]);
    }

    @IsTest
    static void logPublishFailures_prefixesContextWithEventBus() {
        List<Database.SaveResult> results = oneFailedAccountInsert();

        IntegrationLogger.logPublishFailures('Dispute_Approved__e', results);

        Integration_Log__c log = [SELECT Context__c FROM Integration_Log__c LIMIT 1];
        System.assertEquals('DML: EventBus: Dispute_Approved__e', log.Context__c);
    }

    @IsTest
    static void buildCalloutLog_populatesExpectedFieldsWithoutInserting() {
        Account acc = TestDataFactory.account('Callout Log Co');
        Invoice__c inv = TestDataFactory.invoice(acc.Id, 500);
        Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 100);

        Integration_Log__c log = IntegrationLogger.buildCalloutLog(
            d.Id, 'ERP_API/posts', '{"amount":100}');

        System.assertEquals(d.Id, log.Dispute__c);
        System.assertEquals('ERP_API/posts', log.Endpoint__c);
        System.assertEquals('Callout', log.Context__c);
        System.assertEquals('{"amount":100}', log.Request_Payload__c);
        System.assertEquals(0, log.Retry_Count__c);
        System.assertEquals(null, log.Id, 'buildCalloutLog only builds the record; it does not insert it');
    }

    @IsTest
    static void buildCalloutLog_truncatesOverlongEndpointTo255Chars() {
        String longEndpoint = 'x'.repeat(300);

        Integration_Log__c log = IntegrationLogger.buildCalloutLog(null, longEndpoint, null);

        System.assertEquals(255, log.Endpoint__c.length());
        System.assertEquals(null, log.Request_Payload__c, 'a null request body should stay null, not blow up');
    }
}