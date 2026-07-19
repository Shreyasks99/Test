// DisputeApprovalRouter.cls — dynamic approver from Custom Metadata
// Invoked by the approval-submission Flow (@InvocableMethod), so routing
// rules are DATA (deployable CMDT records), not hard-coded logic.
public with sharing class DisputeApprovalRouter {
 
    public class RouteRequest {
        @InvocableVariable(required=true) public Id disputeId;
        @InvocableVariable(required=true) public String disputeType;
        @InvocableVariable(required=true) public Decimal amount;
    }
    public class RouteResult {
        @InvocableVariable public Id approverId;      // User to route to
        @InvocableVariable public String approverType; // User | Queue
    }
 
    @InvocableMethod(label='Resolve Dispute Approver')
    public static List<RouteResult> resolve(List<RouteRequest> requests) {
        // CMDT: Dispute_Approval_Rule__mdt
        //   Dispute_Type__c, Min_Amount__c, Max_Amount__c,
        //   Approver_Type__c (User/Queue/Manager), Approver_Ref__c (username/queue devname)
        List<Dispute_Approval_Rule__mdt> rules = [
            SELECT Dispute_Type__c, Min_Amount__c, Max_Amount__c,
                   Approver_Type__c, Approver_Ref__c
            FROM Dispute_Approval_Rule__mdt ORDER BY Min_Amount__c ASC
        ];
        List<RouteResult> out = new List<RouteResult>();
        for (RouteRequest req : requests) {
            RouteResult res = new RouteResult();
            for (Dispute_Approval_Rule__mdt r : rules) {
                Boolean typeOk = r.Dispute_Type__c == req.disputeType
                              || r.Dispute_Type__c == 'Any';
                Boolean amtOk  = req.amount >= r.Min_Amount__c
                              && (r.Max_Amount__c == null
                                  || req.amount < r.Max_Amount__c);
                if (typeOk && amtOk) {
                    res.approverType = r.Approver_Type__c;
                    res.approverId = ApproverResolver.toId(
                        r.Approver_Type__c, r.Approver_Ref__c, req.disputeId);
                    break;
                }
            }
            out.add(res);
        }
        return out;
    }
}