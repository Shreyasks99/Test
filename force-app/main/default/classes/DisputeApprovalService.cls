/**
 * DisputeApprovalService.cls
 * Stamps the dynamically-resolved approver on the record, then
 * submits it into the standard Approval Process. Callable from a
 * Flow/Quick Action (@InvocableMethod) or from the trigger.
 */
public with sharing class DisputeApprovalService {

    private static final String PROCESS_API_NAME = 'Dispute_Approval';

    @InvocableMethod(label='Submit Dispute for Approval')
    public static void submit(List<Id> disputeIds) {
        Id approverId;
        List<Dispute__c> disputes = [
            SELECT Id, Type__c, Disputed_Amount__c, Status__c, OwnerId
            FROM Dispute__c
            WHERE Id IN :disputeIds
        ];

        // 1) Resolve + stamp the approver (bulk-safe via cached resolver)
        List<Dispute__c> toStamp = new List<Dispute__c>();
        for (Dispute__c d : disputes) {
            approverId = ApproverResolver.forDispute(d);
            if (approverId == null
                    || approverId.getSobjectType() != User.SObjectType) {
                d.addError('No user approver could be resolved — '
                    + 'check Dispute_Approval_Rule__mdt records.');
                continue;
            }
            toStamp.add(new Dispute__c(Id = d.Id,
                Approver__c = approverId));
        }
        if (toStamp.isEmpty()) { return; }
        update toStamp; // must commit BEFORE submit so the step
                        // reads the related-user field correctly

        // 2) Submit — one bulk Approval.process call, never in a loop
        List<Approval.ProcessSubmitRequest> requests =
            new List<Approval.ProcessSubmitRequest>();
        for (Dispute__c d : toStamp) {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(d.Id);
            req.setComments('Auto-submitted: dynamic routing by amount/type');
            req.setSkipEntryCriteria(false);
            req.setNextApproverIds(new Id[] { approverId });
            requests.add(req);
        }
        List<Approval.ProcessResult> results =
            Approval.process(requests, false); // partial success

        // 3) Log anything that bounced
        for (Approval.ProcessResult r : results) {
            if (!r.isSuccess()) {
                System.debug(LoggingLevel.ERROR,
                    'Approval submit failed: ' + r.getErrors());
            }
        }
    }
}