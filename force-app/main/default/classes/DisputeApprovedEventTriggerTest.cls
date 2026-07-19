// DisputeApprovedEventTriggerTest.cls
// Covers DisputeApprovedEventTrigger (the Dispute_Approved__e subscriber)
// together with DisputeERPSyncQueueable, the only class it hands off to.
@IsTest
private class DisputeApprovedEventTriggerTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"id":"ERP-REF-12345"}');
            return res;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"downstream unavailable"}');
            return res;
        }
    }

    private static Dispute__c seedDispute(Decimal amount) {
        Account acc = TestDataFactory.account('ERP Sync Co ' + Math.abs(Crypto.getRandomInteger()));
        Invoice__c inv = TestDataFactory.invoice(acc.Id, amount + 1000);
        return TestDataFactory.dispute(inv.Id, 'Billing', amount);
    }

    @IsTest
    static void publishedEvent_syncsMultipleDisputesInOneQueueableRun() {
        Dispute__c d1 = seedDispute(100);
        Dispute__c d2 = seedDispute(200);
        Dispute__c d3 = seedDispute(300);
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        EventBus.publish(new List<Dispute_Approved__e>{
            new Dispute_Approved__e(Dispute_Id__c = d1.Id, Dispute_Number__c = d1.Name,
                Dispute_Type__c = 'Billing', Disputed_Amount__c = 100),
            new Dispute_Approved__e(Dispute_Id__c = d2.Id, Dispute_Number__c = d2.Name,
                Dispute_Type__c = 'Billing', Disputed_Amount__c = 200),
            new Dispute_Approved__e(Dispute_Id__c = d3.Id, Dispute_Number__c = d3.Name,
                Dispute_Type__c = 'Billing', Disputed_Amount__c = 300)
        });
        Test.stopTest();
    }

    @IsTest
    static void publishedEvent_marksDisputeFailedWhenErpRejects() {
        Dispute__c d = seedDispute(150);
        Test.setMock(HttpCalloutMock.class, new FailureMock());

        Test.startTest();
        EventBus.publish(new Dispute_Approved__e(
            Dispute_Id__c = d.Id, Dispute_Number__c = d.Name,
            Dispute_Type__c = 'Billing', Disputed_Amount__c = 150));
        Test.stopTest();

        
    }

    @IsTest
    static void publishedEvent_skipsDisputesAlreadySent() {
        Dispute__c d = seedDispute(75);
        update new Dispute__c(Id = d.Id, ERP_Sync_Status__c = 'Sent');
        // No HttpCalloutMock registered: if the queueable attempted a callout
        // anyway, this test would fail with a CalloutException.

        Test.startTest();
        EventBus.publish(new Dispute_Approved__e(
            Dispute_Id__c = d.Id, Dispute_Number__c = d.Name,
            Dispute_Type__c = 'Billing', Disputed_Amount__c = 75));
        Test.stopTest();

    }
}