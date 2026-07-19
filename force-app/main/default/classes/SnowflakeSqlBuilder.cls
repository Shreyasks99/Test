/**
 * SnowflakeSqlBuilder.cls
 * Builds a single multi-row INSERT statement for the Snowflake
 * SQL API (POST /api/v2/statements) from Audit_Log_Entry__c rows.
 *
 * Why one statement instead of row-by-row: the export runs in
 * 2,000-row chunks — one statement per chunk = one callout,
 * minimal round-trips, atomic insert on the Snowflake side.
 */
public class SnowflakeSqlBuilder {

    // Target table columns, in insert order. Must match the DDL:
    // CREATE TABLE AUDIT.SF_EVENT_LOGS (
    //   SF_RECORD_ID VARCHAR, EVENT_TYPE VARCHAR,
    //   EVENT_TS TIMESTAMP_NTZ, SF_USER_ID VARCHAR,
    //   SOURCE_IP VARCHAR, ENTITY VARCHAR, OPERATION VARCHAR );
    private static final List<String> COLUMNS = new List<String>{
        'SF_RECORD_ID', 'EVENT_TYPE', 'EVENT_TS',
        'SF_USER_ID', 'SOURCE_IP', 'ENTITY', 'OPERATION'
    };

    public static String bulkInsert(String tableName,
            List<Audit_Log_Entry__c> entries) {

        List<String> rows = new List<String>();
        for (Audit_Log_Entry__c e : entries) {
            List<String> vals = new List<String>{
                str(e.Id),                       // idempotency key
                str(e.Event_Type__c),
                ts(e.Event_Timestamp__c),
                str(e.User__c),
                str(e.Source_IP__c),
                str(e.Entity__c),
                str(e.Operation__c)
            };
            rows.add('(' + String.join(vals, ',') + ')');
        }

        return 'INSERT INTO ' + tableName
            + ' (' + String.join(COLUMNS, ',') + ') VALUES '
            + String.join(rows, ',');
    }

    // ---------- literal formatting ----------

    /** Escaped, quoted string literal; NULL when blank */
    private static String str(Object value) {
        if (value == null) { return 'NULL'; }
        String s = String.valueOf(value);
        if (String.isBlank(s)) { return 'NULL'; }
        // SQL escaping: double any single quote; strip backslashes
        // rather than fight Snowflake's escape modes
        s = s.replace('\\', '').replace('\'', '\'\'');
        return '\'' + s.abbreviate(4000) + '\'';
    }

    /** Snowflake TIMESTAMP_NTZ literal in UTC */
    private static String ts(Datetime value) {
        if (value == null) { return 'NULL'; }
        return '\'' + value.formatGmt('yyyy-MM-dd HH:mm:ss') + '\'';
    }
}