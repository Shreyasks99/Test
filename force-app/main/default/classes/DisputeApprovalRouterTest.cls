// DisputeApprovalRouterTest.cls
// DisputeApprovalRouter is invoked by the approval-submission Flow, not by
// a trigger, so it gets its own test class. Unlike ApproverResolverTest,
// this class cannot inject fake CMDT rows (the router queries
// Dispute_Approval_Rule__mdt directly rather than through
// ApproverResolver's cache), so assertions stay structural/deterministic
// rather than asserting a specific approver identity.
@IsTest
private class DisputeApprovalRouterTest {

    @IsTest
    static void resolve_returnsOneResultPerRequest_bulkSafe() {
        Account acc = TestDataFactory.account('Router Co');
        Invoice__c inv = TestDataFactory.invoice(acc.Id, 5000);

        List<DisputeApprovalRouter.RouteRequest> requests =
            new List<DisputeApprovalRouter.RouteRequest>();
        for (Integer i = 0; i < 5; i++) {
            Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 10 + i);
            DisputeApprovalRouter.RouteRequest req = new DisputeApprovalRouter.RouteRequest();
            req.disputeId = d.Id;
            req.disputeType = 'Billing';
            req.amount = 10 + i;
            requests.add(req);
        }

        Test.startTest();
        List<DisputeApprovalRouter.RouteResult> results = DisputeApprovalRouter.resolve(requests);
        Test.stopTest();

        System.assertEquals(requests.size(), results.size(),
            'Exactly one RouteResult must come back per RouteRequest');
        for (DisputeApprovalRouter.RouteResult r : results) {
            // approverType/approverId are only populated together, or not at all
            System.assertEquals(r.approverType != null, r.approverId != null,
                'approverType and approverId must be resolved (or unresolved) together');
        }
    }

    @IsTest
    static void resolve_leavesResultEmptyWhenNoRuleCanPossiblyMatch() {
        Account acc = TestDataFactory.account('Router Co 2');
        Invoice__c inv = TestDataFactory.invoice(acc.Id, 5000);
        Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 1);

        DisputeApprovalRouter.RouteRequest req = new DisputeApprovalRouter.RouteRequest();
        req.disputeId = d.Id;
        req.disputeType = 'Billing';
        req.amount = -999999; // below any sane Min_Amount__c, so no rule can match

        List<DisputeApprovalRouter.RouteResult> results =
            DisputeApprovalRouter.resolve(new List<DisputeApprovalRouter.RouteRequest>{ req });

        System.assertEquals(1, results.size());
        System.assertEquals(null, results[0].approverId);
        System.assertEquals(null, results[0].approverType);
    }
}