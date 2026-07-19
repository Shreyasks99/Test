// OnboardingVendorSyncQueueableTest.cls
@IsTest
private class OnboardingVendorSyncQueueableTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assertEquals('callout:Vendor_API/posts', req.getEndpoint());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"id":"VEND-42"}');
            return res;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('{"error":"bad request"}');
            return res;
        }
    }

    private static Onboarding_Application__c seedApplication() {
        Account acc = TestDataFactory.account('Vendor Sync Co');
        Contact c = TestDataFactory.contact(acc.Id, 'vendor.sync@testorg.example.com');
        return TestDataFactory.application(acc.Id, c.Id);
    }

    @IsTest
    static void execute_updatesApplicationOnSuccessfulVendorResponse() {
        Onboarding_Application__c app = seedApplication();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        new OnboardingVendorSyncQueueable(new Set<Id>{ app.Id }).execute(null);
        Test.stopTest();

        Onboarding_Application__c reloaded = [
            SELECT External_Vendor_Id__c, Stage__c FROM Onboarding_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals('VEND-42', reloaded.External_Vendor_Id__c);
        System.assertEquals('Provisioned', reloaded.Stage__c);
    }

    @IsTest
    static void execute_leavesApplicationUntouchedWhenVendorRejects() {
        Onboarding_Application__c app = seedApplication();
        String originalStage = app.Stage__c;
        Test.setMock(HttpCalloutMock.class, new FailureMock());

        Test.startTest();
        new OnboardingVendorSyncQueueable(new Set<Id>{ app.Id }).execute(null);
        Test.stopTest();

        Onboarding_Application__c reloaded = [
            SELECT External_Vendor_Id__c, Stage__c FROM Onboarding_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals(null, reloaded.External_Vendor_Id__c);
        System.assertEquals(originalStage, reloaded.Stage__c);
    }
}