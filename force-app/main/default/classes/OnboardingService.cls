public with sharing class OnboardingService {

    private static final String APPLICANT_PROFILE = 'Globex Partner';

    public class Request {
        @InvocableVariable(required=true label='Account Id')
        public Id accountId;
        @InvocableVariable(required=true label='Contact Id')
        public Id contactId;
    }
    public class Result {
        @InvocableVariable public Id applicationId;
    }

    @InvocableMethod(label='Initiate Partner Onboarding')
    public static List<Result> initiate(List<Request> requests) {

        // Dynamic templates: whatever picklist values are ACTIVE on the
        // two objects right now defines the checklist. Admins change
        // onboarding requirements by editing picklists — no code change.
        List<String> docTypes = activeValues(
            Document_Requirement__c.Document_Type__c.getDescribe());
        List<String> stepTypes = activeValues(
            Onboarding_Step__c.Step_Type__c.getDescribe());

        // ---- 1) Applications ----
        List<Onboarding_Application__c> apps =
            new List<Onboarding_Application__c>();
        for (Request r : requests) {
            apps.add(new Onboarding_Application__c(
                Account__c         = r.accountId,
                Primary_Contact__c = r.contactId,
                Stage__c           = 'Docs Pending'));
        }
        insert apps;

        // ---- 2) Children from the dynamic templates ----
        List<Document_Requirement__c> docs =
            new List<Document_Requirement__c>();
        List<Onboarding_Step__c> steps = new List<Onboarding_Step__c>();

        for (Onboarding_Application__c app : apps) {
            for (String dt : docTypes) {
                docs.add(new Document_Requirement__c(
                    Onboarding_Application__c   = app.Id,
                    Document_Type__c = dt,
                    Status__c        = 'Awaiting'));
            }
            Integer seq = 1;
            for (String st : stepTypes) {
                steps.add(new Onboarding_Step__c(
                    Onboarding_Application__c = app.Id,
                    Step_Type__c   = st,
                    Sequence__c    = seq++,   // picklist order = sequence
                    Status__c      = 'Not Started'));
            }
        }
        insert docs;
        insert steps;

        // ---- 3) Portal user, async ----
        System.enqueueJob(new ApplicantUserJob(
            new Map<Id, Onboarding_Application__c>(apps).keySet()));

        // ---- 4) Return to Flow ----
        List<Result> out = new List<Result>();
        for (Onboarding_Application__c app : apps) {
            Result res = new Result();
            res.applicationId = app.Id;
            out.add(res);
        }
        return out;
    }

    // Active picklist values, in the order they're defined in Setup
    private static List<String> activeValues(
            Schema.DescribeFieldResult field) {
        List<String> vals = new List<String>();
        for (Schema.PicklistEntry pe : field.getPicklistValues()) {
            if (pe.isActive()) {
                vals.add(pe.getValue());
            }
        }
        return vals;
    }

    public class ApplicantUserJob implements Queueable {
        private final Set<Id> appIds;
        public ApplicantUserJob(Set<Id> appIds) { this.appIds = appIds; }

        public void execute(QueueableContext ctx) {
            List<Onboarding_Application__c> apps = [
                SELECT Id, Primary_Contact__c,
                       Primary_Contact__r.FirstName,
                       Primary_Contact__r.LastName,
                       Primary_Contact__r.Email
                FROM Onboarding_Application__c
                WHERE Id IN :appIds
            ];

            // Idempotency: skip contacts that already have users
            Set<Id> contactIds = new Set<Id>();
            for (Onboarding_Application__c a : apps) {
                contactIds.add(a.Primary_Contact__c);
            }
            Set<Id> haveUsers = new Set<Id>();
            for (User u : [SELECT ContactId FROM User
                           WHERE ContactId IN :contactIds]) {
                haveUsers.add(u.ContactId);
            }

            Profile p = [SELECT Id FROM Profile
                         WHERE Name = :APPLICANT_PROFILE LIMIT 1];

            List<User> users = new List<User>();
            for (Onboarding_Application__c app : apps) {
                if (haveUsers.contains(app.Primary_Contact__c)) { continue; }
                String email = app.Primary_Contact__r.Email;
                users.add(new User(
                    ContactId         = app.Primary_Contact__c,
                    ProfileId         = p.Id,
                    FirstName         = app.Primary_Contact__r.FirstName,
                    LastName          = app.Primary_Contact__r.LastName,
                    Email             = email,
                    Username          = email + '.globexpartner',
                    Alias             = (app.Primary_Contact__r.LastName)
                                            .left(5) + 'p',
                    CommunityNickname = email.substringBefore('@')
                                        + Crypto.getRandomInteger(),
                    EmailEncodingKey  = 'UTF-8',
                    TimeZoneSidKey    = 'Asia/Kolkata',
                    LocaleSidKey      = 'en_IN',
                    LanguageLocaleKey = 'en_US'));
            }
            if (users.isEmpty()) { return; }

            List<Database.SaveResult> results =
                Database.insert(users, false);
            IntegrationLogger.logDmlFailures('User(applicant)', results);

            // Send the "set your password" email — plain User inserts
            // do NOT send welcome emails on their own.
            for (Database.SaveResult r : results) {
                if (r.isSuccess()) {
                    System.resetPassword(r.getId(), true);
                }
            }
        }
    }

}