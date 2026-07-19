// BillingSchedulerTest.cls
@IsTest
private class BillingSchedulerTest {

    @IsTest
    static void execute_createsOneBillingRunPerRegionAndRunsTheBatch() {
        Test.startTest();
        new BillingScheduler().execute(null); // SchedulableContext is unused by execute()
        Test.stopTest();

        List<Billing_Run__c> runs = [
            SELECT Period_Start__c, Period_End__c, Records_Processed__c, Records_Failed__c
            FROM Billing_Run__c ORDER BY CreatedDate
        ];
        System.assertEquals(3, runs.size(), 'One Billing_Run__c per region: APAC, EMEA, AMER');
        for (Billing_Run__c r : runs) {
            System.assertEquals(Date.today().toStartOfMonth(), r.Period_Start__c);
            System.assertEquals(Date.today(), r.Period_End__c);
            System.assertEquals(0, r.Records_Processed__c, 'No subscriptions exist, so the batch finds nothing to bill');
            System.assertEquals(0, r.Records_Failed__c);
        }
    }

    @IsTest
    static void schedulable_canBeScheduledViaCron() {
        Test.startTest();
        String jobId = System.schedule('Monthly Billing Test', '0 0 2 1 * ?', new BillingScheduler());
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'BillingScheduler must be schedulable via System.schedule');
    }
}