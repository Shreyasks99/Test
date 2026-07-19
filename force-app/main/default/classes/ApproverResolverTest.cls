// ApproverResolverTest.cls
// ApproverResolver is a shared utility (no trigger of its own) consumed by
// DisputeApprovalRouter, DisputeApprovalService and DisputeSharingService.
// This class drives every resolver branch directly via the @TestVisible
// setRulesForTest hook, since Dispute_Approval_Rule__mdt rows cannot be
// inserted through DML in a test context.
@IsTest
private class ApproverResolverTest {

    private static Dispute_Approval_Rule__mdt rule(String type, Decimal min,
            Decimal max, String approverType, String ref) {
        return new Dispute_Approval_Rule__mdt(
            Dispute_Type__c = type,
            Min_Amount__c = min,
            Max_Amount__c = max,
            Approver_Type__c = approverType,
            Approver_Ref__c = ref);
    }

    // ---------- toId: User ----------

    @IsTest
    static void toId_user_resolvesActiveUsername() {
        String myUsername = UserInfo.getUsername();
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Billing', 0, null, 'User', myUsername)
        });

        Id resolved = ApproverResolver.toId('User', myUsername, null);

        System.assertEquals(UserInfo.getUserId(), resolved);
    }

    @IsTest
    static void toId_user_throwsWhenUsernameUnknown() {
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Billing', 0, null, 'User', 'nonexistent.user@nowhere.invalid')
        });

        try {
            ApproverResolver.toId('User', 'nonexistent.user@nowhere.invalid', null);
            System.assert(false, 'Expected a ResolverException for an unknown username');
        } catch (ApproverResolver.ResolverException e) {
            System.assert(e.getMessage().contains('No active user'));
        }
    }

    // ---------- toId: Queue ----------

    @IsTest
    static void toId_queue_throwsWhenDeveloperNameUnknown() {
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Billing', 0, null, 'Queue', 'No_Such_Queue_Dev_Name')
        });

        try {
            ApproverResolver.toId('Queue', 'No_Such_Queue_Dev_Name', null);
            System.assert(false, 'Expected a ResolverException for an unknown queue');
        } catch (ApproverResolver.ResolverException e) {
            System.assert(e.getMessage().contains('No queue'));
        }
    }

    @IsTest
    static void toId_queue_resolvesRealQueueWhenAvailable() {
        List<Group> queues = [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' LIMIT 1];
        if (queues.isEmpty()) {
            return; // no queue configured in this org; negative path already covered above
        }
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Billing', 0, null, 'Queue', queues[0].DeveloperName)
        });

        Id resolved = ApproverResolver.toId('Queue', queues[0].DeveloperName, null);

        System.assertEquals(queues[0].Id, resolved);
    }

    // ---------- toId: Role ----------

    @IsTest
    static void toId_role_throwsWhenDeveloperNameUnknown() {
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Billing', 0, null, 'Role', 'No_Such_Role_Dev_Name')
        });

        try {
            ApproverResolver.toId('Role', 'No_Such_Role_Dev_Name', null);
            System.assert(false, 'Expected a ResolverException for an unknown role group');
        } catch (ApproverResolver.ResolverException e) {
            System.assert(e.getMessage().contains('No role group'));
        }
    }

    @IsTest
    static void toId_role_resolvesRealRoleGroupWhenAvailable() {
        List<Group> roleGroups = [SELECT Id, DeveloperName FROM Group WHERE Type = 'Role' LIMIT 1];
        if (roleGroups.isEmpty()) {
            return; // no role configured in this org; negative path already covered above
        }
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Billing', 0, null, 'Role', roleGroups[0].DeveloperName)
        });

        Id resolved = ApproverResolver.toId('Role', roleGroups[0].DeveloperName, null);

        System.assertEquals(roleGroups[0].Id, resolved);
    }

    // ---------- toId: Manager ----------

    @IsTest
    static void toId_manager_returnsNullWhenDisputeIdIsNull() {
        System.assertEquals(null, ApproverResolver.toId('Manager', 'ignored', null));
    }

    @IsTest
    static void toId_manager_returnsNullWhenDisputeNoLongerExists() {
        Account acc = TestDataFactory.account('Manager Resolve Co');
        Invoice__c inv = TestDataFactory.invoice(acc.Id, 500);
        Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 100);
        Id deletedId = d.Id;
        delete d;

        System.assertEquals(null, ApproverResolver.toId('Manager', 'ignored', deletedId));
    }

    @IsTest
    static void toId_manager_resolvesOwningUsersManager() {
        Account acc = TestDataFactory.account('Manager Resolve Co 2');
        Invoice__c inv = TestDataFactory.invoice(acc.Id, 500);
        Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 100); // owned by running user by default

        Id expectedManagerId = [SELECT ManagerId FROM User WHERE Id = :UserInfo.getUserId()].ManagerId;

        Id resolved = ApproverResolver.toId('Manager', 'ignored', d.Id);

        System.assertEquals(expectedManagerId, resolved,
            'Resolver should return the current owning user\'s ManagerId, whatever that is');
    }

    // ---------- toId: unknown type ----------

    @IsTest
    static void toId_throwsOnUnknownApproverType() {
        try {
            ApproverResolver.toId('Bogus', 'ref', null);
            System.assert(false, 'Expected a ResolverException for an unrecognized approver type');
        } catch (ApproverResolver.ResolverException e) {
            System.assert(e.getMessage().contains('Unknown Approver_Type__c'));
        }
    }

    // ---------- forDispute ----------

    @IsTest
    static void forDispute_resolvesFromFirstMatchingRuleByAmountAndType() {
        String myUsername = UserInfo.getUsername();
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Billing', 0, 50, 'User', 'unused.low.band@nowhere.invalid'),
            rule('Billing', 50, null, 'User', myUsername),
            rule('Any', 0, null, 'User', myUsername)
        });
        Account acc = TestDataFactory.account('ForDispute Co');
        Invoice__c inv = TestDataFactory.invoice(acc.Id, 500);
        Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 100);

        Id resolved = ApproverResolver.forDispute(d);

        System.assertEquals(UserInfo.getUserId(), resolved,
            'Should match the 50+ band rule, not the 0-50 band or the catch-all "Any" rule');
    }

    @IsTest
    static void forDispute_returnsNullWhenNoRuleMatches() {
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Refund', 0, null, 'User', UserInfo.getUsername())
        });
        Account acc = TestDataFactory.account('ForDispute Co 2');
        Invoice__c inv = TestDataFactory.invoice(acc.Id, 500);
        Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 100);

        System.assertEquals(null, ApproverResolver.forDispute(d));
    }

    @IsTest
    static void forDispute_swallowsResolverExceptionAndReturnsNull() {
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>{
            rule('Billing', 0, null, 'Queue', 'No_Such_Queue_Dev_Name')
        });
        Account acc = TestDataFactory.account('ForDispute Co 3');
        Invoice__c inv = TestDataFactory.invoice(acc.Id, 500);
        Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 100);

        System.assertEquals(null, ApproverResolver.forDispute(d),
            'A misconfigured rule must not block dispute DML; forDispute should swallow the exception');
    }
}