public class EventLogReportLoader {

    public static void loadReportEvents() {

        System.debug('=== START loadReportEvents ===');

        List<EventLogFile> logs = [
            SELECT Id, EventType, LogDate, LogFile
            FROM EventLogFile
            WHERE EventType IN (
                'Login',
                'Report',
                'ContentTransfer'
                //'ReportContentTransfer'
            )
            ORDER BY LogDate DESC
            LIMIT 10
        ];

        System.debug('Total EventLogFile records fetched: ' + logs.size());

        List<Report_Usage_Log__c> records = new List<Report_Usage_Log__c>();

        for (EventLogFile log : logs) {

            System.debug('Processing EventType: ' + log.EventType);

            // Convert Blob to String
            String csvText = log.LogFile.toString();

            // Split rows
            List<String> rows = csvText.split('\n');
            if (rows.size() <= 1) {
                System.debug('No data rows found, skipping');
                continue;
            }

            
            List<String> headers = parseCsvRow(rows[0]);
            Map<String, Integer> columnMap = new Map<String, Integer>();

            for (Integer i = 0; i < headers.size(); i++) {
                columnMap.put(headers[i].trim(), i);
            }

            System.debug('Column Map: ' + columnMap);
 
            for (Integer r = 1; r < rows.size(); r++) {

                if (String.isBlank(rows[r])) {
                    continue;
                }

                List<String> cols = parseCsvRow(rows[r]);

                Report_Usage_Log__c rec = new Report_Usage_Log__c();

                 rec.Event_Type__c =
                    getColValue(cols, columnMap, 'EVENT_TYPE');

                rec.User_Id__c =
                    getColValue(cols, columnMap, 'USER_ID');

                rec.DOCUMENT_ID__c =
                    getColValue(cols, columnMap, 'DOCUMENT_ID');

                rec.VERSION_ID__c =
                    getColValue(cols, columnMap, 'VERSION_ID');

                rec.FILE_TYPE__c =
                    getColValue(cols, columnMap, 'FILE_TYPE');
 				rec.REPORT_ID__c =
                    getColValue(cols, columnMap, 'REPORT_ID');
                rec.User_Name__c =
                    getColValue(cols, columnMap, 'USER_NAME');
                
               
String ts = getColValue(cols, columnMap, 'TIMESTAMP_DERIVED');

if (!String.isBlank(ts)) {

    // Remove T and Z
    ts = ts.replace('T', ' ').replace('Z', '');

    // Remove milliseconds if present
    if (ts.contains('.')) {
        ts = ts.substring(0, ts.indexOf('.'));
    }

    rec.Event_Time__c = Datetime.valueOfGmt(ts);
}


               
                // Optional: store EventType for reference
                rec.Event_Type__c = log.EventType;

                records.add(rec);
            }
        }

        System.debug('Total records to insert: ' + records.size());

        if (!records.isEmpty()) {
            insert records;
            System.debug('Records inserted successfully');
        }

        System.debug('=== END loadReportEvents ===');
    }

    
    private static List<String> parseCsvRow(String row) {

        List<String> result = new List<String>();
        Boolean inQuotes = false;
        String current = '';

        for (Integer i = 0; i < row.length(); i++) {
            String ch = row.substring(i, i + 1);

            if (ch == '"') {
                inQuotes = !inQuotes;
            } else if (ch == ',' && !inQuotes) {
                result.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        result.add(current);

        return result;
    }

    
    private static String getColValue(
        List<String> cols,
        Map<String, Integer> colMap,
        String colName
    ) {
        if (colMap.containsKey(colName)) {
            Integer idx = colMap.get(colName);
            if (idx < cols.size()) {
                return cols[idx];
            }
        }
        return null;
    }
}