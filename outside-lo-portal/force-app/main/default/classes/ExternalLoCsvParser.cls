public with sharing class ExternalLoCsvParser {
    public class Table {
        public List<String> headers = new List<String>();
        public List<List<String>> rows = new List<List<String>>();
    }

    public static Table parse(String csvBody) {
        Table table = new Table();
        if (String.isBlank(csvBody)) {
            return table;
        }
        String body = csvBody.startsWith('\uFEFF') ? csvBody.substring(1) : csvBody;
        List<List<String>> parsedRows = new List<List<String>>();
        List<String> current = new List<String>();
        String value = '';
        Boolean inQuotes = false;
        Integer index = 0;
        Integer length = body.length();
        while (index < length) {
            String ch = body.substring(index, index + 1);
            if (inQuotes) {
                if (ch == '"') {
                    if (index + 1 < length && body.substring(index + 1, index + 2) == '"') {
                        value += '"';
                        index++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    value += ch;
                }
            } else if (ch == '"') {
                inQuotes = true;
            } else if (ch == ',') {
                current.add(value);
                value = '';
            } else if (ch == '\n' || ch == '\r') {
                if (ch == '\r' && index + 1 < length && body.substring(index + 1, index + 2) == '\n') {
                    index++;
                }
                current.add(value);
                value = '';
                if (!isEmptyRow(current)) {
                    parsedRows.add(current);
                }
                current = new List<String>();
            } else {
                value += ch;
            }
            index++;
        }
        current.add(value);
        if (!isEmptyRow(current)) {
            parsedRows.add(current);
        }
        if (parsedRows.isEmpty()) {
            return table;
        }
        for (String header : parsedRows[0]) {
            table.headers.add(normalizeHeader(header));
        }
        for (Integer rowIndex = 1; rowIndex < parsedRows.size(); rowIndex++) {
            table.rows.add(parsedRows[rowIndex]);
        }
        return table;
    }

    public static String cell(List<String> row, Map<String, Integer> headerIndex, String key) {
        Integer position = headerIndex.get(key);
        if (position == null || position < 0 || position >= row.size()) {
            return null;
        }
        String value = row[position];
        return String.isBlank(value) ? null : value.trim();
    }

    public static Map<String, Integer> headerIndex(List<String> headers) {
        Map<String, Integer> indexByHeader = new Map<String, Integer>();
        for (Integer i = 0; i < headers.size(); i++) {
            indexByHeader.put(headers[i], i);
        }
        return indexByHeader;
    }

    private static Boolean isEmptyRow(List<String> row) {
        for (String value : row) {
            if (!String.isBlank(value)) {
                return false;
            }
        }
        return true;
    }

    private static String normalizeHeader(String header) {
        if (header == null) {
            return '';
        }
        return header.trim().toLowerCase().replaceAll('[^a-z0-9]', '');
    }
}