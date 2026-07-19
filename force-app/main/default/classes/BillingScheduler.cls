public class BillingScheduler implements Schedulable {
 
    public void execute(SchedulableContext sc) {
        for (String region : new List<String>{'APAC', 'EMEA', 'AMER'}) {
            Billing_Run__c run = new Billing_Run__c(
                Period_Start__c = Date.today().toStartOfMonth(),
                Period_End__c   = Date.today(),
                Status__c       = 'Processing');
            insert run;
            // scope 200: safe headroom under the 10,000-row DML limit
            // per execute (200 subs → ~200 lines + invoices + updates)
            Database.executeBatch(
                new SubscriptionBillingBatch(run.Id, region), 200);
        }
    }
}
// Schedule (Execute Anonymous, 2 AM on the 1st):
// System.schedule('Monthly Billing', '0 0 2 1 * ?',
//                 new BillingScheduler());