// SnowflakeSqlBuilderTest.cls
// bulkInsert() only reads field values in memory; the Audit_Log_Entry__c
// rows are deliberately never inserted, so field-length limits on the
// real object don't constrain how long a value this test can exercise.
@IsTest
private class SnowflakeSqlBuilderTest {

    @IsTest
    static void bulkInsert_rendersColumnListAndNullsForAnEmptyRow() {
        String sql = SnowflakeSqlBuilder.bulkInsert(
            'AUDIT.SF_EVENT_LOGS', new List<Audit_Log_Entry__c>{ new Audit_Log_Entry__c() });

        System.assertEquals(
            'INSERT INTO AUDIT.SF_EVENT_LOGS ' +
            '(SF_RECORD_ID,EVENT_TYPE,EVENT_TS,SF_USER_ID,SOURCE_IP,ENTITY,OPERATION) ' +
            'VALUES (NULL,NULL,NULL,NULL,NULL,NULL,NULL)',
            sql);
    }

    @IsTest
    static void bulkInsert_escapesQuotesAndStripsBackslashes() {
        Audit_Log_Entry__c e = new Audit_Log_Entry__c(
            Event_Type__c = 'O\'Brien',
            Entity__c = 'back\\slash\\path');

        String sql = SnowflakeSqlBuilder.bulkInsert('T', new List<Audit_Log_Entry__c>{ e });

        System.assert(sql.contains('\'O\'\'Brien\''), 'single quotes must be doubled: ' + sql);
        System.assert(sql.contains('\'backslashpath\''), 'backslashes must be stripped: ' + sql);
    }

    @IsTest
    static void bulkInsert_blankStringNormalizesToNull() {
        Audit_Log_Entry__c e = new Audit_Log_Entry__c(Event_Type__c = '');

        String sql = SnowflakeSqlBuilder.bulkInsert('T', new List<Audit_Log_Entry__c>{ e });

        System.assert(sql.contains('VALUES (NULL,NULL'), 'blank string should render as NULL, not \'\': ' + sql);
    }

    @IsTest
    static void bulkInsert_formatsTimestampAsGmtNtzLiteral() {
        Audit_Log_Entry__c e = new Audit_Log_Entry__c(
            Event_Timestamp__c = Datetime.newInstanceGmt(2026, 1, 2, 3, 4, 5));

        String sql = SnowflakeSqlBuilder.bulkInsert('T', new List<Audit_Log_Entry__c>{ e });

        System.assert(sql.contains('\'2026-01-02 03:04:05\''), sql);
    }

    @IsTest
    static void bulkInsert_abbreviatesValuesLongerThan4000Chars() {
        String longValue = 'x'.repeat(5000);
        Audit_Log_Entry__c e = new Audit_Log_Entry__c(Entity__c = longValue);

        String sql = SnowflakeSqlBuilder.bulkInsert('T', new List<Audit_Log_Entry__c>{ e });

    }

    @IsTest
    static void bulkInsert_joinsMultipleRowsWithCommas() {
        Audit_Log_Entry__c e1 = new Audit_Log_Entry__c(Event_Type__c = 'Login');
        Audit_Log_Entry__c e2 = new Audit_Log_Entry__c(Event_Type__c = 'API');

        String sql = SnowflakeSqlBuilder.bulkInsert('T', new List<Audit_Log_Entry__c>{ e1, e2 });

        System.assert(sql.contains('\'Login\''));
        System.assert(sql.contains('\'API\''));
        System.assert(sql.contains('),('), 'two value tuples should be comma-joined: ' + sql);
    }
}