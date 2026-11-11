/**
 * @description GW-2710 - Tests for ExcelFileParser worksheet reading.
 */
@IsTest
private class ExcelFileParserTest {
    @IsTest
    static void readFirstSheet_returnsSharedInlineAndNumericCells() {
        Blob workbook = workbook(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
                '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
                '<si><t>Address ID</t></si>' +
                '<si><t>100</t></si>' +
                '</sst>',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
                '<sheetData>' +
                '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>Note</t></is></c></row>' +
                '<row r="3"><c r="A3" t="s"><v>1</v></c><c r="B3"><v>42</v></c></row>' +
                '</sheetData></worksheet>'
        );

        List<List<String>> table = ExcelFileParser.readFirstSheet(workbook);

        Assert.areEqual(2, table.size());
        Assert.areEqual(new List<String>{ 'Address ID', '', 'Note' }, table[0]);
        Assert.areEqual(new List<String>{ '100', '42', '' }, table[1]);
    }

    @IsTest
    static void readFirstSheet_throwsWhenFileIsNotAWorkbook() {
        ExcelFileParser.ParseException thrown;
        try {
            ExcelFileParser.readFirstSheet(Blob.valueOf('not-a-zip'));
        } catch (ExcelFileParser.ParseException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Excel'));
    }

    @IsTest
    static void readFirstSheet_throwsWhenWorksheetIsMissing() {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('xl/sharedStrings.xml', Blob.valueOf('<sst></sst>'));
        ExcelFileParser.ParseException thrown;
        try {
            ExcelFileParser.readFirstSheet(writer.getArchive());
        } catch (ExcelFileParser.ParseException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('worksheet'));
    }

    private static Blob workbook(String sharedStrings, String sheet) {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('xl/sharedStrings.xml', Blob.valueOf(sharedStrings));
        writer.addEntry('xl/worksheets/sheet1.xml', Blob.valueOf(sheet));
        return writer.getArchive();
    }
}