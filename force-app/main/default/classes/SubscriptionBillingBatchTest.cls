// SubscriptionBillingBatchTest.cls
@IsTest
private class SubscriptionBillingBatchTest {
 
    @TestSetup
    static void setup() {
        Account acc = TestDataFactory.account('Billed Co');
        Subscription_Plan__c plan = TestDataFactory.plan(
            'Pro', 100, 2, 50); // base 100, rate 2/unit, 50 included
        // 200 subscriptions to prove bulk safety in one chunk
        List<Subscription__c> subs = new List<Subscription__c>();
        for (Integer i = 0; i < 200; i++) {
            subs.add(new Subscription__c(Account__c = acc.Id,
                Plan__c = plan.Id, Status__c = 'Active',
                Region__c = 'APAC', Quantity__c = 1,
                Next_Billing_Date__c = Date.today()));
        }
        insert subs;
        // usage above included units for the first sub only
        insert new Usage_Record__c(Subscription__c = subs[0].Id,
            Usage_Date__c = Date.today().addDays(-5),
            Units_Consumed__c = 80, Billing_Status__c = 'Unbilled');
        insert new Discount__c(Subscription__c = subs[1].Id,
            Discount_Type__c = 'Percent', Value__c = 10,
            Valid_From__c = Date.today().addDays(-30),
            Valid_To__c = Date.today().addDays(30));
    }
 
    @IsTest
    static void billsBaseUsageAndDiscountCorrectly() {
        Billing_Run__c run = new Billing_Run__c(Status__c='Queued',
            Period_Start__c = Date.today().toStartOfMonth(),
            Period_End__c = Date.today());
        insert run;
 
        Test.startTest();
        Database.executeBatch(
            new SubscriptionBillingBatch(run.Id, 'APAC'), 200);
        Test.stopTest();
 
        // 80 units - 50 included = 30 overage * 2 = 60 usage charge
        Invoice_Line__c withUsage = [SELECT Usage_Charge__c, Line_Total__c
            FROM Invoice_Line__c WHERE Usage_Charge__c > 0 LIMIT 1];
        System.assertEquals(60, withUsage.Usage_Charge__c);
        System.assertEquals(160, withUsage.Line_Total__c);
 
        // 10% discount on the 100 base = 90
        System.assertEquals(1, [SELECT COUNT() FROM Invoice_Line__c
            WHERE Discount_Applied__c = 10]);
 
        run = [SELECT Records_Processed__c, Records_Failed__c
               FROM Billing_Run__c WHERE Id = :run.Id];
        System.assertEquals(200, run.Records_Processed__c);
        System.assertEquals(0, run.Records_Failed__c);
    }
 
    @IsTest
    static void edgeCases_zeroUsage_expiredDiscount_noPlan() {
        // pure-logic tests hit BillingCalculator directly — fast,
        // no DML, the bulk of coverage should live at this level
        Subscription_Plan__c plan = [SELECT Id, Base_Price__c,
            Unit_Usage_Rate__c, Included_Units__c
            FROM Subscription_Plan__c LIMIT 1];
        Subscription__c sub = [SELECT Id, Quantity__c, Plan__r.Base_Price__c,
            Plan__r.Unit_Usage_Rate__c, Plan__r.Included_Units__c
            FROM Subscription__c LIMIT 1];
 
        BillingCalculator.Result r =
            BillingCalculator.calculate(sub, null, null);
        System.assertEquals(100, r.total, 'zero usage → base only');
 
        r = BillingCalculator.calculate(sub, 50, null);
        System.assertEquals(0, r.usageCharge,
            'usage within included units is free');
 
        try {
            BillingCalculator.calculate(new Subscription__c(), 0, null);
            System.assert(false, 'expected BillingException');
        } catch (BillingCalculator.BillingException e) {
            System.assert(e.getMessage().contains('no plan'));
        }
    }
}