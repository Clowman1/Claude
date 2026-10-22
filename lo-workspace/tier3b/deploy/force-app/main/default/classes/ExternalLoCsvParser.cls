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
        String delimiter = detectDelimiter(body);
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
            } else if (ch == delimiter) {
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
        // Common spreadsheet headings ("Phone Number", "Brokerage", "E-mail Address"...). An exact
        // canonical column always wins over an alias.
        for (Integer i = 0; i < headers.size(); i++) {
            String canonical = HEADER_ALIASES.get(headers[i]);
            if (canonical != null && !indexByHeader.containsKey(canonical)) {
                indexByHeader.put(canonical, i);
            }
        }
        return indexByHeader;
    }

    // Normalized alias -> canonical key (headers are already lower-case, letters and digits only).
    private static final Map<String, String> HEADER_ALIASES = new Map<String, String>{
        'first' => 'firstname', 'givenname' => 'firstname', 'fname' => 'firstname',
        'last' => 'lastname', 'surname' => 'lastname', 'familyname' => 'lastname', 'lname' => 'lastname',
        'fullname' => 'name', 'contactname' => 'name', 'agentname' => 'name',
        'phonenumber' => 'phone', 'mobile' => 'phone', 'mobilephone' => 'phone', 'mobilenumber' => 'phone',
        'cell' => 'phone', 'cellphone' => 'phone', 'cellnumber' => 'phone', 'primaryphone' => 'phone',
        'phone1' => 'phone', 'directphone' => 'phone', 'telephone' => 'phone',
        'emailaddress' => 'email', 'email1' => 'email', 'primaryemail' => 'email',
        'brokerage' => 'company', 'brokeragename' => 'company', 'companyname' => 'company',
        'office' => 'company', 'firm' => 'company', 'agency' => 'company', 'organization' => 'company',
        'area' => 'market', 'region' => 'market', 'city' => 'market',
        'type' => 'partnertype', 'industry' => 'partnertype', 'category' => 'partnertype', 'role' => 'partnertype',
        'amount' => 'loanamount', 'loanpurpose' => 'purpose', 'note' => 'notes', 'comments' => 'notes',
        'closedate' => 'closingdate', 'closeddate' => 'closingdate', 'fundeddate' => 'closingdate',
        'fundingdate' => 'closingdate', 'coedate' => 'closingdate',
        'price' => 'purchaseprice', 'salesprice' => 'purchaseprice', 'saleprice' => 'purchaseprice',
        'homeprice' => 'purchaseprice',
        // CRM exports (Follow Up Boss, kvCORE, LO spreadsheets): past-client stage, property address, loan.
        'stage' => 'type', 'status' => 'type', 'contacttype' => 'type', 'leadtype' => 'type', 'clienttype' => 'type',
        'addresscity' => 'city', 'propertycity' => 'city', 'mailingcity' => 'city',
        'propertyaddress' => 'street', 'address' => 'street', 'streetaddress' => 'street', 'address1' => 'street',
        'addressline1' => 'street', 'addressstreet' => 'street', 'propertystreet' => 'street', 'mailingaddress' => 'street',
        'mailingstreet' => 'street', 'homeaddress' => 'street', 'subjectproperty' => 'street', 'subjectpropertyaddress' => 'street',
        'st' => 'state', 'addressstate' => 'state', 'propertystate' => 'state', 'mailingstate' => 'state',
        'zipcode' => 'zip', 'postalcode' => 'zip', 'addresszip' => 'zip', 'propertyzip' => 'zip', 'mailingzip' => 'zip',
        'closed' => 'closingdate', 'closedon' => 'closingdate', 'dateclosed' => 'closingdate', 'closing' => 'closingdate',
        'loanamt' => 'loanamount', 'mortgageamount' => 'loanamount', 'baseloanamount' => 'loanamount', 'totalloanamount' => 'loanamount',
        'interestrate' => 'rate', 'noterate' => 'rate', 'intrate' => 'rate',
        'loanterm' => 'term', 'termmonths' => 'term', 'amortizationterm' => 'term',
        'mortgagetype' => 'loantype', 'loanprogram' => 'loantype', 'program' => 'loantype', 'loanproduct' => 'loantype', 'product' => 'loantype',
        'investor' => 'lender', 'servicer' => 'lender', 'mortgagecompany' => 'lender', 'currentlender' => 'lender',
        'tag' => 'tags'
    };

    /** Comma, semicolon (European Excel) or tab: whichever appears most in the header line. Ties keep comma. */
    @TestVisible
    static String detectDelimiter(String body) {
        String header = body.split('[\\r\\n]', 2)[0].replaceAll('"[^"]*"', '');
        String best = ',';
        for (String candidate : new List<String>{ ';', '\t' }) {
            if (header.countMatches(candidate) > header.countMatches(best)) {
                best = candidate;
            }
        }
        return best;
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