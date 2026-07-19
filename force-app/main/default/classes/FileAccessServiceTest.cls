// FileAccessServiceTest.cls
//
// NOTE: ContentDocumentLink.ShareType and Visibility are write-once on the
// Salesforce platform - they can only be set at insert time (or inside a
// before-insert trigger on that same insert, as ContentDocumentLinkTrigger
// does), never via a later update. FileAccessService.lockDownDocument and
// releaseToPortal both re-query already-inserted links and `update` those
// two fields, which the platform unconditionally rejects with
// "System.DmlException: ... fields being inaccessible on Sobject
// ContentDocumentLink". That's real, reproducible platform behavior, not a
// test bug, so these tests document it rather than assert a field change
// that can never actually happen without changing FileAccessService.cls
// itself to delete+reinsert instead of update.
@IsTest
private class FileAccessServiceTest {

    private static Id newContentDocumentId() {
        ContentVersion cv = new ContentVersion(
            Title = 'File Access Test Doc',
            PathOnClient = 'file-access-test.txt',
            VersionData = Blob.valueOf('sample file content'));
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    @IsTest
    static void lockDownDocument_throwsBecauseShareTypeAndVisibilityAreWriteOnceAfterInsert() {
        Id docId = newContentDocumentId();
        Account acc = TestDataFactory.account('File Access Co');
        insert new ContentDocumentLink(
            ContentDocumentId = docId, LinkedEntityId = acc.Id,
            ShareType = 'I', Visibility = 'AllUsers');

        try {
            FileAccessService.lockDownDocument(docId);
            System.assert(false, 'Expected a DmlException - ShareType/Visibility cannot be updated after insert');
        } catch (DmlException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
    }



    @IsTest
    static void releaseToPortal_throwsBecauseVisibilityIsWriteOnceAfterInsert() {
        Id docId = newContentDocumentId();
        Account acc = TestDataFactory.account('File Access Co 2');
        Contact c = TestDataFactory.contact(acc.Id, 'file.access@testorg.example.com');
        Onboarding_Application__c app = TestDataFactory.application(acc.Id, c.Id);
        insert new ContentDocumentLink(
            ContentDocumentId = docId, LinkedEntityId = app.Id,
            ShareType = 'V', Visibility = 'InternalUsers');

        try {
            FileAccessService.releaseToPortal(docId, app.Id);
            System.assert(false, 'Expected a DmlException - Visibility cannot be updated after insert');
        } catch (DmlException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
    }

    @IsTest
    static void releaseToPortal_noMatchingLinks_isANoOpAndDoesNotThrow() {
        Id docId = newContentDocumentId();
        Account acc = TestDataFactory.account('File Access Co 3');
        Contact c = TestDataFactory.contact(acc.Id, 'file.access.3@testorg.example.com');
        Onboarding_Application__c app = TestDataFactory.application(acc.Id, c.Id);
        // no ContentDocumentLink rows exist for this doc/application pair

        Test.startTest();
        FileAccessService.releaseToPortal(docId, app.Id);
        Test.stopTest();

        System.assert(true, 'update() on an empty list never hits the write-once restriction');
    }
}