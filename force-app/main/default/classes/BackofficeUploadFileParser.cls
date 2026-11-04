/**
 * @description GW-2706 - Shared CSV/Excel reader for the Field Service Backoffice Tool upload screens
 *              (Tech Account Alignment, District Zone Alignment). Extracted from GW-2710 TechAccountAlignmentService.
 */
public with sharing class BackofficeUploadFileParser {
    /**
     * @description Reads the uploaded file into a table of trimmed-or-raw cell values. Row 0 is the header.
     * @param version Latest ContentVersion of the uploaded file.
     * @return Non-empty rows of the first worksheet (Excel) or the CSV body.
     */
    public static List<List<String>> parse(ContentVersion version) {
        String extension = version.FileExtension == null ? '' : version.FileExtension.toLowerCase();
        String pathOnClient = version.PathOnClient == null ? '' : version.PathOnClient.toLowerCase();
        Boolean isExcel = extension == 'xlsx' || pathOnClient.endsWith('.xlsx');
        List<List<String>> table;
        if (isExcel) {
            try {
                table = parseXlsx(version.VersionData);
            } catch (AuraHandledException e) {
                throw e;
            } catch (Exception e) {
                throw auraError('Unable to read the Excel file. Download the template and save it as CSV.');
            }
        } else {
            table = parseCsv(version.VersionData.toString());
        }
        if (table.isEmpty()) {
            throw auraError('The uploaded file is empty.');
        }
        return table;
    }

    /**
     * @description Maps normalized header names to their first column index.
     * @param header Header row.
     * @return Column index keyed by normalized header name.
     */
    public static Map<String, Integer> columnIndexByName(List<String> header) {
        Map<String, Integer> columnIndexByName = new Map<String, Integer>();
        for (Integer i = 0; i < header.size(); i++) {
            String headerName = normalizeHeader(header[i]);
            if (String.isNotBlank(headerName) && !columnIndexByName.containsKey(headerName)) {
                columnIndexByName.put(headerName, i);
            }
        }
        return columnIndexByName;
    }

    /**
     * @description Returns the first non-blank value among the given column aliases.
     * @param cells Row cells.
     * @param columnIndexByName Column index keyed by normalized header name.
     * @param keys Normalized header aliases, in priority order.
     * @return Trimmed value, or null.
     */
    public static String firstPresent(List<String> cells, Map<String, Integer> columnIndexByName, List<String> keys) {
        for (String key : keys) {
            if (columnIndexByName.containsKey(key)) {
                String value = cellValue(cells, columnIndexByName.get(key));
                if (String.isNotBlank(value)) {
                    return value;
                }
            }
        }
        return null;
    }

    /**
     * @description True when at least one of the given column aliases is in the header.
     * @param columnIndexByName Column index keyed by normalized header name.
     * @param keys Normalized header aliases.
     * @return Whether the column is present.
     */
    public static Boolean hasColumn(Map<String, Integer> columnIndexByName, List<String> keys) {
        for (String key : keys) {
            if (columnIndexByName.containsKey(key)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Trimmed cell value, or null when the cell is blank or missing.
     * @param cells Row cells.
     * @param index Column index.
     * @return Trimmed value, or null.
     */
    public static String cellValue(List<String> cells, Integer index) {
        if (index == null || cells == null || index < 0 || index >= cells.size()) {
            return null;
        }
        String value = cells[index];
        return String.isBlank(value) ? null : value.trim();
    }

    /**
     * @description Lower-cases a header and strips BOM, spaces, underscores, hyphens, '#' and '.'.
     * @param header Raw header text.
     * @return Normalized header name, or null.
     */
    public static String normalizeHeader(String header) {
        if (String.isBlank(header)) {
            return null;
        }
        return header
            .replace('\uFEFF', '')
            .replace('_', '')
            .replace(' ', '')
            .replace('-', '')
            .replace('#', '')
            .replace('.', '')
            .trim()
            .toLowerCase();
    }

    /**
     * @description Quotes a value for a CSV cell when needed.
     * @param value Raw value.
     * @return CSV-safe value.
     */
    public static String csvEscape(String value) {
        if (value == null) {
            return '';
        }
        if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
            return '"' + value.replace('"', '""') + '"';
        }
        return value;
    }

    private static List<List<String>> parseCsv(String csvBody) {
        String body = csvBody == null ? '' : csvBody.replace('\uFEFF', '').replace('\r\n', '\n').replace('\r', '\n');
        List<List<String>> table = new List<List<String>>();
        List<String> currentRow = new List<String>();
        String currentValue = '';
        Boolean inQuotes = false;
        for (Integer i = 0; i < body.length(); i++) {
            String currentChar = body.substring(i, i + 1);
            if (inQuotes) {
                if (currentChar == '"') {
                    Boolean isEscapedQuote = i + 1 < body.length() && body.substring(i + 1, i + 2) == '"';
                    if (isEscapedQuote) {
                        currentValue += '"';
                        i++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    currentValue += currentChar;
                }
            } else if (currentChar == '"') {
                inQuotes = true;
            } else if (currentChar == ',') {
                currentRow.add(currentValue);
                currentValue = '';
            } else if (currentChar == '\n') {
                currentRow.add(currentValue);
                if (!isEmptyRow(currentRow)) {
                    table.add(currentRow);
                }
                currentRow = new List<String>();
                currentValue = '';
            } else {
                currentValue += currentChar;
            }
        }
        currentRow.add(currentValue);
        if (!isEmptyRow(currentRow)) {
            table.add(currentRow);
        }
        return table;
    }

    private static Boolean isEmptyRow(List<String> row) {
        for (String value : row) {
            if (String.isNotBlank(value)) {
                return false;
            }
        }
        return true;
    }

    private static List<List<String>> parseXlsx(Blob fileBody) {
        Compression.ZipReader zipReader = new Compression.ZipReader(fileBody);
        String sharedStringsXml;
        String sheetXml;
        for (Compression.ZipEntry entry : zipReader.getEntries()) {
            String entryName = entry.getName() == null ? '' : entry.getName().replace('\\', '/').toLowerCase();
            if (entryName.endsWith('xl/sharedstrings.xml')) {
                sharedStringsXml = zipReader.extract(entry).toString();
            } else if (entryName.endsWith('xl/worksheets/sheet1.xml')) {
                sheetXml = zipReader.extract(entry).toString();
            } else if (sheetXml == null && entryName.contains('xl/worksheets/sheet') && entryName.endsWith('.xml')) {
                sheetXml = zipReader.extract(entry).toString();
            }
        }
        if (String.isBlank(sheetXml)) {
            throw auraError('The Excel file does not contain a worksheet that can be read. Save the template as CSV and try again.');
        }
        List<String> sharedStrings = parseSharedStrings(sharedStringsXml);
        return parseSheetXml(sheetXml, sharedStrings);
    }

    private static List<String> parseSharedStrings(String xmlBody) {
        List<String> values = new List<String>();
        if (String.isBlank(xmlBody)) {
            return values;
        }
        XmlStreamReader reader = new XmlStreamReader(xmlBody);
        while (reader.hasNext()) {
            if (reader.getEventType() == XmlTag.START_ELEMENT && reader.getLocalName() == 't') {
                reader.next();
                values.add(reader.getEventType() == XmlTag.CHARACTERS ? reader.getText() : '');
            }
            reader.next();
        }
        return values;
    }

    private static List<List<String>> parseSheetXml(String xmlBody, List<String> sharedStrings) {
        Map<Integer, Map<Integer, String>> cellsByRow = new Map<Integer, Map<Integer, String>>();
        Integer maxColumn = 0;
        XmlStreamReader reader = new XmlStreamReader(xmlBody);
        String cellRef;
        String cellType;
        while (reader.hasNext()) {
            if (reader.getEventType() == XmlTag.START_ELEMENT) {
                String localName = reader.getLocalName();
                if (localName == 'c') {
                    cellRef = reader.getAttributeValue(null, 'r');
                    cellType = reader.getAttributeValue(null, 't');
                } else if (localName == 'v' && String.isNotBlank(cellRef)) {
                    reader.next();
                    String rawValue = reader.getEventType() == XmlTag.CHARACTERS ? reader.getText() : '';
                    putCell(cellsByRow, cellRef, resolveCellValue(cellType, rawValue, sharedStrings));
                    Integer columnIndex = columnIndexFromRef(cellRef);
                    if (columnIndex > maxColumn) {
                        maxColumn = columnIndex;
                    }
                } else if (localName == 't' && cellType == 'inlineStr' && String.isNotBlank(cellRef)) {
                    reader.next();
                    String rawValue = reader.getEventType() == XmlTag.CHARACTERS ? reader.getText() : '';
                    putCell(cellsByRow, cellRef, rawValue);
                    Integer columnIndex = columnIndexFromRef(cellRef);
                    if (columnIndex > maxColumn) {
                        maxColumn = columnIndex;
                    }
                }
            }
            reader.next();
        }

        List<Integer> rowNumbers = new List<Integer>(cellsByRow.keySet());
        rowNumbers.sort();
        List<List<String>> table = new List<List<String>>();
        for (Integer rowNumber : rowNumbers) {
            Map<Integer, String> rowCells = cellsByRow.get(rowNumber);
            List<String> row = new List<String>();
            for (Integer columnIndex = 0; columnIndex <= maxColumn; columnIndex++) {
                row.add(rowCells.containsKey(columnIndex) ? rowCells.get(columnIndex) : '');
            }
            if (!isEmptyRow(row)) {
                table.add(row);
            }
        }
        return table;
    }

    private static void putCell(Map<Integer, Map<Integer, String>> cellsByRow, String cellRef, String value) {
        Integer rowNumber = rowIndexFromRef(cellRef);
        Integer columnIndex = columnIndexFromRef(cellRef);
        if (!cellsByRow.containsKey(rowNumber)) {
            cellsByRow.put(rowNumber, new Map<Integer, String>());
        }
        cellsByRow.get(rowNumber).put(columnIndex, value);
    }

    private static String resolveCellValue(String cellType, String rawValue, List<String> sharedStrings) {
        if (cellType == 's') {
            Integer index = Integer.valueOf(rawValue);
            return index >= 0 && index < sharedStrings.size() ? sharedStrings[index] : rawValue;
        }
        return rawValue;
    }

    private static Integer columnIndexFromRef(String cellRef) {
        String letters = '';
        for (Integer i = 0; i < cellRef.length(); i++) {
            String currentChar = cellRef.substring(i, i + 1);
            if (currentChar >= 'A' && currentChar <= 'Z') {
                letters += currentChar;
            } else {
                break;
            }
        }
        Integer index = 0;
        for (Integer i = 0; i < letters.length(); i++) {
            index = (index * 26) + (letters.charAt(i) - 64);
        }
        return index - 1;
    }

    private static Integer rowIndexFromRef(String cellRef) {
        String digits = '';
        for (Integer i = 0; i < cellRef.length(); i++) {
            String currentChar = cellRef.substring(i, i + 1);
            if (currentChar >= '0' && currentChar <= '9') {
                digits += currentChar;
            }
        }
        return Integer.valueOf(digits);
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}