/**
 * UsageService.cls
 * Owns the Usage_Record__c lifecycle. Kept separate from the batch so
 * the same logic serves the billing run, a future reprocess batch,
 * and any manual correction path — one owner for "what does billed
 * mean", no copy-pasted DML.
 */
public without sharing class UsageService {

    /**
     * Marks all UNBILLED usage for the given subscriptions as Billed.
     * Called once per batch chunk (subIds ≤ 200 subscriptions).
     */
    public static void markBilled(Set<Id> subscriptionIds) {
        if (subscriptionIds == null || subscriptionIds.isEmpty()) {
            return;
        }
        List<Usage_Record__c> updates = new List<Usage_Record__c>();
        for (Usage_Record__c u : [
                SELECT Id FROM Usage_Record__c
                WHERE Subscription__c IN :subscriptionIds
                  AND Billing_Status__c = 'Unbilled']) {
            updates.add(new Usage_Record__c(
                Id = u.Id,
                Billing_Status__c = 'Billed'));
        }
        if (updates.isEmpty()) { return; }

        // Partial success: one locked/bad row must not fail the chunk
        Database.SaveResult[] results = Database.update(updates, false);
        IntegrationLogger.logDmlFailures('Usage_Record__c(markBilled)',
                                         results);
    }

    /**
     * Reopens usage for a subscription (used by the error-reprocess
     * path: if a line failed and gets corrected, its usage must be
     * billable again on the next run).
     */
    public static void reopen(Set<Id> subscriptionIds) {
        if (subscriptionIds == null || subscriptionIds.isEmpty()) {
            return;
        }
        List<Usage_Record__c> updates = new List<Usage_Record__c>();
        for (Usage_Record__c u : [
                SELECT Id FROM Usage_Record__c
                WHERE Subscription__c IN :subscriptionIds
                  AND Billing_Status__c = 'Billed'
                  AND LastModifiedDate = TODAY]) {
            updates.add(new Usage_Record__c(
                Id = u.Id,
                Billing_Status__c = 'Unbilled'));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, false);
        }
    }
}