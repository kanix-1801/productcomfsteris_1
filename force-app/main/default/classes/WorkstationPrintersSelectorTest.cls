/**
 * @description Tests for WorkstationPrintersSelector (GW-4751).
 */
@IsTest
private class WorkstationPrintersSelectorTest {
    /**
     * @description GW-4751 - Selector SOQL targets WorkstationPrinter__c.
     */
    @IsTest
    static void testConstructorTargetsWorkstationPrinter() {
        String soql = new WorkstationPrintersSelector()
            .selectField('Id')
            .limitTo(1)
            .toSoql();

        Assert.isTrue(soql.contains('FROM WorkstationPrinter__c'), soql);
    }
}