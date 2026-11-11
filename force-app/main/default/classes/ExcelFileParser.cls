/**
 * @description GW-2710 - Reads the first worksheet of an .xlsx file into rows of cell text.
 *              Built on Compression.ZipReader. Shared strings and inline strings are returned as text.
 *              Numeric and date cells are returned as the raw worksheet value, not a formatted date.
 */
public with sharing class ExcelFileParser {
    /**
     * @description Thrown when the file is not a readable workbook or has no worksheet.
     */
    public class ParseException extends Exception {}

    /**
     * @description Reads the first worksheet. Prefers xl/worksheets/sheet1.xml.
     * @param fileBody XLSX file body.
     * @return Rows of cell text, with empty rows omitted. Columns with no value are blank strings.
     */
    public static List<List<String>> readFirstSheet(Blob fileBody) {
        try {
            return readSheet(fileBody);
        } catch (ParseException e) {
            throw e;
        } catch (Exception e) {
            throw new ParseException('Unable to read the Excel file.');
        }
    }

    private static List<List<String>> readSheet(Blob fileBody) {
        if (fileBody == null) {
            throw new ParseException('Unable to read the Excel file.');
        }
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
            throw new ParseException('The Excel file does not contain a worksheet that can be read.');
        }
        return parseSheetXml(sheetXml, parseSharedStrings(sharedStringsXml));
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
                    maxColumn = maxColumnIndex(maxColumn, cellRef);
                } else if (localName == 't' && cellType == 'inlineStr' && String.isNotBlank(cellRef)) {
                    reader.next();
                    String rawValue = reader.getEventType() == XmlTag.CHARACTERS ? reader.getText() : '';
                    putCell(cellsByRow, cellRef, rawValue);
                    maxColumn = maxColumnIndex(maxColumn, cellRef);
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

    private static Integer maxColumnIndex(Integer maxColumn, String cellRef) {
        Integer columnIndex = columnIndexFromRef(cellRef);
        return columnIndex > maxColumn ? columnIndex : maxColumn;
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

    private static Boolean isEmptyRow(List<String> row) {
        for (String value : row) {
            if (String.isNotBlank(value)) {
                return false;
            }
        }
        return true;
    }
}