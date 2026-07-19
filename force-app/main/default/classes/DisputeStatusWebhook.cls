// DisputeStatusWebhook.cls — inbound status update from ERP
// Exposed on a public site / Experience Cloud with IP allow-listing,
// or called by middleware authenticated via Connected App (preferred).
@RestResource(urlMapping='/erp/dispute-status/*')
global with sharing class DisputeStatusWebhook {
 
    global class StatusPayload {
        public String erpReference;
        public String disputeNumber;
        public String status; // ACKNOWLEDGED / RESOLVED / REJECTED
    }
 
    @HttpPost
    global static void updateStatus() {
        StatusPayload p = (StatusPayload) JSON.deserialize(
            RestContext.request.requestBody.toString(), StatusPayload.class);
 
        // Publish a Platform Event instead of direct DML:
        // decouples the webhook from row locks and lets the
        // subscriber apply business rules in one place.
        EventBus.publish(new Dispute_Status_Update__e(
            Dispute_Number__c = p.disputeNumber,
            ERP_Reference__c  = p.erpReference,
            New_Status__c     = p.status));
        RestContext.response.statusCode = 202; // accepted
    }
}