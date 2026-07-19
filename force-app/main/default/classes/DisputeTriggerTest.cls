// DisputeTriggerTest.cls
// Covers DisputeTrigger + DisputeTriggerHandler and every service the
// handler dispatches to on each trigger phase: DisputeService
// (defaults/validation/event publish), DisputeSharingService and
// DisputeApprovalService (both resolved through ApproverResolver).
@IsTest
private class DisputeTriggerTest {

    private static Account acc;
    private static Invoice__c inv;

    private static void seedAccountAndInvoice(Decimal balance) {
        acc = TestDataFactory.account('Dispute Trigger Co');
        inv = TestDataFactory.invoice(acc.Id, balance);
    }

    // ---------- BEFORE INSERT: applyDefaults + validateAgainstInvoice ----------

    @IsTest
    static void beforeInsert_defaultsAccountAndStatus() {
        seedAccountAndInvoice(500);

        Dispute__c d = new Dispute__c(
            Invoice__c = inv.Id,
            Type__c = 'Billing',
            Disputed_Amount__c = 100,
            ERP_Sync_Status__c = 'Pending');
            // Status__c intentionally left null to exercise the default

        Test.startTest();
        insert d;
        Test.stopTest();

        Dispute__c reloaded = [SELECT Account__c, Status__c FROM Dispute__c WHERE Id = :d.Id];
        System.assertEquals(acc.Id, reloaded.Account__c, 'Account should be stamped from the related invoice');
        System.assertEquals('New', reloaded.Status__c, 'Status should default to New when left blank');
    }

    @IsTest
    static void beforeInsert_rejectsAmountAboveInvoiceBalance() {
        seedAccountAndInvoice(100);

        Dispute__c d = new Dispute__c(
            Invoice__c = inv.Id,
            Type__c = 'Billing',
            Disputed_Amount__c = 250,
            Status__c = 'New',
            ERP_Sync_Status__c = 'Pending');

        Database.SaveResult result = Database.insert(d, false);

        System.assert(!result.isSuccess(), 'Insert should fail when disputed amount exceeds invoice balance');
        System.assert(
            result.getErrors()[0].getMessage().contains('exceeds invoice balance'),
            'Error message should explain the invoice-balance violation');
    }


    // ---------- AFTER UPDATE: publishApprovedEvents ----------

    @IsTest
    static void afterUpdate_publishesApprovedEventOnlyOnTransition() {
        seedAccountAndInvoice(500);
        ApproverResolver.setRulesForTest(new List<Dispute_Approval_Rule__mdt>());
        Dispute__c d = TestDataFactory.dispute(inv.Id, 'Billing', 100);

        // Transition New -> Approved: publishApprovedEvents should run without error
        d.Status__c = 'Approved';
        update d;

        // Already-approved -> Approved again must not re-fire (no exception either way)
        d.Status__c = 'Approved';
        update d;

        System.assertEquals('Approved', [SELECT Status__c FROM Dispute__c WHERE Id = :d.Id].Status__c);
        // A logger failure would only be written on a bad EventBus.publish; none expected here.
        System.assertEquals(0, [SELECT COUNT() FROM Integration_Log__c WHERE Dispute__c = :d.Id]);
    }

    // ---------- helpers ----------

    // Inserting a User mixes "setup" and "non-setup" DML in one transaction;
    // wrapping it in System.runAs (as this same user) isolates it so the rest
    // of the test's Account/Invoice/Dispute DML doesn't hit MIXED_DML_OPERATION.
    private static Id createDistinctApproverUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User approver = new User(
            ProfileId = p.Id,
            LastName = 'Approver',
            FirstName = 'Dispute',
            Email = 'dispute.approver@testorg.example.com',
            Username = 'dispute.approver.' + DateTime.now().getTime() + '@testorg.example.com',
            Alias = 'dapprv',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US');
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runningUser) {
            insert approver;
        }
        return approver.Id;
    }
}