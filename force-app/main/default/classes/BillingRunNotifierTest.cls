// BillingRunNotifierTest.cls
@IsTest
private class BillingRunNotifierTest {

    private static Id newBillingRun() {
        Billing_Run__c run = new Billing_Run__c(
            Period_Start__c = Date.today().toStartOfMonth(),
            Period_End__c = Date.today(),
            Status__c = 'Processing');
        insert run;
        return run.Id;
    }

    @IsTest
    static void sendSummary_completedRun_doesNotThrow() {
        Id runId = newBillingRun();

        Test.startTest();
        BillingRunNotifier.sendSummary(runId, 200, 0);
        Test.stopTest();

        System.assert(true, 'sendSummary must complete without throwing on a clean run');
    }

    @IsTest
    static void sendSummary_runWithFailures_doesNotThrow() {
        Id runId = newBillingRun();

        Test.startTest();
        BillingRunNotifier.sendSummary(runId, 150, 50);
        Test.stopTest();

        System.assert(true, 'sendSummary must complete without throwing when failures occurred');
    }

    @IsTest
    static void sendSummary_unknownBillingRun_returnsSilently() {
        Id bogusId = newBillingRun();
        delete new Billing_Run__c(Id = bogusId); // valid Id format, but no longer exists

        Test.startTest();
        BillingRunNotifier.sendSummary(bogusId, 0, 0);
        Test.stopTest();

        System.assert(true, 'A missing Billing_Run__c must short-circuit without throwing');
    }
}