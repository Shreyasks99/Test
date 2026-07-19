/** 
 * ApproverResolver.cls
 * Translates the approver defined in Dispute_Approval_Rule__mdt
 * (plain text: username / queue name / role name / "Manager")
 * into a concrete Id usable by:
 *   - DisputeApprovalRouter  -> approval routing (User/Queue Id)
 *   - DisputeSharingService  -> Dispute__Share.UserOrGroupId
 *
 * Bulk-safe: all lookup sources are cached statically, so 200 calls
 * in one transaction cost at most a handful of queries.
 * Update code test git
 */
public without sharing class ApproverResolver {

    // ---------- per-transaction caches ----------
    private static List<Dispute_Approval_Rule__mdt> rulesCache;
    private static Map<String, Id> queueIdByDevName;
    private static Map<String, Id> userIdByUsername;
    private static Map<String, Id> roleGroupByDevName;

    public class ResolverException extends Exception {}

    // =========================================================
    // Entry point 1 — DisputeApprovalRouter (@InvocableMethod)
    // Throws on misconfiguration: the Flow SHOULD fail loudly.
    // =========================================================
    public static Id toId(String approverType, String approverRef, Id disputeId) {
        switch on approverType {
            when 'User'    { return resolveUser(approverRef); }
            when 'Queue'   { return resolveQueue(approverRef); }
            when 'Role'    { return resolveRoleGroup(approverRef); }
            when 'Manager' { return resolveOwnerManager(disputeId); }
            when else {
                throw new ResolverException(
                    'Unknown Approver_Type__c: ' + approverType);
            }
        }
    }

    // =========================================================
    // Entry point 2 — DisputeSharingService (trigger context)
    // Returns null on misconfiguration: sharing must never
    // block the dispute DML itself.
    // =========================================================
    public static Id forDispute(Dispute__c d) {
        for (Dispute_Approval_Rule__mdt r : rules()) {
            Boolean typeOk = r.Dispute_Type__c == d.Type__c
                          || r.Dispute_Type__c == 'Any';
            Boolean amtOk  = d.Disputed_Amount__c >= r.Min_Amount__c
                          && (r.Max_Amount__c == null
                              || d.Disputed_Amount__c < r.Max_Amount__c);
            if (typeOk && amtOk) {
                try {
                    return toId(r.Approver_Type__c, r.Approver_Ref__c, d.Id);
                } catch (ResolverException e) {
                    return null;
                }
            }
        }
        return null; // no matching rule
    }

    // ---------------------------------------------------------
    // Resolvers — each lazy-loads its cache exactly once
    // ---------------------------------------------------------
    private static Id resolveUser(String username) {
        if (userIdByUsername == null) {
            userIdByUsername = new Map<String, Id>();
            for (User u : [SELECT Id, Username FROM User
                           WHERE Username IN :refsOfType('User')
                             AND IsActive = true]) {
                userIdByUsername.put(u.Username, u.Id);
            }
        }
        Id result = userIdByUsername.get(username);
        if (result == null) {
            throw new ResolverException('No active user: ' + username);
        }
        return result;
    }

    private static Id resolveQueue(String queueDevName) {
        if (queueIdByDevName == null) {
            queueIdByDevName = new Map<String, Id>();
            for (Group g : [SELECT Id, DeveloperName FROM Group
                            WHERE Type = 'Queue'
                              AND DeveloperName IN :refsOfType('Queue')]) {
                queueIdByDevName.put(g.DeveloperName, g.Id);
            }
        }
        Id result = queueIdByDevName.get(queueDevName);
        if (result == null) {
            throw new ResolverException('No queue: ' + queueDevName);
        }
        return result;
    }

    // Returns the ROLE GROUP Id — valid for Dispute__Share.UserOrGroupId.
    // (Approval steps can't target a role; use User/Queue rules for routing.)
    private static Id resolveRoleGroup(String roleDevName) {
        if (roleGroupByDevName == null) {
            roleGroupByDevName = new Map<String, Id>();
            for (Group g : [SELECT Id, DeveloperName FROM Group
                            WHERE Type = 'Role'
                              AND DeveloperName IN :refsOfType('Role')]) {
                roleGroupByDevName.put(g.DeveloperName, g.Id);
            }
        }
        Id result = roleGroupByDevName.get(roleDevName);
        if (result == null) {
            throw new ResolverException('No role group: ' + roleDevName);
        }
        return result;
    }

    // FIXED: Owner is polymorphic (User OR Queue), so SOQL cannot
    // traverse Owner.ManagerId — it resolves to the generic 'Name'
    // entity which has no ManagerId. Fetch OwnerId first, confirm
    // it's a User, then query User.ManagerId directly.
    private static Id resolveOwnerManager(Id disputeId) {
        if (disputeId == null) { return null; }

        List<Dispute__c> rows = [
            SELECT OwnerId FROM Dispute__c
            WHERE Id = :disputeId LIMIT 1
        ];
        if (rows.isEmpty()) { return null; }

        Id ownerId = rows[0].OwnerId;
        if (ownerId.getSobjectType() != User.SObjectType) {
            return null; // queue-owned: queues have no manager
        }

        List<User> owners = [
            SELECT ManagerId FROM User
            WHERE Id = :ownerId LIMIT 1
        ];
        return owners.isEmpty() ? null : owners[0].ManagerId;
    }

    // ---------------------------------------------------------
    // Shared helpers
    // ---------------------------------------------------------
    private static List<Dispute_Approval_Rule__mdt> rules() {
        if (rulesCache == null) {
            rulesCache = [
                SELECT Dispute_Type__c, Min_Amount__c, Max_Amount__c,
                       Approver_Type__c, Approver_Ref__c
                FROM Dispute_Approval_Rule__mdt
                ORDER BY Min_Amount__c ASC
            ];
        }
        return rulesCache;
    }

    private static Set<String> refsOfType(String approverType) {
        Set<String> refs = new Set<String>();
        for (Dispute_Approval_Rule__mdt r : rules()) {
            if (r.Approver_Type__c == approverType) {
                refs.add(r.Approver_Ref__c);
            }
        }
        return refs;
    }

    // CMDT records can't be inserted in tests — tests inject rules here
    @TestVisible
    private static void setRulesForTest(List<Dispute_Approval_Rule__mdt> testRules) {
        rulesCache = testRules;
    }
}