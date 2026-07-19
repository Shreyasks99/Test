// UsageServiceTest.cls
@IsTest
private class UsageServiceTest {

    private static Id newSubscription(Id accountId, Id planId) {
        Subscription__c sub = new Subscription__c(
            Account__c = accountId, Plan__c = planId, Status__c = 'Active',
            Region__c = 'AMER', Quantity__c = 1, Next_Billing_Date__c = Date.today());
        insert sub;
        return sub.Id;
    }

    @IsTest
    static void markBilled_flipsOnlyUnbilledRecordsForTargetedSubscriptions() {
        Account acc = TestDataFactory.account('Usage Co');
        Subscription_Plan__c plan = TestDataFactory.plan('Usage Plan', 100, 1, 10);
        Id sub1 = newSubscription(acc.Id, plan.Id);
        Id sub2 = newSubscription(acc.Id, plan.Id);

        Usage_Record__c u1 = TestDataFactory.usage(sub1, 5); // Unbilled
        insert new Usage_Record__c(Subscription__c = sub1, Usage_Date__c = Date.today(),
            Units_Consumed__c = 3, Billing_Status__c = 'Billed'); // already billed, should stay untouched
        Usage_Record__c u3 = TestDataFactory.usage(sub2, 7); // different subscription, not targeted

        Test.startTest();
        UsageService.markBilled(new Set<Id>{ sub1 });
        Test.stopTest();

        System.assertEquals('Billed', [SELECT Billing_Status__c FROM Usage_Record__c WHERE Id = :u1.Id].Billing_Status__c);
        System.assertEquals('Unbilled', [SELECT Billing_Status__c FROM Usage_Record__c WHERE Id = :u3.Id].Billing_Status__c,
            'A subscription outside the requested set must not be touched');
        System.assertEquals(2, [SELECT COUNT() FROM Usage_Record__c WHERE Subscription__c = :sub1 AND Billing_Status__c = 'Billed']);
    }

    @IsTest
    static void markBilled_handlesNullAndEmptySetsGracefully() {
        UsageService.markBilled(null);
        UsageService.markBilled(new Set<Id>());
        System.assert(true, 'null/empty sets must short-circuit without throwing');
    }

    @IsTest
    static void reopen_movesTodaysBilledUsageBackToUnbilled() {
        Account acc = TestDataFactory.account('Usage Co 2');
        Subscription_Plan__c plan = TestDataFactory.plan('Usage Plan 2', 100, 1, 10);
        Id sub1 = newSubscription(acc.Id, plan.Id);
        Id sub2 = newSubscription(acc.Id, plan.Id);

        Usage_Record__c billedToday = new Usage_Record__c(
            Subscription__c = sub1, Usage_Date__c = Date.today(),
            Units_Consumed__c = 5, Billing_Status__c = 'Billed');
        insert billedToday;
        Usage_Record__c untouched = TestDataFactory.usage(sub2, 4); // Unbilled, different subscription

        Test.startTest();
        UsageService.reopen(new Set<Id>{ sub1 });
        Test.stopTest();

        System.assertEquals('Unbilled', [SELECT Billing_Status__c FROM Usage_Record__c WHERE Id = :billedToday.Id].Billing_Status__c);
        System.assertEquals('Unbilled', [SELECT Billing_Status__c FROM Usage_Record__c WHERE Id = :untouched.Id].Billing_Status__c);
    }

    @IsTest
    static void reopen_handlesNullAndEmptySetsGracefully() {
        UsageService.reopen(null);
        UsageService.reopen(new Set<Id>());
        System.assert(true, 'null/empty sets must short-circuit without throwing');
    }
}