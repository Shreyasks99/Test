// OnboardingVendorSyncQueueable.cls — 3rd-party notification
public class OnboardingVendorSyncQueueable
        implements Queueable, Database.AllowsCallouts {
 
    private final Set<Id> appIds;
    public OnboardingVendorSyncQueueable(Set<Id> appIds) {
        this.appIds = appIds;
    }
 
    public void execute(QueueableContext ctx) {
        List<Onboarding_Application__c> apps = [
            SELECT Id, Name, Account__r.Name, Stage__c
            FROM Onboarding_Application__c WHERE Id IN :appIds
        ];
        List<Onboarding_Application__c> updates =
            new List<Onboarding_Application__c>();
 
        for (Onboarding_Application__c app : apps) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Vendor_API/posts');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(20000);
            req.setBody(JSON.serialize(new Map<String, Object>{
                'partnerName' => app.Account__r.Name,
                'application' => app.Name,
                'status'      => 'PROVISIONED'
            }));
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() < 300) {
                Map<String, Object> body = (Map<String, Object>)
                    JSON.deserializeUntyped(res.getBody());
                updates.add(new Onboarding_Application__c(
                    Id = app.Id,
                    External_Vendor_Id__c = String.valueOf(body.get('id')),
                    Stage__c = 'Provisioned'));
            }
        }
        if (!updates.isEmpty()) { update updates; } // DML after callouts
    }
}