/**
 * BillingRunNotifier.cls
 * Sends the end-of-run summary from Batch finish(). Non-critical
 * observability: it must NEVER throw and fail the run — a billing
 * run that completed but couldn't email about it is still a
 * completed billing run.
 */
public without sharing class BillingRunNotifier {

    public static void sendSummary(Id billingRunId,
                                   Integer processed,
                                   Integer failed) {
        try {
            List<Billing_Run__c> runs = [
                SELECT Name, Period_Start__c, Period_End__c
                FROM Billing_Run__c WHERE Id = :billingRunId LIMIT 1
            ];
            if (runs.isEmpty()) { return; }
            Billing_Run__c run = runs[0];

            String subject = 'Billing Run ' + run.Name + ' — '
                + (failed == 0 ? 'Completed'
                               : 'Completed with ' + failed + ' errors');

            String body =
                  'Billing run:      ' + run.Name + '\n'
                + 'Period:           ' + run.Period_Start__c.format()
                + ' to ' + run.Period_End__c.format() + '\n'
                + 'Processed:        ' + processed + '\n'
                + 'Failed:           ' + failed + '\n\n'
                + (failed > 0
                    ? 'Failed subscriptions are quarantined in '
                      + 'Billing Error records under this run — '
                      + 'fix and reprocess; successful lines were '
                      + 'NOT rolled back.\n'
                    : 'No errors. All usage marked Billed and next '
                      + 'billing dates advanced.\n')
                + '\nRecord: ' + Url.getOrgDomainUrl().toExternalForm()
                + '/' + billingRunId;

            Messaging.SingleEmailMessage mail =
                new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(UserInfo.getUserId()); // billing admin
            mail.setSaveAsActivity(false);   // required with user target
            mail.setSubject(subject);
            mail.setPlainTextBody(body);

            Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            // Observability must not break the pipeline it observes
            System.debug(LoggingLevel.ERROR,
                'BillingRunNotifier failed: ' + e.getMessage());
        }
    }
}