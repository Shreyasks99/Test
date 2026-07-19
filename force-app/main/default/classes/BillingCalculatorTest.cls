// BillingCalculatorTest.cls
@IsTest
private class BillingCalculatorTest {

    private static Subscription__c subWithPlan(Decimal basePrice, Decimal unitRate,
            Decimal includedUnits, Decimal quantity) {
        Account acc = TestDataFactory.account('Calc Co');
        Subscription_Plan__c plan = TestDataFactory.plan('Calc Plan', basePrice, unitRate, includedUnits);
        Subscription__c sub = new Subscription__c(
            Account__c = acc.Id, Plan__c = plan.Id, Status__c = 'Active',
            Region__c = 'AMER', Quantity__c = quantity,
            Next_Billing_Date__c = Date.today());
        insert sub;
        return [
            SELECT Quantity__c, Plan__r.Base_Price__c, Plan__r.Unit_Usage_Rate__c,
                   Plan__r.Included_Units__c
            FROM Subscription__c WHERE Id = :sub.Id
        ];
    }

    @IsTest
    static void calculate_baseChargeOnly_whenUsageWithinIncludedUnits() {
        Subscription__c sub = subWithPlan(100, 2, 50, 1);

        BillingCalculator.Result r = BillingCalculator.calculate(sub, 30, null);

        System.assertEquals(100, r.baseCharge);
        System.assertEquals(0, r.usageCharge);
        System.assertEquals(0, r.discount);
        System.assertEquals(100, r.total);
    }

    @IsTest
    static void calculate_usageOverageIsBilledAtUnitRate() {
        Subscription__c sub = subWithPlan(100, 2, 50, 1);

        BillingCalculator.Result r = BillingCalculator.calculate(sub, 80, null);

        System.assertEquals(60, r.usageCharge, '30 overage units * 2/unit');
        System.assertEquals(160, r.total);
    }

    @IsTest
    static void calculate_nullUnitsAndNullQuantityDefaultSafely() {
        Account acc = TestDataFactory.account('Calc Co 2');
        Subscription_Plan__c plan = TestDataFactory.plan('Calc Plan 2', 50, 1, 10);
        Subscription__c sub = new Subscription__c(
            Account__c = acc.Id, Plan__c = plan.Id, Status__c = 'Active',
            Region__c = 'AMER', Next_Billing_Date__c = Date.today()); // Quantity__c left null
        insert sub;
        sub = [SELECT Quantity__c, Plan__r.Base_Price__c, Plan__r.Unit_Usage_Rate__c,
                      Plan__r.Included_Units__c FROM Subscription__c WHERE Id = :sub.Id];

        BillingCalculator.Result r = BillingCalculator.calculate(sub, null, null);

        System.assertEquals(50, r.baseCharge, 'null quantity should default to 1');
        System.assertEquals(0, r.usageCharge, 'null units consumed should default to 0');
        System.assertEquals(50, r.total);
    }

    @IsTest
    static void calculate_percentDiscountAppliedToGross() {
        Subscription__c sub = subWithPlan(100, 2, 50, 1);
        Discount__c disc = new Discount__c(Discount_Type__c = 'Percent', Value__c = 10);

        BillingCalculator.Result r = BillingCalculator.calculate(sub, 0, disc);

        System.assertEquals(10, r.discount, '10% of the 100 base charge');
        System.assertEquals(90, r.total);
    }

    @IsTest
    static void calculate_flatDiscountIsCappedAtGrossCharge() {
        Subscription__c sub = subWithPlan(100, 2, 50, 1);
        Discount__c disc = new Discount__c(Discount_Type__c = 'Flat', Value__c = 500);

        BillingCalculator.Result r = BillingCalculator.calculate(sub, 0, disc);

        System.assertEquals(100, r.discount, 'flat discount cannot exceed the gross charge');
        System.assertEquals(0, r.total);
    }

    @IsTest
    static void calculate_throwsWhenNegativeTotalWouldResult() {
        Subscription__c sub = subWithPlan(100, 2, 50, 1);
        Discount__c disc = new Discount__c(Discount_Type__c = 'Percent', Value__c = 150);

        try {
            BillingCalculator.calculate(sub, 0, disc);
            System.assert(false, 'Expected a BillingException for a negative total');
        } catch (BillingCalculator.BillingException e) {
            System.assert(e.getMessage().contains('Negative invoice total'));
        }
    }

    @IsTest
    static void calculate_throwsWhenSubscriptionHasNoPlan() {
        try {
            BillingCalculator.calculate(new Subscription__c(), 0, null);
            System.assert(false, 'Expected a BillingException when Plan__r is null');
        } catch (BillingCalculator.BillingException e) {
            System.assert(e.getMessage().contains('no plan'));
        }
    }
}