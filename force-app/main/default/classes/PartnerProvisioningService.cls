// PartnerProvisioningService.cls
// Invoked by the final approval Flow. User DML cannot be mixed with
// setup/non-setup sObject DML in one transaction (MIXED_DML), so the
// user creation runs in its own async context (Queueable).
public without sharing class PartnerProvisioningService {
 
    @InvocableMethod(label='Provision Partner User')
    public static void provision(List<Id> applicationIds) {
        System.enqueueJob(new ProvisionJob(new Set<Id>(applicationIds)));
    }
 
    public class ProvisionJob implements Queueable {
        private final Set<Id> appIds;
        public ProvisionJob(Set<Id> appIds) { this.appIds = appIds; }
 
        public void execute(QueueableContext ctx) {
            List<Onboarding_Application__c> apps = [
                SELECT Id, Account__c, Primary_Contact__c,
                       Primary_Contact__r.FirstName,
                       Primary_Contact__r.LastName,
                       Primary_Contact__r.Email
                FROM Onboarding_Application__c WHERE Id IN :appIds
            ];
            Profile p = [SELECT Id FROM Profile
                         WHERE Name = 'Partner Community User' LIMIT 1];
 
            List<User> users = new List<User>();
            for (Onboarding_Application__c app : apps) {
                users.add(new User(
                    ContactId = app.Primary_Contact__c,
                    ProfileId = p.Id,
                    FirstName = app.Primary_Contact__r.FirstName,
                    LastName  = app.Primary_Contact__r.LastName,
                    Email     = app.Primary_Contact__r.Email,
                    Username  = app.Primary_Contact__r.Email
                                + '.globexpartner',
                    Alias     = ('p' + app.Id).left(8),
                    EmailEncodingKey = 'UTF-8',
                    TimeZoneSidKey   = 'Asia/Kolkata',
                    LocaleSidKey     = 'en_IN',
                    LanguageLocaleKey= 'en_US'
                ));
            }
            Database.SaveResult[] results = Database.insert(users, false);
            IntegrationLogger.logDmlFailures('User', results);
 
            // Chain the vendor callout AFTER user DML commits —
            // you cannot make a callout after DML in one transaction.
            System.enqueueJob(new OnboardingVendorSyncQueueable(appIds));
        }
    }
}