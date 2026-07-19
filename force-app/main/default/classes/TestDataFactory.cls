/**
 * TestDataFactory.cls
 * Single source of test data — every test class builds records here,
 * so a required-field change is fixed in ONE place, not thirty tests.
 * Convention: each method inserts and returns the record; the "s"
 * (list) variants build in bulk without inserting, for limit tests.
 */
@IsTest
public class TestDataFactory {

    // ---------- UC1: Disputes ----------
    public static Account account(String name) {
        Account a = new Account(Name = name, Customer_Tier__c = 'Gold');
        insert a;
        return a;
    }

    public static Contact contact(Id accountId, String email) {
        Contact c = new Contact(AccountId = accountId,
            FirstName = 'Test', LastName = 'Contact', Email = email);
        insert c;
        return c;
    }

    public static Invoice__c invoice(Id accountId, Decimal amount) {
        Invoice__c inv = new Invoice__c(
            Account__c       = accountId,
            Invoice_Number__c= 'ERP-' + generateKey(),
            Total_Amount__c  = amount,
            Balance_Due__c   = amount,
            Status__c        = 'Posted',
            Invoice_Date__c  = Date.today().addDays(-10));
        insert inv;
        return inv;
    }

    public static Dispute__c dispute(Id invoiceId, String type,
                                     Decimal amount) {
        Dispute__c d = new Dispute__c(
            Invoice__c         = invoiceId,
            Type__c            = type,
            Disputed_Amount__c = amount,
            Status__c          = 'New',
            ERP_Sync_Status__c = 'Pending');
        insert d;
        return d;
    }

    // ---------- UC3: Billing ----------
    public static Subscription_Plan__c plan(String name, Decimal basePrice,
            Decimal unitRate, Decimal includedUnits) {
        Subscription_Plan__c p = new Subscription_Plan__c(
            Name                = name,
            Base_Price__c       = basePrice,
            Unit_Usage_Rate__c  = unitRate,
            Included_Units__c   = includedUnits,
            Billing_Frequency__c= 'Monthly');
        insert p;
        return p;
    }

    // Bulk builder — returns WITHOUT inserting so tests control DML
    public static List<Subscription__c> subscriptions(Id accountId,
            Id planId, Integer count, String region) {
        List<Subscription__c> subs = new List<Subscription__c>();
        for (Integer i = 0; i < count; i++) {
            subs.add(new Subscription__c(
                Account__c           = accountId,
                Plan__c              = planId,
                Status__c            = 'Active',
                Region__c            = region,
                Tier__c              = 'T1',
                Quantity__c          = 1,
                Next_Billing_Date__c = Date.today()));
        }
        return subs;
    }

    public static Usage_Record__c usage(Id subscriptionId, Decimal units) {
        Usage_Record__c u = new Usage_Record__c(
            Subscription__c   = subscriptionId,
            Usage_Date__c     = Date.today().addDays(-5),
            Units_Consumed__c = units,
            Billing_Status__c = 'Unbilled');
        insert u;
        return u;
    }

    // ---------- UC2: Onboarding ----------
    public static Onboarding_Application__c application(Id accountId,
                                                        Id contactId) {
        Onboarding_Application__c app = new Onboarding_Application__c(
            Account__c         = accountId,
            Primary_Contact__c = contactId,
            Stage__c           = 'Draft');
        insert app;
        return app;
    }

    // ---------- helpers ----------
    // Unique-enough key WITHOUT Math.random(): deterministic per call
    private static Integer keyCounter = 0;
    public static String generateKey() {
        keyCounter++;
        return String.valueOf(Crypto.getRandomInteger()).left(9)
             + '-' + keyCounter;
    }
}