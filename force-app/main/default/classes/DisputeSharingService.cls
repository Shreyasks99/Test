// DisputeSharingService.cls — Apex Managed Sharing
// OWD for Dispute__c = Private. Owner gets full access implicitly;
// approvers get Edit via a custom Apex sharing reason so the grant
// survives ownership changes (unlike manual shares).
public without sharing class DisputeSharingService {
 
    // Apex sharing reason defined on Dispute__c: Approver_Access__c
    public static void shareWithApprovers(List<Dispute__c> disputes) {
        List<Dispute__Share> shares = new List<Dispute__Share>();
        // Resolve the approver for each dispute from the same CMDT
        // routing table used by the approval process.
        for (Dispute__c d : disputes) {
            Id approverId = ApproverResolver.forDispute(d);
            if (approverId == null || approverId == d.OwnerId) { continue; }
            shares.add(new Dispute__Share(
                ParentId      = d.Id,
                UserOrGroupId = approverId,
                AccessLevel   = 'Edit',
                RowCause      = Schema.Dispute__Share.RowCause.Approver_Access__c
            ));
        }
        // Partial success: one bad row must not block the batch
        Database.SaveResult[] results = Database.insert(shares, false);
        IntegrationLogger.logDmlFailures('Dispute__Share', results);
    }
}