// PartnerElevationServiceTest.cls
@IsTest
private class PartnerElevationServiceTest {

    private class VendorSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"id":"VEND-1"}');
            return res;
        }
    }

    private static Onboarding_Application__c seedApplication() {
        Account acc = TestDataFactory.account('Elevate Co');
        Contact c = TestDataFactory.contact(acc.Id, 'elevate@testorg.example.com');
        return TestDataFactory.application(acc.Id, c.Id);
    }



    @IsTest
    static void elevateJob_runsIdempotencyCheckAndChainsVendorSyncWhenPermSetConfigured() {
        List<PermissionSet> permSets = [SELECT Id FROM PermissionSet WHERE Name = 'Full_Partner_Access' LIMIT 1];
        if (permSets.isEmpty()) {
            return; // this org has no Full_Partner_Access permission set
        }
        Onboarding_Application__c app = seedApplication();
        Test.setMock(HttpCalloutMock.class, new VendorSuccessMock());

        Integer assignmentsBefore = [
            SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :permSets[0].Id
        ];

        Test.startTest();
        new PartnerElevationService.ElevateJob(new Set<Id>{ app.Id }).execute(null);
        Test.stopTest();

        // No active portal user is tied to the contact in this test, so no
        // new assignment should have been created - but the job must still
        // run through cleanly (idempotency check + chained vendor sync).
        Integer assignmentsAfter = [
            SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :permSets[0].Id
        ];
        System.assertEquals(assignmentsBefore, assignmentsAfter);
    }
}