/**
 * IntegrationLogger.cls
 * One place where every "something failed silently in async land"
 * becomes a queryable record. Used by triggers, queueables and
 * batches — so it must NEVER throw and must be bulk-safe.
 */
public without sharing class IntegrationLogger {

    // Partial-success DML: log only the failed rows
    public static void logDmlFailures(String context,
                                      List<Database.SaveResult> results) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Database.SaveResult r : results) {
            if (r.isSuccess()) { continue; }
            logs.add(new Integration_Log__c(
                Context__c   = ('DML: ' + context).left(255),
                Dispute__c = r.getId(),          // null on insert failures
                Status__c    = 'Failed',
                Response_Payload__c = flatten(r.getErrors())));
        }
        persist(logs);
    }

    // EventBus.publish also returns SaveResults — same shape
    public static void logPublishFailures(String eventName,
                                          List<Database.SaveResult> results) {
        logDmlFailures('EventBus: ' + eventName, results);
    }

    // Callout logging (used by DisputeERPSyncQueueable & friends)
    public static Integration_Log__c buildCalloutLog(Id disputeId,
            String endpoint, String requestBody) {
        return new Integration_Log__c(
            Dispute__c          = disputeId,
            Endpoint__c         = endpoint.left(255),
            Context__c          = 'Callout',
            Request_Payload__c  = safe(requestBody),
            Retry_Count__c      = 0);
    }

    // ---------- internals ----------
    private static String flatten(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error e : errors) {
            parts.add(e.getStatusCode() + ': ' + e.getMessage()
                + ' [' + String.join(e.getFields(), ',') + ']');
        }
        return safe(String.join(parts, ' | '));
    }

    private static String safe(String s) {
        return s == null ? null : s.abbreviate(32000); // long text cap
    }

    // A logger that breaks the transaction it's observing is worse
    // than no logger — swallow its own failures, but leave a debug
    // trail for developers.
    private static void persist(List<Integration_Log__c> logs) {
        if (logs.isEmpty()) { return; }
        try {
            Database.insert(logs, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationLogger failed: ' + e.getMessage());
        }
    }
}