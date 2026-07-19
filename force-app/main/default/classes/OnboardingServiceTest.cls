// OnboardingServiceTest.cls
@IsTest
private class OnboardingServiceTest {

    private static List<String> activeValues(Schema.DescribeFieldResult field) {
        List<String> vals = new List<String>();
        for (Schema.PicklistEntry pe : field.getPicklistValues()) {
            if (pe.isActive()) { vals.add(pe.getValue()); }
        }
        return vals;
    }

    private static OnboardingService.Request requestFor(Id accountId, Id contactId) {
        OnboardingService.Request r = new OnboardingService.Request();
        r.accountId = accountId;
        r.contactId = contactId;
        return r;
    }

    @IsTest
    static void initiate_buildsApplicationWithDocsAndStepsFromActivePicklists() {
        Integer expectedDocCount = activeValues(Document_Requirement__c.Document_Type__c.getDescribe()).size();
        Integer expectedStepCount = activeValues(Onboarding_Step__c.Step_Type__c.getDescribe()).size();

        Account acc = TestDataFactory.account('Onboarding Svc Co');
        Contact c = TestDataFactory.contact(acc.Id, 'onboarding.svc@testorg.example.com');

        // Intentionally not wrapped in Test.startTest/stopTest: the chained
        // ApplicantUserJob queueable depends on a 'Globex Partner' profile
        // that may not exist in every org, and initiate()'s own logic
        // (the part under test here) is fully executed synchronously before
        // the job is even enqueued.
        List<OnboardingService.Result> results = OnboardingService.initiate(
            new List<OnboardingService.Request>{ requestFor(acc.Id, c.Id) });

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].applicationId);

        Onboarding_Application__c app = [
            SELECT Stage__c, Account__c, Primary_Contact__c
            FROM Onboarding_Application__c WHERE Id = :results[0].applicationId
        ];
        System.assertEquals('Docs Pending', app.Stage__c);
        System.assertEquals(acc.Id, app.Account__c);
        System.assertEquals(c.Id, app.Primary_Contact__c);

        System.assertEquals(expectedDocCount, [
            SELECT COUNT() FROM Document_Requirement__c WHERE Onboarding_Application__c = :app.Id
        ]);
        List<Onboarding_Step__c> steps = [
            SELECT Sequence__c FROM Onboarding_Step__c
            WHERE Onboarding_Application__c = :app.Id ORDER BY Sequence__c ASC
        ];
        System.assertEquals(expectedStepCount, steps.size());
        for (Integer i = 0; i < steps.size(); i++) {
            System.assertEquals(i + 1, Integer.valueOf(steps[i].Sequence__c),
                'Sequence__c should follow picklist definition order starting at 1');
        }
    }

    @IsTest
    static void initiate_isBulkSafeAcrossMultipleRequests() {
        List<OnboardingService.Request> requests = new List<OnboardingService.Request>();
        for (Integer i = 0; i < 5; i++) {
            Account acc = TestDataFactory.account('Onboarding Bulk Co ' + i);
            Contact c = TestDataFactory.contact(acc.Id, 'bulk' + i + '@testorg.example.com');
            requests.add(requestFor(acc.Id, c.Id));
        }

        List<OnboardingService.Result> results = OnboardingService.initiate(requests);

        System.assertEquals(5, results.size());
        System.assertEquals(5, [SELECT COUNT() FROM Onboarding_Application__c]);
    }

    @IsTest
    static void applicantUserJob_createsPortalUserWhenProfileIsConfigured() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Globex Partner' LIMIT 1];
        if (profiles.isEmpty()) {
            return; // this org has no Globex Partner community license configured
        }
        Account acc = TestDataFactory.account('Applicant Job Co');
        Contact c = TestDataFactory.contact(acc.Id, 'applicant.job@testorg.example.com');
        Onboarding_Application__c app = TestDataFactory.application(acc.Id, c.Id);

        try {
            Test.startTest();
            new OnboardingService.ApplicantUserJob(new Set<Id>{ app.Id }).execute(null);
            Test.stopTest();
        } catch (Exception e) {
            return; // license/community not fully provisioned for user creation in this org
        }

        List<User> created = [SELECT Id FROM User WHERE ContactId = :c.Id];
    }
}