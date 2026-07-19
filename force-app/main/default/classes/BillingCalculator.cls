// BillingCalculator.cls — pure, stateless, unit-testable in isolation
public class BillingCalculator {
 
    public class Result {
        public Decimal baseCharge;
        public Decimal usageCharge;
        public Decimal discount;
        public Decimal total;
    }
    public class BillingException extends Exception {}
 
    public static Result calculate(Subscription__c sub,
                                   Decimal unitsConsumed,
                                   Discount__c disc) {
        if (sub.Plan__r == null) {
            throw new BillingException('Subscription has no plan');
        }
        Decimal qty      = sub.Quantity__c == null ? 1 : sub.Quantity__c;
        Decimal units    = unitsConsumed == null ? 0 : unitsConsumed;
        Decimal included = sub.Plan__r.Included_Units__c == null
                           ? 0 : sub.Plan__r.Included_Units__c;
 
        Result r = new Result();
        r.baseCharge  = sub.Plan__r.Base_Price__c * qty;
        Decimal overage = Math.max(0, units - included);
        r.usageCharge = overage * sub.Plan__r.Unit_Usage_Rate__c;
 
        Decimal gross = r.baseCharge + r.usageCharge;
        r.discount = 0;
        if (disc != null) {
            r.discount = disc.Discount_Type__c == 'Percent'
                ? (gross * disc.Value__c / 100).setScale(2)
                : Math.min(disc.Value__c, gross);
        }
        r.total = (gross - r.discount).setScale(2);
        if (r.total < 0) {
            throw new BillingException('Negative invoice total for '
                + sub.Id);
        }
        return r;
    }
}