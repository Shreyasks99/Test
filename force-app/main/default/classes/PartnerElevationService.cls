/**
 * PartnerElevationService.cls
 * On final approval: assign the Full Partner Access permission set
 * to the applicant's portal user. Async because
 * PermissionSetAssignment is a setup object (MIXED_DML).
 */
public without sharing class PartnerElevationService {

    private static final String PERM_SET_NAME = 'Full_Partner_Access';

    @InvocableMethod(label='Elevate to Full Partner')
    public static void elevate(List<Id> applicationIds) {
        System.enqueueJob(new ElevateJob(new Set<Id>(applicationIds)));
    }

    public class ElevateJob implements Queueable {
        private final Set<Id> appIds;
        public ElevateJob(Set<Id> appIds) { this.appIds = appIds; }

        public void execute(QueueableContext ctx) {
            // application -> contact -> user
            Set<Id> contactIds = new Set<Id>();
            for (Onboarding_Application__c a : [
                    SELECT Primary_Contact__c
                    FROM Onboarding_Application__c WHERE Id IN :appIds]) {
                contactIds.add(a.Primary_Contact__c);
            }
            Map<Id, Id> userByContact = new Map<Id, Id>();
            for (User u : [SELECT Id, ContactId FROM User
                           WHERE ContactId IN :contactIds AND IsActive = true]) { userByContact.put(u.ContactId, u.Id);
            }

            PermissionSet ps = [SELECT Id FROM PermissionSet
                                WHERE Name = :PERM_SET_NAME LIMIT 1];

            // Idempotency: don't double-assign (insert would fail)
            Set<Id> alreadyAssigned = new Set<Id>();
            for (PermissionSetAssignment psa : [
                    SELECT AssigneeId FROM PermissionSetAssignment
                    WHERE PermissionSetId = :ps.Id
                      AND AssigneeId IN :userByContact.values()]) { alreadyAssigned.add(psa.AssigneeId);
            }

            List<PermissionSetAssignment> assignments =
                new List<PermissionSetAssignment>();
            for (Id userId : userByContact.values()) {
                if (!alreadyAssigned.contains(userId)) { assignments.add(new PermissionSetAssignment(AssigneeId = userId,PermissionSetId = ps.Id));
                }
            }
            if (!assignments.isEmpty()) {
                Database.SaveResult[] results = Database.insert(assignments, false); IntegrationLogger.logDmlFailures('PermissionSetAssignment', results);
            }

            System.enqueueJob(new OnboardingVendorSyncQueueable(appIds));
        }
    }
}