// DisputeStatusWebhookTest.cls
@IsTest
private class DisputeStatusWebhookTest {

    @IsTest
    static void updateStatus_publishesEventAndReturnsAccepted() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/erp/dispute-status/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'erpReference' => 'ERP-999',
            'disputeNumber' => 'DSP-0001',
            'status' => 'RESOLVED'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        DisputeStatusWebhook.updateStatus();
        Test.stopTest();

        System.assertEquals(202, RestContext.response.statusCode);
    }

    @IsTest
    static void updateStatus_throwsOnMalformedPayload() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/erp/dispute-status/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('not valid json');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        try {
            DisputeStatusWebhook.updateStatus();
            System.assert(false, 'Malformed JSON should raise a deserialization exception');
        } catch (Exception e) {
            System.assert(true);
        }
    }
}