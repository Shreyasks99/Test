// ParserUtilTest.cls
@IsTest
private class ParserUtilTest {

    // ---------- parseCsvLine ----------

    @IsTest
    static void parseCsvLine_splitsSimpleUnquotedFields() {
        List<String> fields = ParserUtil.parseCsvLine('a,b,c');
        System.assertEquals(new List<String>{ 'a', 'b', 'c' }, fields);
    }

    @IsTest
    static void parseCsvLine_keepsCommaInsideQuotesAsOneField() {
        List<String> fields = ParserUtil.parseCsvLine('"hello, world",b');
        System.assertEquals(new List<String>{ 'hello, world', 'b' }, fields);
    }

    @IsTest
    static void parseCsvLine_unescapesDoubledQuotes() {
        List<String> fields = ParserUtil.parseCsvLine('"she said ""hi""",b');
        System.assertEquals(new List<String>{ 'she said "hi"', 'b' }, fields);
    }

    @IsTest
    static void parseCsvLine_stripsTrailingCarriageReturn() {
        List<String> fields = ParserUtil.parseCsvLine('a,b\r');
        System.assertEquals(new List<String>{ 'a', 'b' }, fields);
    }

    @IsTest
    static void parseCsvLine_returnsEmptyListForBlankLine() {
        System.assertEquals(0, ParserUtil.parseCsvLine('').size());
        System.assertEquals(0, ParserUtil.parseCsvLine(null).size());
    }

    // ---------- toMap ----------

    @IsTest
    static void toMap_zipsHeadersAndValuesWithUppercaseKeys() {
        Map<String, String> row = ParserUtil.toMap(
            new List<String>{ 'user_id', 'client_ip' },
            new List<String>{ '005xx', '10.0.0.1' });

        System.assertEquals('005xx', row.get('USER_ID'));
        System.assertEquals('10.0.0.1', row.get('CLIENT_IP'));
    }

    @IsTest
    static void toMap_missingTrailingValuesBecomeNull() {
        Map<String, String> row = ParserUtil.toMap(
            new List<String>{ 'A', 'B', 'C' },
            new List<String>{ '1' });

        System.assertEquals('1', row.get('A'));
        System.assertEquals(null, row.get('B'));
        System.assertEquals(null, row.get('C'));
    }

    @IsTest
    static void toMap_blankValuesNormalizeToNull() {
        Map<String, String> row = ParserUtil.toMap(
            new List<String>{ 'A' }, new List<String>{ '' });

        System.assertEquals(null, row.get('A'));
    }

    // ---------- ts ----------

    @IsTest
    static void ts_parsesIso8601TimestampDerived() {
        Datetime dt = ParserUtil.ts('2026-07-15T02:12:34.000Z');

        System.assertEquals(2026, dt.yearGmt());
        System.assertEquals(7, dt.monthGmt());
        System.assertEquals(15, dt.dayGmt());
        System.assertEquals(2, dt.hourGmt());
        System.assertEquals(12, dt.minuteGmt());
        System.assertEquals(34, dt.secondGmt());
    }

    @IsTest
    static void ts_parsesRawGmtDigits() {
        Datetime dt = ParserUtil.ts('20260715021234.567');

        Datetime expected = Datetime.newInstanceGmt(2026, 7, 15, 2, 12, 34);
        System.assertEquals(expected, dt);
    }

    @IsTest
    static void ts_returnsNullForBlankOrTooShortOrUnparseableInput() {
        System.assertEquals(null, ParserUtil.ts(null));
        System.assertEquals(null, ParserUtil.ts(''));
        System.assertEquals(null, ParserUtil.ts('2026')); // shorter than 14 raw digits
        System.assertEquals(null, ParserUtil.ts('not-a-date-at-all'));
    }
}