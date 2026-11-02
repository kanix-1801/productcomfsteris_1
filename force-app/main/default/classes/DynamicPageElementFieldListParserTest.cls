/**
 * @date 2026/07/28
 *
 * @group Account Management
 *
 * @description
 * Tests for DynamicPageElementFieldListParser CSV and suffix parsing.
 * GC-3183
 */
@IsTest(SeeAllData=false)
private class DynamicPageElementFieldListParserTest {

    /**
     * @description
     * Verifies blank input returns an empty list.
     */
    @IsTest
    static void testParseBlankReturnsEmpty() {
        System.assertEquals(0, DynamicPageElementFieldListParser.parse(null).size());
        System.assertEquals(0, DynamicPageElementFieldListParser.parse('').size());
        System.assertEquals(0, DynamicPageElementFieldListParser.parse('   ').size());
    }

    /**
     * @description
     * Verifies required, readonly, editable, and default suffix handling.
     */
    @IsTest
    static void testParseSuffixModes() {
        List<DynamicPageElementFieldListParser.FieldListItem> items = DynamicPageElementFieldListParser.parse(
            'Name*,Phone#,Industry$,AccountSource'
        );

        System.assertEquals(4, items.size());
        System.assertEquals('Name', items[0].fieldApiName);
        System.assertEquals(DynamicPageElementFieldListParser.MODE_REQUIRED, items[0].mode);
        System.assertEquals('Phone', items[1].fieldApiName);
        System.assertEquals(DynamicPageElementFieldListParser.MODE_READONLY, items[1].mode);
        System.assertEquals('Industry', items[2].fieldApiName);
        System.assertEquals(DynamicPageElementFieldListParser.MODE_EDITABLE, items[2].mode);
        System.assertEquals('AccountSource', items[3].fieldApiName);
        System.assertEquals(DynamicPageElementFieldListParser.MODE_READONLY, items[3].mode);
    }

    /**
     * @description
     * Verifies custom field API names with __c suffix parse correctly.
     */
    @IsTest
    static void testParseCustomFieldApiNames() {
        List<DynamicPageElementFieldListParser.FieldListItem> items = DynamicPageElementFieldListParser.parse(
            'Status__c#,Type$'
        );

        System.assertEquals(2, items.size());
        System.assertEquals('Status__c', items[0].fieldApiName);
        System.assertEquals(DynamicPageElementFieldListParser.MODE_READONLY, items[0].mode);
        System.assertEquals('Type', items[1].fieldApiName);
        System.assertEquals(DynamicPageElementFieldListParser.MODE_EDITABLE, items[1].mode);
    }

    /**
     * @description
     * Verifies whitespace around tokens is trimmed.
     */
    @IsTest
    static void testParseTrimsWhitespace() {
        List<DynamicPageElementFieldListParser.FieldListItem> items = DynamicPageElementFieldListParser.parse(
            ' Name* , Phone# '
        );

        System.assertEquals(2, items.size());
        System.assertEquals('Name', items[0].fieldApiName);
        System.assertEquals('Phone', items[1].fieldApiName);
    }

    /**
     * @description
     * Verifies invalid suffix-only tokens are skipped during parse.
     */
    @IsTest
    static void testParseSkipsInvalidTokens() {
        List<DynamicPageElementFieldListParser.FieldListItem> items =
            DynamicPageElementFieldListParser.parse('Name*,,#,$,Phone#');

        System.assertEquals(2, items.size());
        System.assertEquals('Name', items[0].fieldApiName);
        System.assertEquals('Phone', items[1].fieldApiName);
    }

    /**
     * @description
     * Verifies parseToken returns null for blank and suffix-only tokens.
     */
    @IsTest
    static void testParseTokenReturnsNullForInvalidTokens() {
        System.assertEquals(null, DynamicPageElementFieldListParser.parseToken(null));
        System.assertEquals(null, DynamicPageElementFieldListParser.parseToken('   '));
        System.assertEquals(null, DynamicPageElementFieldListParser.parseToken('*'));
        System.assertEquals(null, DynamicPageElementFieldListParser.parseToken('#'));
        System.assertEquals(null, DynamicPageElementFieldListParser.parseToken('$'));
    }
}