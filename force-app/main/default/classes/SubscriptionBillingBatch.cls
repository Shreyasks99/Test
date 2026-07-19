// SubscriptionBillingBatch.cls
// Batchable = QueryLocator streams up to 50M rows (vs 50K for iterable).
// Stateful = carry success/failure counters across chunks.
public class SubscriptionBillingBatch implements
        Database.Batchable<SObject>, Database.Stateful {
 
    private final Id billingRunId;
    private final String regionFilter;   // optional segmentation
    private Integer processed = 0;
    private Integer failed = 0;
 
    public SubscriptionBillingBatch(Id billingRunId, String regionFilter) {
        this.billingRunId = billingRunId;
        this.regionFilter = regionFilter;
    }
 
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Dynamic, SELECTIVE query: Status + Next_Billing_Date are
        // indexed; bind variables via queryWithBinds (injection-safe).
        String q = 'SELECT Id, Account__c, Quantity__c, Region__c, '
            + 'Plan__r.Base_Price__c, Plan__r.Unit_Usage_Rate__c, '
            + 'Plan__r.Included_Units__c '
            + 'FROM Subscription__c '
            + 'WHERE Status__c = :status '
            + 'AND Next_Billing_Date__c <= :billDate ';
        Map<String, Object> binds = new Map<String, Object>{
            'status'   => 'Active',
            'billDate' => Date.today()
        };
        if (String.isNotBlank(regionFilter)) {
            q += 'AND Region__c = :region ';
            binds.put('region', regionFilter);
        }
        return Database.getQueryLocatorWithBinds(q, binds,
            AccessLevel.SYSTEM_MODE);
    }
 
    public void execute(Database.BatchableContext bc,
                        List<Subscription__c> scope) {
        Set<Id> subIds = new Map<Id, Subscription__c>(scope).keySet();
 
        // ONE aggregate query for the whole chunk — never per record
        Map<Id, Decimal> usageBySub = new Map<Id, Decimal>();
        for (AggregateResult ar : [
                SELECT Subscription__c sub, SUM(Units_Consumed__c) total
                FROM Usage_Record__c
                WHERE Subscription__c IN :subIds
                  AND Billing_Status__c = 'Unbilled'
                GROUP BY Subscription__c]) {
            usageBySub.put((Id) ar.get('sub'),
                           (Decimal) ar.get('total'));
        }
 
        // Active discounts for the chunk
        Map<Id, Discount__c> discountBySub = new Map<Id, Discount__c>();
        for (Discount__c disc : [
                SELECT Subscription__c, Discount_Type__c, Value__c
                FROM Discount__c
                WHERE Subscription__c IN :subIds
                  AND Valid_From__c <= TODAY AND Valid_To__c >= TODAY]) {
            discountBySub.put(disc.Subscription__c, disc);
        }
 
        Map<Id, Invoice__c> invoiceByAccount = new Map<Id, Invoice__c>();
        List<Invoice_Line__c> lines = new List<Invoice_Line__c>();
        List<Billing_Error__c> errors = new List<Billing_Error__c>();
 
        for (Subscription__c sub : scope) {
            try {
                BillingCalculator.Result r = BillingCalculator.calculate(
                    sub,
                    usageBySub.get(sub.Id),
                    discountBySub.get(sub.Id));
 
                if (!invoiceByAccount.containsKey(sub.Account__c)) {
                    invoiceByAccount.put(sub.Account__c, new Invoice__c(
                        Account__c = sub.Account__c,
                        Billing_Run__c = billingRunId,
                        Status__c = 'Draft'));
                }
                lines.add(new Invoice_Line__c(
                    Subscription__c    = sub.Id,
                    Base_Charge__c     = r.baseCharge,
                    Usage_Charge__c    = r.usageCharge,
                    Discount_Applied__c= r.discount,
                    Line_Total__c      = r.total,
                    Account_Key__c     = sub.Account__c // temp FK
                ));
                processed++;
            } catch (Exception e) {
                failed++;
                errors.add(new Billing_Error__c(
                    Billing_Run__c = billingRunId,
                    Subscription__c = sub.Id,
                    Error_Message__c = e.getMessage()));
            }
        }
 
        insert invoiceByAccount.values();
        for (Invoice_Line__c l : lines) {          // re-parent lines
            l.Invoice__c = invoiceByAccount.get(l.Account_Key__c).Id;
        }
        Database.SaveResult[] lineResults = Database.insert(lines, false);
        IntegrationLogger.logDmlFailures('Invoice_Line__c', lineResults);
        if (!errors.isEmpty()) { insert errors; }
 
        // Mark usage as billed + roll Next_Billing_Date forward
        List<Subscription__c> subUpdates = new List<Subscription__c>();
        for (Subscription__c sub : scope) {
            subUpdates.add(new Subscription__c(Id = sub.Id,
                Next_Billing_Date__c = Date.today().addMonths(1)));
        }
        update subUpdates;
        UsageService.markBilled(subIds);
    }
 
    public void finish(Database.BatchableContext bc) {
        update new Billing_Run__c(Id = billingRunId,
            Status__c = failed == 0 ? 'Completed' : 'Completed',
            Records_Processed__c = processed,
            Records_Failed__c = failed);
        // Notify + optionally chain the next region:
        BillingRunNotifier.sendSummary(billingRunId, processed, failed);
    }
}