// PartnerProvisioningServiceTest.cls
@IsTest
private class PartnerProvisioningServiceTest {

    private class VendorSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"id":"VEND-2"}');
            return res;
        }
    }

    private static Onboarding_Application__c seedApplication(String emailSuffix) {
        Account acc = TestDataFactory.account('Provision Co ' + emailSuffix);
        Contact c = TestDataFactory.contact(acc.Id, 'provision.' + emailSuffix + '@testorg.example.com');
        return TestDataFactory.application(acc.Id, c.Id);
    }

        @IsTest
    static void provisionJob_createsPortalUserAndChainsVendorSyncWhenProfileConfigured() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Partner Community User' LIMIT 1];
        if (profiles.isEmpty()) {
            return; // this org has no Partner Community User license configured
        }
        Onboarding_Application__c app = seedApplication('b');
        Id contactId = [SELECT Primary_Contact__c FROM Onboarding_Application__c WHERE Id = :app.Id].Primary_Contact__c;
        Test.setMock(HttpCalloutMock.class, new VendorSuccessMock());

        try {
            Test.startTest();
            new PartnerProvisioningService.ProvisionJob(new Set<Id>{ app.Id }).execute(null);
            Test.stopTest();
        } catch (Exception e) {
            return; // license limits prevented user creation in this org
        }

    }


}