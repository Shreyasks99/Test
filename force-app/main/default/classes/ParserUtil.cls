/**
 * ParserUtil.cls
 * CSV + timestamp helpers for EventLogFile parsing (UC5).
 *
 * EventLogFile CSVs are RFC-4180 style: every field is quoted,
 * commas appear INSIDE quoted values (URIs, user agents), and a
 * literal quote is escaped by doubling (""). A naive
 * line.split(',') silently shifts columns on such rows — which is
 * the entire reason this class exists.
 */
public class ParserUtil {

    private static final Integer QUOTE = 34;  // "
    private static final Integer COMMA = 44;  // ,

    /** Parses one CSV line, honoring quotes and escaped quotes. */
    public static List<String> parseCsvLine(String line) {
        List<String> fields = new List<String>();
        if (String.isBlank(line)) { return fields; }

        line = line.removeEnd('\r');   // CRLF-safe
        Integer len = line.length();
        Boolean inQuotes = false;
        String current = '';

        for (Integer i = 0; i < len; i++) {
            Integer ch = line.charAt(i);
            if (ch == QUOTE) {
                if (inQuotes && i + 1 < len
                        && line.charAt(i + 1) == QUOTE) {
                    current += '"';    // "" inside quotes = literal "
                    i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (ch == COMMA && !inQuotes) {
                fields.add(current);
                current = '';
            } else {
                current += line.substring(i, i + 1);
            }
        }
        fields.add(current);
        return fields;
    }

    /**
     * Zips header + value lists into a row map.
     * Headers uppercased so lookups are case-stable; tolerant of
     * ragged rows (missing trailing fields become null).
     */
    public static Map<String, String> toMap(List<String> headers,
                                            List<String> values) {
        Map<String, String> row = new Map<String, String>();
        for (Integer i = 0; i < headers.size(); i++) {
            String v = i < values.size() ? values[i] : null;
            row.put(headers[i].toUpperCase(),
                    String.isBlank(v) ? null : v);
        }
        return row;
    }

    /**
     * EventLogFile timestamps arrive in two shapes:
     *   TIMESTAMP_DERIVED: 2026-07-15T02:12:34.000Z  (ISO 8601, UTC)
     *   TIMESTAMP:         20260715021234.567         (raw GMT digits)
     * Returns null on anything unparseable — one bad row must not
     * kill a batch chunk.
     */
    public static Datetime ts(String raw) {
        if (String.isBlank(raw)) { return null; }
        try {
            if (raw.contains('-') && raw.contains('T')) {
                // JSON deserializer handles ISO 8601 incl. the Z zone
                return (Datetime) JSON.deserialize(
                    '"' + raw + '"', Datetime.class);
            }
            // raw digits: yyyyMMddHHmmss(.SSS), GMT
            String d = raw.substringBefore('.');
            if (d.length() < 14) { return null; }
            return Datetime.newInstanceGmt(
                Integer.valueOf(d.substring(0, 4)),
                Integer.valueOf(d.substring(4, 6)),
                Integer.valueOf(d.substring(6, 8)),
                Integer.valueOf(d.substring(8, 10)),
                Integer.valueOf(d.substring(10, 12)),
                Integer.valueOf(d.substring(12, 14)));
        } catch (Exception e) {
            return null;
        }
    }
}