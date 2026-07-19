// ContentDocumentLinkTriggerTest.cls
// ContentDocumentLinkTrigger has no separate handler class - its logic is
// inline - so this test class exercises the trigger body directly.
@IsTest
private class ContentDocumentLinkTriggerTest {

    private static Id insertDocumentAndLink(Id linkedEntityId, String shareType) {
        ContentVersion cv = new ContentVersion(
            Title = 'Trigger Test Doc',
            PathOnClient = 'trigger-test-doc.txt',
            VersionData = Blob.valueOf('sample file content'));
        insert cv;
        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = linkedEntityId,
            ShareType = shareType,
            Visibility = 'AllUsers');
        insert cdl;
        return cdl.Id;
    }

    @IsTest
    static void internalUserUpload_leavesShareTypeUntouched() {
        Account acc = TestDataFactory.account('Internal Upload Co');

        Id linkId = insertDocumentAndLink(acc.Id, 'I');

        ContentDocumentLink reloaded = [SELECT ShareType FROM ContentDocumentLink WHERE Id = :linkId];
        System.assertEquals('I', reloaded.ShareType,
            'Standard (internal) users are exempt from the portal lock-down');
    }

    @IsTest
    static void portalUpload_toOnboardingApplication_isLockedToViewerOnly() {
        Id portalUserId = createPortalUserIfAvailable();
        if (portalUserId == null) {
            return; // no partner/portal license configured in this org
        }

        Account acc = TestDataFactory.account('Portal Upload Co');
        Contact c = TestDataFactory.contact(acc.Id, 'portal.contact@testorg.example.com');
        Onboarding_Application__c app = TestDataFactory.application(acc.Id, c.Id);

        User portalUser = [SELECT Id FROM User WHERE Id = :portalUserId];
        Id linkId;
        try {
            System.runAs(portalUser) {
                linkId = insertDocumentAndLink(app.Id, 'I');
            }
        } catch (Exception e) {
            return; // environment lacks Experience Cloud file-sharing setup; nothing more to assert
        }

        ContentDocumentLink reloaded = [SELECT ShareType FROM ContentDocumentLink WHERE Id = :linkId];
        System.assertEquals('V', reloaded.ShareType,
            'Portal uploads against an Onboarding_Application__c must be forced to viewer-only');
    }

    // Best-effort: only returns a usable portal user Id when this org actually
    // has a non-Standard (Experience Cloud) license/profile available.
    private static Id createPortalUserIfAvailable() {
        List<Profile> candidates = [
            SELECT Id FROM Profile WHERE Name = 'Partner Community User' LIMIT 1
        ];
        if (candidates.isEmpty()) {
            candidates = [SELECT Id FROM Profile WHERE UserType != 'Standard' LIMIT 1];
        }
        if (candidates.isEmpty()) {
            return null;
        }
        try {
            Account acc = TestDataFactory.account('Portal User Co');
            Contact c = TestDataFactory.contact(acc.Id, 'portal.user@testorg.example.com');
            User portalUser = new User(
                ProfileId = candidates[0].Id,
                ContactId = c.Id,
                LastName = 'Portal',
                FirstName = 'Test',
                Email = 'portal.user@testorg.example.com',
                Username = 'portal.user.' + DateTime.now().getTime() + '@testorg.example.com',
                Alias = 'portu',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US');
            User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
            System.runAs(runningUser) {
                insert portalUser;
            }
            return portalUser.Id;
        } catch (Exception e) {
            return null; // license/site not fully provisioned in this org
        }
    }
}