// FileAccessService.cls — ContentVersion / ContentDocumentLink control
public with sharing class FileAccessService {
 
    // Called right after a portal upload:
    //  1) Visibility = 'InternalUsers' hides the raw link from other
    //     portal members on the same record until verified.
    //  2) ShareType 'V' (viewer) prevents the uploader editing/deleting
    //     the file after submission (compliance requirement).
    public static void lockDownDocument(Id contentDocumentId) {
        List<ContentDocumentLink> links = [
            SELECT Id, Visibility, ShareType
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
        ];
        for (ContentDocumentLink l : links) {
            l.Visibility = 'InternalUsers';
            l.ShareType  = 'V';
        }
        update links;
    }
 
    // After verification, expose the doc back to the partner:
    public static void releaseToPortal(Id contentDocumentId,
                                       Id applicationId) {
        List<ContentDocumentLink> links = [
            SELECT Id, Visibility FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
              AND LinkedEntityId = :applicationId
        ];
        for (ContentDocumentLink l : links) {
            l.Visibility = 'AllUsers';
        }
        update links;
    }
}