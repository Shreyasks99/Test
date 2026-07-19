public with sharing class OnboardingController {

    // ---------- DTOs ----------
    public class StatusDTO {
        @AuraEnabled public Id applicationId;
        @AuraEnabled public String applicationName;
        @AuraEnabled public String stage;
        @AuraEnabled public Boolean isFullPartner;
        @AuraEnabled public List<StepDTO> steps;
        @AuraEnabled public List<DocDTO> documents;
    }
    public class StepDTO {
        @AuraEnabled public String stepType;
        @AuraEnabled public String status;
        @AuraEnabled public Integer sequence;
    }
    public class DocDTO {
        @AuraEnabled public Id requirementId;
        @AuraEnabled public String documentType;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isUploaded;
    }

    // ---------- READ ----------
    @AuraEnabled(cacheable=true)
    public static StatusDTO getStatus(Id applicationId) {
        Id appId = applicationId != null
                 ? applicationId
                 : findMyApplicationId();
        if (appId == null) { return null; }
        
        List<Onboarding_Application__c> apps = [
            SELECT Id, Name, Stage__c,
                (SELECT Step_Type__c, Status__c, Sequence__c
                 FROM Onboarding_Steps__r ORDER BY Sequence__c ASC),
                (SELECT Id, Document_Type__c, Status__c
                 FROM Document_Requirements__r
                 ORDER BY Document_Type__c ASC)
            FROM Onboarding_Application__c
            WHERE Id = :appId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apps.isEmpty()) { return null; }

        Onboarding_Application__c app = apps[0];
        StatusDTO dto = new StatusDTO();
        dto.applicationId   = app.Id;
        dto.applicationName = app.Name;
        dto.stage           = app.Stage__c;
        dto.isFullPartner = FeatureManagement.checkPermission(
                        'Full_Partner_Access');

        dto.steps = new List<StepDTO>();
        for (Onboarding_Step__c s : app.Onboarding_Steps__r) {
            StepDTO sd = new StepDTO();
            sd.stepType = s.Step_Type__c;
            sd.status   = s.Status__c;
            sd.sequence = s.Sequence__c == null
                          ? 0 : Integer.valueOf(s.Sequence__c);
            dto.steps.add(sd);
        }

        dto.documents = new List<DocDTO>();
        for (Document_Requirement__c dr : app.Document_Requirements__r) {
            DocDTO dd = new DocDTO();
            dd.requirementId = dr.Id;
            dd.documentType  = dr.Document_Type__c;
            dd.status        = dr.Status__c;
            dd.isUploaded    = dr.Status__c != 'Awaiting';
            dto.documents.add(dd);
        }
        return dto;
    }

    // ---------- WRITE ----------
    @AuraEnabled
    public static void registerUpload(Id requirementId,
                                      Id contentDocumentId) {
        if (requirementId == null || contentDocumentId == null) {
            throw new AuraHandledException('Missing upload parameters.');
        }
        // Never trust client-supplied Ids — sharing decides access
        List<Document_Requirement__c> reqs = [
            SELECT Id FROM Document_Requirement__c
            WHERE Id = :requirementId
            WITH USER_MODE
            LIMIT 1
        ];
        if (reqs.isEmpty()) {
            throw new AuraHandledException(
                'Document requirement not found or not accessible.');
        }
        // File lockdown (ShareType 'V') is enforced by the
        // ContentDocumentLink trigger at link creation.
        update as user new Document_Requirement__c(
            Id                   = requirementId,
            Status__c            = 'Uploaded',
            ContentDocumentId__c = contentDocumentId);
    }

    // ---------- private ----------
    private static Id findMyApplicationId() {
        List<User> me = [
            SELECT ContactId FROM User
            WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        if (me.isEmpty() || me[0].ContactId == null) { return null; }
        List<Onboarding_Application__c> apps = [
            SELECT Id FROM Onboarding_Application__c
            WHERE Primary_Contact__c = :me[0].ContactId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return apps.isEmpty() ? null : apps[0].Id;
    }
}