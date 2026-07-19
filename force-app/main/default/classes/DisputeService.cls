public with sharing class DisputeService {
 
    // BEFORE INSERT: default owner queue + stamp Account from Invoice
    public static void applyDefaults(List<Dispute__c> disputes) {
        Set<Id> invoiceIds = new Set<Id>();
        for (Dispute__c d : disputes) { invoiceIds.add(d.Invoice__c); }
 
        Map<Id, Invoice__c> invoices = new Map<Id, Invoice__c>([
            SELECT Id, Account__c, Balance_Due__c, Status__c
            FROM Invoice__c WHERE Id IN :invoiceIds WITH USER_MODE
        ]);
        for (Dispute__c d : disputes) {
            Invoice__c inv = invoices.get(d.Invoice__c);
            if (inv != null) { d.Account__c = inv.Account__c; }
            if (d.Status__c == null) { d.Status__c = 'New'; }
        }
    }
 
    // BEFORE INSERT: cannot dispute more than the invoice balance
    public static void validateAgainstInvoice(List<Dispute__c> disputes) {
        Set<Id> invoiceIds = new Set<Id>();
        for (Dispute__c d : disputes) { invoiceIds.add(d.Invoice__c); }
        Map<Id, Invoice__c> invoices = new Map<Id, Invoice__c>([
            SELECT Id, Balance_Due__c FROM Invoice__c
            WHERE Id IN :invoiceIds WITH USER_MODE
        ]);
        for (Dispute__c d : disputes) {
            Invoice__c inv = invoices.get(d.Invoice__c);
            if (inv != null && d.Disputed_Amount__c > inv.Balance_Due__c) {
                d.addError('Disputed amount exceeds invoice balance of ' + inv.Balance_Due__c);
            }
        }
    }
 
    // AFTER UPDATE: fire Platform Event exactly once per approval
    public static void publishApprovedEvents(
            List<Dispute__c> newList, Map<Id, Dispute__c> oldMap) {
 
        List<Dispute_Approved__e> events = new List<Dispute_Approved__e>();
        for (Dispute__c d : newList) {
            Boolean justApproved = d.Status__c == 'Approved' && oldMap.get(d.Id).Status__c != 'Approved';
            if (justApproved) {
                events.add(new Dispute_Approved__e(
                    Dispute_Id__c      = d.Id,
                    Dispute_Number__c  = d.Name,
                    Dispute_Type__c    = d.Type__c,
                    Disputed_Amount__c = d.Disputed_Amount__c
                ));
            }
        }
        if (!events.isEmpty()) {
            List<Database.SaveResult> results = EventBus.publish(events);
            IntegrationLogger.logPublishFailures('Dispute_Approved__e', results);
        }
    }
}