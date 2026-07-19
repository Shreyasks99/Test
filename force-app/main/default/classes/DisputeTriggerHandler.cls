// DisputeTriggerHandler.cls — thin dispatcher, logic lives in services
public with sharing class DisputeTriggerHandler {
 
    public void run() {
        if (Trigger.isBefore && Trigger.isInsert) {
            DisputeService.applyDefaults((List<Dispute__c>) Trigger.new);
            DisputeService.validateAgainstInvoice((List<Dispute__c>) Trigger.new);
        }
        if (Trigger.isAfter && Trigger.isInsert) {
            DisputeSharingService.shareWithApprovers((List<Dispute__c>) Trigger.new);
            DisputeApprovalService.submit(new List<Id>(Trigger.newMap.keySet()));
        }
        if (Trigger.isAfter && Trigger.isUpdate) {
            DisputeService.publishApprovedEvents((List<Dispute__c>) Trigger.new,(Map<Id, Dispute__c>) Trigger.oldMap);
        }
    }
}