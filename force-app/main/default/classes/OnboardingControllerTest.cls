// OnboardingControllerTest.cls
@IsTest
private class OnboardingControllerTest {

    private static Onboarding_Application__c seedApplication() {
        Account acc = TestDataFactory.account('Onboarding Ctrl Co');
        Contact c = TestDataFactory.contact(acc.Id, 'onboarding.ctrl@testorg.example.com');
        return TestDataFactory.application(acc.Id, c.Id);
    }

    @IsTest
    static void getStatus_returnsStepsAndDocumentsForGivenApplication() {
        Onboarding_Application__c app = seedApplication();
        insert new Onboarding_Step__c(
            Onboarding_Application__c = app.Id, Step_Type__c = 'KYC',
            Status__c = 'Not Started', Sequence__c = 1);
        insert new Document_Requirement__c(
            Onboarding_Application__c = app.Id, Document_Type__c = 'W-9',
            Status__c = 'Awaiting');

        Test.startTest();
        OnboardingController.StatusDTO dto = OnboardingController.getStatus(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto);
        System.assertEquals(app.Id, dto.applicationId);
        System.assertEquals(1, dto.steps.size());
        System.assertEquals('KYC', dto.steps[0].stepType);
        System.assertEquals(1, dto.documents.size());
        System.assertEquals('W-9', dto.documents[0].documentType);
        System.assertEquals(false, dto.documents[0].isUploaded, 'Awaiting status means not yet uploaded');
    }

    @IsTest
    static void getStatus_marksDocumentUploadedWhenStatusIsNotAwaiting() {
        Onboarding_Application__c app = seedApplication();
        insert new Document_Requirement__c(
            Onboarding_Application__c = app.Id, Document_Type__c = 'W-9',
            Status__c = 'Uploaded');

        OnboardingController.StatusDTO dto = OnboardingController.getStatus(app.Id);

        System.assertEquals(true, dto.documents[0].isUploaded);
    }

    @IsTest
    static void getStatus_returnsNullWhenNoIdGivenAndRunningUserHasNoMatchingApplication() {
        // The running test user isn't a portal user tied to any Onboarding_Application__c,
        // so findMyApplicationId() should come back empty and getStatus should return null.
        System.assertEquals(null, OnboardingController.getStatus(null));
    }

    @IsTest
    static void getStatus_returnsNullForUnknownApplicationId() {
        Onboarding_Application__c app = seedApplication();
        Id deletedId = app.Id;
        delete app;

        System.assertEquals(null, OnboardingController.getStatus(deletedId));
    }

    @IsTest
    static void registerUpload_marksRequirementUploadedWithDocumentId() {
        Onboarding_Application__c app = seedApplication();
        Document_Requirement__c req = new Document_Requirement__c(
            Onboarding_Application__c = app.Id, Document_Type__c = 'W-9', Status__c = 'Awaiting');
        insert req;

        ContentVersion cv = new ContentVersion(
            Title = 'W9', PathOnClient = 'w9.pdf', VersionData = Blob.valueOf('pdf bytes'));
        insert cv;
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        Test.startTest();
        OnboardingController.registerUpload(req.Id, contentDocumentId);
        Test.stopTest();

        Document_Requirement__c reloaded = [
            SELECT Status__c, ContentDocumentId__c FROM Document_Requirement__c WHERE Id = :req.Id
        ];
        System.assertEquals('Uploaded', reloaded.Status__c);
        System.assertEquals(contentDocumentId, reloaded.ContentDocumentId__c);
    }

    @IsTest
    static void registerUpload_throwsWhenParametersMissing() {
        try {
            OnboardingController.registerUpload(null, null);
            System.assert(false, 'Expected an AuraHandledException for missing parameters');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void registerUpload_throwsWhenRequirementNotFound() {
        Onboarding_Application__c app = seedApplication();
        Document_Requirement__c req = new Document_Requirement__c(
            Onboarding_Application__c = app.Id, Document_Type__c = 'W-9', Status__c = 'Awaiting');
        insert req;
        Id deletedReqId = req.Id;
        delete req;

        try {
            OnboardingController.registerUpload(deletedReqId, UserInfo.getUserId());
            System.assert(false, 'Expected an AuraHandledException for a missing requirement');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}